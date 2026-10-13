import Foundation
import os

public enum QAStore {
    public static let maxItemsDefaultsKey = "IH.qaMaxItems"
    public static let defaultMaxItems = 25
    private static let maxItemsCap = 500
    private static let log = Logger(subsystem: KeychainStore.service, category: "QAStore")

    public static var maxItems: Int {
        let n = UserDefaults.standard.integer(forKey: maxItemsDefaultsKey)
        return n > 0 ? min(n, maxItemsCap) : defaultMaxItems
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
        Array(readAll().prefix(maxItems))
    }

    public static func append(_ entry: QARecord) {
        var items = readAll()
        items.insert(entry, at: 0)
        writeAll(Array(items.prefix(maxItems)))
    }

    public static func upsert(_ entry: QARecord) {
        var items = readAll()
        if let index = items.firstIndex(where: { $0.id == entry.id }) {
            items[index] = entry
        } else {
            items.insert(entry, at: 0)
        }
        writeAll(Array(items.prefix(maxItems)))
    }

    /// Corrupt lines are skipped so one bad row never wipes the rest of the history.
    private static func readAll() -> [QARecord] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return []
        }
        let decoder = JSONDecoder()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        return lines.compactMap { try? decoder.decode(QARecord.self, from: Data($0.utf8)) }
    }

    private static func writeAll(_ items: [QARecord]) {
        let url = fileURL
        let encoder = JSONEncoder()
        let body = items.compactMap { try? String(decoding: encoder.encode($0), as: UTF8.self) }.joined(separator: "\n")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (body.isEmpty ? "" : body + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            log.error("Failed to write Q&A history to \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
