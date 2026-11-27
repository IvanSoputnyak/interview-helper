// Guards from helpers/block-real-openai.js, which package.json preloads into every test file.
const test = require("node:test");
const assert = require("node:assert/strict");

test("the real OpenAI key from .env is not visible to tests", () => {
  assert.equal(process.env.OPENAI_API_KEY, "");
});

test("a request to the real OpenAI API is refused without touching the network", async () => {
  await assert.rejects(fetch("https://api.openai.com/v1/models"), /blocked in tests/);
});

test("an OpenAI client created with a key but no fake server cannot reach the real API", async () => {
  const OpenAI = require("openai");
  const client = new OpenAI({ apiKey: "would-be-real-key", maxRetries: 0 });
  await assert.rejects(client.models.list(), /Connection error|blocked in tests/);
});

test("requests to other hosts, like the local fake server, still work", async () => {
  const http = require("http");
  const server = http.createServer((_req, res) => res.end("ok"));
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/`);
    assert.equal(await response.text(), "ok");
  } finally {
    server.close();
  }
});
