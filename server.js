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
  IMPROVE_SYSTEM_PROMPT,
  SYSTEM_PROMPT,
  analysisJsonSchema,
  buildImprovePrompt,
  pickAnalysisFields,
  resolveModel,
  stripCodeFences,
  withOriginalQuestionIfMissing,
} = require("./lib/analysis-schema");

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer);

const DEFAULT_PORT = Number(process.env.PORT) || 3000;
const MODEL = resolveModel(process.env.OPENAI_MODEL);
const MAX_FILE_SIZE_BYTES = 8 * 1024 * 1024;
const MAX_HISTORY_ITEMS = Number(process.env.HISTORY_MAX_ITEMS) || 25;
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
  raw: null,
};
let analysisHistory = [];

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

function pushHistory(entry) {
  analysisHistory.unshift(entry);
  analysisHistory = analysisHistory.slice(0, MAX_HISTORY_ITEMS);
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
    raw: parsed,
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
  pushHistory(analysis);
  const row = toQA(analysis);
  if (replaceQA) {
    qaStore.upsert(row);
  } else {
    qaStore.append(row);
  }
  io.emit("analysis:update", latestAnalysis);
  io.emit("qa:list", qaStore.list());
}

function analysisRequest(schemaName, system, content) {
  return {
    model: MODEL,
    input: [
      { role: "system", content: system },
      { role: "user", content },
    ],
    text: {
      format: {
        type: "json_schema",
        name: schemaName,
        schema: analysisJsonSchema,
        strict: true,
      },
    },
  };
}

// Registered before express.static so public/viewer.html is never served without a token.
app.get(["/viewer", "/viewer.html"], requireViewerToken, (_req, res) => {
  res.sendFile(path.join(__dirname, "public", "viewer.html"));
});

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

app.get("/api/history", requireViewerToken, (_req, res) => {
  res.json({ items: analysisHistory });
});

app.get("/api/qa", requireViewerToken, (_req, res) => {
  res.json({ items: qaStore.list() });
});

app.post(
  "/api/analyze",
  requireViewerToken,
  upload.single("screenshot"),
  async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: "Missing screenshot file." });
      }
      if (!openai) {
        return res.status(400).json({ error: "OPENAI_API_KEY is missing." });
      }

      const prompt = (req.body && req.body.prompt) || DEFAULT_ANALYZE_PROMPT;
      const dataUrl = `data:${req.file.mimetype};base64,${req.file.buffer.toString("base64")}`;

      const completion = await openai.responses.create(
        analysisRequest("screen_analysis", SYSTEM_PROMPT, [
          { type: "input_text", text: prompt },
          { type: "input_image", image_url: dataUrl },
        ]),
      );

      commitAnalysis({
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
        ...normalizeAnalysisShape(parseModelOutput(completion.output_text)),
      });
      return res.json(latestAnalysis);
    } catch (error) {
      return res.status(500).json({
        error: "Failed to analyze screenshot.",
        details: error.message,
      });
    }
  },
);

app.post("/api/improve", requireViewerToken, async (_req, res) => {
  try {
    if (!openai) {
      return res.status(400).json({ error: "OPENAI_API_KEY is missing." });
    }
    // Snapshot: a concurrent /api/analyze may replace latestAnalysis while we await the model.
    const current = latestAnalysis;
    if (!current.id) {
      return res.status(400).json({ error: "No analysis to improve yet." });
    }

    const improvementPrompt = buildImprovePrompt(current);

    const completion = await openai.responses.create(
      analysisRequest("screen_analysis_improved", IMPROVE_SYSTEM_PROMPT, [
        { type: "input_text", text: improvementPrompt },
      ]),
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
      qaStore.upsert(toQA(committed));
      io.emit("qa:list", qaStore.list());
    }
    return res.json(committed);
  } catch (error) {
    return res.status(500).json({
      error: "Failed to improve solution.",
      details: error.message,
    });
  }
});

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
      console.log(`Viewer: http://<this-mac>.local:${port}/viewer?token=${VIEWER_TOKEN}`);
      console.log(
        "If another device cannot open the viewer URL, allow Node through the firewall: System Settings → Network → Firewall.",
      );
    })
    .catch((error) => {
      console.error("Failed to start server:", error);
      process.exit(1);
    });
}
