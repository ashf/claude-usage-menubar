import AppKit

var appDelegate: AppDelegate!

MainActor.assumeIsolated {
    appDelegate = AppDelegate()
    NSApplication.shared.delegate = appDelegate
}
NSApplication.shared.run()
