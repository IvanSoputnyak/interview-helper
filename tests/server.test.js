const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");

process.env.VIEWER_TOKEN = "test-token";
process.env.OPENAI_API_KEY = "";
process.env.QA_STORE_PATH = path.join(
  os.tmpdir(),
  `ih-qa-api-${process.pid}.jsonl`,
);

const { startListening, httpServer, toQA } = require("../server");

let baseUrl = "";

test.before(async () => {
  const { port } = await startListening(0, "127.0.0.1");
  baseUrl = `http://127.0.0.1:${port}`;
});

test.after(async () => {
  await new Promise((resolve) => httpServer.close(resolve));
  try {
    fs.unlinkSync(process.env.QA_STORE_PATH);
  } catch {
    // ignore
  }
});

test("viewer route requires token", async () => {
  const unauthorized = await fetch(`${baseUrl}/viewer`);
  assert.equal(unauthorized.status, 401);

  const authorized = await fetch(`${baseUrl}/viewer?token=test-token`);
  assert.equal(authorized.status, 200);
});

test("latest/history require token", async () => {
  const latestUnauthorized = await fetch(`${baseUrl}/api/latest`);
  assert.equal(latestUnauthorized.status, 401);

  const latestAuthorized = await fetch(`${baseUrl}/api/latest`, {
    headers: { "x-viewer-token": "test-token" },
  });
  assert.equal(latestAuthorized.status, 200);

  const historyAuthorized = await fetch(`${baseUrl}/api/history`, {
    headers: { "x-viewer-token": "test-token" },
  });
  assert.equal(historyAuthorized.status, 200);
  const payload = await historyAuthorized.json();
  assert.ok(Array.isArray(payload.items));
});

test("toQA keeps only q and a", () => {
  const row = toQA({
    id: "x",
    createdAt: "2020-01-01T00:00:00.000Z",
    question: "Find duplicate",
    summary: "summary",
    codeSnippet: "return 1;",
    solution: "use set",
  });
  assert.deepEqual(row, {
    id: "x",
    at: "2020-01-01T00:00:00.000Z",
    q: "Find duplicate",
    a: "return 1;",
  });
});

test("analyze writes history entry when no api key", async () => {
  const form = new FormData();
  form.append("prompt", "test prompt");
  form.append(
    "screenshot",
    new Blob([new Uint8Array([137, 80, 78, 71])], { type: "image/png" }),
    "capture.png",
  );

  const analyzeRes = await fetch(`${baseUrl}/api/analyze`, {
    method: "POST",
    body: form,
  });
  assert.equal(analyzeRes.status, 200);
  const analyzePayload = await analyzeRes.json();
  assert.equal(typeof analyzePayload.codeSnippet, "string");
  assert.equal(typeof analyzePayload.explanation, "string");
  assert.equal(typeof analyzePayload.algorithmWhy, "string");
  assert.equal(typeof analyzePayload.timeComplexity, "string");
  assert.equal(typeof analyzePayload.spaceComplexity, "string");

  const historyRes = await fetch(`${baseUrl}/api/history`, {
    headers: { "x-viewer-token": "test-token" },
  });
  const history = await historyRes.json();
  assert.ok(history.items.length >= 1);
  assert.equal(history.items[0].summary, "OPENAI_API_KEY is missing.");

  const qaRes = await fetch(`${baseUrl}/api/qa`, {
    headers: { "x-viewer-token": "test-token" },
  });
  assert.equal(qaRes.status, 200);
  const qa = await qaRes.json();
  assert.ok(qa.items.length >= 1);
  assert.equal(typeof qa.items[0].q, "string");
  assert.equal(typeof qa.items[0].a, "string");
});

test("qa route requires token", async () => {
  const unauthorized = await fetch(`${baseUrl}/api/qa`);
  assert.equal(unauthorized.status, 401);
});

test("improve requires viewer token", async () => {
  const unauthorized = await fetch(`${baseUrl}/api/improve`, {
    method: "POST",
  });
  assert.equal(unauthorized.status, 401);
});

test("health exposes viewer token to loopback clients", async () => {
  const response = await fetch(`${baseUrl}/api/health`);
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.ok, true);
  assert.equal(typeof payload.viewerToken, "string");
  assert.ok(payload.viewerToken.length > 0);
});

test("improve returns clear error when api key missing", async () => {
  const response = await fetch(`${baseUrl}/api/improve`, {
    method: "POST",
    headers: { "x-viewer-token": "test-token" },
  });
  assert.equal(response.status, 400);
  const payload = await response.json();
  assert.match(payload.error, /OPENAI_API_KEY is missing/i);
});
