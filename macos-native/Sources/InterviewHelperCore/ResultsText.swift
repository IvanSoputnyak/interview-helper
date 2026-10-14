import Foundation

/// Text of the Results window for one analysis: the solution (or just the question when hidden),
/// followed by the beginner explanation once one has been fetched.
public enum ResultsText {
    public static let explanationHeading = "━━ Explained simply ━━"
    static let hiddenSolutionNote = "Solution hidden. Click “Show solution” to reveal it."

    public static func compose(analysis: ScreenAnalysis, explanation: String?, showSolution: Bool) -> String {
        let solutionPart = showSolution ? analysis.displayText : questionOnly(analysis)
        guard let explanation else {
            return solutionPart
        }
        return [solutionPart, explanationHeading, explanation].joined(separator: "\n\n")
    }

    /// Hidden mode keeps the question (and leaves out the summary, which gives the approach away).
    private static func questionOnly(_ analysis: ScreenAnalysis) -> String {
        "Question\n\(analysis.value(forKey: "question"))\n\n\(hiddenSolutionNote)"
    }
}
