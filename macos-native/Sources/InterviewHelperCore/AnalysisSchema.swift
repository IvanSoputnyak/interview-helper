import Foundation

/// JSON schema for the model's structured output, built from `AnalysisContract` (shared/analysis-contract.json).
public enum AnalysisSchema {
    public static let keys = AnalysisContract.fields.map(\.key)

    public static func makeJSONSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": Dictionary(uniqueKeysWithValues: AnalysisContract.fields.map { ($0.key, property(for: $0)) }),
            "required": keys,
        ]
    }

    private static func property(for field: AnalysisField) -> [String: Any] {
        var property: [String: Any] = ["type": "string", "description": field.description]
        if !field.allowedValues.isEmpty {
            property["enum"] = field.allowedValues
        }
        return property
    }
}
