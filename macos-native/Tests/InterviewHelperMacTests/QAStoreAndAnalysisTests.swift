import Foundation
import Testing
import InterviewHelperCore

/// Serialized: every test points the process-wide `QA_STORE_PATH` at its own temp file.
@Suite("QAStore", .serialized)
struct QAStoreTests {
    private func withTempStore(_ lines: [String]? = nil, _ body: () throws -> Void) rethrows {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ih-qa-swift-\(UUID().uuidString).jsonl")
        if let lines {
            try? (lines.joined(separator: "\n") + "\n").write(to: path, atomically: true, encoding: .utf8)
        }
        setenv("QA_STORE_PATH", path.path, 1)
        defer {
            unsetenv("QA_STORE_PATH")
            try? FileManager.default.removeItem(at: path)
        }
        try body()
    }

    @Test func test_append_withTwoRows_listsNewestFirst() {
        withTempStore {
            QAStore.append(QARecord(id: "1", at: "t1", q: "Q1", a: "A1"))
            QAStore.append(QARecord(id: "2", at: "t2", q: "Q2", a: "A2"))
            #expect(QAStore.list().map(\.id) == ["2", "1"])
        }
    }

    @Test func test_list_whenStoreFileMissing_returnsEmpty() {
        withTempStore {
            #expect(QAStore.list().isEmpty)
        }
    }

    @Test func test_upsert_whenIdExists_replacesRowInPlace() {
        withTempStore {
            QAStore.append(QARecord(id: "1", at: "t1", q: "Q1", a: "old"))
            QAStore.append(QARecord(id: "2", at: "t2", q: "Q2", a: "A2"))
            QAStore.upsert(QARecord(id: "1", at: "t3", q: "Q1", a: "new"))

            let items = QAStore.list()
            #expect(items.map(\.id) == ["2", "1"])
            #expect(items[1].a == "new")
            #expect(items[1].at == "t3")
        }
    }

    @Test func test_upsert_whenIdUnknown_insertsAtTop() {
        withTempStore {
            QAStore.append(QARecord(id: "1", at: "t1", q: "Q1", a: "A1"))
            QAStore.upsert(QARecord(id: "new", at: "t2", q: "Q2", a: "A2"))
            #expect(QAStore.list().first?.id == "new")
        }
    }

    @Test func test_list_whenLineCorrupt_skipsItAndKeepsHistoryOnNextWrite() {
        withTempStore([
            #"{"id":"1","at":"t1","q":"Q1","a":"A1"}"#,
            "{not valid json",
            #"{"id":"2","at":"t2","q":"Q2","a":"A2"}"#,
        ]) {
            #expect(QAStore.list().map(\.id) == ["1", "2"])
            QAStore.append(QARecord(id: "3", at: "t3", q: "Q3", a: "A3"))
            #expect(QAStore.list().map(\.id) == ["3", "1", "2"])
        }
    }

    @Test func test_append_beyondMaxItems_truncatesOldest() {
        withTempStore {
            for i in 0 ..< QAStore.maxItems + 3 {
                QAStore.append(QARecord(id: "\(i)", at: "t", q: "q", a: "a"))
            }
            let items = QAStore.list()
            #expect(items.count == QAStore.maxItems)
            #expect(items.first?.id == "\(QAStore.maxItems + 2)")
        }
    }
}

@Suite("ScreenAnalysis")
struct ScreenAnalysisTests {
    @Test func test_qaRecord_whenQuestionAndCodePresent_usesThem() {
        let analysis = ScreenAnalysis(
            summary: "sum pair",
            question: "Two sum",
            solution: "hash map",
            codeSnippet: "code here"
        )
        let row = QARecord.from(analysis)
        #expect(row.q == "Two sum")
        #expect(row.a == "code here")
    }

    @Test func test_qaRecord_whenQuestionAndCodeEmpty_fallsBackToSummaryAndSolution() {
        let row = QARecord.from(ScreenAnalysis(summary: "sum", solution: "sol"))
        #expect(row.q == "sum")
        #expect(row.a == "sol")
    }

    @Test func test_qaRecord_whenFieldsTooLong_truncatesToLimits() {
        let long = String(repeating: "x", count: QARecord.answerMaxChars + 10)
        let row = QARecord.from(ScreenAnalysis(question: long, codeSnippet: long))
        #expect(row.q.count == QARecord.questionMaxChars)
        #expect(row.a.count == QARecord.answerMaxChars)
    }

    @Test func test_fromParsedJSON_whenKeysMissing_fillsDefaults() {
        let analysis = ScreenAnalysis.fromParsedJSON(["summary": "S"], id: "fixed")
        #expect(analysis.id == "fixed")
        #expect(analysis.question == "S")
        #expect(analysis.codeSnippet.isEmpty)
        #expect(analysis.detectedContentType == "unknown")
        #expect(ScreenAnalysis.fromParsedJSON([:]).summary == "No summary")
    }
}

@Suite("AnalyzePrompt")
struct AnalyzePromptTests {
    @Test func test_effectivePrompt_whenCustomPromptLocked_returnsDefault() {
        #expect(AnalyzePrompt.effective(unlockEnabled: false, customPrompt: "custom") == AnalyzePrompt.defaultBundled)
    }

    @Test func test_effectivePrompt_whenUnlockedWithCustomText_returnsTrimmedCustom() {
        #expect(AnalyzePrompt.effective(unlockEnabled: true, customPrompt: "  my prompt  ") == "my prompt")
    }

    @Test func test_effectivePrompt_whenUnlockedButEmptyOrNil_returnsDefault() {
        #expect(AnalyzePrompt.effective(unlockEnabled: true, customPrompt: "   ") == AnalyzePrompt.defaultBundled)
        #expect(AnalyzePrompt.effective(unlockEnabled: true, customPrompt: nil) == AnalyzePrompt.defaultBundled)
    }
}
