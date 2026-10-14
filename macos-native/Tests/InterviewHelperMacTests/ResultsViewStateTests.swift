import Foundation
import Testing
@testable import InterviewHelperCore

private let twoSum = ScreenAnalysis(id: "a", summary: "Hash map", question: "Two sum", codeSnippet: "return []")
private let threeSum = ScreenAnalysis(id: "b", summary: "Sort + two pointers", question: "Three sum", codeSnippet: "return [[]]")

private func stateShowing(_ analysis: ScreenAnalysis = twoSum) -> ResultsViewState {
    var state = ResultsViewState()
    state.show(analysis)
    return state
}

private func stateWithExplanation() -> ResultsViewState {
    var state = stateShowing()
    _ = state.receiveExplanation("1. The idea", for: twoSum)
    return state
}

@Suite("ResultsViewState requests")
struct ResultsViewStateRequestTests {
    @Test func test_canStartRequest_whenNoAnalysis_isFalse() {
        #expect(!ResultsViewState().canStartRequest)
    }

    @Test func test_canStartRequest_whenAnalysisShownAndIdle_isTrue() {
        #expect(stateShowing().canStartRequest)
    }

    @Test func test_canStartRequest_whileARequestIsPending_isFalse() {
        var state = stateShowing()
        state.begin(.explain)
        #expect(!state.canStartRequest)
    }

    @Test func test_canStartRequest_whileShowingHistory_isFalse() {
        var state = stateShowing()
        state.showHistory()
        #expect(!state.canStartRequest)
    }

    @Test func test_finishRequest_afterBegin_allowsNextRequest() {
        var state = stateShowing()
        state.begin(.improve)
        state.finishRequest()
        #expect(state.canStartRequest)
    }

    @Test func test_improveButtonTitle_whileImproving_showsBusy() {
        var state = stateShowing()
        state.begin(.improve)
        #expect(state.improveButtonTitle == "Improving…")
    }

    @Test func test_improveButtonTitle_whileRetrying_showsReconnectProgress() {
        var state = stateShowing()
        state.begin(.improve)
        state.noteRetry(.retrying(attempt: 1, of: 3))
        #expect(state.improveButtonTitle == "Reconnecting (1/3)…")
    }

    @Test func test_explainButtonTitle_whileImproving_isUnaffectedByImproveRetry() {
        var state = stateShowing()
        state.begin(.improve)
        state.noteRetry(.waitingForNetwork)
        #expect(state.explainButtonTitle == "Explain simply")
    }

    @Test func test_begin_clearsRetryTextFromPreviousRequest() {
        var state = stateShowing()
        state.begin(.explain)
        state.noteRetry(.waitingForNetwork)
        state.finishRequest()
        state.begin(.explain)
        #expect(state.explainButtonTitle == "Explaining…")
    }

    @Test func test_failureTitle_forImprove_namesImprove() {
        #expect(ResultsViewState.PendingAction.improve.failureTitle == "Improve failed")
    }

    @Test func test_failureTitle_forExplain_namesExplain() {
        #expect(ResultsViewState.PendingAction.explain.failureTitle == "Explain failed")
    }

    @Test func test_isCurrent_whenSameAnalysisStillShown_isTrue() {
        #expect(stateShowing().isCurrent(twoSum))
    }

    @Test func test_isCurrent_whenNewerCaptureArrived_isFalse() {
        var state = stateShowing()
        state.show(threeSum)
        #expect(!state.isCurrent(twoSum))
    }
}

@Suite("ResultsViewState explanation")
struct ResultsViewStateExplanationTests {
    @Test func test_explainButtonTitle_withoutExplanation_offersExplain() {
        #expect(stateShowing().explainButtonTitle == "Explain simply")
    }

    @Test func test_receiveExplanation_forShownAnalysis_isAccepted() {
        var state = stateShowing()
        let accepted = state.receiveExplanation("1. The idea", for: twoSum)
        #expect(accepted)
    }

    @Test func test_receiveExplanation_afterNewerCapture_isDropped() {
        var state = stateShowing()
        state.show(threeSum)
        _ = state.receiveExplanation("1. The idea", for: twoSum)
        #expect(state.explanation == nil)
    }

    @Test func test_analysisText_withExplanation_showsItUnderSolution() {
        let text = stateWithExplanation().analysisText ?? ""
        #expect(text.hasPrefix(twoSum.displayText) && text.hasSuffix("1. The idea"))
    }

    @Test func test_toggleCachedExplanation_withoutExplanation_returnsFalse() {
        var state = stateShowing()
        let toggled = state.toggleCachedExplanation()
        #expect(!toggled)
    }

    @Test func test_toggleCachedExplanation_withExplanation_hidesIt() {
        var state = stateWithExplanation()
        _ = state.toggleCachedExplanation()
        #expect(state.analysisText == twoSum.displayText)
    }

    @Test func test_explainButtonTitle_whenExplanationHidden_offersShow() {
        var state = stateWithExplanation()
        _ = state.toggleCachedExplanation()
        #expect(state.explainButtonTitle == "Show explanation")
    }

    @Test func test_explainButtonTitle_whenExplanationVisible_offersHide() {
        #expect(stateWithExplanation().explainButtonTitle == "Hide explanation")
    }

    @Test func test_show_whenSameAnalysisReshown_keepsExplanation() {
        var state = stateWithExplanation()
        state.show(twoSum)
        #expect(state.explanation == "1. The idea")
    }

    @Test func test_show_whenImprovedAnalysisArrives_dropsStaleExplanation() {
        var state = stateWithExplanation()
        var improved = twoSum
        improved.codeSnippet = "return better"
        state.show(improved)
        #expect(state.explanation == nil)
    }
}

@Suite("ResultsViewState solution visibility and history")
struct ResultsViewStateVisibilityTests {
    @Test func test_toggleSolution_hidesCodeButKeepsQuestion() {
        var state = stateShowing()
        state.toggleSolution()
        let text = state.analysisText ?? ""
        #expect(!text.contains(twoSum.codeSnippet) && text.contains(twoSum.question))
    }

    @Test func test_solutionButtonTitle_whenHidden_offersShow() {
        var state = stateShowing()
        state.toggleSolution()
        #expect(state.solutionButtonTitle == "Show solution")
    }

    @Test func test_hiddenSolution_staysHiddenForNextCapture() {
        var state = stateShowing()
        state.toggleSolution()
        state.show(threeSum)
        #expect(!(state.analysisText ?? "").contains(threeSum.codeSnippet))
    }

    @Test func test_analysisText_whileShowingHistory_isNil() {
        var state = stateShowing()
        state.showHistory()
        #expect(state.analysisText == nil)
    }

    @Test func test_canToggleSolution_whileShowingHistory_isFalse() {
        var state = stateShowing()
        state.showHistory()
        #expect(!state.canToggleSolution)
    }

    @Test func test_show_afterHistory_returnsToAnalysis() {
        var state = stateShowing()
        state.showHistory()
        state.show(twoSum)
        #expect(state.analysisText == twoSum.displayText)
    }

    @Test func test_canToggleSolution_withoutAnalysis_isFalse() {
        #expect(!ResultsViewState().canToggleSolution)
    }
}
