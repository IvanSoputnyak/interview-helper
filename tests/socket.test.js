// Socket.io viewers and shared-screen frames, exercised over the raw Engine.IO v4 polling transport
// (see helpers/socket-polling.js), so no socket.io-client dependency is needed.
const test = require("node:test");
const assert = require("node:assert/strict");

process.env.OPENAI_API_KEY = "";

const { startListening, httpServer } = require("../server");
const { lanAddresses } = require("../lib/local-network");
const { SOCKET_CONNECT, binaryAttachment, createPollingClient, eventNames } = require("./helpers/socket-polling");

const MAX_FRAME_BYTES = 3 * 1024 * 1024;
/** This machine's Wi-Fi/Ethernet address: connecting through it looks like another device on the network. */
const [LAN_ADDRESS] = lanAddresses();
const NEEDS_LAN = { skip: !LAN_ADDRESS && "no Wi-Fi/Ethernet address on this machine" };
/** Client on this Mac (loopback), like the share page. */
let client;
/** Client arriving over the network, like a phone. */
let phoneClient;

/** Compares by size first: a deepEqual failure on a multi-MB buffer spends minutes rendering the diff. */
function assertSameFrame(received, expected) {
  assert.equal(received.length, expected.length);
  assert.ok(received.equals(expected));
}

test.before(async () => {
  const { port } = await startListening(0, "0.0.0.0");
  client = createPollingClient(`http://127.0.0.1:${port}`);
  phoneClient = LAN_ADDRESS && createPollingClient(`http://${LAN_ADDRESS}:${port}`);
});

test.after(async () => {
  await new Promise((resolve) => httpServer.close(resolve));
});

test("a socket needs no token to connect", async () => {
  const { packets } = await client.connect();
  assert.ok(packets.some((packet) => packet.startsWith(SOCKET_CONNECT)));
});

// Runs before any frame is shared, so the viewer is told nothing is being shared.
test("a new socket immediately receives the latest analysis and screen:stop", async () => {
  const { packets } = await client.connect();
  assert.deepEqual(eventNames(packets), ["analysis:update", "screen:stop"]);
});

test("a phone on the network receives the shared frame", NEEDS_LAN, async () => {
  const broadcaster = await client.connect();
  const frame = Buffer.from([0xff, 0xd8, 11]);
  await client.emitBinary(broadcaster.sid, "screen:frame", frame);

  const { packets } = await phoneClient.connect();

  assertSameFrame(binaryAttachment(packets), frame);
});

test("a frame sent from another device is ignored", NEEDS_LAN, async () => {
  const broadcaster = await client.connect();
  const frame = Buffer.from([0xff, 0xd8, 12]);
  await client.emitBinary(broadcaster.sid, "screen:frame", frame);
  const phone = await phoneClient.connect();

  await phoneClient.emitBinary(phone.sid, "screen:frame", Buffer.from([0xff, 0xd8, 13]));

  assertSameFrame(binaryAttachment((await client.connect()).packets), frame);
});

test("screen:stop from another device does not stop sharing", NEEDS_LAN, async () => {
  const broadcaster = await client.connect();
  const frame = Buffer.from([0xff, 0xd8, 14]);
  await client.emitBinary(broadcaster.sid, "screen:frame", frame);
  const phone = await phoneClient.connect();

  await phoneClient.emit(phone.sid, "screen:stop");

  assertSameFrame(binaryAttachment((await client.connect()).packets), frame);
});

test("a frame shared by one socket is relayed to an already connected viewer", async () => {
  const viewer = await client.connect();
  const broadcaster = await client.connect();
  const frame = Buffer.from([0xff, 0xd8, 1, 2, 3]);

  await client.emitBinary(broadcaster.sid, "screen:frame", frame);

  assert.deepEqual(binaryAttachment(await client.poll(viewer.sid)), frame);
});

test("a viewer that connects after a frame was shared receives that frame at once", async () => {
  const broadcaster = await client.connect();
  const frame = Buffer.from([0xff, 0xd8, 9, 9]);
  await client.emitBinary(broadcaster.sid, "screen:frame", frame);

  const { packets } = await client.connect();

  assert.deepEqual(binaryAttachment(packets), frame);
});

test("a non-binary frame payload is ignored and the last valid frame is kept", async () => {
  const broadcaster = await client.connect();
  const frame = Buffer.from([0xff, 0xd8, 7]);
  await client.emitBinary(broadcaster.sid, "screen:frame", frame);

  await client.emit(broadcaster.sid, "screen:frame", "not an image");

  assertSameFrame(binaryAttachment((await client.connect()).packets), frame);
});

test("an oversized frame is ignored and the last valid frame is kept", async () => {
  const broadcaster = await client.connect();
  const frame = Buffer.from([0xff, 0xd8, 5]);
  await client.emitBinary(broadcaster.sid, "screen:frame", frame);

  await client.emitBinary(broadcaster.sid, "screen:frame", Buffer.alloc(MAX_FRAME_BYTES + 1));

  assertSameFrame(binaryAttachment((await client.connect()).packets), frame);
});

test("a viewer that reconnects is resent the analysis and latest frame", async () => {
  const broadcaster = await client.connect();
  await client.emitBinary(broadcaster.sid, "screen:frame", Buffer.from([0xff, 0xd8, 3]));

  const { packets } = await client.connect();

  assert.deepEqual(eventNames(packets), ["analysis:update", "screen:frame"]);
});

test("screen:stop from the sharer is relayed to an already connected viewer", async () => {
  const broadcaster = await client.connect();
  await client.emitBinary(broadcaster.sid, "screen:frame", Buffer.from([0xff, 0xd8, 4]));
  const viewer = await client.connect();

  await client.emit(broadcaster.sid, "screen:stop");

  assert.deepEqual(eventNames(await client.poll(viewer.sid)), ["screen:stop"]);
});

test("a viewer that connects after screen:stop receives no frame", async () => {
  const broadcaster = await client.connect();
  await client.emitBinary(broadcaster.sid, "screen:frame", Buffer.from([0xff, 0xd8, 6]));
  await client.emit(broadcaster.sid, "screen:stop");

  const { packets } = await client.connect();

  assert.equal(binaryAttachment(packets), null);
});

test("when the sharing socket disconnects its frame is dropped", async () => {
  const broadcaster = await client.connect();
  await client.emitBinary(broadcaster.sid, "screen:frame", Buffer.from([0xff, 0xd8, 8]));

  await client.close(broadcaster.sid);

  assert.deepEqual(eventNames((await client.connect()).packets), ["analysis:update", "screen:stop"]);
});

test("when a socket other than the sharer disconnects the frame is kept", async () => {
  const broadcaster = await client.connect();
  const frame = Buffer.from([0xff, 0xd8, 10]);
  await client.emitBinary(broadcaster.sid, "screen:frame", frame);
  const viewer = await client.connect();

  await client.close(viewer.sid);

  assertSameFrame(binaryAttachment((await client.connect()).packets), frame);
});
