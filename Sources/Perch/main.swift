// Entry point. Perch is a regular app: Dock icon, Cmd+Tab, plus the island over the camera.
// Clicking the Dock icon opens Settings.
import AppKit

// `Perch --perch-health-check <file>`: the installer runs this on a fresh copy before replacing anything.
// Reaching this line means macOS let the app start and every framework loaded.
if let i = CommandLine.arguments.firstIndex(of: "--perch-health-check"), i + 1 < CommandLine.arguments.count {
    let v = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
    let body = "{\"ok\":true,\"version\":\"\(v)\",\"path\":\"\(Bundle.main.bundlePath)\"}"
    try? body.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
    exit(0)
}

MainActor.assumeIsolated {
    if Snapshots.runIfRequested() { exit(0) }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
    _ = delegate
}
