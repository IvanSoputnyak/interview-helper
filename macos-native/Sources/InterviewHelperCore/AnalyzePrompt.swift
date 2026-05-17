import Foundation

public enum AnalyzePrompt {
    public static let defaultBundled = """
Interview question solver mode.
Assume FAANG-style coding interview.
Give a good solution: not brute force unless optimal, and not over-engineered.
Return a well-formatted code snippet.
Use few words and simple words.
Also include:
- why this algorithm is used
- time complexity
- space complexity
"""

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
