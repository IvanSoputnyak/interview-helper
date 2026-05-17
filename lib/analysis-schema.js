const ANALYSIS_JSON_KEYS =
  "summary, question, solution, codeSnippet, explanation, algorithmWhy, timeComplexity, spaceComplexity, detectedContentType";

const analysisJsonSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    summary: { type: "string" },
    question: { type: "string" },
    solution: { type: "string" },
    codeSnippet: { type: "string" },
    explanation: { type: "string" },
    algorithmWhy: { type: "string" },
    timeComplexity: { type: "string" },
    spaceComplexity: { type: "string" },
    detectedContentType: { type: "string" },
  },
  required: [
    "summary",
    "question",
    "solution",
    "codeSnippet",
    "explanation",
    "algorithmWhy",
    "timeComplexity",
    "spaceComplexity",
    "detectedContentType",
  ],
};

module.exports = { ANALYSIS_JSON_KEYS, analysisJsonSchema };
