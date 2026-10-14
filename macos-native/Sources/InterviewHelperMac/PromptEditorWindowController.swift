import AppKit
import InterviewHelperCore

@MainActor
final class PromptEditorWindowController: NSWindowController {
    private let scrollView = NSTextView.scrollableTextView()
    private var textView: NSTextView { scrollView.documentView as! NSTextView }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Analysis prompt"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("InterviewHelperPromptEditor")
        super.init(window: window)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Reloads the saved prompt each time so a cancelled edit never lingers.
    func present() {
        textView.string = UserDefaults.standard.string(forKey: UDKeys.customPromptText) ?? AnalyzePrompt.defaultBundled
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func save() {
        UserDefaults.standard.set(textView.string, forKey: UDKeys.customPromptText)
        close()
    }

    @objc private func cancel() {
        close()
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        let padding: CGFloat = 12

        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [scrollView, saveButton, cancelButton] {
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: padding),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -padding),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: padding),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -padding),
            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -padding),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -padding),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -10),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])
    }
}
