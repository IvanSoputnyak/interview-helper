// Minimal Socket.IO client over the raw Engine.IO v4 polling transport, so tests need no socket.io-client.
// Packets in one HTTP body are separated by \x1e; a binary attachment travels as "b" + base64.
const PACKET_SEPARATOR = "\x1e";
const SOCKET_CONNECT = "40";
const SOCKET_CONNECT_ERROR = "44";
const SOCKET_EVENT = "42";
const SOCKET_BINARY_EVENT = "451-";
const BINARY_PREFIX = "b";

function createPollingClient(baseUrl) {
  const pollingUrl = (sid) => `${baseUrl}/socket.io/?EIO=4&transport=polling${sid ? `&sid=${sid}` : ""}`;

  async function send(sid, body) {
    await fetch(pollingUrl(sid), {
      method: "POST",
      headers: { "content-type": "text/plain;charset=UTF-8" },
      body,
    });
  }

  /** Next batch of packets the server has queued for this session. */
  async function poll(sid) {
    return (await (await fetch(pollingUrl(sid))).text()).split(PACKET_SEPARATOR);
  }

  /** Opens a session, sends CONNECT (with `auth` unless undefined), and returns the session id and first packets. */
  async function connect(auth) {
    const handshake = await (await fetch(pollingUrl())).text();
    const { sid } = JSON.parse(handshake.slice(1));
    await send(sid, auth === undefined ? SOCKET_CONNECT : `${SOCKET_CONNECT}${JSON.stringify(auth)}`);
    return { sid, packets: await poll(sid) };
  }

  /** Emits `event` with one binary argument. */
  async function emitBinary(sid, event, bytes) {
    const header = `${SOCKET_BINARY_EVENT}${JSON.stringify([event, { _placeholder: true, num: 0 }])}`;
    await send(sid, `${header}${PACKET_SEPARATOR}${BINARY_PREFIX}${Buffer.from(bytes).toString("base64")}`);
  }

  async function emit(sid, event, value) {
    await send(sid, `${SOCKET_EVENT}${JSON.stringify([event, value])}`);
  }

  return { connect, poll, emit, emitBinary };
}

function eventNames(packets) {
  return packets
    .filter((packet) => packet.startsWith(SOCKET_EVENT) || packet.startsWith(SOCKET_BINARY_EVENT))
    .map((packet) => JSON.parse(packet.slice(packet.indexOf("[")))[0]);
}

/** Bytes of the first binary attachment among `packets`, or null. */
function binaryAttachment(packets) {
  const packet = packets.find((p) => p.startsWith(BINARY_PREFIX));
  return packet ? Buffer.from(packet.slice(BINARY_PREFIX.length), "base64") : null;
}

module.exports = { SOCKET_CONNECT, SOCKET_CONNECT_ERROR, binaryAttachment, createPollingClient, eventNames };
