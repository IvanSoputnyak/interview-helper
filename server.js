require("dotenv").config();
const path = require("path");
const crypto = require("crypto");
const express = require("express");
const multer = require("multer");
const { execFile } = require("child_process");
const { createServer } = require("http");
const { Server } = require("socket.io");
const OpenAI = require("openai");
const {
  DEFAULT_ANALYZE_PROMPT: CONTRACT_ANALYZE_PROMPT,
  EXPLAIN_SYSTEM_PROMPT,
  IMPROVE_SYSTEM_PROMPT,
  SYSTEM_PROMPT,
  analysisJsonSchema,
  buildExplainPrompt,
  buildImprovePrompt,
  pickAnalysisFields,
  resolveModel,
  stripCodeFences,
  stripInlineCodeMarks,
  withOriginalQuestionIfMissing,
  withoutInlineCodeMarks,
} = require("./lib/analysis-schema");
const {
  PHONE_HOST_NAME,
  announcePhoneHostName,
  hostWithPort,
  isLoopbackAddress,
  lanAddresses,
} = require("./lib/local-network");

const DEFAULT_PORT = Number(process.env.PORT) || 80;
const MODEL = resolveModel(process.env.OPENAI_MODEL);
/** "low" answered about twice as fast as the model default with the same correctness in our screenshot benchmarks. */
const REASONING_EFFORT = process.env.OPENAI_REASONING_EFFORT || "low";
const MAX_FILE_SIZE_BYTES = 8 * 1024 * 1024;
/** One JPEG frame of the screen shared from /broadcast (a 2048px frame is usually well under 1 MB). */
const MAX_FRAME_BYTES = 3 * 1024 * 1024;
/** Socket message cap: a frame plus base64 overhead (+33%) when the polling transport is used. */
const MAX_SOCKET_MESSAGE_BYTES = Math.ceil((MAX_FRAME_BYTES * 4) / 3) + 1024;
const FRAME_MIME_TYPE = "image/jpeg";
const NO_SHARED_SCREEN_MESSAGE =
  "No shared screen yet. On the Mac, run make start and press Start sharing.";
const ANALYZE_SCHEMA_NAME = "screen_analysis";
const IMPROVE_SCHEMA_NAME = "screen_analysis_improved";
const ALLOWED_IMAGE_TYPES = new Set([
  "image/png",
  "image/jpeg",
  "image/webp",
  "image/gif",
]);
const DEFAULT_ANALYZE_PROMPT = process.env.ANALYZE_PROMPT || CONTRACT_ANALYZE_PROMPT;

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

/** The state before any capture and after Clear: it has no id, so the phone hides the answer. */
const NO_ANALYSIS = Object.freeze({ id: null, createdAt: null, ...pickAnalysisFields({ summary: "No analysis yet." }) });
let latestAnalysis = NO_ANALYSIS;
/** Latest JPEG frame of the shared screen, or null while nothing is being shared. */
let latestFrame = null;
/** Socket that sent `latestFrame`; when it disconnects (share tab closed) the frame is dropped. */
let frameSenderId = null;

/** Sharing the screen and uploading screenshots are for this Mac only; phones on the Wi-Fi just watch and ask. */
function requireThisMac(req, res, next) {
  if (!isLoopbackAddress(req.socket.remoteAddress)) {
    return res.status(403).json({ error: "Only the Mac running the server can do this." });
  }
  return next();
}

/** Every schema field as a string; `question` falls back to `summary` (matches ScreenAnalysis.fromParsedJSON). */
function normalizeAnalysisShape(parsed) {
  const fields = withoutInlineCodeMarks(pickAnalysisFields(parsed));
  return {
    ...fields,
    summary: fields.summary || "No summary",
    question: fields.question || fields.summary,
    codeSnippet: stripCodeFences(fields.codeSnippet),
    detectedContentType: fields.detectedContentType || "unknown",
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

/** Makes `analysis` the live one and pushes it to every viewer. */
function commitAnalysis(analysis) {
  latestAnalysis = analysis;
  io.emit("analysis:update", latestAnalysis);
}

/** Responses API request; with `schemaName` the reply is the strict analysis JSON, without it plain text. */
function modelRequest(system, content, schemaName) {
  const request = {
    model: MODEL,
    reasoning: { effort: REASONING_EFFORT },
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
  frameSenderId = socket.id;
  socket.broadcast.emit("screen:frame", frame);
}

/** Sharing ended: forget the frame so nothing analyzes or shows an old screen, and tell the viewers. */
function clearFrame() {
  latestFrame = null;
  frameSenderId = null;
  io.emit("screen:stop");
}

/** Port the server is bound to, or `fallback` before it listens. */
function boundPort(fallback) {
  const address = httpServer.address();
  return typeof address === "object" && address ? address.port : fallback;
}

/** Sends public/`page`.html. */
function sendPage(page) {
  return (_req, res) => res.sendFile(path.join(__dirname, "public", `${page}.html`));
}

// The phone opens the bare address (h.local), so the viewer is the home page.
app.get("/", sendPage("viewer"));
// Registered before express.static so the share page is never served to another device.
app.get(["/broadcast", "/broadcast.html"], requireThisMac, sendPage("broadcast"));

app.use(express.static(path.join(__dirname, "public")));
// Syntax highlighting for the viewer's code block, served locally so the phone needs no internet access.
app.use("/vendor/highlight", express.static(path.join(__dirname, "node_modules", "@highlightjs", "cdn-assets")));

io.on("connection", (socket) => {
  socket.emit("analysis:update", latestAnalysis);
  // A viewer that slept through "screen:stop" still learns that sharing ended.
  if (latestFrame) {
    socket.emit("screen:frame", latestFrame);
  } else {
    socket.emit("screen:stop");
  }
  // Only the share page on this Mac may change the shared screen; phones only receive it.
  if (isLoopbackAddress(socket.handshake.address)) {
    socket.on("screen:frame", (frame) => receiveFrame(socket, frame));
    socket.on("screen:stop", clearFrame);
  }
  socket.on("disconnect", () => {
    if (socket.id === frameSenderId) {
      clearFrame();
    }
  });
});

app.get("/api/health", (_req, res) => {
  res.json({
    ok: true,
    hasOpenAiKey: Boolean(openai),
    model: MODEL,
    port: boundPort(DEFAULT_PORT),
  });
});

app.get("/api/latest", (_req, res) => {
  res.json(latestAnalysis);
});

/** Wraps an async route so an unexpected error becomes JSON 500 with `failureMessage`. */
function jsonRoute(failureMessage, handler) {
  return async (req, res) => {
    try {
      await handler(req, res);
    } catch (error) {
      console.error(`${failureMessage} ${req.method} ${req.path}:`, error);
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
  requireThisMac,
  upload.single("screenshot"),
  requireScreenshot,
  requireOpenAI,
  jsonRoute("Failed to analyze screenshot.", async (req, res) => {
    res.json(await analyzeImage(req.file.mimetype, req.file.buffer, req.body.prompt || DEFAULT_ANALYZE_PROMPT));
  }),
);

/** Analyzes the latest frame of the screen shared from /broadcast. */
app.post(
  "/api/analyze-screen",
  requireOpenAI,
  jsonRoute("Failed to analyze the shared screen.", async (req, res) => {
    // 503, not 400: right after a server restart the viewer can reconnect before the Mac's next frame
    // arrives, so the viewer retries this (see public/request-retry.js) instead of failing at once.
    if (!latestFrame) {
      return res.status(503).json({ error: NO_SHARED_SCREEN_MESSAGE });
    }
    return res.json(await analyzeImage(FRAME_MIME_TYPE, latestFrame, DEFAULT_ANALYZE_PROMPT));
  }),
);

app.post(
  "/api/improve",
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
      commitAnalysis(committed);
    }
    return res.json(committed);
  }),
);

/**
 * Clear: forgets the live analysis on every viewer, so a reconnect does not bring it back. An Improve still
 * running keeps it gone too: it only replaces the live analysis when that is still the one it improved.
 */
app.post("/api/clear", (_req, res) => {
  commitAnalysis(NO_ANALYSIS);
  res.json(NO_ANALYSIS);
});

/** Beginner walkthrough of the live analysis, as plain text (same prompt as the Mac app's "Explain simply"). */
app.post(
  "/api/explain",
  requireOpenAI,
  jsonRoute("Failed to explain solution.", async (_req, res) => {
    const current = latestAnalysis;
    if (!current.id) {
      return res.status(400).json({ error: "No analysis to explain yet." });
    }
    const completion = await openai.responses.create(
      modelRequest(EXPLAIN_SYSTEM_PROMPT, [{ type: "input_text", text: buildExplainPrompt(current) }]),
    );
    const explanation = stripInlineCodeMarks((completion.output_text || "").trim());
    if (!explanation) {
      return res.status(502).json({ error: "The model returned an empty explanation. Try again." });
    }
    return res.json({ id: current.id, explanation });
  }),
);

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
    httpServer.listen(port, host, () => resolve({ port: boundPort(port) }));
  });
}

module.exports = {
  DEFAULT_PORT,
  httpServer,
  io,
  startListening,
  parseModelOutput,
};

/** Prints where to open the viewer and the share page; with OPEN_SHARE_PAGE=1 (make start) opens the share page. */
function announceStarted(port) {
  // getDisplayMedia needs a secure context; http://localhost counts as one, the h.local address does not.
  const sharePageUrl = `http://${hostWithPort("localhost", port)}/broadcast`;
  const [lanAddress] = lanAddresses();
  console.log("Interview Helper is running.");
  if (lanAddress) {
    announcePhoneHostName(port, lanAddress);
    console.log(`Phone:  ${hostWithPort(PHONE_HOST_NAME, port)}   (if that does not open: http://${hostWithPort(lanAddress, port)})`);
  } else {
    console.log("Phone:  not on Wi-Fi or Ethernet, so phones cannot reach this Mac yet. Connect and restart.");
  }
  console.log(`Mac:    ${sharePageUrl}   (press Start sharing there)`);
  console.log("If the phone cannot open it, allow Node through the firewall: System Settings → Network → Firewall.");
  if (process.env.OPEN_SHARE_PAGE === "1") {
    execFile("open", [sharePageUrl]);
  }
}

if (require.main === module) {
  startListening()
    .then(({ port }) => announceStarted(port))
    .catch((error) => {
      console.error("Failed to start server:", error);
      process.exit(1);
    });
}
