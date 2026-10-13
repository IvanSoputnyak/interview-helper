import AppKit
import Carbon
import Foundation
import InterviewHelperCore
import os

private enum TraySymbol {
    static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setStroke()
        let lineWidth: CGFloat = 1.8
        let bubble = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 5.5, width: 19, height: 10), xRadius: 3, yRadius: 3)
        bubble.lineWidth = lineWidth
        bubble.stroke()
        let tail = NSBezierPath()
        tail.lineWidth = lineWidth
        tail.lineJoinStyle = .round
        tail.lineCapStyle = .round
        tail.move(to: NSPoint(x: 10, y: 5.7))
        tail.line(to: NSPoint(x: 11.7, y: 2.4))
        tail.line(to: NSPoint(x: 15.2, y: 5.7))
        tail.stroke()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8.7, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let mark = NSAttributedString(string: "IH", attributes: attrs)
        let textSize = mark.size()
        mark.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: 6.3))
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Interview Helper"
        return image
    }
}

private enum HotKey {
    /// "IHKY" — identifies our hotkey in the Carbon event callback.
    static let signature = OSType(0x49484B59)
    static let captureID: UInt32 = 1
}

private enum Timing {
    static let launchHintDelay: UInt64 = 400_000_000
    static let statusRevertDelay: UInt64 = 3_500_000_000
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: KeychainStore.service, category: "App")

    private var statusItem: NSStatusItem?
    private var captureItem: NSMenuItem?
    private var promptUnlockMenuItem: NSMenuItem?
    private var editPromptMenuItem: NSMenuItem?
    private var statusTextItem: NSMenuItem?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var isCapturing = false
    private var statusResetTask: Task<Void, Never>?

    private lazy var resultsWindow = ResultsWindowController()
    private lazy var settingsWindow = SettingsWindowController()
    private lazy var promptEditorWindow = PromptEditorWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        updateStatus("Idle")
        registerGlobalHotKey()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Timing.launchHintDelay)
            showMenuBarHintIfNeeded()
            if KeychainStore.loadAPIKey() == nil {
                onOpenSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusResetTask?.cancel()
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let hotKeyHandlerRef { RemoveEventHandler(hotKeyHandlerRef) }
    }

    @objc private func onCaptureAnalyze() {
        if isCapturing { return }
        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
            NSAlert.show(title: "API key required", message: "Add your OpenAI API key in Settings.")
            onOpenSettings()
            return
        }
        guard ScreenCapture.hasPermission() else {
            updateStatus("Screen permission required")
            showPermissionAlert()
            return
        }

        isCapturing = true
        setCaptureEnabled(false)
        updateStatus("Capturing...")
        let settings = ModelSettings.load()
        let prompt = effectiveAnalyzePrompt()

        Task { @MainActor in
            defer {
                isCapturing = false
                setCaptureEnabled(true)
            }
            let pngData: Data
            do {
                pngData = try await ScreenCapture.captureDisplayUnderCursor()
            } catch {
                updateStatus("Capture failed")
                NSAlert.show(title: "Capture failed", message: error.localizedDescription)
                return
            }

            updateStatus("Analyzing...")
            do {
                let analysis = try await OpenAIAnalyzer.analyze(
                    screenshotPng: pngData,
                    prompt: prompt,
                    apiKey: apiKey,
                    model: settings.model,
                    reasoningEffort: settings.reasoningEffort,
                    onRetry: { [weak self] event in self?.updateStatus(event.displayText) }
                )
                QAStore.append(QARecord.from(analysis))
                resultsWindow.showAnalysis(analysis)
                scheduleStatusRevert(afterBrief: "Ready")
            } catch {
                updateStatus("Analyze failed")
                NSAlert.show(title: "Analyze failed", message: error.localizedDescription)
            }
        }
    }

    @objc private func onShowResults() {
        resultsWindow.showLatest()
    }

    @objc private func onShowHistory() {
        resultsWindow.showHistory()
    }

    @objc private func onOpenSettings() {
        settingsWindow.present()
    }

    @objc private func onOpenScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func onQuit() {
        NSApp.terminate(nil)
    }

    @objc private func togglePromptUnlock() {
        let ud = UserDefaults.standard
        let newValue = !ud.bool(forKey: UDKeys.promptUnlockEnabled)
        ud.set(newValue, forKey: UDKeys.promptUnlockEnabled)
        promptUnlockMenuItem?.state = newValue ? .on : .off
        editPromptMenuItem?.isEnabled = newValue
        if !newValue { promptEditorWindow.close() }
    }

    @objc private func openPromptEditor() {
        guard UserDefaults.standard.bool(forKey: UDKeys.promptUnlockEnabled) else { return }
        promptEditorWindow.present()
    }

    private func effectiveAnalyzePrompt() -> String {
        AnalyzePrompt.effective(
            unlockEnabled: UserDefaults.standard.bool(forKey: UDKeys.promptUnlockEnabled),
            customPrompt: UserDefaults.standard.string(forKey: UDKeys.customPromptText)
        )
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.toolTip = "Interview Helper — ⌥⇧S capture"
        item.button?.image = TraySymbol.menuBarIcon()
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(disabled: "Interview Helper")
        let capture = NSMenuItem(title: "Capture & Analyze (⌥⇧S)", action: #selector(onCaptureAnalyze), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        captureItem = capture

        let results = NSMenuItem(title: "Show results", action: #selector(onShowResults), keyEquivalent: "r")
        results.keyEquivalentModifierMask = .command
        results.target = self
        menu.addItem(results)

        let history = NSMenuItem(title: "Show history", action: #selector(onShowHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)

        let settings = NSMenuItem(title: "Settings…", action: #selector(onOpenSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem.separator())
        let unlock = NSMenuItem(title: "Customize prompt (advanced)", action: #selector(togglePromptUnlock), keyEquivalent: "")
        unlock.target = self
        unlock.state = UserDefaults.standard.bool(forKey: UDKeys.promptUnlockEnabled) ? .on : .off
        promptUnlockMenuItem = unlock
        menu.addItem(unlock)
        let editPrompt = NSMenuItem(title: "Edit custom prompt…", action: #selector(openPromptEditor), keyEquivalent: "")
        editPrompt.target = self
        editPrompt.isEnabled = UserDefaults.standard.bool(forKey: UDKeys.promptUnlockEnabled)
        editPromptMenuItem = editPrompt
        menu.addItem(editPrompt)

        menu.addItem(NSMenuItem.separator())
        let screen = NSMenuItem(title: "Screen Recording settings…", action: #selector(onOpenScreenRecordingSettings), keyEquivalent: "")
        screen.target = self
        menu.addItem(screen)

        let status = NSMenuItem(title: "Status · Idle", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusTextItem = status

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    private func registerGlobalHotKey() {
        let hotKeyID = EventHotKeyID(signature: HotKey.signature, id: HotKey.captureID)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            guard GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID) == noErr else {
                return OSStatus(eventNotHandledErr)
            }
            if hkID.signature == HotKey.signature, hkID.id == HotKey.captureID {
                let controller = Unmanaged<AppController>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { controller.onCaptureAnalyze() }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandlerRef)
        let registerStatus = installStatus == noErr
            ? RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
            : installStatus
        if registerStatus != noErr {
            // Most often another app already owns ⌥⇧S; the menu item still works.
            Self.log.error("Global hotkey ⌥⇧S unavailable (OSStatus \(registerStatus))")
            captureItem?.title = "Capture & Analyze (hotkey unavailable)"
        }
    }

    private func updateStatus(_ status: String) {
        statusResetTask?.cancel()
        statusTextItem?.title = "Status · \(status)"
    }

    private func scheduleStatusRevert(afterBrief message: String) {
        updateStatus(message)
        statusResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Timing.statusRevertDelay)
            if !Task.isCancelled { statusTextItem?.title = "Status · Idle" }
        }
    }

    private func setCaptureEnabled(_ enabled: Bool) { captureItem?.isEnabled = enabled }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screen Recording permission required"
        alert.informativeText = "Enable Screen Recording for Interview Helper in System Settings, then try again."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onOpenScreenRecordingSettings()
        }
    }

    private func showMenuBarHintIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: UDKeys.hasShownMenuBarHint) else { return }
        ud.set(true, forKey: UDKeys.hasShownMenuBarHint)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Interview Helper is running"
        alert.informativeText = "Look for IH in the menu bar. Press ⌥⇧S to capture a coding question."
        alert.runModal()
    }
}

private extension NSMenu {
    func addItem(disabled title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}
