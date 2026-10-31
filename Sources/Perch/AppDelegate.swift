// Wires Perch together: the island, every store behind it, moments, fitting, settings and updates.
import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Prefs.shared
    private let hub = Hub()
    private var island: IslandController!
    private var bag = Set<AnyCancellable>()
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

        island = IslandController(hub: hub)
        island.model.onOpenSettings = { [weak self] in self?.island.close(); self?.openSettings() }
        island.model.onCheckForUpdates = { [weak self] in self?.island.close(); self?.updater?.checkForUpdates() }
        island.model.onRecalibrate = { [weak self] in self?.island.close(); self?.startCalibration() }
        island.model.onQuit = { NSApp.terminate(nil) }
        island.show()
        wireMoments()
        startServices()

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

    private func wireMoments() {
        hub.board.onFinish = { [weak self] agent in
            guard let self else { return }
            let ok = agent.status == .finished
            self.island.flash(Moment(kind: .agent, symbol: "sparkle", title: agent.name,
                                     detail: agent.note ?? (ok ? "finished its job" : "ran into trouble"),
                                     tint: ok ? Ink.accent : Ink.coral, level: nil, duration: 3.6))
            if self.prefs.chimeOnFinish { Chime.play(success: ok) }
        }
        hub.timers.onFinish = { [weak self] r in
            guard let self else { return }
            let title: String
            let detail: String
            switch r.kind {
            case .countdown: title = "Time's up"; detail = r.label
            case .focus: title = "Focus done"; detail = "Take \(Int(self.prefs.pomodoroBreak)) minutes"
            case .rest: title = "Break's over"; detail = "Round \(r.round + 1)"
            }
            self.island.flash(Moment(kind: .timer, symbol: "timer", title: title, detail: detail, tint: Ink.accent, level: nil, duration: 5))
            Chime.play(success: true)
            if self.prefs.haptics { Haptics.level() }
        }
        hub.signals.onMoment = { [weak self] m in
            guard let self else { return }
            self.island.flash(m)
            if m.kind == .charging, m.symbol == "bolt.fill", self.prefs.waterSounds { WaterSound.play(.fill, volume: 0.35) }
        }
        hub.calendar.onSoon = { [weak self] e in
            self?.island.flash(Moment(kind: .event, symbol: "calendar", title: e.title, detail: untilText(e.start.timeIntervalSinceNow).capitalizedFirst,
                                      tint: e.calendarColor, level: nil, duration: 4.5))
        }
        hub.gmail.onNewMail = { [weak self] m in
            self?.island.flash(Moment(kind: .mail, symbol: "envelope.fill", title: m.from, detail: m.subject, tint: Ink.accent, level: nil, duration: 4))
        }
        MediaKeyTap.shared.onBrightness = { [weak self] v in
            let sym = v < 0.34 ? "sun.min.fill" : "sun.max.fill"
            self?.island.flash(Moment(kind: .brightness, symbol: sym, title: "\(Int((v * 100).rounded()))", detail: nil,
                                      tint: Ink.amber, level: Double(v), duration: 1.6))
        }
        Hotkey.shared.action = { [weak self] in self?.island.toggle() }
    }

    private func startServices() {
        hub.board.start()
        hub.music.start()
        hub.signals.start()
        hub.weather.start()
        hub.calendar.start()
        hub.gmail.start()
        if prefs.clipboardOn { hub.shelf.startClipboard() }
        if prefs.replaceSystemHUD && MediaKeyTap.trusted { MediaKeyTap.shared.start() }
        prefs.$shortcut.removeDuplicates().sink { Hotkey.shared.apply($0) }.store(in: &bag)
        prefs.$clipboardOn.removeDuplicates().dropFirst().sink { [weak self] on in
            MainActor.assumeIsolated { on ? self?.hub.shelf.startClipboard() : self?.hub.shelf.stopClipboard() }
        }.store(in: &bag)
        prefs.$calendarOn.removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.hub.calendar.start() }
        }.store(in: &bag)
        prefs.$theme.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.settingsWindow?.backgroundColor = NSColor(Ink.window) }
        }.store(in: &bag)
        // Turning on Accessibility happens in System Settings; start the key tap when it lands.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated {
                if Prefs.shared.replaceSystemHUD && !MediaKeyTap.shared.isRunning && MediaKeyTap.trusted { MediaKeyTap.shared.start() }
            }
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
        hub.music.stop()
        AdapterStream.killAll()
        hub.notes.saveNow()
        MediaKeyTap.shared.stop()
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
            let view = SettingsView(refit: { [weak self] in self?.settingsWindow?.orderOut(nil); self?.startCalibration() },
                                    checkForUpdates: { [weak self] in self?.updater?.checkForUpdates() },
                                    autoUpdates: autoBinding)
                .hub(hub, island.model)
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsView.size),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Perch Settings"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = NSColor(Ink.window)
            w.contentView = NSHostingView(rootView: view)
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
