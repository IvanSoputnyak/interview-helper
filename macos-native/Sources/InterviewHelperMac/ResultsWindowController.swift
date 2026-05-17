import AppKit
import InterviewHelperCore

@MainActor
final class ResultsWindowController: NSWindowController, NSWindowDelegate {
    private let textView = NSTextView()
    private var latest: ScreenAnalysis?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Interview Helper"
        window.minSize = NSSize(width: 420, height: 360)
        window.center()
        window.setFrameAutosaveName("InterviewHelperResults")
        super.init(window: window)
        window.delegate = self
        setupUI()
        reloadSaved()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAnalysis(_ analysis: ScreenAnalysis) {
        latest = analysis
        textView.string = analysis.displayText
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSavedOnly() {
        reloadSaved()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func improve() {
        guard let latest else { return }
        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
            NSAlert.show(title: "API key required", message: "Add your OpenAI API key in Settings.")
            return
        }
        let model = UserDefaults.standard.string(forKey: UDKeys.openAIModel) ?? OpenAIAnalyzer.defaultModel
        Task { @MainActor in
            do {
                let improved = try await OpenAIAnalyzer.improve(current: latest, apiKey: apiKey, model: model)
                QAStore.upsert(QARecord.from(improved))
                showAnalysis(improved)
            } catch {
                NSAlert.show(title: "Improve failed", message: error.localizedDescription)
            }
        }
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        scroll.documentView = textView

        let improveButton = NSButton(title: "Improve", target: self, action: #selector(improve))
        improveButton.bezelStyle = .rounded
        improveButton.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scroll)
        content.addSubview(improveButton)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: improveButton.topAnchor, constant: -10),
            improveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            improveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    private func reloadSaved() {
        let rows = QAStore.list()
        guard !rows.isEmpty else {
            if latest == nil {
                textView.string = "No saved Q&A yet.\n\nCapture with ⌥⇧S from the menu bar."
            }
            return
        }
        let saved = rows.prefix(15).enumerated().map { index, row in
            "\(index + 1). Q: \(row.q)\nA: \(row.a)"
        }.joined(separator: "\n\n———\n\n")
        if latest == nil {
            textView.string = "Saved Q&A\n\n\(saved)"
        }
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
