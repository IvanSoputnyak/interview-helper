import Foundation

public enum AnalysisSchema {
    public static let jsonKeys =
        "summary, question, solution, codeSnippet, explanation, algorithmWhy, timeComplexity, spaceComplexity, detectedContentType"

    public static let followUpInstruction =
        "Prefer an efficient solution (not brute force, but not over-engineered). Return strict JSON with keys: \(jsonKeys). Put the problem statement in question. Keep words minimal and simple."

    public static func makeJSONSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "summary": ["type": "string"],
                "question": ["type": "string"],
                "solution": ["type": "string"],
                "codeSnippet": ["type": "string"],
                "explanation": ["type": "string"],
                "algorithmWhy": ["type": "string"],
                "timeComplexity": ["type": "string"],
                "spaceComplexity": ["type": "string"],
                "detectedContentType": ["type": "string"],
            ],
            "required": [
                "summary", "question", "solution", "codeSnippet", "explanation",
                "algorithmWhy", "timeComplexity", "spaceComplexity", "detectedContentType",
            ],
        ]
    }
}
