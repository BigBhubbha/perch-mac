// Makes sure Perch runs from /Applications. Apps opened from Downloads or the disk image get
// "translocated" by macOS and cannot update themselves, which is how duplicate copies happen.
import AppKit

@MainActor
enum Installer {
    static let systemTarget = URL(fileURLWithPath: "/Applications/Perch.app")
    static var userTarget: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Perch.app")
    }

    /// /Applications when this account can write there, otherwise ~/Applications (non-admin accounts).
    /// Sparkle updates in place wherever Perch lives, as long as that folder is writable.
    static var target: URL {
        FileManager.default.isWritableFile(atPath: "/Applications") ? systemTarget : userTarget
    }

    static var isInApplications: Bool {
        let here = Bundle.main.bundleURL.standardizedFileURL.path
        return here == systemTarget.path || here == userTarget.standardizedFileURL.path
    }

    /// Returns true when Perch is moving itself and this copy is about to quit.
    static func offerMoveIfNeeded() -> Bool {
        guard !isInApplications else { return false }
        let here = Bundle.main.bundleURL
        // Never nag about builds sitting in a developer's build folder.
        if here.path.contains("/build/") || here.path.contains("/.build/") { return false }

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Move Perch to Applications?"
        alert.informativeText = "Perch keeps itself up to date from there, and macOS remembers its permissions in one place. It only takes a second."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not now")
        alert.icon = NSApp.applicationIconImage
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let original = originalLocation(of: here)
        do {
            let fm = FileManager.default
            // Quit any other Perch first so its files are free.
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                app.terminate()
            }
            let target = self.target
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) {
                try fm.trashItem(at: target, resultingItemURL: nil)
            }
            // ditto keeps the framework symlinks intact; --noqtn leaves the download warning behind,
            // since you already said yes to opening Perch.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["--noqtn", here.path, target.path]
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0, fm.fileExists(atPath: target.path) else {
                throw NSError(domain: "Perch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Copying into Applications did not work."])
            }
            // Tidy the old copy away (not the disk image, which is read only).
            if let original, !original.path.hasPrefix("/Volumes/"), fm.isDeletableFile(atPath: original.path) {
                try? fm.trashItem(at: original, resultingItemURL: nil)
            }
        } catch {
            let fail = NSAlert()
            fail.messageText = "Perch could not move itself"
            fail.informativeText = "Paste this into Terminal instead:\ncurl -fsSL https://raw.githubusercontent.com/BigBhubbha/perch-mac/main/scripts/install.sh | sh\n\n\(error.localizedDescription)"
            fail.runModal()
            return false
        }
        relaunch(from: target)
        return true
    }

    /// Opens the new copy once this one has fully quit.
    static func relaunch(from url: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", url.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// Where a translocated app really lives, using the same Security call LetsMove relies on.
    private static func originalLocation(of url: URL) -> URL? {
        guard url.path.contains("/AppTranslocation/") else { return url }
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(url as CFURL, nil)?.takeRetainedValue() as URL?
    }
}
