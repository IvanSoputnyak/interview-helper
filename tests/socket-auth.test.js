// Socket.io viewer auth, exercised over the raw Engine.IO v4 polling transport
// (handshake → CONNECT packet with auth → poll), so no socket.io-client dependency is needed.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");

process.env.VIEWER_TOKEN = "test-token";
process.env.OPENAI_API_KEY = "";
process.env.QA_STORE_PATH = path.join(os.tmpdir(), `ih-qa-socket-${process.pid}.jsonl`);

const { startListening, httpServer } = require("../server");

const PACKET_SEPARATOR = "\x1e";
const SOCKET_CONNECT = "40";
const SOCKET_CONNECT_ERROR = "44";
const SOCKET_EVENT = "42";
let baseUrl = "";

function pollingUrl(sid) {
  const sidParam = sid ? `&sid=${sid}` : "";
  return `${baseUrl}/socket.io/?EIO=4&transport=polling${sidParam}`;
}

async function openSession() {
  const body = await (await fetch(pollingUrl())).text();
  return JSON.parse(body.slice(1)).sid;
}

/** Sends the Socket.IO CONNECT packet (optionally with auth) and returns the packets the server answers with. */
async function connectWith(auth) {
  const sid = await openSession();
  const connectPacket = auth === undefined ? SOCKET_CONNECT : `${SOCKET_CONNECT}${JSON.stringify(auth)}`;
  await fetch(pollingUrl(sid), {
    method: "POST",
    headers: { "content-type": "text/plain;charset=UTF-8" },
    body: connectPacket,
  });
  const reply = await (await fetch(pollingUrl(sid))).text();
  return reply.split(PACKET_SEPARATOR);
}

function eventNames(packets) {
  return packets
    .filter((packet) => packet.startsWith(SOCKET_EVENT))
    .map((packet) => JSON.parse(packet.slice(SOCKET_EVENT.length))[0]);
}

test.before(async () => {
  const { port } = await startListening(0, "127.0.0.1");
  baseUrl = `http://127.0.0.1:${port}`;
});

test.after(async () => {
  await new Promise((resolve) => httpServer.close(resolve));
  fs.rmSync(process.env.QA_STORE_PATH, { force: true });
});

test("socket with the viewer token is accepted", async () => {
  const packets = await connectWith({ token: "test-token" });
  assert.ok(packets.some((packet) => packet.startsWith(SOCKET_CONNECT)));
});

test("socket with the viewer token immediately receives the latest analysis and saved Q&A", async () => {
  const packets = await connectWith({ token: "test-token" });
  assert.deepEqual(eventNames(packets), ["analysis:update", "qa:list"]);
});

test("socket with a wrong token is rejected as unauthorized", async () => {
  const packets = await connectWith({ token: "wrong-token" });
  assert.ok(packets.some((packet) => packet.startsWith(SOCKET_CONNECT_ERROR) && packet.includes("unauthorized")));
});

test("socket with a wrong token receives no data", async () => {
  const packets = await connectWith({ token: "wrong-token" });
  assert.deepEqual(eventNames(packets), []);
});

test("socket without any token is rejected as unauthorized", async () => {
  const packets = await connectWith(undefined);
  assert.ok(packets.some((packet) => packet.startsWith(SOCKET_CONNECT_ERROR) && packet.includes("unauthorized")));
});
