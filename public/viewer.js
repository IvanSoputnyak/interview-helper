const updatedAtEl = document.getElementById("updatedAt");
const contentTypeEl = document.getElementById("contentType");
const summaryEl = document.getElementById("summary");
const solutionEl = document.getElementById("solution");
const historyEl = document.getElementById("history");
const codeSnippetEl = document.getElementById("codeSnippet");
const explanationEl = document.getElementById("explanation");
const algorithmWhyEl = document.getElementById("algorithmWhy");
const timeComplexityEl = document.getElementById("timeComplexity");
const spaceComplexityEl = document.getElementById("spaceComplexity");
const improveBtn = document.getElementById("improveBtn");
const improveStatusEl = document.getElementById("improveStatus");
const params = new URLSearchParams(window.location.search);
const viewerToken = params.get("token");

if (!viewerToken) {
  summaryEl.textContent = "Missing viewer token in URL.";
}

function renderAnalysis(data) {
  updatedAtEl.textContent = data.createdAt || "-";
  contentTypeEl.textContent = data.detectedContentType || "unknown";
  summaryEl.textContent = data.summary || "No summary";
  solutionEl.textContent = data.solution || "No solution yet.";
  codeSnippetEl.textContent = data.codeSnippet || "// No code yet.";
  explanationEl.textContent = data.explanation || "No explanation yet.";
  algorithmWhyEl.textContent = data.algorithmWhy || "No algorithm details yet.";
  timeComplexityEl.textContent = data.timeComplexity || "-";
  spaceComplexityEl.textContent = data.spaceComplexity || "-";
}

function renderHistory(items) {
  if (!Array.isArray(items) || items.length === 0) {
    historyEl.textContent = "No history yet.";
    return;
  }

  const preview = items
    .slice(0, 10)
    .map((item, index) => {
      const when = item.createdAt || "-";
      const type = item.detectedContentType || "unknown";
      const text = item.summary || "No summary";
      return `${index + 1}. [${when}] (${type}) ${text}`;
    })
    .join("\n\n");
  historyEl.textContent = preview;
}

async function improveSolution() {
  if (!viewerToken) {
    return;
  }
  improveBtn.disabled = true;
  improveStatusEl.textContent = "Improving...";
  try {
    const response = await fetch("/api/improve", {
      method: "POST",
      headers: { "x-viewer-token": viewerToken },
    });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || "Improve failed.");
    }
    renderAnalysis(payload);
    improveStatusEl.textContent = "Improved.";
  } catch (error) {
    improveStatusEl.textContent = `Error: ${error.message}`;
  } finally {
    improveBtn.disabled = false;
  }
}

async function bootstrap() {
  if (!viewerToken) {
    return;
  }

  try {
    const response = await fetch("/api/latest", {
      headers: { "x-viewer-token": viewerToken },
    });
    if (!response.ok) {
      throw new Error(`Latest request failed (${response.status})`);
    }
    const data = await response.json();
    renderAnalysis(data);
  } catch (_error) {
    summaryEl.textContent = "Failed to load initial analysis.";
  }

  try {
    const historyResponse = await fetch("/api/history", {
      headers: { "x-viewer-token": viewerToken },
    });
    if (historyResponse.ok) {
      const payload = await historyResponse.json();
      renderHistory(payload.items || []);
    }
  } catch (_error) {
    historyEl.textContent = "Failed to load history.";
  }

  const socket = io({
    auth: { token: viewerToken },
  });
  socket.on("analysis:update", renderAnalysis);
  socket.on("analysis:history", renderHistory);
  improveBtn.addEventListener("click", improveSolution);
}

bootstrap();
