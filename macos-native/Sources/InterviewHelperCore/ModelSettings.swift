import Foundation

/// `reasoning.effort` sent to the Responses API. No value (nil) means "let the model decide" and omits the parameter.
public enum ReasoningEffort: String, CaseIterable, Sendable {
    case low
    case medium
    case high
}

/// The user's model choices, persisted in UserDefaults. Only non-default values are stored,
/// so a future default change (in shared/analysis-contract.json) reaches every user.
public struct ModelSettings: Equatable, Sendable {
    static let modelKey = "IH.openAIModel"
    static let reasoningEffortKey = "IH.reasoningEffort"

    public let model: String
    public let reasoningEffort: ReasoningEffort?

    public static func load(from defaults: UserDefaults = .standard) -> ModelSettings {
        ModelSettings(
            model: OpenAIAnalyzer.resolvedModel(defaults.string(forKey: modelKey)),
            reasoningEffort: defaults.string(forKey: reasoningEffortKey).flatMap(ReasoningEffort.init(rawValue:))
        )
    }

    public static func save(model: String, reasoningEffort: ReasoningEffort?, to defaults: UserDefaults = .standard) {
        let resolved = OpenAIAnalyzer.resolvedModel(model)
        if resolved == OpenAIAnalyzer.defaultModel {
            defaults.removeObject(forKey: modelKey)
        } else {
            defaults.set(resolved, forKey: modelKey)
        }

        if let reasoningEffort {
            defaults.set(reasoningEffort.rawValue, forKey: reasoningEffortKey)
        } else {
            defaults.removeObject(forKey: reasoningEffortKey)
        }
    }
}
