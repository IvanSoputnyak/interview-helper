// Drives /api/analyze and /api/improve end to end against a fake OpenAI Responses endpoint
// (the SDK honours OPENAI_BASE_URL), so model replies, races, and fallbacks are exercised for real.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");

const contract = require("../shared/analysis-contract.json");

const AUTH = { "x-viewer-token": "test-token" };
const fakeReplies = [];
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

/** Queue the next fake model reply: output text, optional delay, optional HTTP status. */
function replyWith(text, { delayMs = 0, status = 200 } = {}) {
  fakeReplies.push({ text, delayMs, status });
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
      fakeRequests.push(JSON.parse(raw));
      const reply = fakeReplies.shift() || { text: analysisJSON({ summary: "default" }), delayMs: 0, status: 200 };
      setTimeout(() => {
        res.writeHead(reply.status, { "content-type": "application/json" });
        const body = reply.status === 200 ? responsesBody(reply.text) : { error: { message: reply.text } };
        res.end(JSON.stringify(body));
      }, reply.delayMs);
    });
  });
  return new Promise((resolve) => fakeOpenAI.listen(0, "127.0.0.1", resolve));
}

async function analyze() {
  const form = new FormData();
  form.append("screenshot", new Blob([new Uint8Array([137, 80, 78, 71])], { type: "image/png" }), "c.png");
  const response = await fetch(`${baseUrl}/api/analyze`, { method: "POST", headers: AUTH, body: form });
  return { status: response.status, body: await response.json() };
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

test.after(async () => {
  await new Promise((resolve) => server.httpServer.close(resolve));
  await new Promise((resolve) => fakeOpenAI.close(resolve));
  fs.rmSync(process.env.QA_STORE_PATH, { force: true });
});

test("analyze sends the contract default model when OPENAI_MODEL is a retired default", async () => {
  replyWith(analysisJSON({ summary: "s", question: "Two sum" }));
  await analyze();
  assert.equal(fakeRequests.at(-1).model, contract.defaultModel);
});

test("analyze sends the contract system prompt", async () => {
  replyWith(analysisJSON({ summary: "s", question: "Two sum" }));
  await analyze();
  assert.equal(fakeRequests.at(-1).input[0].content, contract.systemPrompt);
});

test("analyze requests the strict schema with field descriptions", async () => {
  replyWith(analysisJSON({ summary: "s", question: "Two sum" }));
  await analyze();
  const schema = fakeRequests.at(-1).text.format.schema;
  assert.equal(schema.properties.codeSnippet.description, contract.fields.find((f) => f.key === "codeSnippet").description);
});

test("analyze strips markdown fences from the returned code", async () => {
  replyWith(analysisJSON({ question: "Two sum", codeSnippet: "```java\nreturn new int[0];\n```" }));
  const { body } = await analyze();
  assert.equal(body.codeSnippet, "return new int[0];");
});

test("analyze surfaces an OpenAI error as JSON 500", async () => {
  replyWith("Invalid schema", { status: 400 });
  const { status, body } = await analyze();
  assert.equal(status, 500);
  assert.equal(body.error, "Failed to analyze screenshot.");
});

test("improve sends the improve prompt built from the current analysis", async () => {
  replyWith(analysisJSON({ question: "Two sum", codeSnippet: "v1" }));
  await analyze();
  replyWith(analysisJSON({ question: "Two sum", codeSnippet: "v2" }));
  await improve();
  assert.match(fakeRequests.at(-1).input[1].content[0].text, /^Current codeSnippet: v1$/m);
});

test("improve uses the model's question when it provides one", async () => {
  replyWith(analysisJSON({ question: "Two sum" }));
  await analyze();
  replyWith(analysisJSON({ question: "Two sum (indices, exactly one answer)" }));
  const { body } = await improve();
  assert.equal(body.question, "Two sum (indices, exactly one answer)");
});

test("improve keeps the original question when the model leaves it empty", async () => {
  replyWith(analysisJSON({ question: "Two sum" }));
  await analyze();
  replyWith(analysisJSON({ summary: "better", question: "" }));
  const { body } = await improve();
  assert.equal(body.question, "Two sum");
});

test("improve keeps the previous code when the model output is not JSON", async () => {
  replyWith(analysisJSON({ question: "Two sum", codeSnippet: "keep me" }));
  await analyze();
  replyWith("not json at all");
  const { body } = await improve();
  assert.equal(body.codeSnippet, "keep me");
});

test("improve fallback does not nest the previous raw payload", async () => {
  replyWith(analysisJSON({ question: "Two sum" }));
  await analyze();
  replyWith("not json");
  await improve();
  replyWith("still not json");
  const { body } = await improve();
  assert.equal(body.raw.raw, undefined);
});

test("improve finishing after a newer analyze does not replace the live analysis", async () => {
  replyWith(analysisJSON({ question: "Old problem" }));
  const old = (await analyze()).body;
  replyWith(analysisJSON({ question: "Old problem", codeSnippet: "improved" }), { delayMs: 300 });
  const pendingImprove = improve();
  await new Promise((resolve) => setTimeout(resolve, 50));
  replyWith(analysisJSON({ question: "New problem" }));
  const newer = (await analyze()).body;
  const improved = (await pendingImprove).body;

  assert.equal(improved.id, old.id);
  assert.equal((await latest()).id, newer.id);
});

test("improve finishing after a newer analyze still updates the old question's saved answer", async () => {
  replyWith(analysisJSON({ question: "Old problem 2" }));
  const old = (await analyze()).body;
  replyWith(analysisJSON({ question: "Old problem 2", codeSnippet: "improved later" }), { delayMs: 300 });
  const pendingImprove = improve();
  await new Promise((resolve) => setTimeout(resolve, 50));
  replyWith(analysisJSON({ question: "New problem 2" }));
  await analyze();
  await pendingImprove;

  const row = (await qaItems()).find((item) => item.id === old.id);
  assert.equal(row.a, "improved later");
});
