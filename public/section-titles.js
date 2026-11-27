// Titles of the viewer's folded sections, named for the kind of task on screen (detectedContentType in
// shared/analysis-contract.json), so "Issues" shows for a code review instead of "Steps".
// Loaded as a plain <script> in the browser (global `SectionTitles`) and with require() in the Node tests.
(function exportSectionTitles(root) {
  /** Coding challenges and any task without its own titles below. */
  const DEFAULT_TITLES = {
    solution: "Steps",
    algorithmWhy: "Why this works",
    explanation: "Example, step by step",
  };
  const TITLES_BY_CONTENT_TYPE = {
    code_review: { solution: "Issues", algorithmWhy: "Why it matters" },
    code_fix: { solution: "What to fix", algorithmWhy: "Why it broke" },
    system_design: { solution: "Main parts", algorithmWhy: "Trade-offs", explanation: "One request, step by step" },
    multiple_choice: { solution: "Why not the others" },
  };

  /** Title of the section showing analysis field `field` for an analysis of kind `contentType`. */
  function sectionTitle(contentType, field) {
    const titles = TITLES_BY_CONTENT_TYPE[contentType] || {};
    return titles[field] || DEFAULT_TITLES[field];
  }

  const api = { sectionTitle };
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.SectionTitles = api;
  }
})(typeof window === "undefined" ? globalThis : window);
