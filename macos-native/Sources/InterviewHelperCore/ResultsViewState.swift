import Foundation

/// UI state of the Results window, kept free of AppKit so its rules are testable:
/// one model request at a time, late replies for a superseded analysis are dropped,
/// the explanation is cached per analysis, and "Hide solution" survives new captures.
public struct ResultsViewState: Equatable, Sendable {
    public enum PendingAction: Equatable, Sendable {
        case improve
        case explain
    }

    public private(set) var analysis: ScreenAnalysis?
    public private(set) var explanation: String?
    public private(set) var isExplanationVisible = true
    public private(set) var isSolutionVisible = true
    public private(set) var isShowingHistory = false
    public private(set) var pendingAction: PendingAction?
    private var retryText: String?

    public init() {}

    // MARK: Transitions

    /// A different analysis drops the cached explanation; re-showing the same one keeps it.
    public mutating func show(_ newAnalysis: ScreenAnalysis) {
        if newAnalysis != analysis {
            explanation = nil
            isExplanationVisible = true
        }
        analysis = newAnalysis
        isShowingHistory = false
    }

    public mutating func showHistory() {
        isShowingHistory = true
    }

    public mutating func toggleSolution() {
        isSolutionVisible.toggle()
    }

    /// Toggles a cached explanation and returns `true`; returns `false` when there is none yet (fetch one).
    public mutating func toggleCachedExplanation() -> Bool {
        guard explanation != nil else {
            return false
        }
        isExplanationVisible.toggle()
        return true
    }

    /// Callers check `canStartRequest` first.
    public mutating func begin(_ action: PendingAction) {
        pendingAction = action
        retryText = nil
    }

    public mutating func noteRetry(_ event: RetryEvent) {
        retryText = event.displayText
    }

    public mutating func finishRequest() {
        pendingAction = nil
        retryText = nil
    }

    /// Stores the explanation only if `source` is still the analysis on screen; returns whether it was accepted.
    public mutating func receiveExplanation(_ text: String, for source: ScreenAnalysis) -> Bool {
        guard source == analysis else {
            return false
        }
        explanation = text
        isExplanationVisible = true
        return true
    }

    /// Whether a reply computed for `source` (e.g. an improvement) still belongs to the analysis on screen.
    public func isCurrent(_ source: ScreenAnalysis) -> Bool {
        analysis?.id == source.id
    }

    // MARK: Derived UI

    public var canStartRequest: Bool {
        analysis != nil && !isShowingHistory && pendingAction == nil
    }

    public var canToggleSolution: Bool {
        analysis != nil && !isShowingHistory
    }

    public var solutionButtonTitle: String {
        isSolutionVisible ? "Hide solution" : "Show solution"
    }

    public var explainButtonTitle: String {
        if pendingAction == .explain {
            return retryText ?? "Explaining…"
        }
        guard explanation != nil else {
            return "Explain simply"
        }
        return isExplanationVisible ? "Hide explanation" : "Show explanation"
    }

    public var improveButtonTitle: String {
        pendingAction == .improve ? (retryText ?? "Improving…") : "Improve"
    }

    /// Window text for the analysis, or `nil` when there is none or history is showing.
    public var analysisText: String? {
        guard let analysis, !isShowingHistory else {
            return nil
        }
        return ResultsText.compose(
            analysis: analysis,
            explanation: isExplanationVisible ? explanation : nil,
            showSolution: isSolutionVisible
        )
    }
}
