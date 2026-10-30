// Built-in updates through Sparkle 2. Feed URL, public EdDSA key and daily checks live in Info.plist.
// Updates replace /Applications/Perch.app in place and keep the same signature, so permissions stay.
import AppKit
import Sparkle

@MainActor
final class Updater {
    private let driverDelegate = UpdaterDriverDelegate()
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                  userDriverDelegate: driverDelegate)
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

/// Perch lives at the top of the screen, so bring Sparkle's window forward when it has news.
final class UpdaterDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }
}
