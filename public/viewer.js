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

  qaListEl.textContent = items
    .slice(0, 15)
    .map((row, index) => `${index + 1}. Q: ${row.q || "—"}\nA: ${row.a || "—"}`)
    .join("\n\n");
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

async function loadQA() {
  const response = await fetch("/api/qa", {
    headers: { "x-viewer-token": viewerToken },
  });
  if (!response.ok) {
    throw new Error(`QA request failed (${response.status})`);
  }
  const payload = await response.json();
  renderQA(payload.items || []);
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
    await loadQA();
  } catch (_error) {
    qaListEl.textContent = "Failed to load saved Q&A.";
  }

  const socket = io({
    auth: { token: viewerToken },
  });
  socket.on("analysis:update", renderAnalysis);
  socket.on("qa:list", renderQA);
  improveBtn.addEventListener("click", improveSolution);
}

bootstrap();
