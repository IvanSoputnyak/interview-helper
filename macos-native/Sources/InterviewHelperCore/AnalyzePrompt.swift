import Foundation

public enum AnalyzePrompt {
    public static let defaultBundled = AnalysisContract.defaultAnalyzePrompt

    /// Effective prompt for capture + upload (hardcoded unless unlock is on + non-empty custom text).
    public static func effective(unlockEnabled: Bool, customPrompt: String?) -> String {
        guard unlockEnabled else {
            return defaultBundled
        }
        let custom = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if custom.isEmpty {
            return defaultBundled
        }
        return custom
    }
}
