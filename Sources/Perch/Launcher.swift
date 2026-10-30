// Quick launch: pinned apps, your Shortcuts, and a few one-tap Mac actions.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LaunchApp: Codable, Identifiable, Equatable {
    var id: String { path }
    var path: String
    var name: String { (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "") }
}

@MainActor
final class LauncherStore: ObservableObject {
    @Published var apps: [LaunchApp] = []
    @Published var shortcuts: [String] = []
    @Published var pinnedShortcuts: [String] = []
    @Published var runningShortcut: String?
    @Published var lastResult: String?

    private let appsKey = "launcher.apps"
    private let pinsKey = "launcher.shortcuts"

    init() {
        if let a = UserDefaults.standard.stringArray(forKey: appsKey) {
            apps = a.filter { FileManager.default.fileExists(atPath: $0) }.map { LaunchApp(path: $0) }
        } else {
            apps = Self.defaults().map { LaunchApp(path: $0) }
        }
        pinnedShortcuts = UserDefaults.standard.stringArray(forKey: pinsKey) ?? []
    }

    static func defaults() -> [String] {
        let candidates = ["/Applications/Spotify.app", "/System/Applications/Music.app", "/Applications/Safari.app",
                          "/Applications/Google Chrome.app", "/System/Applications/Notes.app", "/System/Applications/Calendar.app",
                          "/System/Applications/Messages.app", "/Applications/Notion.app", "/Applications/Cursor.app",
                          "/System/Applications/System Settings.app", "/Applications/Discord.app", "/System/Applications/Mail.app"]
        let home = NSHomeDirectory()
        return candidates.compactMap { p in
            if FileManager.default.fileExists(atPath: p) { return p }
            let alt = home + p
            return FileManager.default.fileExists(atPath: alt) ? alt : nil
        }.prefix(8).map { $0 }
    }

    func icon(_ a: LaunchApp) -> NSImage { NSWorkspace.shared.icon(forFile: a.path) }

    func launch(_ a: LaunchApp) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: a.path), configuration: NSWorkspace.OpenConfiguration())
    }

    func addApps(_ urls: [URL]) {
        for u in urls where u.pathExtension == "app" && !apps.contains(where: { $0.path == u.path }) {
            apps.append(LaunchApp(path: u.path))
        }
        save()
    }

    func remove(_ a: LaunchApp) { apps.removeAll { $0 == a }; save() }

    func pickApps() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.allowedContentTypes = [.application]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        if p.runModal() == .OK { addApps(p.urls) }
    }

    private func save() { UserDefaults.standard.set(apps.map(\.path), forKey: appsKey) }

    // MARK: Shortcuts

    func loadShortcuts() {
        Task.detached {
            let out = Self.run("/usr/bin/shortcuts", ["list"])
            let names = out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            await MainActor.run { self.shortcuts = names }
        }
    }

    func togglePin(_ name: String) {
        if let i = pinnedShortcuts.firstIndex(of: name) { pinnedShortcuts.remove(at: i) } else { pinnedShortcuts.append(name) }
        UserDefaults.standard.set(pinnedShortcuts, forKey: pinsKey)
    }

    func runShortcut(_ name: String) {
        runningShortcut = name
        Task.detached {
            _ = Self.run("/usr/bin/shortcuts", ["run", name])
            await MainActor.run {
                self.runningShortcut = nil
                self.lastResult = "Ran \(name)"
            }
        }
    }

    nonisolated static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: Mac actions (none need a permission)

    enum Action: String, CaseIterable, Identifiable {
        case screenshot, sleepDisplay, downloads, darkMode, newNote
        var id: String { rawValue }
        var title: String {
            switch self {
            case .screenshot: return "Screenshot"
            case .sleepDisplay: return "Display off"
            case .downloads: return "Downloads"
            case .darkMode: return "Dark mode"
            case .newNote: return "Quick note"
            }
        }
        var symbol: String {
            switch self {
            case .screenshot: return "camera.viewfinder"
            case .sleepDisplay: return "moon.zzz.fill"
            case .downloads: return "arrow.down.circle.fill"
            case .darkMode: return "circle.lefthalf.filled"
            case .newNote: return "square.and.pencil"
            }
        }
    }

    func perform(_ a: Action, quickNote: () -> Void) {
        switch a {
        case .screenshot:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
        case .sleepDisplay:
            Task.detached { _ = Self.run("/usr/bin/pmset", ["displaysleepnow"]) }
        case .downloads:
            NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
        case .darkMode:
            // Uses System Events, so macOS asks once to let Perch control it.
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")?.executeAndReturnError(&err)
        case .newNote:
            quickNote()
        }
    }

    func preview(apps: [LaunchApp], shortcuts: [String]) { self.apps = apps; self.pinnedShortcuts = shortcuts; self.shortcuts = shortcuts }
}
