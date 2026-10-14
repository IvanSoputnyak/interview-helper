import AppKit
import InterviewHelperCore
import ScreenCaptureKit

@MainActor
enum ScreenCapture {
    enum CaptureError: LocalizedError {
        case noDisplay
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .noDisplay:
                return "Could not find the display under the cursor."
            case .encodingFailed:
                return "Could not encode the screenshot."
            }
        }
    }

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    /// PNG of the display under the cursor, excluding Interview Helper's own windows, downscaled to `CaptureSizing`.
    static func captureDisplayUnderCursor() async throws -> Data {
        let mousePoint = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mousePoint) }) ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            throw CaptureError.noDisplay
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        let scale = screen.backingScaleFactor

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let size = CaptureSizing.fit(
            width: Int((CGFloat(display.width) * scale).rounded()),
            height: Int((CGFloat(display.height) * scale).rounded())
        )
        let config = SCStreamConfiguration()
        config.width = size.width
        config.height = size.height
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CaptureError.encodingFailed
        }
        return png
    }
}
