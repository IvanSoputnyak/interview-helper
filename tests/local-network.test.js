const test = require("node:test");
const assert = require("node:assert/strict");

const { hostWithPort, isLoopbackAddress, lanAddresses } = require("../lib/local-network");

function ipv4(address, internal = false) {
  return { address, family: "IPv4", internal };
}

test("IPv4 and IPv6 loopback addresses count as this Mac", () => {
  assert.deepEqual(["127.0.0.1", "::1", "::ffff:127.0.0.1"].map(isLoopbackAddress), [true, true, true]);
});

test("a LAN address does not count as this Mac", () => {
  assert.equal(isLoopbackAddress("192.168.0.42"), false);
});

test("a missing address does not count as this Mac", () => {
  assert.equal(isLoopbackAddress(undefined), false);
});

test("lanAddresses lists IPv4 addresses of Wi-Fi and Ethernet interfaces", () => {
  const interfaces = { en0: [ipv4("192.168.0.185")], en1: [ipv4("10.0.0.7")] };
  assert.deepEqual(lanAddresses(interfaces), ["192.168.0.185", "10.0.0.7"]);
});

test("lanAddresses leaves out VM bridges, VPNs and loopback", () => {
  const interfaces = {
    lo0: [ipv4("127.0.0.1", true)],
    bridge100: [ipv4("192.168.64.1")],
    utun3: [ipv4("100.64.0.1")],
    en0: [ipv4("192.168.0.185")],
  };
  assert.deepEqual(lanAddresses(interfaces), ["192.168.0.185"]);
});

test("lanAddresses leaves out IPv6 addresses", () => {
  const interfaces = { en0: [{ address: "fe80::1", family: "IPv6", internal: false }, ipv4("192.168.0.185")] };
  assert.deepEqual(lanAddresses(interfaces), ["192.168.0.185"]);
});

test("lanAddresses is empty with no network", () => {
  assert.deepEqual(lanAddresses({}), []);
});

test("hostWithPort leaves out the browser's default port 80", () => {
  assert.equal(hostWithPort("h.local", 80), "h.local");
});

test("hostWithPort adds any other port", () => {
  assert.equal(hostWithPort("h.local", 3000), "h.local:3000");
});
