const test = require("node:test");
const assert = require("node:assert/strict");

const { sectionTitle } = require("../public/section-titles");
const contract = require("../shared/analysis-contract.json");

const FOLDED_FIELDS = ["solution", "algorithmWhy", "explanation"];

test("a coding challenge keeps the original titles", () => {
  assert.deepEqual(FOLDED_FIELDS.map((field) => sectionTitle("coding_problem", field)), [
    "Steps",
    "Why this works",
    "Example, step by step",
  ]);
});

test("a code review lists issues and why they matter", () => {
  assert.deepEqual([sectionTitle("code_review", "solution"), sectionTitle("code_review", "algorithmWhy")], [
    "Issues",
    "Why it matters",
  ]);
});

test("a type without its own title for a field falls back to the default", () => {
  assert.equal(sectionTitle("code_review", "explanation"), "Example, step by step");
});

test("an unknown content type uses the default titles", () => {
  assert.equal(sectionTitle("unknown", "solution"), "Steps");
});

test("every content type in the contract has a title for every folded section", () => {
  const contentTypes = contract.fields.find((field) => field.key === "detectedContentType").enum;
  const missing = contentTypes.flatMap((type) => FOLDED_FIELDS.filter((field) => !sectionTitle(type, field)));
  assert.deepEqual(missing, []);
});
