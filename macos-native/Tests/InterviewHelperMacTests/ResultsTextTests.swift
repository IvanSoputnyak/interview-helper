import Foundation
import Testing
@testable import InterviewHelperCore

private let twoSum = ScreenAnalysis(
    summary: "Use a hash map",
    question: "Find two numbers adding to target",
    codeSnippet: "def two_sum(nums, target): ..."
)

@Suite("ResultsText")
struct ResultsTextTests {
    @Test func test_compose_whenSolutionShownWithoutExplanation_isDisplayText() {
        let text = ResultsText.compose(analysis: twoSum, explanation: nil, showSolution: true)
        #expect(text == twoSum.displayText)
    }

    @Test func test_compose_whenSolutionShownWithExplanation_keepsSolutionVisible() {
        let text = ResultsText.compose(analysis: twoSum, explanation: "1. The idea", showSolution: true)
        #expect(text.hasPrefix(twoSum.displayText))
    }

    @Test func test_compose_whenExplanationPresent_appendsItUnderHeading() {
        let text = ResultsText.compose(analysis: twoSum, explanation: "1. The idea", showSolution: true)
        #expect(text.hasSuffix("\(ResultsText.explanationHeading)\n\n1. The idea"))
    }

    @Test func test_compose_whenSolutionHidden_hidesCode() {
        let text = ResultsText.compose(analysis: twoSum, explanation: nil, showSolution: false)
        #expect(!text.contains(twoSum.codeSnippet))
    }

    @Test func test_compose_whenSolutionHidden_hidesSummary() {
        let text = ResultsText.compose(analysis: twoSum, explanation: nil, showSolution: false)
        #expect(!text.contains(twoSum.summary))
    }

    @Test func test_compose_whenSolutionHidden_stillShowsQuestion() {
        let text = ResultsText.compose(analysis: twoSum, explanation: nil, showSolution: false)
        #expect(text.contains(twoSum.question))
    }

    @Test func test_compose_whenSolutionHidden_saysHowToReveal() {
        let text = ResultsText.compose(analysis: twoSum, explanation: nil, showSolution: false)
        #expect(text.contains(ResultsText.hiddenSolutionNote))
    }

    @Test func test_compose_whenSolutionHiddenWithExplanation_stillShowsExplanation() {
        let text = ResultsText.compose(analysis: twoSum, explanation: "1. The idea", showSolution: false)
        #expect(text.hasSuffix("1. The idea"))
    }

    @Test func test_compose_whenHiddenAndQuestionEmpty_fallsBackToSummaryAsQuestion() {
        let analysis = ScreenAnalysis(summary: "Two sum", question: "")
        let text = ResultsText.compose(analysis: analysis, explanation: nil, showSolution: false)
        #expect(text.hasPrefix("Question\nTwo sum\n"))
    }
}
