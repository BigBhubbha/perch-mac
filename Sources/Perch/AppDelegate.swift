// Wires Perch together: the island, music, notes, the agent board, fitting, settings and updates.
import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Prefs.shared
    private let music = NowPlayingCenter()
    private let notes = NotesStore()
    private let board = AgentBoard()
    private var island: IslandController!
    private let calibration = CalibrationController()
    private var settingsWindow: NSWindow?
    private var updater: Updater?
    private var signalSources: [DispatchSourceSignal] = []
    private let loadCheck = CommandLine.arguments.contains("--perch-load-check")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One Perch at a time. A second copy hands over to the first and leaves.
        let mine = ProcessInfo.processInfo.processIdentifier
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != mine }) {
            other.activate()
            NSApp.terminate(nil)
            return
        }
        installSignalHandlers()
        updater = Updater()
        setUpMainMenu()

        island = IslandController(music: music, notes: notes, board: board)
        island.model.onOpenSettings = { [weak self] in self?.island.close(); self?.openSettings() }
        island.model.onCheckForUpdates = { [weak self] in self?.island.close(); self?.updater?.checkForUpdates() }
        island.model.onRecalibrate = { [weak self] in self?.island.close(); self?.startCalibration() }
        island.model.onQuit = { NSApp.terminate(nil) }
        island.show()

        board.onFinish = { [weak self] agent in
            guard let self else { return }
            let ok = agent.status == .finished
            self.island.bloom(BloomInfo(name: agent.name, success: ok, line: agent.note))
            if self.prefs.chimeOnFinish { Chime.play(success: ok) }
        }
        board.start()
        music.start()

        // Finish launching first (so the Dock icon stops bouncing), then ask about moving.
        if !loadCheck && !Installer.isInApplications {
            DispatchQueue.main.async { [weak self] in
                if Installer.offerMoveIfNeeded() { return }
                self?.startFirstRunIfNeeded()
            }
        } else {
            startFirstRunIfNeeded()
        }
    }

    private func startFirstRunIfNeeded() {
        guard !prefs.hasCalibrated && !loadCheck else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.startCalibration(firstRun: true) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        music.stop()
        AdapterStream.killAll()
        notes.saveNow()
    }

    /// `kill` and logout send SIGTERM, which skips applicationWillTerminate. Clean up the helper anyway.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                AdapterStream.killAll()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    // MARK: Fitting

    func startCalibration(firstRun: Bool = false) {
        guard let screen = island.homeScreen else { return }
        island.suspended = true
        calibration.start(on: screen, geometry: prefs.geometry, firstRun: firstRun,
                          done: { [weak self] g in
                              guard let self else { return }
                              self.prefs.geometry = g
                              self.prefs.hasCalibrated = true
                              self.island.suspended = false
                              self.island.place()
                          },
                          cancelled: { [weak self] in
                              guard let self else { return }
                              if firstRun { self.prefs.hasCalibrated = true }
                              self.island.suspended = false
                          })
    }

    // MARK: Menus

    private func setUpMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let app = NSMenu(title: "Perch")
        appItem.submenu = app
        app.addItem(withTitle: "About Perch", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(item("Check for Updates...", #selector(checkForUpdates)))
        app.addItem(.separator())
        app.addItem(item("Settings...", #selector(showSettings), key: ","))
        app.addItem(item("Fit Around the Cover...", #selector(refit)))
        app.addItem(item("Open the Island", #selector(toggleIsland), key: "i"))
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Perch", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Perch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let window = NSMenu(title: "Window")
        windowItem.submenu = window
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func checkForUpdates() { updater?.checkForUpdates() }
    @objc private func showSettings() { openSettings() }
    @objc private func refit() { startCalibration() }
    @objc private func toggleIsland() { island.toggle() }

    // MARK: Settings window

    func openSettings() {
        if settingsWindow == nil {
            let autoBinding = Binding<Bool>(get: { [weak self] in self?.updater?.automaticallyChecks ?? true },
                                            set: { [weak self] in self?.updater?.automaticallyChecks = $0 })
            let view = SettingsView(prefs: prefs, board: board, music: music,
                                    refit: { [weak self] in self?.settingsWindow?.orderOut(nil); self?.startCalibration() },
                                    checkForUpdates: { [weak self] in self?.updater?.checkForUpdates() },
                                    autoUpdates: autoBinding)
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsView.size),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Perch Settings"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(red: 0.067, green: 0.067, blue: 0.075, alpha: 1)
            w.contentView = NSHostingView(rootView: view)
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
