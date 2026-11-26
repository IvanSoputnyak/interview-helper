// Socket.io viewer auth and shared-screen frames, exercised over the raw Engine.IO v4 polling transport
// (see helpers/socket-polling.js), so no socket.io-client dependency is needed.
const test = require("node:test");
const assert = require("node:assert/strict");

process.env.VIEWER_TOKEN = "test-token";
process.env.OPENAI_API_KEY = "";

const { startListening, httpServer } = require("../server");
const {
  SOCKET_CONNECT,
  SOCKET_CONNECT_ERROR,
  binaryAttachment,
  createPollingClient,
  eventNames,
} = require("./helpers/socket-polling");

const AUTH = { token: "test-token" };
const MAX_FRAME_BYTES = 3 * 1024 * 1024;
let client;

/** Compares by size first: a deepEqual failure on a multi-MB buffer spends minutes rendering the diff. */
function assertSameFrame(received, expected) {
  assert.equal(received.length, expected.length);
  assert.ok(received.equals(expected));
}

test.before(async () => {
  const { port } = await startListening(0, "127.0.0.1");
  client = createPollingClient(`http://127.0.0.1:${port}`);
});

test.after(async () => {
  await new Promise((resolve) => httpServer.close(resolve));
});

test("socket with the viewer token is accepted", async () => {
  const { packets } = await client.connect(AUTH);
  assert.ok(packets.some((packet) => packet.startsWith(SOCKET_CONNECT)));
});

// Runs before any frame is shared, so the viewer is told nothing is being shared.
test("socket with the viewer token immediately receives the latest analysis and screen:stop", async () => {
  const { packets } = await client.connect(AUTH);
  assert.deepEqual(eventNames(packets), ["analysis:update", "screen:stop"]);
});

test("socket with a wrong token is rejected as unauthorized", async () => {
  const { packets } = await client.connect({ token: "wrong-token" });
  assert.ok(packets.some((packet) => packet.startsWith(SOCKET_CONNECT_ERROR) && packet.includes("unauthorized")));
});

test("socket with a wrong token receives no data", async () => {
  const { packets } = await client.connect({ token: "wrong-token" });
  assert.deepEqual(eventNames(packets), []);
});

test("socket without any token is rejected as unauthorized", async () => {
  const { packets } = await client.connect(undefined);
  assert.ok(packets.some((packet) => packet.startsWith(SOCKET_CONNECT_ERROR) && packet.includes("unauthorized")));
});

test("a frame shared by one socket is relayed to an already connected viewer", async () => {
  const viewer = await client.connect(AUTH);
  const broadcaster = await client.connect(AUTH);
  const frame = Buffer.from([0xff, 0xd8, 1, 2, 3]);

  await client.emitBinary(broadcaster.sid, "screen:frame", frame);

  assert.deepEqual(binaryAttachment(await client.poll(viewer.sid)), frame);
});

test("a viewer that connects after a frame was shared receives that frame at once", async () => {
  const broadcaster = await client.connect(AUTH);
  const frame = Buffer.from([0xff, 0xd8, 9, 9]);
  await client.emitBinary(broadcaster.sid, "screen:frame", frame);

  const { packets } = await client.connect(AUTH);

  assert.deepEqual(binaryAttachment(packets), frame);
});

test("a non-binary frame payload is ignored and the last valid frame is kept", async () => {
  const broadcaster = await client.connect(AUTH);
  const frame = Buffer.from([0xff, 0xd8, 7]);
  await client.emitBinary(broadcaster.sid, "screen:frame", frame);

  await client.emit(broadcaster.sid, "screen:frame", "not an image");

  assertSameFrame(binaryAttachment((await client.connect(AUTH)).packets), frame);
});

test("an oversized frame is ignored and the last valid frame is kept", async () => {
  const broadcaster = await client.connect(AUTH);
  const frame = Buffer.from([0xff, 0xd8, 5]);
  await client.emitBinary(broadcaster.sid, "screen:frame", frame);

  await client.emitBinary(broadcaster.sid, "screen:frame", Buffer.alloc(MAX_FRAME_BYTES + 1));

  assertSameFrame(binaryAttachment((await client.connect(AUTH)).packets), frame);
});

test("a viewer that reconnects is resent the analysis and latest frame", async () => {
  const broadcaster = await client.connect(AUTH);
  await client.emitBinary(broadcaster.sid, "screen:frame", Buffer.from([0xff, 0xd8, 3]));

  const { packets } = await client.connect(AUTH);

  assert.deepEqual(eventNames(packets), ["analysis:update", "screen:frame"]);
});

test("screen:stop from the sharer is relayed to an already connected viewer", async () => {
  const broadcaster = await client.connect(AUTH);
  await client.emitBinary(broadcaster.sid, "screen:frame", Buffer.from([0xff, 0xd8, 4]));
  const viewer = await client.connect(AUTH);

  await client.emit(broadcaster.sid, "screen:stop");

  assert.deepEqual(eventNames(await client.poll(viewer.sid)), ["screen:stop"]);
});

test("a viewer that connects after screen:stop receives no frame", async () => {
  const broadcaster = await client.connect(AUTH);
  await client.emitBinary(broadcaster.sid, "screen:frame", Buffer.from([0xff, 0xd8, 6]));
  await client.emit(broadcaster.sid, "screen:stop");

  const { packets } = await client.connect(AUTH);

  assert.equal(binaryAttachment(packets), null);
});

test("when the sharing socket disconnects its frame is dropped", async () => {
  const broadcaster = await client.connect(AUTH);
  await client.emitBinary(broadcaster.sid, "screen:frame", Buffer.from([0xff, 0xd8, 8]));

  await client.close(broadcaster.sid);

  assert.deepEqual(eventNames((await client.connect(AUTH)).packets), ["analysis:update", "screen:stop"]);
});

test("when a socket other than the sharer disconnects the frame is kept", async () => {
  const broadcaster = await client.connect(AUTH);
  const frame = Buffer.from([0xff, 0xd8, 10]);
  await client.emitBinary(broadcaster.sid, "screen:frame", frame);
  const viewer = await client.connect(AUTH);

  await client.close(viewer.sid);

  assertSameFrame(binaryAttachment((await client.connect(AUTH)).packets), frame);
});
