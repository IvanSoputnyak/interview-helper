import Foundation
import Testing
import InterviewHelperCore

@Suite("QAStore")
struct QAStoreTests {
    @Test func appendAndList() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ih-qa-swift-\(UUID().uuidString).jsonl")
        setenv("QA_STORE_PATH", path.path, 1)
        defer {
            try? FileManager.default.removeItem(at: path)
        }

        QAStore.append(QARecord(id: "1", at: "t", q: "Q?", a: "A"))
        let items = QAStore.list()
        #expect(items.count == 1)
        #expect(items[0].q == "Q?")
    }
}

@Suite("ScreenAnalysis")
struct ScreenAnalysisTests {
    @Test func qaRecordPrefersCodeSnippet() {
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
}
