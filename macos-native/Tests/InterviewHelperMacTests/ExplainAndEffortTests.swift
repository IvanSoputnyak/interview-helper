import Foundation
import Testing
@testable import InterviewHelperCore

private func decodedBody(reasoningEffort: ReasoningEffort?, schemaName: String?) throws -> [String: Any] {
    let body = try OpenAIAnalyzer.requestBody(
        model: "gpt-test",
        reasoningEffort: reasoningEffort,
        system: "system",
        userParts: [["type": "input_text", "text": "hi"]],
        schemaName: schemaName
    )
    return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func responseBody(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

private func textResponse(_ text: String) -> Data {
    responseBody(["output": [["type": "message", "content": [["type": "output_text", "text": text]]]]])
}

@Suite("Request body")
struct RequestBodyTests {
    @Test func test_requestBody_whenEffortSet_sendsReasoningEffort() throws {
        let body = try decodedBody(reasoningEffort: .high, schemaName: "s")
        #expect((body["reasoning"] as? [String: String])?["effort"] == "high")
    }

    @Test func test_requestBody_whenEffortIsDefault_omitsReasoning() throws {
        let body = try decodedBody(reasoningEffort: nil, schemaName: "s")
        #expect(body["reasoning"] == nil)
    }

    @Test func test_requestBody_whenSchemaNamed_requestsStrictJSONSchema() throws {
        let body = try decodedBody(reasoningEffort: nil, schemaName: "screen_analysis")
        let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
        #expect(format?["name"] as? String == "screen_analysis")
    }

    @Test func test_requestBody_whenNoSchema_omitsTextFormatForPlainText() throws {
        let body = try decodedBody(reasoningEffort: nil, schemaName: nil)
        #expect(body["text"] == nil)
    }
}

@Suite("Plain-text response parsing")
struct TextResponseTests {
    @Test func test_parseTextResponse_whenOutputHasText_returnsIt() throws {
        #expect(try OpenAIAnalyzer.parseTextResponse(textResponse("1. The idea")) == "1. The idea")
    }

    @Test func test_parseTextResponse_whenTextPadded_trimsWhitespace() throws {
        #expect(try OpenAIAnalyzer.parseTextResponse(textResponse("\n  1. The idea \n")) == "1. The idea")
    }

    @Test func test_parseTextResponse_whenOnlyWhitespace_throwsInvalidResponse() {
        #expect(throws: OpenAIAnalyzer.AnalyzerError.invalidResponse) {
            try OpenAIAnalyzer.parseTextResponse(textResponse("  \n "))
        }
    }

    @Test func test_parseTextResponse_whenRefused_throwsRefused() {
        let body = responseBody(["output": [["type": "message", "content": [["type": "refusal", "refusal": "no"]]]]])
        #expect(throws: OpenAIAnalyzer.AnalyzerError.refused("no")) {
            try OpenAIAnalyzer.parseTextResponse(body)
        }
    }

    @Test func test_parseTextResponse_whenIncomplete_throwsIncomplete() {
        let body = responseBody(["status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"]])
        #expect(throws: OpenAIAnalyzer.AnalyzerError.incomplete("max_output_tokens")) {
            try OpenAIAnalyzer.parseTextResponse(body)
        }
    }

    @Test func test_parseTextResponse_whenNoOutput_throwsInvalidResponse() {
        #expect(throws: OpenAIAnalyzer.AnalyzerError.invalidResponse) {
            try OpenAIAnalyzer.parseTextResponse(responseBody(["output": []]))
        }
    }
}

@Suite("Explain prompt")
struct ExplainPromptTests {
    @Test func test_explainPrompt_startsWithContractInstructions() {
        let prompt = OpenAIAnalyzer.explainPrompt(for: ScreenAnalysis(question: "Q"))
        #expect(prompt.hasPrefix(AnalysisContract.explainInstructions))
    }

    @Test func test_explainPrompt_includesCurrentCode() {
        let prompt = OpenAIAnalyzer.explainPrompt(for: ScreenAnalysis(question: "Q", codeSnippet: "return 1"))
        #expect(prompt.contains("\nCurrent codeSnippet: return 1\n"))
    }

    @Test func test_explainPrompt_whenQuestionEmpty_fallsBackToSummary() {
        let prompt = OpenAIAnalyzer.explainPrompt(for: ScreenAnalysis(summary: "Two sum", question: ""))
        #expect(prompt.contains("\nCurrent question: Two sum\n"))
    }

    @Test func test_explainPrompt_doesNotReuseImproveInstructions() {
        let prompt = OpenAIAnalyzer.explainPrompt(for: ScreenAnalysis(question: "Q"))
        #expect(!prompt.contains(AnalysisContract.improveInstructions))
    }
}

@Suite("Readable OpenAI errors")
struct ReadableErrorTests {
    @Test func test_errorDescription_whenBodyIsOpenAIErrorJSON_showsOnlyMessage() {
        let body = #"{"error":{"message":"Incorrect API key provided.","type":"invalid_request_error","code":"invalid_api_key"}}"#
        let error = OpenAIAnalyzer.AnalyzerError.httpStatus(401, body)
        #expect(error.errorDescription == "OpenAI error 401: Incorrect API key provided.")
    }

    @Test func test_errorDescription_whenBodyIsNotJSON_showsRawBody() {
        let error = OpenAIAnalyzer.AnalyzerError.httpStatus(502, "<html>Bad gateway</html>")
        #expect(error.errorDescription == "OpenAI error 502: <html>Bad gateway</html>")
    }

    @Test func test_errorDescription_whenErrorMessageEmpty_showsRawBody() {
        let body = #"{"error":{"message":""}}"#
        #expect(OpenAIAnalyzer.AnalyzerError.httpStatus(500, body).errorDescription == "OpenAI error 500: \(body)")
    }
}
