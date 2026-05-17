import AppKit
import InterviewHelperCore

enum UDKeys {
    static let promptUnlockEnabled = "IH.promptUnlockEnabled"
    static let customPromptText = "IH.customPromptText"
    static let hasShownMenuBarHint = "IH.hasShownMenuBarHint"
    static let openAIModel = "IH.openAIModel"
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let apiKeyField = NSSecureTextField()
    private let modelField = NSTextField()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        super.init(window: window)
        setupUI()
        loadValues()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func save() {
        do {
            let key = apiKeyField.stringValue
            if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try KeychainStore.deleteAPIKey()
            } else {
                try KeychainStore.saveAPIKey(key)
            }
            UserDefaults.standard.set(modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: UDKeys.openAIModel)
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

        let hint = label("Your key stays in the Mac Keychain. Screenshots are sent only to OpenAI.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [keyLabel, apiKeyField, modelLabel, modelField, hint, saveButton] {
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
            hint.topAnchor.constraint(equalTo: modelField.bottomAnchor, constant: 10),
            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -pad),
        ])
    }

    private func loadValues() {
        apiKeyField.stringValue = KeychainStore.loadAPIKey() ?? ""
        modelField.stringValue = UserDefaults.standard.string(forKey: UDKeys.openAIModel) ?? OpenAIAnalyzer.defaultModel
    }
}
