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
final class AppController: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private static let log = Logger(subsystem: KeychainStore.service, category: "App")
    /// Shown in the terminal when the binary is run directly (e.g. `make mac-native`); launches via Finder/`open` discard stderr.
    private static let terminalLaunchHint = "Interview Helper is running: look for \"IH\" in the menu bar (top right). Press ⌥⇧S to capture.\n"

    private var statusItem: NSStatusItem?
    private var captureItem: NSMenuItem?
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
        FileHandle.standardError.write(Data(Self.terminalLaunchHint.utf8))
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
        QAStore.flush()
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let hotKeyHandlerRef { RemoveEventHandler(hotKeyHandlerRef) }
    }

    @objc private func onCaptureAnalyze() {
        if isCapturing { return }
        guard let apiKey = APIKeyGate.require() else {
            onOpenSettings()
            return
        }
        guard ScreenCapture.hasPermission() else {
            updateStatus("Screen permission required")
            showPermissionAlert()
            return
        }

        isCapturing = true
        updateStatus("Capturing...")
        let settings = ModelSettings.load()
        let prompt = effectiveAnalyzePrompt()

        Task { @MainActor in
            defer { isCapturing = false }
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
                    onRetry: { event in self.updateStatus(event.displayText) }
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
        isPromptUnlocked.toggle()
        if !isPromptUnlocked { promptEditorWindow.close() }
    }

    @objc private func openPromptEditor() {
        guard isPromptUnlocked else { return }
        promptEditorWindow.present()
    }

    private var isPromptUnlocked: Bool {
        get { UserDefaults.standard.bool(forKey: UDKeys.promptUnlockEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: UDKeys.promptUnlockEnabled) }
    }

    private func effectiveAnalyzePrompt() -> String {
        AnalyzePrompt.effective(
            unlockEnabled: isPromptUnlocked,
            customPrompt: UserDefaults.standard.string(forKey: UDKeys.customPromptText)
        )
    }

    /// Menu items are auto-enabled, so their enabled/checked state is decided here each time the menu opens.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(onCaptureAnalyze):
            return !isCapturing
        case #selector(togglePromptUnlock):
            menuItem.state = isPromptUnlocked ? .on : .off
            return true
        case #selector(openPromptEditor):
            return isPromptUnlocked
        default:
            return true
        }
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.toolTip = "Interview Helper — ⌥⇧S capture"
        item.button?.image = TraySymbol.menuBarIcon()
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addAction("Interview Helper")
        captureItem = menu.addAction("Capture & Analyze (⌥⇧S)", #selector(onCaptureAnalyze), target: self)
        menu.addAction("Show results", #selector(onShowResults), target: self, key: "r")
        menu.addAction("Show history", #selector(onShowHistory), target: self)
        menu.addAction("Settings…", #selector(onOpenSettings), target: self, key: ",")
        menu.addItem(.separator())
        menu.addAction("Customize prompt (advanced)", #selector(togglePromptUnlock), target: self)
        menu.addAction("Edit custom prompt…", #selector(openPromptEditor), target: self)
        menu.addItem(.separator())
        menu.addAction("Screen Recording settings…", #selector(onOpenScreenRecordingSettings), target: self)
        statusTextItem = menu.addAction("Status · Idle")
        menu.addItem(.separator())
        menu.addAction("Quit", #selector(onQuit), target: self, key: "q")
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

    private func showPermissionAlert() {
        if NSAlert.show(
            title: "Screen Recording permission required",
            message: "Enable Screen Recording for Interview Helper in System Settings, then try again.",
            buttons: ["Open Settings", "Cancel"]
        ) {
            onOpenScreenRecordingSettings()
        }
    }

    private func showMenuBarHintIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: UDKeys.hasShownMenuBarHint) else { return }
        ud.set(true, forKey: UDKeys.hasShownMenuBarHint)
        NSAlert.show(
            title: "Interview Helper is running",
            message: "Look for IH in the menu bar. Press ⌥⇧S to capture a coding question.",
            style: .informational
        )
    }
}
