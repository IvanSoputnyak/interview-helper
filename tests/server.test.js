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

const { startListening, httpServer, toQA, parseModelOutput } = require("../server");

const AUTH = { "x-viewer-token": "test-token" };
let baseUrl = "";

function screenshotForm(type = "image/png", bytes = [137, 80, 78, 71]) {
  const form = new FormData();
  form.append("prompt", "test prompt");
  form.append("screenshot", new Blob([new Uint8Array(bytes)], { type }), "capture.png");
  return form;
}

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

test("viewer page rejects missing token and serves with valid token", async () => {
  const unauthorized = await fetch(`${baseUrl}/viewer`);
  assert.equal(unauthorized.status, 401);

  const authorized = await fetch(`${baseUrl}/viewer?token=test-token`);
  assert.equal(authorized.status, 200);
});

test("viewer.html static path cannot bypass the token check", async () => {
  const response = await fetch(`${baseUrl}/viewer.html`);
  assert.equal(response.status, 401);
});

test("wrong token of a different length is rejected", async () => {
  const response = await fetch(`${baseUrl}/api/latest`, {
    headers: { "x-viewer-token": "nope" },
  });
  assert.equal(response.status, 401);
});

test("latest and history reject missing token and return data with token", async () => {
  const latestUnauthorized = await fetch(`${baseUrl}/api/latest`);
  assert.equal(latestUnauthorized.status, 401);

  const latestAuthorized = await fetch(`${baseUrl}/api/latest`, { headers: AUTH });
  assert.equal(latestAuthorized.status, 200);

  const historyAuthorized = await fetch(`${baseUrl}/api/history`, { headers: AUTH });
  assert.equal(historyAuthorized.status, 200);
  const payload = await historyAuthorized.json();
  assert.ok(Array.isArray(payload.items));
});

test("toQA prefers question and code snippet", () => {
  const row = toQA({
    id: "x",
    createdAt: "2100-01-01T00:00:00.000Z",
    question: "Find duplicate",
    summary: "summary",
    codeSnippet: "return 1;",
    solution: "use set",
  });
  assert.deepEqual(row, {
    id: "x",
    at: "2100-01-01T00:00:00.000Z",
    q: "Find duplicate",
    a: "return 1;",
  });
});

test("toQA falls back to summary and solution when question and code are empty", () => {
  const row = toQA({ id: "y", createdAt: "t", summary: "sum", solution: "sol" });
  assert.equal(row.q, "sum");
  assert.equal(row.a, "sol");
});

test("parseModelOutput returns parsed JSON or keeps fallback fields on bad JSON", () => {
  assert.deepEqual(parseModelOutput('{"summary":"ok"}'), { summary: "ok" });
  const broken = parseModelOutput("not json", { question: "Q" });
  assert.equal(broken.summary, "not json");
  assert.equal(broken.question, "Q");
  assert.equal(parseModelOutput("").summary, "Could not parse model output.");
});

test("analyze without token is rejected before upload is processed", async () => {
  const response = await fetch(`${baseUrl}/api/analyze`, {
    method: "POST",
    body: screenshotForm(),
  });
  assert.equal(response.status, 401);
});

test("analyze without api key returns 400 and does not persist a QA row", async () => {
  const before = await (await fetch(`${baseUrl}/api/qa`, { headers: AUTH })).json();

  const response = await fetch(`${baseUrl}/api/analyze`, {
    method: "POST",
    headers: AUTH,
    body: screenshotForm(),
  });
  assert.equal(response.status, 400);
  const payload = await response.json();
  assert.match(payload.error, /OPENAI_API_KEY is missing/i);

  const after = await (await fetch(`${baseUrl}/api/qa`, { headers: AUTH })).json();
  assert.equal(after.items.length, before.items.length);
});

test("analyze rejects a missing screenshot with JSON 400", async () => {
  const response = await fetch(`${baseUrl}/api/analyze`, {
    method: "POST",
    headers: AUTH,
    body: new FormData(),
  });
  assert.equal(response.status, 400);
  assert.match((await response.json()).error, /Missing screenshot/);
});

test("analyze rejects non-image uploads with JSON 400", async () => {
  const response = await fetch(`${baseUrl}/api/analyze`, {
    method: "POST",
    headers: AUTH,
    body: screenshotForm("text/html", [60, 104, 49, 62]),
  });
  assert.equal(response.status, 400);
  assert.match((await response.json()).error, /PNG, JPEG/);
});

test("analyze rejects oversized uploads with JSON 413", async () => {
  const response = await fetch(`${baseUrl}/api/analyze`, {
    method: "POST",
    headers: AUTH,
    body: screenshotForm("image/png", new Uint8Array(8 * 1024 * 1024 + 1)),
  });
  assert.equal(response.status, 413);
  assert.match((await response.json()).error, /exceeds/);
});

test("qa route requires token", async () => {
  const unauthorized = await fetch(`${baseUrl}/api/qa`);
  assert.equal(unauthorized.status, 401);
});

test("improve requires viewer token", async () => {
  const unauthorized = await fetch(`${baseUrl}/api/improve`, { method: "POST" });
  assert.equal(unauthorized.status, 401);
});

test("health reports status without leaking the viewer token", async () => {
  const response = await fetch(`${baseUrl}/api/health`);
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.ok, true);
  assert.equal(payload.viewerToken, undefined);
  assert.equal(payload.port, Number(new URL(baseUrl).port));
});

test("improve returns clear error when api key missing", async () => {
  const response = await fetch(`${baseUrl}/api/improve`, {
    method: "POST",
    headers: AUTH,
  });
  assert.equal(response.status, 400);
  const payload = await response.json();
  assert.match(payload.error, /OPENAI_API_KEY is missing/i);
});
