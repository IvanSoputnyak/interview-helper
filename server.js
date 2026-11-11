require("dotenv").config();
const path = require("path");
const crypto = require("crypto");
const express = require("express");
const multer = require("multer");
const { createServer } = require("http");
const { Server } = require("socket.io");
const OpenAI = require("openai");
const qaStore = require("./lib/qa-store");
const {
  DEFAULT_ANALYZE_PROMPT: CONTRACT_ANALYZE_PROMPT,
  EXPLAIN_SYSTEM_PROMPT,
  IMPROVE_SYSTEM_PROMPT,
  SYSTEM_PROMPT,
  analysisJsonSchema,
  buildAnalyzePrompt,
  buildExplainPrompt,
  buildImprovePrompt,
  pickAnalysisFields,
  resolveModel,
  stripCodeFences,
  withOriginalQuestionIfMissing,
} = require("./lib/analysis-schema");

const DEFAULT_PORT = Number(process.env.PORT) || 3000;
const MODEL = resolveModel(process.env.OPENAI_MODEL);
const MAX_FILE_SIZE_BYTES = 8 * 1024 * 1024;
/** One JPEG frame of the screen shared from /broadcast (a 2048px frame is usually well under 1 MB). */
const MAX_FRAME_BYTES = 3 * 1024 * 1024;
/** Socket message cap: a frame plus base64 overhead (+33%) when the polling transport is used. */
const MAX_SOCKET_MESSAGE_BYTES = Math.ceil((MAX_FRAME_BYTES * 4) / 3) + 1024;
const FRAME_MIME_TYPE = "image/jpeg";
const NO_SHARED_SCREEN_MESSAGE =
  "No shared screen yet. On the Mac, open /broadcast?token=… and press Start sharing.";
const ANALYZE_SCHEMA_NAME = "screen_analysis";
const IMPROVE_SCHEMA_NAME = "screen_analysis_improved";
const QA_QUESTION_MAX_CHARS = 4000;
const QA_ANSWER_MAX_CHARS = 12000;
const ALLOWED_IMAGE_TYPES = new Set([
  "image/png",
  "image/jpeg",
  "image/webp",
  "image/gif",
]);
const DEFAULT_ANALYZE_PROMPT = process.env.ANALYZE_PROMPT || CONTRACT_ANALYZE_PROMPT;
const VIEWER_TOKEN =
  process.env.VIEWER_TOKEN || crypto.randomBytes(12).toString("hex");

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, { maxHttpBufferSize: MAX_SOCKET_MESSAGE_BYTES });

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_FILE_SIZE_BYTES },
  fileFilter: (_req, file, cb) => {
    if (ALLOWED_IMAGE_TYPES.has(file.mimetype)) {
      return cb(null, true);
    }
    return cb(new multer.MulterError("LIMIT_UNEXPECTED_FILE", file.fieldname));
  },
});

const openai = process.env.OPENAI_API_KEY
  ? new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
  : null;

let latestAnalysis = {
  id: null,
  createdAt: null,
  summary: "No analysis yet.",
  question: "",
  solution: "",
  codeSnippet: "",
  explanation: "",
  algorithmWhy: "",
  timeComplexity: "",
  spaceComplexity: "",
  detectedContentType: "",
};
/** Latest JPEG frame of the shared screen, or null until /broadcast starts sharing. */
let latestFrame = null;

function tokenFromRequest(req) {
  return req.get("x-viewer-token") || req.query.token || null;
}

function isValidToken(token) {
  if (typeof token !== "string") {
    return false;
  }
  const given = Buffer.from(token);
  const expected = Buffer.from(VIEWER_TOKEN);
  return given.length === expected.length && crypto.timingSafeEqual(given, expected);
}

function requireViewerToken(req, res, next) {
  if (!isValidToken(tokenFromRequest(req))) {
    return res.status(401).json({ error: "Unauthorized viewer token." });
  }
  return next();
}

function normalizeAnalysisShape(parsed) {
  return {
    summary: parsed.summary || "No summary",
    question: parsed.question || parsed.summary || "",
    solution: parsed.solution || "",
    codeSnippet: stripCodeFences(parsed.codeSnippet || ""),
    explanation: parsed.explanation || "",
    algorithmWhy: parsed.algorithmWhy || "",
    timeComplexity: parsed.timeComplexity || "",
    spaceComplexity: parsed.spaceComplexity || "",
    detectedContentType: parsed.detectedContentType || "unknown",
  };
}

/** Parse model JSON; on failure keep `fallback` fields and surface the raw text as the summary. */
function parseModelOutput(outputText, fallback = {}) {
  try {
    return JSON.parse(outputText);
  } catch {
    return {
      ...fallback,
      summary: outputText || "Could not parse model output.",
    };
  }
}

function toQA(analysis) {
  return {
    id: analysis.id,
    at: analysis.createdAt,
    q: (analysis.question || analysis.summary || "").slice(0, QA_QUESTION_MAX_CHARS),
    a: (analysis.codeSnippet || analysis.solution || "").slice(0, QA_ANSWER_MAX_CHARS),
  };
}

function commitAnalysis(analysis, { replaceQA = false } = {}) {
  latestAnalysis = analysis;
  const row = toQA(analysis);
  io.emit("analysis:update", latestAnalysis);
  io.emit("qa:list", replaceQA ? qaStore.upsert(row) : qaStore.append(row));
}

/** Responses API request; with `schemaName` the reply is the strict analysis JSON, without it plain text. */
function modelRequest(system, content, schemaName) {
  const request = {
    model: MODEL,
    input: [
      { role: "system", content: system },
      { role: "user", content },
    ],
  };
  if (schemaName) {
    request.text = {
      format: { type: "json_schema", name: schemaName, schema: analysisJsonSchema, strict: true },
    };
  }
  return request;
}

function isValidFrame(frame) {
  return Buffer.isBuffer(frame) && frame.length > 0 && frame.length <= MAX_FRAME_BYTES;
}

/** Keeps the newest shared-screen frame and relays it to every other viewer; invalid payloads are dropped. */
function receiveFrame(socket, frame) {
  if (!isValidFrame(frame)) {
    return;
  }
  latestFrame = frame;
  socket.broadcast.emit("screen:frame", frame);
}

// Registered before express.static so these pages are never served without a token.
for (const page of ["viewer", "broadcast"]) {
  app.get([`/${page}`, `/${page}.html`], requireViewerToken, (_req, res) => {
    res.sendFile(path.join(__dirname, "public", `${page}.html`));
  });
}

app.use(express.static(path.join(__dirname, "public")));

io.use((socket, next) => {
  const token = socket.handshake.auth.token || socket.handshake.query.token;
  if (!isValidToken(token)) {
    return next(new Error("unauthorized"));
  }
  return next();
});

io.on("connection", (socket) => {
  socket.emit("analysis:update", latestAnalysis);
  socket.emit("qa:list", qaStore.list());
  if (latestFrame) {
    socket.emit("screen:frame", latestFrame);
  }
  socket.on("screen:frame", (frame) => receiveFrame(socket, frame));
});

app.get("/api/health", (_req, res) => {
  const address = httpServer.address();
  res.json({
    ok: true,
    hasOpenAiKey: Boolean(openai),
    model: MODEL,
    viewerTokenConfigured: Boolean(process.env.VIEWER_TOKEN),
    port: typeof address === "object" && address ? address.port : DEFAULT_PORT,
  });
});

app.get("/api/latest", requireViewerToken, (_req, res) => {
  res.json(latestAnalysis);
});

app.get("/api/qa", requireViewerToken, (_req, res) => {
  res.json({ items: qaStore.list() });
});

/** Wraps an async route so an unexpected error becomes JSON 500 with `failureMessage`. */
function jsonRoute(failureMessage, handler) {
  return async (req, res) => {
    try {
      await handler(req, res);
    } catch (error) {
      res.status(500).json({ error: failureMessage, details: error.message });
    }
  };
}

function requireOpenAI(_req, res, next) {
  if (!openai) {
    return res.status(400).json({ error: "OPENAI_API_KEY is missing." });
  }
  return next();
}

function requireScreenshot(req, res, next) {
  if (!req.file) {
    return res.status(400).json({ error: "Missing screenshot file." });
  }
  return next();
}

/** The request's own prompt (or the default), plus the viewer's optional question. */
function analyzePromptFor(body = {}) {
  return buildAnalyzePrompt(body.prompt || DEFAULT_ANALYZE_PROMPT, body.question);
}

/** Runs the analysis model on one image and makes the result the live analysis. */
async function analyzeImage(mimeType, imageBytes, prompt) {
  const completion = await openai.responses.create(
    modelRequest(SYSTEM_PROMPT, [
      { type: "input_text", text: prompt },
      { type: "input_image", image_url: `data:${mimeType};base64,${imageBytes.toString("base64")}` },
    ], ANALYZE_SCHEMA_NAME),
  );
  commitAnalysis({
    id: crypto.randomUUID(),
    createdAt: new Date().toISOString(),
    ...normalizeAnalysisShape(parseModelOutput(completion.output_text)),
  });
  return latestAnalysis;
}

app.post(
  "/api/analyze",
  requireViewerToken,
  upload.single("screenshot"),
  requireScreenshot,
  requireOpenAI,
  jsonRoute("Failed to analyze screenshot.", async (req, res) => {
    res.json(await analyzeImage(req.file.mimetype, req.file.buffer, analyzePromptFor(req.body)));
  }),
);

/** Analyzes the latest frame of the screen shared from /broadcast. */
app.post(
  "/api/analyze-screen",
  requireViewerToken,
  requireOpenAI,
  express.json(),
  jsonRoute("Failed to analyze the shared screen.", async (req, res) => {
    // 503, not 400: right after a server restart the viewer can reconnect before the Mac's next frame
    // arrives, so the viewer retries this (see public/request-retry.js) instead of failing at once.
    if (!latestFrame) {
      return res.status(503).json({ error: NO_SHARED_SCREEN_MESSAGE });
    }
    return res.json(await analyzeImage(FRAME_MIME_TYPE, latestFrame, analyzePromptFor(req.body)));
  }),
);

app.post(
  "/api/improve",
  requireViewerToken,
  requireOpenAI,
  jsonRoute("Failed to improve solution.", async (_req, res) => {
    // Snapshot: a concurrent /api/analyze may replace latestAnalysis while we await the model.
    const current = latestAnalysis;
    if (!current.id) {
      return res.status(400).json({ error: "No analysis to improve yet." });
    }

    const completion = await openai.responses.create(
      modelRequest(IMPROVE_SYSTEM_PROMPT, [
        { type: "input_text", text: buildImprovePrompt(current) },
      ], IMPROVE_SCHEMA_NAME),
    );

    const parsed = parseModelOutput(completion.output_text, pickAnalysisFields(current));
    const committed = {
      id: current.id,
      createdAt: new Date().toISOString(),
      ...normalizeAnalysisShape(withOriginalQuestionIfMissing(parsed, current)),
    };
    // Only replace the live view if no newer analysis arrived meanwhile.
    if (latestAnalysis.id === current.id) {
      commitAnalysis(committed, { replaceQA: true });
    } else {
      io.emit("qa:list", qaStore.upsert(toQA(committed)));
    }
    return res.json(committed);
  }),
);

/** Beginner walkthrough of the live analysis, as plain text (same prompt as the Mac app's "Explain simply"). */
app.post(
  "/api/explain",
  requireViewerToken,
  requireOpenAI,
  jsonRoute("Failed to explain solution.", async (_req, res) => {
    const current = latestAnalysis;
    if (!current.id) {
      return res.status(400).json({ error: "No analysis to explain yet." });
    }
    const completion = await openai.responses.create(
      modelRequest(EXPLAIN_SYSTEM_PROMPT, [{ type: "input_text", text: buildExplainPrompt(current) }]),
    );
    const explanation = (completion.output_text || "").trim();
    if (!explanation) {
      return res.status(502).json({ error: "The model returned an empty explanation. Try again." });
    }
    return res.json({ id: current.id, explanation });
  }),
);

app.get("/", (_req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

// Turn multer errors (oversized / non-image upload) into JSON instead of Express's HTML 500.
app.use((error, _req, res, next) => {
  if (error instanceof multer.MulterError) {
    const status = error.code === "LIMIT_FILE_SIZE" ? 413 : 400;
    const message =
      error.code === "LIMIT_FILE_SIZE"
        ? `Screenshot exceeds ${MAX_FILE_SIZE_BYTES / (1024 * 1024)} MB.`
        : "Screenshot must be a PNG, JPEG, WebP, or GIF image.";
    return res.status(status).json({ error: message });
  }
  return next(error);
});

function startListening(port = DEFAULT_PORT, host = "0.0.0.0") {
  return new Promise((resolve, reject) => {
    httpServer.once("error", reject);
    httpServer.listen(port, host, () => {
      const address = httpServer.address();
      resolve({
        port:
          typeof address === "object" && address
            ? address.port
            : port,
      });
    });
  });
}

module.exports = {
  DEFAULT_PORT,
  VIEWER_TOKEN,
  httpServer,
  io,
  startListening,
  toQA,
  qaStore,
  parseModelOutput,
};

if (require.main === module) {
  console.log(`Viewer token: ${VIEWER_TOKEN}`);
  startListening()
    .then(({ port }) => {
      console.log(`Interview Helper listening on http://localhost:${port}`);
      console.log(`Viewer (phone/tablet): http://<this-mac>.local:${port}/viewer?token=${VIEWER_TOKEN}`);
      // getDisplayMedia needs a secure context; http://localhost counts as one, the .local address does not.
      console.log(`Share this Mac's screen (open on this Mac): http://localhost:${port}/broadcast?token=${VIEWER_TOKEN}`);
      console.log(
        "If another device cannot open the viewer URL, allow Node through the firewall: System Settings → Network → Firewall.",
      );
    })
    .catch((error) => {
      console.error("Failed to start server:", error);
      process.exit(1);
    });
}
