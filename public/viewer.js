const updatedAtEl = document.getElementById("updatedAt");
const contentTypeEl = document.getElementById("contentType");
const summaryEl = document.getElementById("summary");
const questionEl = document.getElementById("question");
const solutionEl = document.getElementById("solution");
const codeSnippetEl = document.getElementById("codeSnippet");
const explanationEl = document.getElementById("explanation");
const algorithmWhyEl = document.getElementById("algorithmWhy");
const timeComplexityEl = document.getElementById("timeComplexity");
const spaceComplexityEl = document.getElementById("spaceComplexity");
const qaListEl = document.getElementById("qaList");
const liveScreenEl = document.getElementById("liveScreen");
const liveStatusEl = document.getElementById("liveStatus");
const questionInput = document.getElementById("questionInput");
const analyzeScreenBtn = document.getElementById("analyzeScreenBtn");
const analyzeStatusEl = document.getElementById("analyzeStatus");
const improveBtn = document.getElementById("improveBtn");
const explainBtn = document.getElementById("explainBtn");
const actionStatusEl = document.getElementById("actionStatus");
const explainedCardEl = document.getElementById("explainedCard");
const explainedEl = document.getElementById("explained");
const connectionStatusEl = document.getElementById("connectionStatus");
const viewerToken = new URLSearchParams(window.location.search).get("token");
/** After this long without a new frame the picture is flagged as not live. */
const STALE_FRAME_MS = 5000;
const STALE_CHECK_INTERVAL_MS = 1000;
/** A phone that slept or left the browser this long may hold a dead connection; reconnect at once. */
const RECONNECT_AFTER_HIDDEN_MS = 5000;
let shownAnalysisId = null;
let liveFrameUrl = null;
let lastFrameAt = null;
let hiddenSince = null;
let socket = null;

function renderAnalysis(data) {
  // The explanation belongs to one analysis; a different one hides it.
  if (data.id !== shownAnalysisId) {
    explainedCardEl.hidden = true;
  }
  shownAnalysisId = data.id || null;
  updatedAtEl.textContent = data.createdAt || "-";
  contentTypeEl.textContent = data.detectedContentType || "unknown";
  summaryEl.textContent = data.summary || "No summary";
  questionEl.textContent = data.question || data.summary || "—";
  solutionEl.textContent = data.solution || "No solution yet.";
  codeSnippetEl.textContent = data.codeSnippet || "// No code yet.";
  explanationEl.textContent = data.explanation || "No explanation yet.";
  algorithmWhyEl.textContent = data.algorithmWhy || "No algorithm details yet.";
  timeComplexityEl.textContent = data.timeComplexity || "-";
  spaceComplexityEl.textContent = data.spaceComplexity || "-";
}

function renderQA(items) {
  if (!Array.isArray(items) || items.length === 0) {
    qaListEl.textContent = "None yet.";
    return;
  }

  // Every row the server keeps (capped there by HISTORY_MAX_ITEMS).
  qaListEl.textContent = items
    .map((row, index) => `${index + 1}. Q: ${row.q || "—"}\nA: ${row.a || "—"}`)
    .join("\n\n");
}

/** Shows the newest shared-screen JPEG; the previous object URL is released so memory stays flat. */
function renderFrame(frame) {
  const nextUrl = URL.createObjectURL(new Blob([frame], { type: "image/jpeg" }));
  if (liveFrameUrl) {
    URL.revokeObjectURL(liveFrameUrl);
  }
  liveFrameUrl = nextUrl;
  liveScreenEl.src = nextUrl;
  liveScreenEl.hidden = false;
  lastFrameAt = Date.now();
  updateLiveStatus();
}

/** "Live · time" while frames keep coming; otherwise says how long the picture has been frozen. */
function updateLiveStatus() {
  if (lastFrameAt === null) {
    return;
  }
  const frameTime = new Date(lastFrameAt).toLocaleTimeString();
  const ageMs = Date.now() - lastFrameAt;
  if (ageMs <= STALE_FRAME_MS) {
    liveStatusEl.textContent = `Live · ${frameTime}`;
    return;
  }
  const reason = socket && socket.connected ? "sharing on the Mac is paused or stopped" : "reconnecting";
  liveStatusEl.textContent = `No new frame for ${Math.round(ageMs / 1000)}s (${reason}) · last ${frameTime}`;
}

function showConnection(text, isOffline) {
  connectionStatusEl.textContent = text;
  connectionStatusEl.classList.toggle("offline", isOffline);
}

/** Resolves true as soon as the socket is connected, or false after `timeoutMs`. */
function waitForConnection(timeoutMs) {
  if (socket.connected) {
    return Promise.resolve(true);
  }
  return new Promise((resolve) => {
    const onConnect = () => {
      clearTimeout(timer);
      resolve(true);
    };
    const timer = setTimeout(() => {
      socket.off("connect", onConnect);
      resolve(false);
    }, timeoutMs);
    socket.once("connect", onConnect);
  });
}

/** One POST; a non-2xx reply becomes RequestRetry.HttpError with the server's message. */
async function postJSON(route, body) {
  const response = await fetch(route, {
    method: "POST",
    headers: { "x-viewer-token": viewerToken, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new RequestRetry.HttpError(response.status, payload.error || `Request failed (${response.status}).`);
  }
  return payload;
}

/**
 * POSTs `body` to `route` while `button` shows as busy, retrying network drops and temporary server errors
 * (see request-retry.js); `describeSuccess(payload)` returns the status line. Final errors show in `statusEl`.
 */
async function runAction({ button, statusEl, busyText, route, body = {} }, describeSuccess) {
  button.disabled = true;
  statusEl.textContent = busyText;
  try {
    const payload = await RequestRetry.withRetry(() => postJSON(route, body), {
      onRetry: (text) => {
        statusEl.textContent = text;
      },
      isOnline: () => socket.connected,
      waitForConnection,
    });
    statusEl.textContent = describeSuccess(payload);
  } catch (error) {
    statusEl.textContent = `Error: ${error.message}`;
  } finally {
    button.disabled = false;
  }
}

function analyzeScreen() {
  const action = {
    button: analyzeScreenBtn,
    statusEl: analyzeStatusEl,
    busyText: "Analyzing the screen…",
    route: "/api/analyze-screen",
    body: { question: questionInput.value },
  };
  return runAction(action, (payload) => {
    renderAnalysis(payload);
    return "Done.";
  });
}

function improveSolution() {
  const action = { button: improveBtn, statusEl: actionStatusEl, busyText: "Improving…", route: "/api/improve" };
  return runAction(action, (payload) => {
    // A newer capture may have replaced the one being improved; the server pushes the live view over the socket.
    if (payload.id !== shownAnalysisId) {
      return "Improved (a newer capture is shown).";
    }
    renderAnalysis(payload);
    return "Improved.";
  });
}

function explainSolution() {
  const action = { button: explainBtn, statusEl: actionStatusEl, busyText: "Explaining…", route: "/api/explain" };
  return runAction(action, (payload) => {
    if (payload.id !== shownAnalysisId) {
      return "Explained an older capture; tap again for the current one.";
    }
    explainedEl.textContent = payload.explanation;
    explainedCardEl.hidden = false;
    explainedCardEl.scrollIntoView({ behavior: "smooth" });
    return "Explained below.";
  });
}

/** A dead connection after sleep can look alive for up to a minute; a fresh one resyncs everything at once. */
function reconnectAfterLongHide() {
  if (document.hidden) {
    hiddenSince = Date.now();
    return;
  }
  const hiddenForMs = hiddenSince === null ? 0 : Date.now() - hiddenSince;
  hiddenSince = null;
  if (hiddenForMs >= RECONNECT_AFTER_HIDDEN_MS) {
    socket.disconnect().connect();
  }
}

function connect() {
  if (!viewerToken) {
    showConnection("Missing token: open the full viewer link printed by npm start.", true);
    return;
  }
  // socket.io reconnects by itself (1s, then up to 5s between tries, forever); on every (re)connect the
  // server pushes the latest analysis, saved Q&A and shared-screen frame, so the page resyncs with no reload.
  socket = io({ auth: { token: viewerToken } });
  socket.on("analysis:update", renderAnalysis);
  socket.on("qa:list", renderQA);
  socket.on("screen:frame", renderFrame);
  socket.on("connect", () => showConnection("Connected", false));
  socket.on("disconnect", () => showConnection("Connection lost · reconnecting…", true));
  socket.on("connect_error", (error) => {
    // The server rejected the token: socket.io stops retrying, and so do we.
    const text = error.message === "unauthorized"
      ? "Invalid viewer token: open the link printed by npm start again."
      : "Cannot reach the server · retrying…";
    showConnection(text, true);
  });
  document.addEventListener("visibilitychange", reconnectAfterLongHide);
  setInterval(updateLiveStatus, STALE_CHECK_INTERVAL_MS);
  analyzeScreenBtn.addEventListener("click", analyzeScreen);
  improveBtn.addEventListener("click", improveSolution);
  explainBtn.addEventListener("click", explainSolution);
}

connect();
