import Foundation

public enum OpenAIAnalyzer {
    public static let defaultModel = AnalysisContract.defaultModel
    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    /// Reasoning models can think for a while on hard problems before answering.
    private static let requestTimeout: TimeInterval = 180

    public enum AnalyzerError: LocalizedError, Equatable {
        case missingAPIKey
        case invalidResponse
        case refused(String)
        case incomplete(String)
        case httpStatus(Int, String)

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add your OpenAI API key in Settings."
            case .invalidResponse:
                return "Could not read the model response."
            case .refused(let reason):
                return "The model declined to answer: \(reason)"
            case .incomplete(let reason):
                return "The model response was cut off (\(reason)). Try again."
            case .httpStatus(let code, let body):
                return "OpenAI error \(code): \(Self.readableMessage(fromBody: body))"
            }
        }

        /// OpenAI's `error.message` when the body is its standard error JSON, otherwise the raw body.
        static func readableMessage(fromBody body: String) -> String {
            guard let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any],
                  let error = json["error"] as? [String: Any],
                  let message = error["message"] as? String, !message.isEmpty
            else {
                return body
            }
            return message
        }
    }

    /// Stored model setting, falling back to the default when unset, blank, or a retired default
    /// (older Settings saved the prefilled default verbatim, which would pin users to it forever).
    public static func resolvedModel(_ stored: String?) -> String {
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty || AnalysisContract.retiredDefaultModels.contains(trimmed) {
            return defaultModel
        }
        return trimmed
    }

    public static func analyze(
        screenshotPng: Data,
        prompt: String,
        apiKey: String,
        model: String = defaultModel,
        reasoningEffort: ReasoningEffort? = nil,
        onRetry: RetryObserver? = nil
    ) async throws -> ScreenAnalysis {
        let dataUrl = "data:image/png;base64,\(screenshotPng.base64EncodedString())"
        let body = try requestBody(
            model: model,
            reasoningEffort: reasoningEffort,
            system: AnalysisContract.systemPrompt,
            userParts: [
                ["type": "input_text", "text": prompt],
                ["type": "input_image", "image_url": dataUrl],
            ],
            schemaName: "screen_analysis"
        )
        let data = try await performRequest(apiKey: apiKey, body: body, onRetry: onRetry)
        return ScreenAnalysis.fromParsedJSON(try parseResponse(data))
    }

    public static func improve(
        current: ScreenAnalysis,
        apiKey: String,
        model: String = defaultModel,
        reasoningEffort: ReasoningEffort? = nil,
        onRetry: RetryObserver? = nil
    ) async throws -> ScreenAnalysis {
        let body = try requestBody(
            model: model,
            reasoningEffort: reasoningEffort,
            system: AnalysisContract.improveSystemPrompt,
            userParts: [["type": "input_text", "text": improvePrompt(for: current)]],
            schemaName: "screen_analysis_improved"
        )
        let data = try await performRequest(apiKey: apiKey, body: body, onRetry: onRetry)
        return improvedAnalysis(from: try parseResponse(data), current: current)
    }

    /// Beginner-level, plain-text walkthrough of `current` (idea + analogy, traced example, why not brute force, pitfalls).
    public static func explain(
        current: ScreenAnalysis,
        apiKey: String,
        model: String = defaultModel,
        reasoningEffort: ReasoningEffort? = nil,
        onRetry: RetryObserver? = nil
    ) async throws -> String {
        let body = try requestBody(
            model: model,
            reasoningEffort: reasoningEffort,
            system: AnalysisContract.explainSystemPrompt,
            userParts: [["type": "input_text", "text": explainPrompt(for: current)]],
            schemaName: nil
        )
        let data = try await performRequest(apiKey: apiKey, body: body, onRetry: onRetry)
        return try parseTextResponse(data)
    }

    /// Mirrors `buildImprovePrompt` in lib/analysis-schema.js.
    static func improvePrompt(for current: ScreenAnalysis) -> String {
        solutionPrompt(instructions: AnalysisContract.improveInstructions, current: current)
    }

    static func explainPrompt(for current: ScreenAnalysis) -> String {
        solutionPrompt(instructions: AnalysisContract.explainInstructions, current: current)
    }

    /// Contract instructions, a blank line, then the current answer as "Current <key>: <value>" lines.
    private static func solutionPrompt(instructions: String, current: ScreenAnalysis) -> String {
        let context = AnalysisContract.solutionContextKeys.map { "Current \($0): \(current.value(forKey: $0))" }
        return ([instructions, ""] + context).joined(separator: "\n")
    }

    /// Keeps the original id and, when the model omits it, the original question.
    public static func improvedAnalysis(from parsed: [String: String], current: ScreenAnalysis) -> ScreenAnalysis {
        var parsed = parsed
        if parsed["question"]?.isEmpty != false {
            parsed["question"] = current.question
        }
        return ScreenAnalysis.fromParsedJSON(parsed, id: current.id)
    }

    /// Responses API body. `reasoningEffort == nil` omits `reasoning` (model default, works for any model);
    /// `schemaName == nil` omits `text.format`, so the model replies in plain text.
    static func requestBody(
        model: String,
        reasoningEffort: ReasoningEffort?,
        system: String,
        userParts: [[String: String]],
        schemaName: String?
    ) throws -> Data {
        var payload: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": system],
                ["role": "user", "content": userParts],
            ],
        ]
        if let reasoningEffort {
            payload["reasoning"] = ["effort": reasoningEffort.rawValue]
        }
        if let schemaName {
            payload["text"] = [
                "format": [
                    "type": "json_schema",
                    "name": schemaName,
                    "schema": AnalysisSchema.makeJSONSchema(),
                    "strict": true,
                ],
            ]
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Transient network / HTTP failures are retried (see `RetryPolicy`); returns the raw body of the successful response.
    private static func performRequest(apiKey: String, body: Data, onRetry: RetryObserver?) async throws -> Data {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AnalyzerError.missingAPIKey
        }

        var request = URLRequest(url: endpoint, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        return try await withRetry(onRetry: onRetry) {
            try await send(request)
        }
    }

    /// One HTTP round trip; non-2xx responses become `AnalyzerError.httpStatus`.
    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnalyzerError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnalyzerError.httpStatus(http.statusCode, message)
        }
        return data
    }

    /// Extracts the structured analysis from a raw Responses API body.
    public static func parseResponse(_ data: Data) throws -> [String: String] {
        try parseOutputJSON(extractOutputText(data))
    }

    /// Extracts a plain-text answer (trimmed) from a raw Responses API body.
    static func parseTextResponse(_ data: Data) throws -> String {
        let text = try extractOutputText(data).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AnalyzerError.invalidResponse
        }
        return text
    }

    /// First non-empty output text; throws on incomplete responses, refusals, or no text at all.
    private static func extractOutputText(_ data: Data) throws -> String {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AnalyzerError.invalidResponse
        }

        if let status = json["status"] as? String, status == "incomplete" {
            let details = json["incomplete_details"] as? [String: Any]
            throw AnalyzerError.incomplete(details?["reason"] as? String ?? "unknown reason")
        }

        // `output_text` is an SDK convenience; accept it if present, otherwise walk `output[].content[]`.
        if let outputText = json["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }

        for item in json["output"] as? [[String: Any]] ?? [] {
            for block in item["content"] as? [[String: Any]] ?? [] {
                if let refusal = block["refusal"] as? String {
                    throw AnalyzerError.refused(refusal)
                }
                if let text = block["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }

        throw AnalyzerError.invalidResponse
    }

    private static func parseOutputJSON(_ text: String) throws -> [String: String] {
        guard let data = text.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            throw AnalyzerError.invalidResponse
        }
        var out: [String: String] = [:]
        for key in AnalysisSchema.keys {
            if let v = obj[key] as? String {
                out[key] = v
            }
        }
        return out
    }
}
