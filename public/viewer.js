const answerEl = document.getElementById("answer");
const summaryEl = document.getElementById("summary");
const codeBlockEl = document.getElementById("codeBlock");
const codeGutterEl = document.getElementById("codeGutter");
const codeSnippetEl = document.getElementById("codeSnippet");
const complexityEl = document.getElementById("complexity");
/** Collapsed sections, each showing the analysis field named by its data-field attribute. */
const detailEls = document.querySelectorAll("details[data-field]");
const liveScreenEl = document.getElementById("liveScreen");
const liveStatusEl = document.getElementById("liveStatus");
const analyzeScreenBtn = document.getElementById("analyzeScreenBtn");
const analyzeStatusEl = document.getElementById("analyzeStatus");
const improveBtn = document.getElementById("improveBtn");
const explainBtn = document.getElementById("explainBtn");
const actionStatusEl = document.getElementById("actionStatus");
const explainedCardEl = document.getElementById("explainedCard");
const explainedEl = document.getElementById("explained");
const connectionStatusEl = document.getElementById("connectionStatus");
/** After this long without a new frame the picture is flagged as not live. */
const STALE_FRAME_MS = 5000;
const STALE_CHECK_INTERVAL_MS = 1000;
/** A phone that slept or left the browser this long may hold a dead connection; reconnect at once. */
const RECONNECT_AFTER_HIDDEN_MS = 5000;
/** Languages interview problems are written in; auto-detection only picks among these, so short snippets guess better. */
const CODE_LANGUAGES = ["python", "javascript", "typescript", "java", "cpp", "c", "csharp", "go", "kotlin", "swift", "ruby", "rust", "scala", "php", "sql"];
const SHARING_STOPPED_TEXT = "Sharing stopped on the Mac. Press Start sharing there to see the screen again.";
let shownAnalysisId = null;
let liveFrameUrl = null;
let lastFrameAt = null;
let hiddenSince = null;
let socket = null;

/** Shows `code` like an editor: numbered lines and syntax colors (plain text if highlight.js did not load). */
function renderCode(rawCode) {
  // A trailing newline would number one more line than the block shows.
  const code = rawCode.trimEnd();
  codeBlockEl.hidden = !code;
  codeGutterEl.textContent = code.split("\n").map((_, index) => index + 1).join("\n");
  if (window.hljs) {
    // highlight.js escapes the code, so its HTML is safe to insert.
    codeSnippetEl.innerHTML = hljs.highlightAuto(code, CODE_LANGUAGES).value;
  } else {
    codeSnippetEl.textContent = code;
  }
}

/** "Time: …" and "Memory: …" on their own lines, leaving out whichever the model left empty. */
function complexityLine({ timeComplexity, spaceComplexity }) {
  return [timeComplexity && `Time: ${timeComplexity}`, spaceComplexity && `Memory: ${spaceComplexity}`]
    .filter(Boolean)
    .join("\n");
}

function renderAnalysis(data) {
  // The explanation belongs to one analysis; a different one hides it.
  if (data.id !== shownAnalysisId) {
    explainedCardEl.hidden = true;
  }
  shownAnalysisId = data.id || null;
  // Nothing to show before the first analysis (the server's placeholder has no id).
  answerEl.hidden = !shownAnalysisId;
  summaryEl.textContent = data.summary || "";
  renderCode(data.codeSnippet || "");
  const complexity = complexityLine(data);
  complexityEl.textContent = complexity;
  complexityEl.hidden = !complexity;
  for (const detailEl of detailEls) {
    const value = data[detailEl.dataset.field] || "";
    detailEl.hidden = !value;
    detailEl.querySelector(".result-block").textContent = value;
  }
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

/** The Mac stopped sharing: drop the old picture so it is never mistaken for the current screen. */
function clearFrame() {
  // Nothing shown yet: keep the "Waiting for a shared screen" hint.
  if (lastFrameAt === null) {
    return;
  }
  if (liveFrameUrl) {
    URL.revokeObjectURL(liveFrameUrl);
  }
  liveFrameUrl = null;
  lastFrameAt = null;
  liveScreenEl.hidden = true;
  liveScreenEl.removeAttribute("src");
  liveStatusEl.textContent = SHARING_STOPPED_TEXT;
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
  const reason = socket && socket.connected ? "sharing on the Mac is paused" : "reconnecting";
  liveStatusEl.textContent = `No new frame for ${Math.round(ageMs / 1000)}s (${reason}) · last ${frameTime}`;
}

/** Shown only while offline: a healthy connection needs no line on a small screen. */
function showConnection(text, isOffline) {
  connectionStatusEl.textContent = text;
  connectionStatusEl.hidden = !isOffline;
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
    headers: { "content-type": "application/json" },
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
  // socket.io reconnects by itself (1s, then up to 5s between tries, forever); on every (re)connect the
  // server pushes the latest analysis and shared-screen frame, so the page resyncs with no reload.
  socket = io();
  socket.on("analysis:update", renderAnalysis);
  socket.on("screen:frame", renderFrame);
  socket.on("screen:stop", clearFrame);
  socket.on("connect", () => showConnection("Connected", false));
  socket.on("disconnect", () => showConnection("Connection lost · reconnecting…", true));
  socket.on("connect_error", () => showConnection("Cannot reach the server · retrying…", true));
  document.addEventListener("visibilitychange", reconnectAfterLongHide);
  setInterval(updateLiveStatus, STALE_CHECK_INTERVAL_MS);
  analyzeScreenBtn.addEventListener("click", analyzeScreen);
  improveBtn.addEventListener("click", improveSolution);
  explainBtn.addEventListener("click", explainSolution);
}

connect();
