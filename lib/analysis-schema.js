// Schema + prompts built from shared/analysis-contract.json (the Swift app uses the same file via
// AnalysisContract.generated.swift; tests/analysis-schema.test.js fails if that file is stale).
const contract = require("../shared/analysis-contract.json");

const CODE_FENCE = "```";

const ANALYSIS_KEYS = contract.fields.map((field) => field.key);
const DEFAULT_MODEL = contract.defaultModel;
const SYSTEM_PROMPT = contract.systemPrompt;
const DEFAULT_ANALYZE_PROMPT = contract.defaultAnalyzePrompt.join("\n");
const IMPROVE_SYSTEM_PROMPT = contract.improveSystemPrompt;

function schemaProperty(field) {
  const property = { type: "string", description: field.description };
  if (field.enum) {
    property.enum = field.enum;
  }
  return property;
}

const analysisJsonSchema = {
  type: "object",
  additionalProperties: false,
  properties: Object.fromEntries(
    contract.fields.map((field) => [field.key, schemaProperty(field)]),
  ),
  required: ANALYSIS_KEYS,
};

/** Configured model, falling back to the contract default when unset or a retired default (matches the Swift app). */
function resolveModel(configured) {
  const trimmed = (configured || "").trim();
  if (!trimmed || contract.retiredDefaultModels.includes(trimmed)) {
    return DEFAULT_MODEL;
  }
  return trimmed;
}

/** Only the schema fields of an analysis (drops id, createdAt, raw, …). */
function pickAnalysisFields(analysis) {
  return Object.fromEntries(ANALYSIS_KEYS.map((key) => [key, analysis[key] || ""]));
}

/** Model's improved fields, keeping the original question when the model left it empty (matches OpenAIAnalyzer.improvedAnalysis). */
function withOriginalQuestionIfMissing(parsed, original) {
  return parsed.question ? parsed : { ...parsed, question: original.question || "" };
}

/** Field value for the improve prompt; `question` falls back to `summary` (matches the Swift app). */
function contextValue(analysis, key) {
  if (key === "question") {
    return analysis.question || analysis.summary || "";
  }
  return analysis[key] || "";
}

/** Contract instructions followed by the current answer; mirrors OpenAIAnalyzer.improvePrompt. */
function buildImprovePrompt(analysis) {
  const context = contract.solutionContextKeys.map(
    (key) => `Current ${key}: ${contextValue(analysis, key)}`,
  );
  return [...contract.improveInstructions, "", ...context].join("\n");
}

/** Removes one fence pair wrapping the whole snippet (```lang … ```); anything else is returned unchanged. */
function stripCodeFences(code) {
  const lines = code.trim().split("\n");
  const wrapped =
    lines.length >= 2 &&
    lines[0].startsWith(CODE_FENCE) &&
    lines[lines.length - 1].trim() === CODE_FENCE;
  return wrapped ? lines.slice(1, -1).join("\n") : code;
}

module.exports = {
  ANALYSIS_KEYS,
  DEFAULT_ANALYZE_PROMPT,
  DEFAULT_MODEL,
  IMPROVE_SYSTEM_PROMPT,
  SYSTEM_PROMPT,
  analysisJsonSchema,
  buildImprovePrompt,
  pickAnalysisFields,
  resolveModel,
  stripCodeFences,
  withOriginalQuestionIfMissing,
};
