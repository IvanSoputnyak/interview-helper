const test = require("node:test");
const assert = require("node:assert/strict");

process.env.OPENAI_API_KEY = "";

const { startListening, httpServer, parseModelOutput } = require("../server");
const { lanAddresses } = require("../lib/local-network");

/** This machine's Wi-Fi/Ethernet address: requests through it look like another device on the network. */
const [LAN_ADDRESS] = lanAddresses();
const NEEDS_LAN = { skip: !LAN_ADDRESS && "no Wi-Fi/Ethernet address on this machine" };
let baseUrl = "";
let phoneUrl = "";

function screenshotForm(type = "image/png", bytes = [137, 80, 78, 71]) {
  const form = new FormData();
  form.append("prompt", "test prompt");
  form.append("screenshot", new Blob([new Uint8Array(bytes)], { type }), "capture.png");
  return form;
}

test.before(async () => {
  const { port } = await startListening(0, "0.0.0.0");
  baseUrl = `http://127.0.0.1:${port}`;
  phoneUrl = `http://${LAN_ADDRESS}:${port}`;
});

test.after(async () => {
  await new Promise((resolve) => httpServer.close(resolve));
});

test("the home page is the phone viewer", async () => {
  const response = await fetch(`${baseUrl}/`);
  assert.match(await response.text(), /Capture &amp; analyze/);
});

test("a phone on the network opens the viewer with no token", NEEDS_LAN, async () => {
  assert.equal((await fetch(`${phoneUrl}/`)).status, 200);
});

test("latest analysis needs no token", async () => {
  assert.equal((await fetch(`${baseUrl}/api/latest`)).status, 200);
});

test("parseModelOutput returns parsed JSON or keeps fallback fields on bad JSON", () => {
  assert.deepEqual(parseModelOutput('{"summary":"ok"}'), { summary: "ok" });
  const broken = parseModelOutput("not json", { question: "Q" });
  assert.equal(broken.summary, "not json");
  assert.equal(broken.question, "Q");
  assert.equal(parseModelOutput("").summary, "Could not parse model output.");
});

test("analyze without api key returns 400", async () => {
  const response = await fetch(`${baseUrl}/api/analyze`, {
    method: "POST",
    body: screenshotForm(),
  });
  assert.equal(response.status, 400);
  const payload = await response.json();
  assert.match(payload.error, /OPENAI_API_KEY is missing/i);
});

test("analyze rejects a missing screenshot with JSON 400", async () => {
  const response = await fetch(`${baseUrl}/api/analyze`, {
    method: "POST",
    body: new FormData(),
  });
  assert.equal(response.status, 400);
  assert.match((await response.json()).error, /Missing screenshot/);
});

test("analyze rejects non-image uploads with JSON 400", async () => {
  const response = await fetch(`${baseUrl}/api/analyze`, {
    method: "POST",
    body: screenshotForm("text/html", [60, 104, 49, 62]),
  });
  assert.equal(response.status, 400);
  assert.match((await response.json()).error, /PNG, JPEG/);
});

test("analyze rejects oversized uploads with JSON 413", async () => {
  const response = await fetch(`${baseUrl}/api/analyze`, {
    method: "POST",
    body: screenshotForm("image/png", new Uint8Array(8 * 1024 * 1024 + 1)),
  });
  assert.equal(response.status, 413);
  assert.match((await response.json()).error, /exceeds/);
});

test("health reports the port the server is bound to", async () => {
  const response = await fetch(`${baseUrl}/api/health`);
  const payload = await response.json();
  assert.deepEqual([payload.ok, payload.port], [true, Number(new URL(baseUrl).port)]);
});

test("improve returns clear error when api key missing", async () => {
  const response = await fetch(`${baseUrl}/api/improve`, { method: "POST" });
  assert.equal(response.status, 400);
  const payload = await response.json();
  assert.match(payload.error, /OPENAI_API_KEY is missing/i);
});

test("the viewer's syntax highlighter and its theme are served locally", async () => {
  const script = await fetch(`${baseUrl}/vendor/highlight/highlight.min.js`);
  const theme = await fetch(`${baseUrl}/vendor/highlight/styles/vs2015.min.css`);
  assert.deepEqual([script.status, theme.status], [200, 200]);
});

test("analyze-screen returns a clear error when the api key is missing", async () => {
  const response = await fetch(`${baseUrl}/api/analyze-screen`, { method: "POST" });
  assert.equal(response.status, 400);
  assert.match((await response.json()).error, /OPENAI_API_KEY is missing/);
});

test("explain returns a clear error when the api key is missing", async () => {
  const response = await fetch(`${baseUrl}/api/explain`, { method: "POST" });
  assert.equal(response.status, 400);
  assert.match((await response.json()).error, /OPENAI_API_KEY is missing/);
});

test("the share page opens on this Mac", async () => {
  assert.equal((await fetch(`${baseUrl}/broadcast`)).status, 200);
});

test("the share page is refused to another device", NEEDS_LAN, async () => {
  assert.equal((await fetch(`${phoneUrl}/broadcast`)).status, 403);
});

test("broadcast.html cannot bypass the this-Mac check", NEEDS_LAN, async () => {
  assert.equal((await fetch(`${phoneUrl}/broadcast.html`)).status, 403);
});

test("screenshot upload is refused to another device", NEEDS_LAN, async () => {
  const response = await fetch(`${phoneUrl}/api/analyze`, { method: "POST", body: screenshotForm() });
  assert.equal(response.status, 403);
});
