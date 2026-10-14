import Foundation
import os

public enum QAStore {
    public static let maxItemsDefaultsKey = "IH.qaMaxItems"
    public static let defaultMaxItems = 25
    /// Allowed range for the "History size" setting.
    public static let minItems = 1
    public static let maxItemsLimit = 500
    private static let log = Logger(subsystem: KeychainStore.service, category: "QAStore")

    /// How many Q&A rows are kept; lowering it hides older rows now and drops them from disk on the next write.
    public static var maxItems: Int {
        maxItems(from: .standard)
    }

    /// Stored size, or the default when unset / not positive; never above `maxItemsLimit`.
    public static func maxItems(from defaults: UserDefaults) -> Int {
        let stored = defaults.integer(forKey: maxItemsDefaultsKey)
        return stored > 0 ? min(stored, maxItemsLimit) : defaultMaxItems
    }

    /// History size typed into Settings: blank, non-numeric, or below `minItems` means the default
    /// (never 1, which would wipe history on the next capture); above `maxItemsLimit` is capped.
    public static func maxItems(fromFieldText text: String) -> Int {
        guard let typed = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), typed >= minItems else {
            return defaultMaxItems
        }
        return min(typed, maxItemsLimit)
    }

    /// Clamps to `minItems...maxItemsLimit`; the default is not stored, so a future default change reaches everyone.
    public static func saveMaxItems(_ count: Int, to defaults: UserDefaults = .standard) {
        let clamped = min(max(count, minItems), maxItemsLimit)
        if clamped == defaultMaxItems {
            defaults.removeObject(forKey: maxItemsDefaultsKey)
        } else {
            defaults.set(clamped, forKey: maxItemsDefaultsKey)
        }
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
