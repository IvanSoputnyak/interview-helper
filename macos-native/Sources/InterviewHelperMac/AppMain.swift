import AppKit

@MainActor
private enum AppRuntime {
    static var delegate: AppController!
}

@main
struct InterviewHelperMacMain {
    static func main() {
        MainActor.assumeIsolated {
            AppRuntime.delegate = AppController()
            let app = NSApplication.shared
            app.delegate = AppRuntime.delegate
            app.run()
        }
    }
}
