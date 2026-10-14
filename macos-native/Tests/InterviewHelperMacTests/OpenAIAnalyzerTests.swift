import Foundation
import Testing
import InterviewHelperCore

private func analysisJSON(_ fields: [String: String]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: fields)
    return String(decoding: data, as: UTF8.self)
}

private func responseBody(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

@Suite("OpenAIAnalyzer.parseResponse")
struct OpenAIAnalyzerParseTests {
    @Test func test_parseResponse_whenTextInOutputContentBlocks_returnsFields() throws {
        let body = responseBody([
            "status": "completed",
            "output": [
                ["type": "reasoning", "summary": []],
                ["type": "message", "content": [
                    ["type": "output_text", "text": analysisJSON(["summary": "S", "question": "Q", "codeSnippet": "C"])],
                ]],
            ],
        ])
        let parsed = try OpenAIAnalyzer.parseResponse(body)
        #expect(parsed["summary"] == "S")
        #expect(parsed["question"] == "Q")
        #expect(parsed["codeSnippet"] == "C")
    }

    @Test func test_parseResponse_whenTopLevelOutputText_returnsFields() throws {
        let body = responseBody(["output_text": analysisJSON(["summary": "S"])])
        #expect(try OpenAIAnalyzer.parseResponse(body)["summary"] == "S")
    }

    @Test func test_parseResponse_whenUnknownOrNonStringKeys_dropsThem() throws {
        let text = #"{"summary":"S","extra":"x","timeComplexity":5}"#
        let parsed = try OpenAIAnalyzer.parseResponse(responseBody(["output_text": text]))
        #expect(parsed == ["summary": "S"])
    }

    @Test func test_parseResponse_whenRefused_throwsRefusedWithReason() {
        let body = responseBody([
            "output": [["type": "message", "content": [["type": "refusal", "refusal": "nope"]]]],
        ])
        #expect(throws: OpenAIAnalyzer.AnalyzerError.refused("nope")) {
            try OpenAIAnalyzer.parseResponse(body)
        }
    }

    @Test func test_parseResponse_whenIncomplete_throwsIncompleteWithReason() {
        let body = responseBody([
            "status": "incomplete",
            "incomplete_details": ["reason": "max_output_tokens"],
            "output": [["type": "message", "content": [["type": "output_text", "text": "{\"summ"]]]],
        ])
        #expect(throws: OpenAIAnalyzer.AnalyzerError.incomplete("max_output_tokens")) {
            try OpenAIAnalyzer.parseResponse(body)
        }
    }

    @Test func test_parseResponse_whenModelJSONMalformed_throwsInvalidResponse() {
        let body = responseBody(["output_text": "not json"])
        #expect(throws: OpenAIAnalyzer.AnalyzerError.invalidResponse) {
            try OpenAIAnalyzer.parseResponse(body)
        }
    }

    @Test func test_parseResponse_whenBodyNotJSON_throwsInvalidResponse() {
        #expect(throws: OpenAIAnalyzer.AnalyzerError.invalidResponse) {
            try OpenAIAnalyzer.parseResponse(Data("<html>".utf8))
        }
    }

    @Test func test_parseResponse_whenOutputEmpty_throwsInvalidResponse() {
        #expect(throws: OpenAIAnalyzer.AnalyzerError.invalidResponse) {
            try OpenAIAnalyzer.parseResponse(responseBody(["output": []]))
        }
    }
}

@Suite("OpenAIAnalyzer helpers")
struct OpenAIAnalyzerHelperTests {
    @Test func test_resolvedModel_whenNilOrBlank_returnsDefault() {
        #expect(OpenAIAnalyzer.resolvedModel(nil) == OpenAIAnalyzer.defaultModel)
        #expect(OpenAIAnalyzer.resolvedModel("") == OpenAIAnalyzer.defaultModel)
        #expect(OpenAIAnalyzer.resolvedModel("   ") == OpenAIAnalyzer.defaultModel)
    }

    @Test func test_resolvedModel_whenRetiredDefault_returnsCurrentDefault() {
        #expect(OpenAIAnalyzer.resolvedModel("gpt-4.1-mini") == OpenAIAnalyzer.defaultModel)
    }

    @Test func test_resolvedModel_whenDeliberateNonDefault_keepsIt() {
        #expect(OpenAIAnalyzer.resolvedModel("gpt-6-astra") == "gpt-6-astra")
    }

    @Test func test_resolvedModel_whenCustomValuePadded_returnsTrimmed() {
        #expect(OpenAIAnalyzer.resolvedModel(" gpt-5 ") == "gpt-5")
    }

    @Test func test_improvedAnalysis_whenModelQuestionEmpty_keepsIdAndOriginalQuestion() {
        let current = ScreenAnalysis(id: "orig", question: "Two sum")
        let improved = OpenAIAnalyzer.improvedAnalysis(from: ["summary": "better", "question": ""], current: current)
        #expect(improved.id == "orig")
        #expect(improved.question == "Two sum")
        #expect(improved.summary == "better")
    }

    @Test func test_improvedAnalysis_whenModelAndOriginalQuestionEmpty_fallsBackToSummary() {
        let current = ScreenAnalysis(id: "orig", question: "")
        let improved = OpenAIAnalyzer.improvedAnalysis(from: ["summary": "better", "question": ""], current: current)
        #expect(improved.question == "better")
    }

    @Test func test_improvedAnalysis_whenModelProvidesQuestion_usesIt() {
        let current = ScreenAnalysis(id: "orig", question: "Two sum")
        let improved = OpenAIAnalyzer.improvedAnalysis(from: ["question": "Two sum (sorted)"], current: current)
        #expect(improved.question == "Two sum (sorted)")
    }
}

@Suite("AnalysisSchema")
struct AnalysisSchemaTests {
    @Test func test_schema_requiresEveryKey_andForbidsExtras() throws {
        let schema = AnalysisSchema.makeJSONSchema()
        let required = try #require(schema["required"] as? [String])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(required == AnalysisSchema.keys)
        #expect(Set(properties.keys) == Set(AnalysisSchema.keys))
        #expect(schema["additionalProperties"] as? Bool == false)
    }
}

@Suite("CaptureSizing")
struct CaptureSizingTests {
    @Test func test_fit_whenWithinMaxDimension_returnsSizeUnchanged() {
        let size = CaptureSizing.fit(width: 1440, height: 900, maxDimension: 2048)
        #expect(size.width == 1440 && size.height == 900)
    }

    @Test func test_fit_whenLandscapeTooLarge_scalesWidthToMax() {
        let size = CaptureSizing.fit(width: 5120, height: 2880, maxDimension: 2048)
        #expect(size.width == 2048 && size.height == 1152)
    }

    @Test func test_fit_whenPortraitTooLarge_scalesHeightToMax() {
        let size = CaptureSizing.fit(width: 2160, height: 3840, maxDimension: 2048)
        #expect(size.width == 1152 && size.height == 2048)
    }

    @Test func test_fit_whenWidthZero_returnsInputClamped() {
        let size = CaptureSizing.fit(width: 0, height: 100)
        #expect(size.width == 0 && size.height == 100)
    }
}
