// Addresses for the phone viewer and the "only this Mac" check.
const os = require("os");
const { spawn } = require("child_process");

/** The name phones type: announced over Bonjour (mDNS) while the server runs; `.local` needs no router setup. */
const PHONE_HOST_NAME = "h.local";
const BROWSER_DEFAULT_PORT = 80;
/** macOS names Wi-Fi and Ethernet en0, en1, …; bridge*, utun* and similar are VMs and VPNs a phone cannot reach. */
const PHYSICAL_INTERFACE_PREFIX = "en";
const LOOPBACK_ADDRESSES = new Set(["127.0.0.1", "::1", "::ffff:127.0.0.1"]);

/** True when a request or socket comes from this Mac itself. */
function isLoopbackAddress(address) {
  return LOOPBACK_ADDRESSES.has(address);
}

/** IPv4 addresses of this Mac on Wi-Fi/Ethernet, for when the phone cannot resolve `.local` names. */
function lanAddresses(interfaces = os.networkInterfaces()) {
  return Object.entries(interfaces)
    .filter(([name]) => name.startsWith(PHYSICAL_INTERFACE_PREFIX))
    .flatMap(([, entries]) => entries)
    .filter((entry) => entry.family === "IPv4" && !entry.internal)
    .map((entry) => entry.address);
}

/** `host`, plus `:port` unless it is the browser's default, so the phone types as little as possible. */
function hostWithPort(host, port) {
  return port === BROWSER_DEFAULT_PORT ? host : `${host}:${port}`;
}

/**
 * Makes PHONE_HOST_NAME point at `address` on the local network until this process exits, using macOS's
 * built-in dns-sd (a Bonjour proxy record, so the Mac keeps its own name). Returns the child process.
 */
function announcePhoneHostName(port, address) {
  const announcer = spawn(
    "dns-sd",
    ["-P", "Interview Helper", "_http._tcp", "local", String(port), PHONE_HOST_NAME, address],
    { stdio: "ignore" },
  );
  process.on("exit", () => announcer.kill());
  // A signal ends Node without "exit" handlers, which would leave the old name announced and make the next
  // start's announcement clash with it; exiting normally on these signals runs the cleanup above.
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
    process.once(signal, () => process.exit(0));
  }
  return announcer;
}

module.exports = {
  PHONE_HOST_NAME,
  announcePhoneHostName,
  hostWithPort,
  isLoopbackAddress,
  lanAddresses,
};
