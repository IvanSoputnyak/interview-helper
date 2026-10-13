import Foundation

/// Safety net for models that wrap `codeSnippet` in markdown despite the schema description.
public enum CodeFence {
    private static let marker = "```"

    /// Removes one fence pair wrapping the whole snippet (```lang … ```); anything else is returned unchanged.
    public static func strip(_ code: String) -> String {
        let lines = code.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        guard lines.count >= 2,
              let first = lines.first, first.hasPrefix(marker),
              let last = lines.last, last.trimmingCharacters(in: .whitespaces) == marker
        else {
            return code
        }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }
}
