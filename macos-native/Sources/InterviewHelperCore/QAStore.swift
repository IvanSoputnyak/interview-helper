import Foundation

public enum QAStore {
    public static var maxItems: Int {
        let n = UserDefaults.standard.integer(forKey: "IH.qaMaxItems")
        return n > 0 ? min(n, 500) : 25
    }

    public static var fileURL: URL {
        if let override = ProcessInfo.processInfo.environment["QA_STORE_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("InterviewHelper", isDirectory: true)
            .appendingPathComponent("qa.jsonl")
    }

    public static func list() -> [QARecord] {
        readAll().prefix(maxItems).map { $0 }
    }

    public static func append(_ entry: QARecord) {
        var items = readAll()
        items.insert(entry, at: 0)
        writeAll(Array(items.prefix(maxItems)))
    }

    public static func upsert(_ entry: QARecord) {
        var items = readAll()
        if let index = items.firstIndex(where: { $0.id == entry.id }) {
            var row = items[index]
            row.at = entry.at
            row.q = entry.q
            row.a = entry.a
            items[index] = row
        } else {
            items.insert(entry, at: 0)
        }
        writeAll(Array(items.prefix(maxItems)))
    }

    private static func readAll() -> [QARecord] {
        let url = fileURL
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return []
        }
        var rows: [QARecord] = []
        for line in String(data: data, encoding: .utf8)?.split(separator: "\n", omittingEmptySubsequences: true) ?? [] {
            if let row = try? JSONDecoder().decode(QARecord.self, from: Data(line.utf8)) {
                rows.append(row)
            }
        }
        return rows
    }

    private static func writeAll(_ items: [QARecord]) {
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = items.compactMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }.joined(separator: "\n")
        try? (body.isEmpty ? "" : body + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
