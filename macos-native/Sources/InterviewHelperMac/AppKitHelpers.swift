import AppKit
import InterviewHelperCore

extension NSWindowController {
    /// Shows the window in front of other apps (this is a menu bar app, so it is never active on its own).
    func bringToFront() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension NSAlert {
    /// Runs a modal alert; returns `true` when the first button was chosen.
    @discardableResult
    static func show(
        title: String,
        message: String,
        style: NSAlert.Style = .warning,
        buttons: [String] = []
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension NSMenu {
    /// Adds an item; with `autoenablesItems` (the default) an item without an action shows disabled.
    @discardableResult
    func addAction(_ title: String, _ action: Selector? = nil, target: AnyObject? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        addItem(item)
        return item
    }
}

enum APIKeyGate {
    /// The saved key, or `nil` after telling the user to add one in Settings.
    @MainActor
    static func require() -> String? {
        if let key = KeychainStore.loadAPIKey() {
            return key
        }
        NSAlert.show(title: "API key required", message: OpenAIAnalyzer.AnalyzerError.missingAPIKey.errorDescription ?? "")
        return nil
    }
}
