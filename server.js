require("dotenv").config();
const path = require("path");
const crypto = require("crypto");
const express = require("express");
const multer = require("multer");
const { createServer } = require("http");
const { Server } = require("socket.io");
const OpenAI = require("openai");

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer);

const DEFAULT_PORT = Number(process.env.PORT) || 3000;
const MODEL = process.env.OPENAI_MODEL || "gpt-4.1-mini";
const MAX_FILE_SIZE_BYTES = 8 * 1024 * 1024;
const MAX_HISTORY_ITEMS = Number(process.env.HISTORY_MAX_ITEMS) || 25;
const VIEWER_TOKEN =
  process.env.VIEWER_TOKEN || crypto.randomBytes(12).toString("hex");

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_FILE_SIZE_BYTES },
});

const openai = process.env.OPENAI_API_KEY
  ? new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
  : null;

let latestAnalysis = {
  id: null,
  createdAt: null,
  summary: "No analysis yet.",
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

function requireViewerToken(req, res, next) {
  const token = tokenFromRequest(req);
  if (!token || token !== VIEWER_TOKEN) {
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
    solution: parsed.solution || "",
    codeSnippet: parsed.codeSnippet || "",
    explanation: parsed.explanation || "",
    algorithmWhy: parsed.algorithmWhy || "",
    timeComplexity: parsed.timeComplexity || "",
    spaceComplexity: parsed.spaceComplexity || "",
    detectedContentType: parsed.detectedContentType || "unknown",
    raw: parsed,
  };
}

app.use(express.json({ limit: "1mb" }));
app.use(express.static(path.join(__dirname, "public")));

io.use((socket, next) => {
  const token = socket.handshake.auth.token || socket.handshake.query.token;
  if (!token || token !== VIEWER_TOKEN) {
    return next(new Error("unauthorized"));
  }
  return next();
});

io.on("connection", (socket) => {
  socket.emit("analysis:update", latestAnalysis);
  socket.emit("analysis:history", analysisHistory);
});

app.get("/api/health", (_req, res) => {
  const ip = _req.ip || "";
  const isLocalRequest =
    ip === "::1" || ip === "127.0.0.1" || ip.endsWith("127.0.0.1");
  res.json({
    ok: true,
    hasOpenAiKey: Boolean(process.env.OPENAI_API_KEY),
    model: MODEL,
    viewerTokenConfigured: Boolean(process.env.VIEWER_TOKEN),
    viewerToken: isLocalRequest ? VIEWER_TOKEN : undefined,
    port: Number(process.env.PORT) || DEFAULT_PORT,
  });
});

app.get("/api/latest", requireViewerToken, (_req, res) => {
  res.json(latestAnalysis);
});

app.get("/api/history", requireViewerToken, (_req, res) => {
  res.json({ items: analysisHistory });
});

app.post("/api/analyze", upload.single("screenshot"), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: "Missing screenshot file." });
    }

    const prompt =
      (req.body && req.body.prompt) ||
      "Analyze this screenshot and return a short summary plus actionable help.";

    if (!openai) {
      latestAnalysis = {
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
        summary: "OPENAI_API_KEY is missing.",
        solution:
          "Add OPENAI_API_KEY to your .env and restart. Then run a new analysis.",
        codeSnippet: "",
        explanation: "",
        algorithmWhy: "",
        timeComplexity: "",
        spaceComplexity: "",
        detectedContentType: "unknown",
        raw: {
          fallback: true,
          reason: "No OpenAI client configured.",
        },
      };
      pushHistory(latestAnalysis);
      io.emit("analysis:update", latestAnalysis);
      io.emit("analysis:history", analysisHistory);
      return res.json(latestAnalysis);
    }

    const base64Image = req.file.buffer.toString("base64");
    const mimeType = req.file.mimetype || "image/png";
    const dataUrl = `data:${mimeType};base64,${base64Image}`;

    const completion = await openai.responses.create({
      model: MODEL,
      input: [
        {
          role: "system",
          content:
            "You are a FAANG-style interview question solver. Give concise, simple wording.",
        },
        {
          role: "user",
          content: [
            { type: "input_text", text: prompt },
            { type: "input_image", image_url: dataUrl },
            {
              type: "input_text",
              text:
                "Prefer an efficient solution (not brute force, but not over-engineered). Return strict JSON with keys: summary, solution, codeSnippet, explanation, algorithmWhy, timeComplexity, spaceComplexity, detectedContentType. Keep words minimal and simple.",
            },
          ],
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "screen_analysis",
          schema: {
            type: "object",
            additionalProperties: false,
            properties: {
              summary: { type: "string" },
              solution: { type: "string" },
              codeSnippet: { type: "string" },
              explanation: { type: "string" },
              algorithmWhy: { type: "string" },
              timeComplexity: { type: "string" },
              spaceComplexity: { type: "string" },
              detectedContentType: { type: "string" },
            },
            required: [
              "summary",
              "solution",
              "codeSnippet",
              "explanation",
              "algorithmWhy",
              "timeComplexity",
              "spaceComplexity",
              "detectedContentType",
            ],
          },
          strict: true,
        },
      },
    });

    let parsed;
    try {
      parsed = JSON.parse(completion.output_text);
    } catch (_error) {
      parsed = {
        summary: completion.output_text || "Could not parse model output.",
        solution: "",
        codeSnippet: "",
        explanation: "",
        algorithmWhy: "",
        timeComplexity: "",
        spaceComplexity: "",
        detectedContentType: "unknown",
      };
    }

    latestAnalysis = {
      id: crypto.randomUUID(),
      createdAt: new Date().toISOString(),
      ...normalizeAnalysisShape(parsed),
    };

    pushHistory(latestAnalysis);
    io.emit("analysis:update", latestAnalysis);
    io.emit("analysis:history", analysisHistory);
    return res.json(latestAnalysis);
  } catch (error) {
    return res.status(500).json({
      error: "Failed to analyze screenshot.",
      details: error.message,
    });
  }
});

app.post("/api/improve", requireViewerToken, async (_req, res) => {
  try {
    if (!openai) {
      return res.status(400).json({ error: "OPENAI_API_KEY is missing." });
    }
    if (!latestAnalysis || !latestAnalysis.summary) {
      return res.status(400).json({ error: "No analysis to improve yet." });
    }

    const improvementPrompt = [
      "Improve this interview solution.",
      "Target FAANG expectations.",
      "Avoid brute force unless it is optimal.",
      "Use few words and simple words.",
      "Return strict JSON keys: summary, solution, codeSnippet, explanation, algorithmWhy, timeComplexity, spaceComplexity, detectedContentType.",
      "",
      `Current summary: ${latestAnalysis.summary}`,
      `Current solution: ${latestAnalysis.solution}`,
      `Current code: ${latestAnalysis.codeSnippet}`,
      `Current explanation: ${latestAnalysis.explanation}`,
      `Current algorithmWhy: ${latestAnalysis.algorithmWhy}`,
      `Current timeComplexity: ${latestAnalysis.timeComplexity}`,
      `Current spaceComplexity: ${latestAnalysis.spaceComplexity}`,
    ].join("\n");

    const completion = await openai.responses.create({
      model: MODEL,
      input: [
        {
          role: "system",
          content:
            "You are an interview coach improving solutions for correctness, clarity, and complexity.",
        },
        {
          role: "user",
          content: [{ type: "input_text", text: improvementPrompt }],
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "screen_analysis_improved",
          schema: {
            type: "object",
            additionalProperties: false,
            properties: {
              summary: { type: "string" },
              solution: { type: "string" },
              codeSnippet: { type: "string" },
              explanation: { type: "string" },
              algorithmWhy: { type: "string" },
              timeComplexity: { type: "string" },
              spaceComplexity: { type: "string" },
              detectedContentType: { type: "string" },
            },
            required: [
              "summary",
              "solution",
              "codeSnippet",
              "explanation",
              "algorithmWhy",
              "timeComplexity",
              "spaceComplexity",
              "detectedContentType",
            ],
          },
          strict: true,
        },
      },
    });

    let parsed;
    try {
      parsed = JSON.parse(completion.output_text);
    } catch (_error) {
      parsed = {
        summary: completion.output_text || "Could not parse improved output.",
        solution: latestAnalysis.solution || "",
        codeSnippet: latestAnalysis.codeSnippet || "",
        explanation: latestAnalysis.explanation || "",
        algorithmWhy: latestAnalysis.algorithmWhy || "",
        timeComplexity: latestAnalysis.timeComplexity || "",
        spaceComplexity: latestAnalysis.spaceComplexity || "",
        detectedContentType: latestAnalysis.detectedContentType || "unknown",
      };
    }

    latestAnalysis = {
      id: crypto.randomUUID(),
      createdAt: new Date().toISOString(),
      ...normalizeAnalysisShape(parsed),
    };
    pushHistory(latestAnalysis);
    io.emit("analysis:update", latestAnalysis);
    io.emit("analysis:history", analysisHistory);
    return res.json(latestAnalysis);
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

app.get("/viewer", requireViewerToken, (_req, res) => {
  res.sendFile(path.join(__dirname, "public", "viewer.html"));
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
};

if (require.main === module) {
  console.log(`Viewer token: ${VIEWER_TOKEN}`);
  startListening()
    .then(({ port }) => {
      console.log(`Interview Helper listening on http://localhost:${port}`);
      console.log(
        "If another device cannot open the viewer URL: on this Mac allow Node through the firewall (IH menu → Allow Node for incoming connections…) or System Settings → Network → Firewall.",
      );
    })
    .catch((error) => {
      console.error("Failed to start server:", error);
      process.exit(1);
    });
}
