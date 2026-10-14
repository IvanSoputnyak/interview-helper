import Foundation
import Testing
@testable import InterviewHelperCore

@Suite("Analysis schema from contract")
struct AnalysisSchemaContractTests {
    private func property(_ key: String) throws -> [String: Any] {
        let properties = try #require(AnalysisSchema.makeJSONSchema()["properties"] as? [String: Any])
        return try #require(properties[key] as? [String: Any])
    }

    @Test func test_schema_everyProperty_hasNonEmptyDescription() throws {
        let missing = try AnalysisSchema.keys.filter { key in
            (try property(key)["description"] as? String)?.isEmpty != false
        }
        #expect(missing.isEmpty)
    }

    @Test func test_schema_detectedContentType_isRestrictedToContractEnum() throws {
        let allowed = try property("detectedContentType")["enum"] as? [String]
        #expect(allowed == ["coding_problem", "system_design", "multiple_choice", "other"])
    }

    @Test func test_schema_freeTextProperty_hasNoEnum() throws {
        #expect(try property("codeSnippet")["enum"] == nil)
    }

    @Test func test_solutionContextKeys_areAllSchemaFields() {
        #expect(Set(AnalysisContract.solutionContextKeys).isSubset(of: Set(AnalysisSchema.keys)))
    }
}

@Suite("Prompts from contract")
struct PromptContractTests {
    @Test func test_defaultBundledPrompt_isContractDefault() {
        #expect(AnalyzePrompt.defaultBundled == AnalysisContract.defaultAnalyzePrompt)
    }

    @Test func test_improvePrompt_startsWithContractInstructions() {
        let prompt = OpenAIAnalyzer.improvePrompt(for: ScreenAnalysis(question: "Q"))
        #expect(prompt.hasPrefix(AnalysisContract.improveInstructions))
    }

    @Test func test_improvePrompt_includesCurrentCode() {
        let prompt = OpenAIAnalyzer.improvePrompt(for: ScreenAnalysis(question: "Q", codeSnippet: "return 1"))
        #expect(prompt.contains("\nCurrent codeSnippet: return 1\n"))
    }

    @Test func test_improvePrompt_whenQuestionEmpty_fallsBackToSummary() {
        let prompt = OpenAIAnalyzer.improvePrompt(for: ScreenAnalysis(summary: "Two sum", question: ""))
        #expect(prompt.contains("\nCurrent question: Two sum\n"))
    }

    @Test func test_improvePrompt_matchesNodeFormat() {
        let analysis = ScreenAnalysis(summary: "S", question: "Q", solution: "Sol", codeSnippet: "C", explanation: "E", algorithmWhy: "W", timeComplexity: "T", spaceComplexity: "M")
        let expected = AnalysisContract.improveInstructions + "\n\n" + [
            "Current question: Q", "Current summary: S", "Current solution: Sol", "Current codeSnippet: C",
            "Current explanation: E", "Current algorithmWhy: W", "Current timeComplexity: T", "Current spaceComplexity: M",
        ].joined(separator: "\n")
        #expect(OpenAIAnalyzer.improvePrompt(for: analysis) == expected)
    }

    @Test func test_improvePrompt_matchesCrossLanguageFixtureExactly() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/improve-prompt.json")
        let fixture = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        let fields = try #require(fixture["analysis"] as? [String: String])
        let expected = try #require(fixture["expectedImprovePrompt"] as? String)
        let analysis = ScreenAnalysis.fromParsedJSON(fields)
        #expect(OpenAIAnalyzer.improvePrompt(for: analysis) == expected)
    }

    @Test(arguments: AnalysisSchema.keys)
    func test_valueForKey_everySchemaKey_returnsItsField(key: String) {
        let marked = ScreenAnalysis.fromParsedJSON(Dictionary(uniqueKeysWithValues: AnalysisSchema.keys.map { ($0, "value-of-\($0)") }))
        #expect(marked.value(forKey: key) == "value-of-\(key)")
    }

    @Test func test_valueForKey_whenKeyUnknown_returnsEmpty() {
        #expect(ScreenAnalysis(summary: "S").value(forKey: "nope").isEmpty)
    }
}

@Suite("CodeFence")
struct CodeFenceTests {
    @Test func test_strip_whenFencedWithLanguage_returnsInnerCode() {
        #expect(CodeFence.strip("```python\ndef f():\n    return 1\n```") == "def f():\n    return 1")
    }

    @Test func test_strip_whenBareFenceWithSurroundingWhitespace_returnsInnerCode() {
        #expect(CodeFence.strip("\n```\nx = 1\n```  \n") == "x = 1")
    }

    @Test func test_strip_whenUnfenced_returnsInputUnchanged() {
        #expect(CodeFence.strip("x = 1\ny = 2") == "x = 1\ny = 2")
    }

    @Test func test_strip_whenOnlyOpeningFence_returnsInputUnchanged() {
        #expect(CodeFence.strip("```python\nx = 1") == "```python\nx = 1")
    }

    @Test func test_strip_whenFenceIsInsideCode_returnsInputUnchanged() {
        let code = "doc = \"\"\"\n```\n\"\"\""
        #expect(CodeFence.strip(code) == code)
    }

    @Test func test_strip_whenEmpty_returnsEmpty() {
        #expect(CodeFence.strip("").isEmpty)
    }

    @Test func test_fromParsedJSON_whenCodeSnippetFenced_storesRawCode() {
        let analysis = ScreenAnalysis.fromParsedJSON(["codeSnippet": "```js\nreturn 1;\n```"])
        #expect(analysis.codeSnippet == "return 1;")
    }
}
