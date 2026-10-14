import AppKit
import InterviewHelperCore

/// Renders `ResultsViewState` (which holds the rules) and runs the model requests it allows.
@MainActor
final class ResultsWindowController: NSWindowController, NSWindowDelegate {
    private enum ScrollTarget {
        case top
        case explanation
    }

    private let scrollView = NSTextView.scrollableTextView()
    private var textView: NSTextView { scrollView.documentView as! NSTextView }
    private let historyButton = NSButton(title: "History", target: nil, action: nil)
    private let solutionButton = NSButton(title: "Hide solution", target: nil, action: nil)
    private let explainButton = NSButton(title: "Explain simply", target: nil, action: nil)
    private let improveButton = NSButton(title: "Improve", target: nil, action: nil)
    private var state = ResultsViewState()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Interview Helper"
        window.minSize = NSSize(width: 520, height: 360)
        window.center()
        window.setFrameAutosaveName("InterviewHelperResults")
        super.init(window: window)
        window.delegate = self
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAnalysis(_ analysis: ScreenAnalysis) {
        state.show(analysis)
        render(scrollTo: .top)
        present()
    }

    /// Latest analysis if there is one this session, otherwise saved history.
    func showLatest() {
        if let analysis = state.analysis {
            showAnalysis(analysis)
        } else {
            showHistory()
        }
    }

    @objc func showHistory() {
        let rows = QAStore.list()
        if rows.isEmpty {
            textView.string = "No saved Q&A yet.\n\nCapture with ⌥⇧S from the menu bar."
        } else {
            // Every kept row: QAStore.list() is already capped at the History size setting.
            let saved = rows.enumerated().map { index, row in
                "\(index + 1). Q: \(row.q)\nA: \(row.a)"
            }.joined(separator: "\n\n———\n\n")
            textView.string = "Saved Q&A\n\n\(saved)"
        }
        // "Show results" returns to the latest analysis.
        state.showHistory()
        updateButtons()
        present()
    }

    @objc private func toggleSolution() {
        state.toggleSolution()
        render(scrollTo: .top)
    }

    @objc private func explainOrToggleExplanation() {
        if state.toggleCachedExplanation() {
            render(scrollTo: state.isExplanationVisible ? .explanation : .top)
            return
        }
        guard let current = state.analysis else { return }
        perform(.explain) { [weak self] settings, apiKey, onRetry in
            let text = try await OpenAIAnalyzer.explain(
                current: current,
                apiKey: apiKey,
                model: settings.model,
                reasoningEffort: settings.reasoningEffort,
                onRetry: onRetry
            )
            guard let self, self.state.receiveExplanation(text, for: current), !self.state.isShowingHistory else { return }
            self.render(scrollTo: .explanation)
        }
    }

    @objc private func improve() {
        guard let current = state.analysis else { return }
        perform(.improve) { [weak self] settings, apiKey, onRetry in
            let improved = try await OpenAIAnalyzer.improve(
                current: current,
                apiKey: apiKey,
                model: settings.model,
                reasoningEffort: settings.reasoningEffort,
                onRetry: onRetry
            )
            QAStore.upsert(QARecord.from(improved))
            // A newer capture may have arrived meanwhile; history is updated either way, the view only if still current.
            guard let self, self.state.isCurrent(current) else { return }
            self.showAnalysis(improved)
        }
    }

    /// Runs one model request with the busy/retry UI and a failure alert; ignores clicks while another is running.
    private func perform(
        _ action: ResultsViewState.PendingAction,
        request: @escaping @MainActor (ModelSettings, String, @escaping RetryObserver) async throws -> Void
    ) {
        guard state.canStartRequest else { return }
        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
            NSAlert.show(title: "API key required", message: "Add your OpenAI API key in Settings.")
            return
        }
        let settings = ModelSettings.load()
        state.begin(action)
        updateButtons()
        Task { @MainActor in
            defer {
                state.finishRequest()
                updateButtons()
            }
            do {
                try await request(settings, apiKey) { [weak self] event in
                    self?.state.noteRetry(event)
                    self?.updateButtons()
                }
            } catch {
                NSAlert.show(title: action.failureTitle, message: error.localizedDescription)
            }
        }
    }

    private func render(scrollTo target: ScrollTarget) {
        guard let text = state.analysisText else { return }
        textView.string = text
        switch target {
        case .top:
            textView.scrollToBeginningOfDocument(nil)
        case .explanation:
            scrollToExplanationHeading()
        }
        updateButtons()
    }

    /// Puts the "Explained simply" heading at the top of the visible area (the explanation is appended below the solution).
    private func scrollToExplanationHeading() {
        let range = (textView.string as NSString).range(of: ResultsText.explanationHeading)
        guard range.location != NSNotFound,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else {
            return
        }
        layoutManager.ensureLayout(for: container)
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let headingRect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        textView.scroll(NSPoint(x: 0, y: headingRect.minY + textView.textContainerOrigin.y))
    }

    private func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateButtons() {
        solutionButton.title = state.solutionButtonTitle
        solutionButton.isEnabled = state.canToggleSolution
        explainButton.title = state.explainButtonTitle
        explainButton.isEnabled = state.canStartRequest
        improveButton.title = state.improveButtonTitle
        improveButton.isEnabled = state.canStartRequest
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)

        let actions: [(NSButton, Selector)] = [
            (historyButton, #selector(showHistory)),
            (solutionButton, #selector(toggleSolution)),
            (explainButton, #selector(explainOrToggleExplanation)),
            (improveButton, #selector(improve)),
        ]
        for (button, action) in actions {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        updateButtons()

        for view in [scrollView, historyButton, solutionButton, explainButton, improveButton] {
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: improveButton.topAnchor, constant: -10),
            historyButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            historyButton.centerYAnchor.constraint(equalTo: improveButton.centerYAnchor),
            solutionButton.leadingAnchor.constraint(equalTo: historyButton.trailingAnchor, constant: 8),
            solutionButton.centerYAnchor.constraint(equalTo: improveButton.centerYAnchor),
            improveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            improveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            explainButton.trailingAnchor.constraint(equalTo: improveButton.leadingAnchor, constant: -8),
            explainButton.centerYAnchor.constraint(equalTo: improveButton.centerYAnchor),
        ])
    }
}

extension NSAlert {
    static func show(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
