// Captures this screen with the browser's screen-share picker and sends a downscaled JPEG frame
// to the server about once a second; the server keeps the latest one and relays it to viewers.
const FRAME_INTERVAL_MS = 1000;
/** Same longest edge as the Mac app's captures (CaptureSizing.defaultMaxDimension). */
const MAX_FRAME_EDGE = 2048;
const JPEG_QUALITY = 0.8;

const shareBtn = document.getElementById("shareBtn");
const shareStatusEl = document.getElementById("shareStatus");
const connectionStatusEl = document.getElementById("connectionStatus");
const viewerToken = new URLSearchParams(window.location.search).get("token");
const video = document.createElement("video");
const canvas = document.createElement("canvas");
const socket = io({ auth: { token: viewerToken } });
let stream = null;
let frameTimer = null;
let isEncoding = false;

video.muted = true;

/** Scales width×height down (never up) so the longest edge is at most `maxEdge`. */
function fitWithin(width, height, maxEdge) {
  const scale = Math.min(1, maxEdge / Math.max(width, height));
  return { width: Math.round(width * scale), height: Math.round(height * scale) };
}

function encodeFrame() {
  const size = fitWithin(video.videoWidth, video.videoHeight, MAX_FRAME_EDGE);
  canvas.width = size.width;
  canvas.height = size.height;
  canvas.getContext("2d").drawImage(video, 0, 0, size.width, size.height);
  return new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", JPEG_QUALITY));
}

/** Skips a tick while the previous frame is still encoding, so slow machines never build a backlog. */
async function sendFrame() {
  if (isEncoding || !video.videoWidth || !socket.connected) {
    return;
  }
  isEncoding = true;
  try {
    const blob = await encodeFrame();
    if (blob) {
      socket.emit("screen:frame", await blob.arrayBuffer());
      shareStatusEl.textContent = `Sharing · last frame ${new Date().toLocaleTimeString()}`;
    }
  } finally {
    isEncoding = false;
  }
}

function stopSharing() {
  clearInterval(frameTimer);
  stream?.getTracks().forEach((track) => track.stop());
  stream = null;
  shareBtn.textContent = "Start sharing";
  shareStatusEl.textContent = "Not sharing.";
}

async function startSharing() {
  try {
    stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
  } catch (error) {
    shareStatusEl.textContent = `Could not start sharing: ${error.message}`;
    return;
  }
  stream.getVideoTracks()[0].addEventListener("ended", stopSharing);
  video.srcObject = stream;
  await video.play();
  frameTimer = setInterval(sendFrame, FRAME_INTERVAL_MS);
  shareBtn.textContent = "Stop sharing";
  shareStatusEl.textContent = "Sharing…";
}

shareBtn.addEventListener("click", () => (stream ? stopSharing() : startSharing()));

if (!viewerToken) {
  shareBtn.disabled = true;
  shareStatusEl.textContent = "Missing token in URL: open the /broadcast?token=… link printed by npm start.";
} else if (!navigator.mediaDevices?.getDisplayMedia) {
  shareBtn.disabled = true;
  shareStatusEl.textContent = "Screen sharing needs a desktop browser opened at http://localhost (not the .local address).";
}

function showConnection(text, isOffline) {
  connectionStatusEl.textContent = text;
  connectionStatusEl.classList.toggle("offline", isOffline);
}

// socket.io reconnects by itself; the screen share stays open meanwhile and frames simply pause.
socket.on("connect", () => {
  showConnection("Connected to the server", false);
  // Send at once so viewers (and a restarted server) get the screen without waiting for the next tick.
  if (stream) {
    sendFrame();
  }
});
socket.on("disconnect", () => showConnection("Connection lost · reconnecting… (still sharing; frames resume automatically)", true));
socket.on("connect_error", (error) => {
  const text = error.message === "unauthorized"
    ? "Invalid token: open the share link printed by npm start again."
    : "Cannot reach the server · retrying… (still sharing)";
  showConnection(text, true);
});
