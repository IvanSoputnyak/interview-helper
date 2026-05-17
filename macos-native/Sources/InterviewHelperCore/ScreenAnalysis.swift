import Foundation

public struct ScreenAnalysis: Codable, Sendable, Equatable {
    public var id: String
    public var createdAt: String
    public var summary: String
    public var question: String
    public var solution: String
    public var codeSnippet: String
    public var explanation: String
    public var algorithmWhy: String
    public var timeComplexity: String
    public var spaceComplexity: String
    public var detectedContentType: String

    public init(
        id: String = UUID().uuidString,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        summary: String = "",
        question: String = "",
        solution: String = "",
        codeSnippet: String = "",
        explanation: String = "",
        algorithmWhy: String = "",
        timeComplexity: String = "",
        spaceComplexity: String = "",
        detectedContentType: String = "unknown"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.summary = summary
        self.question = question
        self.solution = solution
        self.codeSnippet = codeSnippet
        self.explanation = explanation
        self.algorithmWhy = algorithmWhy
        self.timeComplexity = timeComplexity
        self.spaceComplexity = spaceComplexity
        self.detectedContentType = detectedContentType
    }

    public static func fromParsedJSON(_ parsed: [String: String], id: String? = nil) -> ScreenAnalysis {
        ScreenAnalysis(
            id: id ?? UUID().uuidString,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            summary: parsed["summary"] ?? "No summary",
            question: parsed["question"] ?? parsed["summary"] ?? "",
            solution: parsed["solution"] ?? "",
            codeSnippet: parsed["codeSnippet"] ?? "",
            explanation: parsed["explanation"] ?? "",
            algorithmWhy: parsed["algorithmWhy"] ?? "",
            timeComplexity: parsed["timeComplexity"] ?? "",
            spaceComplexity: parsed["spaceComplexity"] ?? "",
            detectedContentType: parsed["detectedContentType"] ?? "unknown"
        )
    }

    public var displayText: String {
        """
        \(summary)

        Question
        \(question)

        Solution
        \(solution)

        Code
        \(codeSnippet)

        Why
        \(algorithmWhy)
        Time: \(timeComplexity)  Space: \(spaceComplexity)

        \(explanation)
        """
    }
}

public struct QARecord: Codable, Sendable, Equatable {
    public var id: String
    public var at: String
    public var q: String
    public var a: String

    public init(id: String, at: String, q: String, a: String) {
        self.id = id
        self.at = at
        self.q = q
        self.a = a
    }

    public static func from(_ analysis: ScreenAnalysis) -> QARecord {
        QARecord(
            id: analysis.id,
            at: analysis.createdAt,
            q: String((analysis.question.isEmpty ? analysis.summary : analysis.question).prefix(4000)),
            a: String((analysis.codeSnippet.isEmpty ? analysis.solution : analysis.codeSnippet).prefix(12000))
        )
    }
}
