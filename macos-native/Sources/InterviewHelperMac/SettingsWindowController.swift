import AppKit
import InterviewHelperCore

enum UDKeys {
    static let promptUnlockEnabled = "IH.promptUnlockEnabled"
    static let customPromptText = "IH.customPromptText"
    static let hasShownMenuBarHint = "IH.hasShownMenuBarHint"
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let apiKeyField = NSSecureTextField()
    private let modelField = NSTextField()
    private let effortPopup = NSPopUpButton()
    private let historySizeField = NSTextField()
    private static let historySizeFieldWidth: CGFloat = 80
    private static let defaultEffortTitle = "Default (model decides)"
    private static let contentWidth: CGFloat = 440

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 1),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        super.init(window: window)
        setupUI()
        // Height follows the constraint chain so new rows can never overlap the Save button.
        if let content = window.contentView {
            window.setContentSize(NSSize(width: Self.contentWidth, height: content.fittingSize.height))
        }
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Reloads stored values each time so unsaved edits from a closed window never linger.
    func present() {
        loadValues()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func save() {
        do {
            let key = apiKeyField.stringValue
            if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try KeychainStore.deleteAPIKey()
            } else {
                try KeychainStore.saveAPIKey(key)
            }
            ModelSettings.save(model: modelField.stringValue, reasoningEffort: selectedEffort())
            QAStore.saveMaxItems(QAStore.maxItems(fromFieldText: historySizeField.stringValue))
            window?.close()
        } catch {
            NSAlert.show(title: "Could not save", message: error.localizedDescription)
        }
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        let pad: CGFloat = 16

        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.translatesAutoresizingMaskIntoConstraints = false
            return field
        }

        let keyLabel = label("OpenAI API key")
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.placeholderString = "sk-…"
        apiKeyField.focusRingType = .default

        let modelLabel = label("Model")
        modelField.translatesAutoresizingMaskIntoConstraints = false
        modelField.placeholderString = OpenAIAnalyzer.defaultModel

        let effortLabel = label("Reasoning effort (higher = better answers, slower, costlier)")
        effortPopup.translatesAutoresizingMaskIntoConstraints = false
        effortPopup.addItems(withTitles: [Self.defaultEffortTitle] + ReasoningEffort.allCases.map { $0.rawValue.capitalized })

        let historyLabel = label("History size (Q&A rows kept, \(QAStore.minItems)–\(QAStore.maxItemsLimit))")
        historySizeField.translatesAutoresizingMaskIntoConstraints = false
        historySizeField.placeholderString = "\(QAStore.defaultMaxItems)"

        let hint = label("Your key stays in the Mac Keychain. Screenshots are sent only to OpenAI.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [keyLabel, apiKeyField, modelLabel, modelField, effortLabel, effortPopup, historyLabel, historySizeField, hint, saveButton] {
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            keyLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            keyLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: pad),
            apiKeyField.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            apiKeyField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            apiKeyField.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 6),
            modelLabel.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            modelLabel.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: 12),
            modelField.leadingAnchor.constraint(equalTo: modelLabel.leadingAnchor),
            modelField.trailingAnchor.constraint(equalTo: apiKeyField.trailingAnchor),
            modelField.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: apiKeyField.trailingAnchor),
            effortLabel.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            effortLabel.topAnchor.constraint(equalTo: modelField.bottomAnchor, constant: 12),
            effortPopup.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            effortPopup.topAnchor.constraint(equalTo: effortLabel.bottomAnchor, constant: 6),
            historyLabel.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            historyLabel.topAnchor.constraint(equalTo: effortPopup.bottomAnchor, constant: 12),
            historySizeField.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            historySizeField.widthAnchor.constraint(equalToConstant: Self.historySizeFieldWidth),
            historySizeField.topAnchor.constraint(equalTo: historyLabel.bottomAnchor, constant: 6),
            hint.topAnchor.constraint(equalTo: historySizeField.bottomAnchor, constant: 10),
            saveButton.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 14),
            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -pad),
        ])
    }

    private func loadValues() {
        apiKeyField.stringValue = KeychainStore.loadAPIKey() ?? ""
        let settings = ModelSettings.load()
        modelField.stringValue = settings.model
        effortPopup.selectItem(at: Self.popupIndex(for: settings.reasoningEffort))
        historySizeField.integerValue = QAStore.maxItems
    }


    private func selectedEffort() -> ReasoningEffort? {
        Self.effort(atPopupIndex: effortPopup.indexOfSelectedItem)
    }

    // Popup rows: index 0 is "Default (model decides)" (nil), then `ReasoningEffort.allCases` in order.

    private static func popupIndex(for effort: ReasoningEffort?) -> Int {
        guard let effort, let position = ReasoningEffort.allCases.firstIndex(of: effort) else {
            return 0
        }
        return position + 1
    }

    private static func effort(atPopupIndex index: Int) -> ReasoningEffort? {
        guard index > 0, index <= ReasoningEffort.allCases.count else {
            return nil
        }
        return ReasoningEffort.allCases[index - 1]
    }
}
