import Foundation

public enum OpenAIAnalyzer {
    public static let defaultModel = "gpt-4.1-mini"
    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    public enum AnalyzerError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case httpStatus(Int, String)

        public var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add your OpenAI API key in Settings."
            case .invalidResponse:
                return "Could not read the model response."
            case .httpStatus(let code, let body):
                return "OpenAI error \(code): \(body)"
            }
        }
    }

    public static func analyze(
        screenshotPng: Data,
        prompt: String,
        apiKey: String,
        model: String = defaultModel
    ) async throws -> ScreenAnalysis {
        let dataUrl = "data:image/png;base64,\(screenshotPng.base64EncodedString())"
        let body = try requestBody(
            model: model,
            system: "You are a FAANG-style interview question solver. Give concise, simple wording.",
            userParts: [
                ["type": "input_text", "text": prompt],
                ["type": "input_image", "image_url": dataUrl],
                ["type": "input_text", "text": AnalysisSchema.followUpInstruction],
            ],
            schemaName: "screen_analysis"
        )
        let parsed = try await performRequest(apiKey: apiKey, body: body)
        return ScreenAnalysis.fromParsedJSON(parsed)
    }

    public static func improve(
        current: ScreenAnalysis,
        apiKey: String,
        model: String = defaultModel
    ) async throws -> ScreenAnalysis {
        let text = [
            "Improve this interview solution.",
            "Target FAANG expectations.",
            "Return strict JSON keys: \(AnalysisSchema.jsonKeys).",
            "",
            "Current question: \(current.question)",
            "Current summary: \(current.summary)",
            "Current solution: \(current.solution)",
            "Current code: \(current.codeSnippet)",
        ].joined(separator: "\n")

        let body = try requestBody(
            model: model,
            system: "You are an interview coach improving solutions for correctness, clarity, and complexity.",
            userParts: [["type": "input_text", "text": text]],
            schemaName: "screen_analysis_improved"
        )
        var parsed = try await performRequest(apiKey: apiKey, body: body)
        if parsed["question"]?.isEmpty != false {
            parsed["question"] = current.question
        }
        return ScreenAnalysis.fromParsedJSON(parsed, id: current.id)
    }

    private static func requestBody(
        model: String,
        system: String,
        userParts: [[String: String]],
        schemaName: String
    ) throws -> Data {
        let payload: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": system],
                ["role": "user", "content": userParts],
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": schemaName,
                    "schema": AnalysisSchema.makeJSONSchema(),
                    "strict": true,
                ],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private static func performRequest(apiKey: String, body: Data) async throws -> [String: String] {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AnalyzerError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnalyzerError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnalyzerError.httpStatus(http.statusCode, message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnalyzerError.invalidResponse
        }

        if let outputText = json["output_text"] as? String, !outputText.isEmpty {
            return try parseOutputJSON(outputText)
        }

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                if let content = item["content"] as? [[String: Any]] {
                    for block in content {
                        if let text = block["text"] as? String, !text.isEmpty {
                            return try parseOutputJSON(text)
                        }
                    }
                }
            }
        }

        throw AnalyzerError.invalidResponse
    }

    private static func parseOutputJSON(_ text: String) throws -> [String: String] {
        guard let data = text.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw AnalyzerError.invalidResponse
        }
        var out: [String: String] = [:]
        for key in ["summary", "question", "solution", "codeSnippet", "explanation", "algorithmWhy", "timeComplexity", "spaceComplexity", "detectedContentType"] {
            if let v = obj[key] as? String {
                out[key] = v
            }
        }
        return out
    }
}
