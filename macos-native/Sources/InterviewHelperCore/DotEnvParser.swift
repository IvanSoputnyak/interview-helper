import Foundation

/// Reads simple `KEY=value` entries from `projectRoot/.env` (matches `server.js` dotenv usage).
public enum DotEnvParser {
    public static func stringValue(forKey key: String, projectRoot: String) -> String? {
        let upper = key.uppercased()
        guard let text = dotEnvContents(projectRoot: projectRoot) else {
            return nil
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") || t.isEmpty {
                continue
            }
            let parts = t.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            guard parts[0].trimmingCharacters(in: .whitespaces).uppercased() == upper else {
                continue
            }
            let unquoted = unquote(String(parts[1]).trimmingCharacters(in: .whitespaces))
            if !unquoted.isEmpty {
                return unquoted
            }
        }
        return nil
    }

    public static func intValue(forKey key: String, projectRoot: String) -> Int? {
        guard let raw = stringValue(forKey: key, projectRoot: projectRoot), let n = Int(raw) else {
            return nil
        }
        return (1 ... 65_535).contains(n) ? n : nil
    }

    private static func dotEnvContents(projectRoot: String) -> String? {
        let path = URL(fileURLWithPath: projectRoot, isDirectory: true).appendingPathComponent(".env").path
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count < 512_000 else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func unquote(_ value: String) -> String {
        var v = value
        if v.count >= 2, v.first == "\"", v.last == "\"" {
            v = String(v.dropFirst().dropLast())
        } else if v.count >= 2, v.first == "'", v.last == "'" {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }
}
