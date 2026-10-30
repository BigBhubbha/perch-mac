// Entry point. Perch is a regular app: Dock icon, Cmd+Tab, plus the island over the camera.
// Clicking the Dock icon opens Settings.
import AppKit

MainActor.assumeIsolated {
    if Snapshots.runIfRequested() { exit(0) }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
    _ = delegate
}
