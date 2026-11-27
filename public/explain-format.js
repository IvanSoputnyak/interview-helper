// Splits an Explain reply (layout asked for in shared/analysis-contract.json explainInstructions) into rows the
// viewer draws like its code block: "Idea: …" rows get a colored label, "- step" rows a number in the gutter.
// Loaded as a plain <script> in the browser (global `ExplainFormat`) and with require() in the Node tests.
(function exportExplainFormat(root) {
  /** "Watch out: …": a short capitalized label, then the text. */
  const LABEL_LINE = /^([A-Z][A-Za-z ]{0,14}):\s*(.*)$/;
  /** "- …", "• …", "* …" or "1. …" / "1) …": the model may number steps itself; the viewer renumbers them. */
  const STEP_MARKER = /^(?:[-•*]|\d+[.)])\s+/;

  /** Rows of `{ kind: "label", label, text }`, `{ kind: "step", number, text }` or `{ kind: "text", text }`. */
  function explanationRows(explanation) {
    let stepNumber = 0;
    return explanation
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const step = line.match(STEP_MARKER);
        if (step) {
          stepNumber += 1;
          return { kind: "step", number: stepNumber, text: line.slice(step[0].length) };
        }
        const label = line.match(LABEL_LINE);
        if (label) {
          return { kind: "label", label: label[1], text: label[2] };
        }
        return { kind: "text", text: line };
      });
  }

  const api = { explanationRows };
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.ExplainFormat = api;
  }
})(typeof window === "undefined" ? globalThis : window);
