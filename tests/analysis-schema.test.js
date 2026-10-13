const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");

const contract = require("../shared/analysis-contract.json");
const {
  ANALYSIS_KEYS,
  DEFAULT_MODEL,
  analysisJsonSchema,
  buildImprovePrompt,
  pickAnalysisFields,
  resolveModel,
  stripCodeFences,
  withOriginalQuestionIfMissing,
} = require("../lib/analysis-schema");
const improveFixture = require("../shared/fixtures/improve-prompt.json");
const { SWIFT_PATH, loadContract, renderSwift } = require("../scripts/generate-swift-contract");

test("generated Swift contract is up to date (run `npm run contract` after editing the JSON)", () => {
  assert.equal(fs.readFileSync(SWIFT_PATH, "utf8"), renderSwift(loadContract()));
});

test("renderSwift escapes quotes, backslashes, and newlines", () => {
  const swift = renderSwift({ ...contract, systemPrompt: 'say "hi"\\\nbye' });
  assert.match(swift, /static let systemPrompt = "say \\"hi\\"\\\\\\nbye"/);
});

test("default model is not also listed as retired", () => {
  assert.ok(contract.defaultModel);
  assert.equal(contract.retiredDefaultModels.includes(contract.defaultModel), false);
});

test("explain prompt asks for plain text without fences", () => {
  assert.match(contract.explainInstructions.join("\n"), /no markdown, no code fences/);
});

test("contract field keys are unique", () => {
  assert.equal(new Set(ANALYSIS_KEYS).size, ANALYSIS_KEYS.length);
});

test("every solution context key is a schema field", () => {
  const unknown = contract.solutionContextKeys.filter((key) => !ANALYSIS_KEYS.includes(key));
  assert.deepEqual(unknown, []);
});

test("schema requires every key and allows no extras", () => {
  assert.deepEqual(analysisJsonSchema.required, ANALYSIS_KEYS);
  assert.deepEqual(Object.keys(analysisJsonSchema.properties), ANALYSIS_KEYS);
  assert.equal(analysisJsonSchema.additionalProperties, false);
});

test("every schema property carries a non-empty description", () => {
  const missing = ANALYSIS_KEYS.filter(
    (key) => !analysisJsonSchema.properties[key].description,
  );
  assert.deepEqual(missing, []);
});

test("detectedContentType is restricted to the contract enum", () => {
  assert.deepEqual(analysisJsonSchema.properties.detectedContentType.enum, [
    "coding_problem",
    "system_design",
    "multiple_choice",
    "other",
  ]);
});

test("free-text properties have no enum", () => {
  assert.equal(analysisJsonSchema.properties.codeSnippet.enum, undefined);
});

test("buildImprovePrompt starts with the contract instructions", () => {
  const prompt = buildImprovePrompt({ question: "Q" });
  assert.ok(prompt.startsWith(contract.improveInstructions.join("\n")));
});

test("buildImprovePrompt includes the current code", () => {
  const prompt = buildImprovePrompt({ question: "Q", codeSnippet: "return 1" });
  assert.match(prompt, /^Current codeSnippet: return 1$/m);
});

test("buildImprovePrompt falls back to summary when question is empty", () => {
  const prompt = buildImprovePrompt({ question: "", summary: "Two sum" });
  assert.match(prompt, /^Current question: Two sum$/m);
});

test("buildImprovePrompt renders missing fields as empty", () => {
  const prompt = buildImprovePrompt({});
  assert.match(prompt, /^Current timeComplexity: $/m);
});

test("buildImprovePrompt matches the cross-language fixture exactly", () => {
  assert.equal(buildImprovePrompt(improveFixture.analysis), improveFixture.expectedImprovePrompt);
});

test("resolveModel with no configured model returns the contract default", () => {
  assert.equal(resolveModel(undefined), DEFAULT_MODEL);
});

test("resolveModel with a blank model returns the contract default", () => {
  assert.equal(resolveModel("   "), DEFAULT_MODEL);
});

test("resolveModel with a retired default returns the current default", () => {
  assert.equal(resolveModel("gpt-4.1-mini"), DEFAULT_MODEL);
});

test("resolveModel keeps a deliberate custom model, trimmed", () => {
  assert.equal(resolveModel(" gpt-6-astra "), "gpt-6-astra");
});

test("pickAnalysisFields drops non-schema keys such as raw and id", () => {
  const picked = pickAnalysisFields({ id: "x", raw: { a: 1 }, summary: "s" });
  assert.deepEqual(Object.keys(picked), ANALYSIS_KEYS);
});

test("pickAnalysisFields fills missing fields with empty strings", () => {
  assert.equal(pickAnalysisFields({}).codeSnippet, "");
});

test("withOriginalQuestionIfMissing keeps the model question when present", () => {
  assert.equal(withOriginalQuestionIfMissing({ question: "New" }, { question: "Old" }).question, "New");
});

test("withOriginalQuestionIfMissing restores the original question when empty", () => {
  assert.equal(withOriginalQuestionIfMissing({ question: "" }, { question: "Old" }).question, "Old");
});

test("stripCodeFences removes a fence pair with a language tag", () => {
  assert.equal(stripCodeFences("```python\ndef f():\n    return 1\n```"), "def f():\n    return 1");
});

test("stripCodeFences removes a bare fence pair surrounded by whitespace", () => {
  assert.equal(stripCodeFences("\n```\nx = 1\n```  \n"), "x = 1");
});

test("stripCodeFences leaves unfenced code unchanged", () => {
  assert.equal(stripCodeFences("x = 1\ny = 2"), "x = 1\ny = 2");
});

test("stripCodeFences leaves code with only an opening fence unchanged", () => {
  assert.equal(stripCodeFences("```python\nx = 1"), "```python\nx = 1");
});

test("stripCodeFences keeps fences that appear inside the code", () => {
  const code = 'doc = """\n```\n"""';
  assert.equal(stripCodeFences(code), code);
});

test("stripCodeFences returns empty input unchanged", () => {
  assert.equal(stripCodeFences(""), "");
});
