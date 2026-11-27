const test = require("node:test");
const assert = require("node:assert/strict");

const { explanationRows } = require("../public/explain-format");

test("a labelled line becomes a label row", () => {
  assert.deepEqual(explanationRows("Idea: count as you go, like a tally."), [
    { kind: "label", label: "Idea", text: "count as you go, like a tally." },
  ]);
});

test("a two-word label is kept whole", () => {
  assert.deepEqual(explanationRows("Watch out: empty input.")[0].label, "Watch out");
});

test("dash steps are numbered in order", () => {
  const rows = explanationRows("- look at 4\n- remember 4");
  assert.deepEqual(rows, [
    { kind: "step", number: 1, text: "look at 4" },
    { kind: "step", number: 2, text: "remember 4" },
  ]);
});

test("steps the model numbered itself are renumbered without the old numbers", () => {
  assert.deepEqual(explanationRows("3. look\n7) remember").map((row) => [row.number, row.text]), [
    [1, "look"],
    [2, "remember"],
  ]);
});

test("step numbers keep counting across label rows", () => {
  const rows = explanationRows("- a\nAnswer: 3\n- b");
  assert.deepEqual(rows.filter((row) => row.kind === "step").map((row) => row.number), [1, 2]);
});

test("a line that is neither a label nor a step stays plain text", () => {
  assert.deepEqual(explanationRows("The code keeps every running total: fast."), [
    { kind: "text", text: "The code keeps every running total: fast." },
  ]);
});

test("blank lines and surrounding spaces are dropped", () => {
  assert.deepEqual(explanationRows("\n  Answer: 7  \n\n"), [{ kind: "label", label: "Answer", text: "7" }]);
});

test("an empty explanation gives no rows", () => {
  assert.deepEqual(explanationRows(""), []);
});

test("the full layout from the prompt is split into label and step rows", () => {
  const explanation = [
    "Idea: keep a tally of running totals, like a shop till.",
    "Example: weights = [4,5], k = 5",
    "- start with total 0",
    "- add 4, remember total 4",
    "Answer: 1",
    "Watch out: negative totals.",
  ].join("\n");
  assert.deepEqual(explanationRows(explanation).map((row) => row.kind), ["label", "label", "step", "step", "label", "label"]);
});
