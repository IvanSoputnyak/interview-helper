import AppKit
import Carbon
import CoreGraphics
import Foundation

/// Sent to `/api/analyze` when unlock is OFF, or custom text empty while unlocked.
private let defaultBundledAnalysisPrompt = """
Interview question solver mode.
Assume FAANG-style coding interview.
Give a good solution: not brute force unless optimal, and not over-engineered.
Return a well-formatted code snippet.
Use few words and simple words.
Also include:
- why this algorithm is used
- time complexity
- space complexity
"""

private enum UDKeys {
    /// When false (default): always use `defaultBundledAnalysisPrompt`.
    static let promptUnlockEnabled = "IH.promptUnlockEnabled"
    /// Persisted multi-line prompt; only applied when unlock is enabled and non-whitespace after trim.
    static let customPromptText = "IH.customPromptText"
    /// One-time hint so users know this is a menu bar app (no Dock icon).
    static let hasShownMenuBarHint = "IH.hasShownMenuBarHint"
}

private enum TraySymbol {
    static func menuBarIcon() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        guard let img = NSImage(
            systemSymbolName: "doc.text.viewfinder",
            accessibilityDescription: "Interview Helper — capture coding question screen"
        )?.withSymbolConfiguration(config) else {
            return nil
        }
        img.isTemplate = true
        return img
    }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var captureItem: NSMenuItem?
    private var promptUnlockMenuItem: NSMenuItem?
    private var editPromptMenuItem: NSMenuItem?
    private var promptEditorWindow: NSWindow?
    private var promptEditTextView: NSTextView?
    private var statusTextItem: NSMenuItem?
    private var backendProcess: Process?
    private var viewerToken: String?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private let serverBaseURLString: String
    private let projectRoot: String
    private let viewerTokenOverride: String?
    private var isCapturing = false

    /// Clears fleeting status text (e.g. "Done") back to Idle.
    private var statusResetTask: Task<Void, Never>?

    private var serverBaseURL: URL {
        URL(string: serverBaseURLString) ?? URL(string: "http://127.0.0.1:3000")!
    }

    override init() {
        let env = ProcessInfo.processInfo.environment
        self.serverBaseURLString = env["IH_SERVER_BASE_URL"] ?? "http://127.0.0.1:3000"
        self.projectRoot = env["IH_PROJECT_ROOT"] ?? FileManager.default.currentDirectoryPath
        self.viewerTokenOverride = env["VIEWER_TOKEN"]
        super.init()
    }

    /// Effective prompt for capture + upload (hardcoded unless unlock is on + non-empty saved text).
    private func effectiveAnalyzePrompt() -> String {
        let ud = UserDefaults.standard
        guard ud.bool(forKey: UDKeys.promptUnlockEnabled) else {
            return defaultBundledAnalysisPrompt
        }
        let custom = ud.string(forKey: UDKeys.customPromptText)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if custom.isEmpty {
            return defaultBundledAnalysisPrompt
        }
        return custom
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        fputs("Interview Helper: running as a menu bar app — look for “IH” near the clock (no Dock icon).\n", stderr)
        setupMenuBar()
        updateStatus("Idle")
        Task { @MainActor in
            await ensureBackendReady()
        }
        registerGlobalHotKey()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            showMenuBarHintIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusResetTask?.cancel()
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
        }
        backendProcess?.terminate()
    }

    @objc private func onCaptureAnalyze() {
        if isCapturing {
            return
        }
        isCapturing = true

        guard ensureScreenCapturePermission() else {
            isCapturing = false
            updateStatus("Screen permission required")
            showPermissionAlert(
                title: "Screen Recording Permission Required",
                message:
                    "Enable Screen Recording for InterviewHelperMac in System Settings > Privacy & Security > Screen Recording, then capture again.\n\n"
                    + "If that list shows Cursor or Terminal instead of InterviewHelperMac, you started a plain swift run from an IDE terminal. Quit it, launch dist/InterviewHelperMac.app (for example run “make mac-app-debug” in the repo), then enable Screen Recording for InterviewHelperMac only."
            )
            return
        }

        guard let pngData = captureDisplayUnderCursor() else {
            isCapturing = false
            updateStatus("Capture failed")
            showAlert(title: "Capture failed", message: "Could not capture the active display.")
            return
        }

        setCaptureEnabled(false)
        updateStatus("Analyzing...")

        Task { @MainActor in
            do {
                await ensureBackendReady()
                try await uploadForAnalysis(screenshotPng: pngData, prompt: effectiveAnalyzePrompt())
                scheduleStatusRevert(afterBrief: "Ready")
            } catch {
                updateStatus("Analyze failed")
                showAlert(title: "Analyze failed", message: error.localizedDescription)
            }
            isCapturing = false
            setCaptureEnabled(true)
        }
    }

    @objc private func onOpenViewer() {
        guard let token = viewerToken, !token.isEmpty else {
            showAlert(title: "Viewer token missing", message: "Could not resolve VIEWER_TOKEN from backend health.")
            return
        }
        var components = URLComponents(url: serverBaseURL.appendingPathComponent("viewer"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let viewerURL = components?.url else {
            showAlert(title: "Viewer URL error", message: "Failed to build secure viewer URL.")
            return
        }
        NSWorkspace.shared.open(viewerURL)
    }

    @objc private func onCopyViewerURL() {
        guard let token = viewerToken, !token.isEmpty else {
            showAlert(title: "Viewer token missing", message: "Ensure the backend is running and reachable from this app.")
            return
        }
        var components = URLComponents(url: serverBaseURL.appendingPathComponent("viewer"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let viewerURL = components?.url?.absoluteString else {
            showAlert(title: "Copy failed", message: "Could not build viewer URL.")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewerURL, forType: .string)
        scheduleStatusRevert(afterBrief: "Copied link")
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
        if !newValue {
            promptEditorWindow?.close()
        }
    }

    @objc private func openPromptEditor() {
        guard UserDefaults.standard.bool(forKey: UDKeys.promptUnlockEnabled) else {
            return
        }

        if promptEditorWindow != nil {
            promptEditorWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let padding: CGFloat = 12
        let windowRect = NSRect(x: 0, y: 0, width: 480, height: 280)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Interview analysis prompt"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 420, height: 260)
        window.center()
        window.setFrameAutosaveName("InterviewHelperPromptEditor")

        let root = NSView(frame: windowRect)
        root.autoresizesSubviews = true
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView(frame: .zero)
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = UserDefaults.standard.string(forKey: UDKeys.customPromptText) ?? defaultBundledAnalysisPrompt
        scroll.documentView = textView
        promptEditTextView = textView

        let saveButton = NSButton(title: "Save", target: nil, action: nil)
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.target = self
        saveButton.action = #selector(savePromptFromEditor)
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = .command

        let resetButton = NSButton(title: "Reset to default", target: nil, action: nil)
        resetButton.bezelStyle = .rounded
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.target = self
        resetButton.action = #selector(resetPromptDraft)

        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.target = self
        cancelButton.action = #selector(closePromptEditor)

        root.addSubview(scroll)
        root.addSubview(saveButton)
        root.addSubview(resetButton)
        root.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: padding),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -padding),
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: padding),
            scroll.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -padding),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),

            cancelButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: padding),
            resetButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 10),

            resetButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            saveButton.leadingAnchor.constraint(greaterThanOrEqualTo: resetButton.trailingAnchor, constant: 12),
            saveButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -padding),
            saveButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -padding),

            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),

            saveButton.heightAnchor.constraint(equalToConstant: 28),
            cancelButton.heightAnchor.constraint(equalToConstant: 28),
            resetButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        promptEditorWindow = window
        root.frame = CGRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func savePromptFromEditor() {
        if let textView = promptEditTextView {
            UserDefaults.standard.set(textView.string, forKey: UDKeys.customPromptText)
        }
        promptEditorWindow?.close()
    }

    @objc private func closePromptEditor() {
        promptEditorWindow?.close()
    }

    @objc private func resetPromptDraft() {
        promptEditTextView?.string = defaultBundledAnalysisPrompt
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else {
            return
        }
        guard closing === promptEditorWindow else {
            return
        }
        closing.delegate = nil
        promptEditorWindow = nil
        promptEditTextView = nil
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item

        item.button?.toolTip =
            "Interview Helper — ⌥⇧S capture • menu for viewer & prompts"
        // Always show “IH” text so the app is easy to spot (icon-only is easy to miss).
        item.button?.title = "IH"
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        if let trayImage = TraySymbol.menuBarIcon() {
            item.button?.image = trayImage
            item.button?.imagePosition = .imageLeading
        } else {
            item.button?.image = nil
            item.button?.imagePosition = .noImage
        }
        item.button?.setAccessibilityTitle("Interview Helper")

        let menu = NSMenu()

        let headline = NSMenuItem(title: "Interview Helper", action: nil, keyEquivalent: "")
        headline.isEnabled = false
        menu.addItem(headline)

        let capture = NSMenuItem(title: "Capture & Analyze (⌥⇧S)", action: #selector(onCaptureAnalyze), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        self.captureItem = capture

        let openViewer = NSMenuItem(title: "Open Viewer in Browser", action: #selector(onOpenViewer), keyEquivalent: "")
        openViewer.target = self
        menu.addItem(openViewer)

        let copyURL = NSMenuItem(title: "Copy Viewer Link", action: #selector(onCopyViewerURL), keyEquivalent: "c")
        copyURL.keyEquivalentModifierMask = [.command, .shift]
        copyURL.target = self
        menu.addItem(copyURL)

        menu.addItem(NSMenuItem.separator())

        let unlockPromptItem = NSMenuItem(
            title: "Customize prompt (advanced)",
            action: #selector(togglePromptUnlock),
            keyEquivalent: ""
        )
        unlockPromptItem.target = self
        unlockPromptItem.state = UserDefaults.standard.bool(forKey: UDKeys.promptUnlockEnabled) ? .on : .off
        promptUnlockMenuItem = unlockPromptItem
        menu.addItem(unlockPromptItem)

        let editPromptItem = NSMenuItem(title: "Edit custom prompt…", action: #selector(openPromptEditor), keyEquivalent: "")
        editPromptItem.target = self
        editPromptItem.isEnabled = UserDefaults.standard.bool(forKey: UDKeys.promptUnlockEnabled)
        editPromptMenuItem = editPromptItem
        menu.addItem(editPromptItem)

        menu.addItem(NSMenuItem.separator())

        let hint = NSMenuItem(title: "Default prompt is bundled; toggle above only if you edit.", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        menu.addItem(NSMenuItem.separator())

        let statusItem = NSMenuItem(title: "Status · Idle", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        self.statusTextItem = statusItem

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    private func registerGlobalHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x49484B59), id: 1) // "IHKY"
        let modifiers = UInt32(optionKey | shiftKey)
        let keyCode = UInt32(kVK_ANSI_S)

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard
                let eventRef,
                let userData
            else {
                return OSStatus(eventNotHandledErr)
            }

            var hkID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            if status != noErr {
                return status
            }
            if hkID.signature == OSType(0x49484B59) && hkID.id == 1 {
                let controller = Unmanaged<AppController>.fromOpaque(userData).takeUnretainedValue()
                controller.onCaptureAnalyze()
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )
        if installStatus != noErr {
            showAlert(title: "Hotkey setup failed", message: "Could not install global hotkey handler.")
            return
        }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            showAlert(title: "Hotkey unavailable", message: "Could not register Option+Shift+S.")
        }
    }

    private func updateStatus(_ status: String) {
        statusResetTask?.cancel()
        statusTextItem?.title = "Status · \(status)"
    }

    private func scheduleStatusRevert(afterBrief message: String) {
        statusResetTask?.cancel()
        updateStatus(message)
        statusResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled {
                statusTextItem?.title = "Status · Idle"
            }
        }
    }

    private func setCaptureEnabled(_ enabled: Bool) {
        captureItem?.isEnabled = enabled
    }

    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    private func captureDisplayUnderCursor() -> Data? {
        let mousePoint = NSEvent.mouseLocation
        let screens = NSScreen.screens

        guard let targetScreen = screens.first(where: { $0.frame.contains(mousePoint) }) ?? screens.first,
              let screenNumber = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return nil
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    private func ensureBackendReady() async {
        if await isBackendHealthy() {
            return
        }
        startBackendIfNeeded()
        for _ in 0..<25 {
            if await isBackendHealthy() {
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func isBackendHealthy() async -> Bool {
        let healthURL = serverBaseURL.appendingPathComponent("api/health")
        do {
            let (data, response) = try await URLSession.shared.data(from: healthURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return false
            }
            if let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let healthToken = payload["viewerToken"] as? String, !healthToken.isEmpty {
                    viewerToken = healthToken
                } else if let overrideToken = viewerTokenOverride, !overrideToken.isEmpty {
                    viewerToken = overrideToken
                }
                return (payload["ok"] as? Bool) == true
            }
            return false
        } catch {
            return false
        }
    }

    private func startBackendIfNeeded() {
        if backendProcess != nil {
            return
        }
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: projectRoot, isDirectory: true)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "start"]
        var env = ProcessInfo.processInfo.environment
        if let overrideToken = viewerTokenOverride, !overrideToken.isEmpty {
            env["VIEWER_TOKEN"] = overrideToken
        }
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            backendProcess = process
            updateStatus("Starting backend…")
        } catch {
            showAlert(
                title: "Backend start failed",
                message: "Could not run npm start in \(projectRoot). Start backend manually and retry."
            )
        }
    }

    private func uploadForAnalysis(screenshotPng: Data, prompt: String) async throws {
        let endpoint = serverBaseURL.appendingPathComponent("api/analyze")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(boundary: boundary, screenshotPng: screenshotPng, prompt: prompt)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "InterviewHelperMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "InterviewHelperMac", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode). Ensure backend is running at \(serverBaseURL.absoluteString)."])
        }
    }

    private func buildMultipartBody(boundary: String, screenshotPng: Data, prompt: String) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\(lineBreak)")
        append("Content-Disposition: form-data; name=\"prompt\"\(lineBreak)\(lineBreak)")
        append("\(prompt)\(lineBreak)")

        append("--\(boundary)\(lineBreak)")
        append("Content-Disposition: form-data; name=\"screenshot\"; filename=\"capture.png\"\(lineBreak)")
        append("Content-Type: image/png\(lineBreak)\(lineBreak)")
        body.append(screenshotPng)
        append(lineBreak)
        append("--\(boundary)--\(lineBreak)")

        return body
    }

    private func showPermissionAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(settingsURL)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    /// Menu bar apps have no Dock icon; first run we explain where to look.
    private func showMenuBarHintIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: UDKeys.hasShownMenuBarHint) else {
            return
        }
        ud.set(true, forKey: UDKeys.hasShownMenuBarHint)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Interview Helper is running"
        alert.informativeText =
            "This app lives in the menu bar at the top of the screen, not in the Dock.\n\n"
            + "Look for “IH” (and a small document icon) near the Wi‑Fi, battery, and clock.\n\n"
            + "Click it for the menu, or press ⌥⇧S (Option+Shift+S) to capture."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@main
struct InterviewHelperMacMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        app.run()
    }
}
