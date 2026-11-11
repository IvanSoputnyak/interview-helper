// Drives /api/analyze, /api/analyze-screen, /api/improve and /api/explain end to end against a fake OpenAI Responses endpoint
// (the SDK honours OPENAI_BASE_URL), so model replies, races, and fallbacks are exercised for real.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");

const contract = require("../shared/analysis-contract.json");
const { createPollingClient } = require("./helpers/socket-polling");

const AUTH = { "x-viewer-token": "test-token" };
const ANALYZE = "screen_analysis";
const IMPROVE = "screen_analysis_improved";
/** Explain asks for plain text, so its request has no text.format.name. */
const EXPLAIN = "plain_text";
/** Queued fake replies per request kind (text.format.name), so concurrent requests can't take each other's reply. */
const fakeReplies = { [ANALYZE]: [], [IMPROVE]: [], [EXPLAIN]: [] };
const fakeRequests = [];
let fakeOpenAI;
let baseUrl = "";
let server;

function analysisJSON(fields) {
  return JSON.stringify({
    summary: "",
    question: "",
    solution: "",
    codeSnippet: "",
    explanation: "",
    algorithmWhy: "",
    timeComplexity: "",
    spaceComplexity: "",
    detectedContentType: "coding_problem",
    ...fields,
  });
}

/** Queue the next fake model reply for one request kind: output text, optional delay, optional HTTP status. */
function replyWith(kind, text, { delayMs = 0, status = 200 } = {}) {
  fakeReplies[kind].push({ text, delayMs, status });
}

function responsesBody(text) {
  return {
    id: "resp_test",
    object: "response",
    status: "completed",
    output: [
      {
        type: "message",
        id: "msg_test",
        role: "assistant",
        status: "completed",
        content: [{ type: "output_text", text, annotations: [] }],
      },
    ],
  };
}

function startFakeOpenAI() {
  fakeOpenAI = http.createServer((req, res) => {
    let raw = "";
    req.on("data", (chunk) => {
      raw += chunk;
    });
    req.on("end", () => {
      const request = JSON.parse(raw);
      fakeRequests.push(request);
      const queue = fakeReplies[request.text?.format?.name ?? EXPLAIN];
      const reply = queue.shift() || { text: analysisJSON({ summary: "unscripted reply" }), delayMs: 0, status: 200 };
      setTimeout(() => {
        res.writeHead(reply.status, { "content-type": "application/json" });
        const body = reply.status === 200 ? responsesBody(reply.text) : { error: { message: reply.text } };
        res.end(JSON.stringify(body));
      }, reply.delayMs);
    });
  });
  return new Promise((resolve) => fakeOpenAI.listen(0, "127.0.0.1", resolve));
}

async function analyze({ question } = {}) {
  const form = new FormData();
  if (question !== undefined) {
    form.append("question", question);
  }
  form.append("screenshot", new Blob([new Uint8Array([137, 80, 78, 71])], { type: "image/png" }), "c.png");
  const response = await fetch(`${baseUrl}/api/analyze`, { method: "POST", headers: AUTH, body: form });
  return { status: response.status, body: await response.json() };
}

async function postJSON(route, payload = {}) {
  const response = await fetch(`${baseUrl}${route}`, {
    method: "POST",
    headers: { ...AUTH, "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
  return { status: response.status, body: await response.json() };
}

const analyzeScreen = (payload) => postJSON("/api/analyze-screen", payload);
const explain = () => postJSON("/api/explain");

/** Shares one frame from a broadcaster socket, as /broadcast does. */
async function shareFrame(frame) {
  const client = createPollingClient(baseUrl);
  const { sid } = await client.connect({ token: "test-token" });
  await client.emitBinary(sid, "screen:frame", frame);
}

/** Text parts of the user message of a captured model request. */
function userText(request) {
  return request.input[1].content.find((part) => part.type === "input_text").text;
}

async function improve() {
  const response = await fetch(`${baseUrl}/api/improve`, { method: "POST", headers: AUTH });
  return { status: response.status, body: await response.json() };
}

async function latest() {
  return (await fetch(`${baseUrl}/api/latest`, { headers: AUTH })).json();
}

async function qaItems() {
  return (await (await fetch(`${baseUrl}/api/qa`, { headers: AUTH })).json()).items;
}

test.before(async () => {
  await startFakeOpenAI();
  process.env.OPENAI_BASE_URL = `http://127.0.0.1:${fakeOpenAI.address().port}/v1`;
  process.env.OPENAI_API_KEY = "test-key";
  process.env.OPENAI_MODEL = "gpt-4.1-mini";
  process.env.VIEWER_TOKEN = "test-token";
  process.env.QA_STORE_PATH = path.join(os.tmpdir(), `ih-qa-openai-${process.pid}.jsonl`);
  server = require("../server");
  const { port } = await server.startListening(0, "127.0.0.1");
  baseUrl = `http://127.0.0.1:${port}`;
});

test.beforeEach(() => {
  fakeReplies[ANALYZE].length = 0;
  fakeReplies[IMPROVE].length = 0;
  fakeReplies[EXPLAIN].length = 0;
});

// These run first, before any analysis exists or any frame is shared.
test("explain before any analysis answers 400", async () => {
  const { status, body } = await explain();
  assert.equal(status, 400);
  assert.match(body.error, /No analysis to explain/);
});

test("analyze-screen before any frame is shared answers a retryable 503", async () => {
  const { status } = await analyzeScreen();
  assert.equal(status, 503);
});

test("analyze-screen before any frame is shared says how to start sharing", async () => {
  const { body } = await analyzeScreen();
  assert.match(body.error, /broadcast/);
});

test.after(async () => {
  await new Promise((resolve) => server.httpServer.close(resolve));
  await new Promise((resolve) => fakeOpenAI.close(resolve));
  fs.rmSync(process.env.QA_STORE_PATH, { force: true });
});

test("analyze sends the contract default model when OPENAI_MODEL is a retired default", async () => {
  replyWith(ANALYZE, analysisJSON({ summary: "s", question: "Two sum" }));
  await analyze();
  assert.equal(fakeRequests.at(-1).model, contract.defaultModel);
});

test("analyze sends the contract system prompt", async () => {
  replyWith(ANALYZE, analysisJSON({ summary: "s", question: "Two sum" }));
  await analyze();
  assert.equal(fakeRequests.at(-1).input[0].content, contract.systemPrompt);
});

test("analyze requests the strict schema with field descriptions", async () => {
  replyWith(ANALYZE, analysisJSON({ summary: "s", question: "Two sum" }));
  await analyze();
  const schema = fakeRequests.at(-1).text.format.schema;
  assert.equal(schema.properties.codeSnippet.description, contract.fields.find((f) => f.key === "codeSnippet").description);
});

test("analyze strips markdown fences from the returned code", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum", codeSnippet: "```java\nreturn new int[0];\n```" }));
  const { body } = await analyze();
  assert.equal(body.codeSnippet, "return new int[0];");
});

test("analyze surfaces an OpenAI error as JSON 500", async () => {
  replyWith(ANALYZE, "Invalid schema", { status: 400 });
  const { status, body } = await analyze();
  assert.equal(status, 500);
  assert.equal(body.error, "Failed to analyze screenshot.");
});

test("improve sends the improve prompt built from the current analysis", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum", codeSnippet: "v1" }));
  await analyze();
  replyWith(IMPROVE, analysisJSON({ question: "Two sum", codeSnippet: "v2" }));
  await improve();
  assert.match(fakeRequests.at(-1).input[1].content[0].text, /^Current codeSnippet: v1$/m);
});

test("improve uses the model's question when it provides one", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum" }));
  await analyze();
  replyWith(IMPROVE, analysisJSON({ question: "Two sum (indices, exactly one answer)" }));
  const { body } = await improve();
  assert.equal(body.question, "Two sum (indices, exactly one answer)");
});

test("improve keeps the original question when the model leaves it empty", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum" }));
  await analyze();
  replyWith(IMPROVE, analysisJSON({ summary: "better", question: "" }));
  const { body } = await improve();
  assert.equal(body.question, "Two sum");
});

test("improve falls back to the summary when both questions are empty", async () => {
  // Analyze already fills an empty question from the summary, so both are empty only when the summary is too.
  replyWith(ANALYZE, analysisJSON({ summary: "", question: "" }));
  await analyze();
  replyWith(IMPROVE, analysisJSON({ summary: "better", question: "" }));
  const { body } = await improve();
  assert.equal(body.question, "better");
});

test("improve keeps the previous code when the model output is not JSON", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum", codeSnippet: "keep me" }));
  await analyze();
  replyWith(IMPROVE, "not json at all");
  const { body } = await improve();
  assert.equal(body.codeSnippet, "keep me");
});

test("analysis responses carry no raw model payload", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum" }));
  const analyzed = (await analyze()).body;
  replyWith(IMPROVE, "not json");
  const improved = (await improve()).body;
  assert.equal(analyzed.raw, undefined);
  assert.equal(improved.raw, undefined);
});

test("improve finishing after a newer analyze does not replace the live analysis", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Old problem" }));
  const old = (await analyze()).body;
  replyWith(IMPROVE, analysisJSON({ question: "Old problem", codeSnippet: "improved" }), { delayMs: 300 });
  const pendingImprove = improve();
  await new Promise((resolve) => setTimeout(resolve, 50));
  replyWith(ANALYZE, analysisJSON({ question: "New problem" }));
  const newer = (await analyze()).body;
  const improved = (await pendingImprove).body;

  assert.equal(improved.id, old.id);
  assert.equal((await latest()).id, newer.id);
});

test("improve finishing after a newer analyze still updates the old question's saved answer", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Old problem 2" }));
  const old = (await analyze()).body;
  replyWith(IMPROVE, analysisJSON({ question: "Old problem 2", codeSnippet: "improved later" }), { delayMs: 300 });
  const pendingImprove = improve();
  await new Promise((resolve) => setTimeout(resolve, 50));
  replyWith(ANALYZE, analysisJSON({ question: "New problem 2" }));
  await analyze();
  await pendingImprove;

  const row = (await qaItems()).find((item) => item.id === old.id);
  assert.equal(row.a, "improved later");
});

test("analyze without a question sends exactly the default prompt", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum" }));
  await analyze();
  assert.equal(userText(fakeRequests.at(-1)), contract.defaultAnalyzePrompt.join("\n"));
});

test("analyze with a question sends it after the default prompt", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum" }));
  await analyze({ question: "why a hash map?" });
  assert.match(userText(fakeRequests.at(-1)), /\nQuestion: why a hash map\?$/);
});

test("analyze-screen sends the latest shared frame as a JPEG image", async () => {
  const frame = Buffer.from([0xff, 0xd8, 0xff, 42]);
  await shareFrame(frame);
  replyWith(ANALYZE, analysisJSON({ question: "From the screen" }));
  await analyzeScreen();
  const image = fakeRequests.at(-1).input[1].content.find((part) => part.type === "input_image");
  assert.equal(image.image_url, `data:image/jpeg;base64,${frame.toString("base64")}`);
});

test("analyze-screen makes its result the live analysis", async () => {
  await shareFrame(Buffer.from([0xff, 0xd8, 1]));
  replyWith(ANALYZE, analysisJSON({ question: "Live screen problem" }));
  const { body } = await analyzeScreen();
  assert.equal((await latest()).id, body.id);
});

test("analyze-screen with a question sends it in the prompt", async () => {
  await shareFrame(Buffer.from([0xff, 0xd8, 2]));
  replyWith(ANALYZE, analysisJSON({ question: "Q" }));
  await analyzeScreen({ question: "what does line 3 do?" });
  assert.match(userText(fakeRequests.at(-1)), /\nQuestion: what does line 3 do\?$/);
});

test("explain sends the contract explain system prompt", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum", codeSnippet: "return 1" }));
  await analyze();
  replyWith(EXPLAIN, "1. The idea: ...");
  await explain();
  assert.equal(fakeRequests.at(-1).input[0].content, contract.explainSystemPrompt);
});

test("explain asks for plain text, not the analysis schema", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum" }));
  await analyze();
  replyWith(EXPLAIN, "1. The idea: ...");
  await explain();
  assert.equal(fakeRequests.at(-1).text, undefined);
});

test("explain sends the current code in the explain prompt", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum", codeSnippet: "return 42" }));
  await analyze();
  replyWith(EXPLAIN, "1. The idea: ...");
  await explain();
  assert.match(userText(fakeRequests.at(-1)), /^Current codeSnippet: return 42$/m);
});

test("explain returns the trimmed explanation with the analysis id", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum" }));
  const analyzed = (await analyze()).body;
  replyWith(EXPLAIN, "  1. The idea: use a map.  \n");
  const { body } = await explain();
  assert.deepEqual(body, { id: analyzed.id, explanation: "1. The idea: use a map." });
});

test("explain answers 502 when the model returns empty text", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum" }));
  await analyze();
  replyWith(EXPLAIN, "   ");
  const { status } = await explain();
  assert.equal(status, 502);
});

test("explain surfaces an OpenAI error as JSON 500", async () => {
  replyWith(ANALYZE, analysisJSON({ question: "Two sum" }));
  await analyze();
  replyWith(EXPLAIN, "boom", { status: 400 });
  const { status, body } = await explain();
  assert.equal(status, 500);
  assert.equal(body.error, "Failed to explain solution.");
});

// The OpenAI SDK retries 408/429/5xx and dropped connections itself (maxRetries 2, with backoff).
test("analyze still succeeds when OpenAI answers 503 once", async () => {
  replyWith(ANALYZE, "overloaded", { status: 503 });
  replyWith(ANALYZE, analysisJSON({ question: "After a hiccup" }));
  const { status, body } = await analyze();
  assert.equal(status, 200);
  assert.equal(body.question, "After a hiccup");
});

test("analyze does not retry a permanent OpenAI 400", async () => {
  const before = fakeRequests.length;
  replyWith(ANALYZE, "bad request", { status: 400 });
  const { status } = await analyze();
  assert.equal(status, 500);
  assert.equal(fakeRequests.length - before, 1);
});
