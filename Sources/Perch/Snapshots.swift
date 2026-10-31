// `Perch --perch-snapshots <folder>` renders every surface to PNGs, then the motion frames, and quits.
// CI uses it so the design can be reviewed without a Mac. The scenes include a drawn stand-in for
// the lime camera cover, since on the real screen the cover sits on top of the island.
// All sample data here is made up.
import AppKit
import SwiftUI

@MainActor
enum Snapshots {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--perch-snapshots"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        RenderMode.snapshot = true
        render(to: dir)
        return true
    }

    private static var count = 0

    private static func save<V: View>(_ view: V, _ name: String, to dir: URL) {
        count += 1
        let file = String(format: "%02d-%@", count, name)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { print("snapshot failed: \(file)"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: dir.appendingPathComponent(file + ".png"))
            print("snapshot: \(file).png \(cg.width)x\(cg.height)")
        }
    }

    static func sampleArtwork() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: false) { r in
            NSGradient(colors: [NSColor(red: 0.98, green: 0.47, blue: 0.27, alpha: 1),
                                NSColor(red: 0.55, green: 0.12, blue: 0.35, alpha: 1)])?.draw(in: r, angle: -60)
            NSColor(red: 1, green: 0.85, blue: 0.55, alpha: 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 150, y: 150, width: 92, height: 92)).fill()
            NSColor(white: 0, alpha: 0.25).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 300, height: 90)).fill()
            return true
        }
    }

    private static func render(to dir: URL) {
        let prefs = Prefs.shared
        prefs.geometry = .standard
        prefs.showWings = true
        prefs.theme = .ink
        prefs.accentMode = .art
        prefs.hiddenTabs = []
        prefs.hiddenCards = []
        prefs.calendarOn = true
        prefs.lyricsOn = true
        prefs.clipboardOn = true

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("perch-snap-notes.json")
        let hub = Hub(notesFile: tmp)
        let now = Date()
        let cal = Calendar.current

        hub.notes.setSample([
            Note(text: "# Lab week\n## Before Friday\n- [x] Email the lab about the summer spot\n- [ ] Print the poster at the library\n- [ ] Ask for a letter\nBring the **USB drive** and the *good* pen.",
                 pinned: true, created: now, updated: now.addingTimeInterval(-600)),
            Note(text: "APUSH\nUnit 6 DBQ outline, three sources minimum", created: now, updated: now.addingTimeInterval(-7200)),
            Note(text: "Perch ideas\nLyrics on the left wing? A tiny weather glyph", created: now, updated: now.addingTimeInterval(-86400)),
        ])
        hub.tasks.preview([
            TaskItem(title: "DBQ outline", subject: "APUSH", due: cal.date(byAdding: .day, value: 1, to: now)),
            TaskItem(title: "Lab report 4", subject: "Chem", due: now.addingTimeInterval(3600 * 5)),
            TaskItem(title: "Read ch. 9 and annotate", subject: "AP Lang", due: cal.date(byAdding: .day, value: 3, to: now)),
            TaskItem(title: "Problem set 12", subject: "Calc", due: now.addingTimeInterval(-3600 * 20)),
            TaskItem(title: "Renew library books", subject: "", due: nil),
            TaskItem(title: "Vocab quiz study", subject: "Spanish", due: nil, done: true),
        ])

        let art = sampleArtwork()
        let track = Track(title: "Pink + White", artist: "Frank Ocean", album: "Blonde", bundleID: "com.spotify.client",
                          playing: true, duration: 184, elapsed: 71, measuredAt: now, shuffle: true, repeatMode: 0)
        let lyrics = [LyricLine(time: 52, text: "That's the way everyday goes"), LyricLine(time: 60, text: "Every time we've no control"),
                      LyricLine(time: 67, text: "If the sky is pink and white"), LyricLine(time: 74, text: "If the ground is black and yellow"),
                      LyricLine(time: 81, text: "It's the same way you showed me"), LyricLine(time: 88, text: "Nod my head, don't close my eyes")]
        hub.music.showSample(track, art: art, lyrics: lyrics)

        let ms = now.timeIntervalSince1970 * 1000
        let agents = [
            Agent(id: "architect-iii", name: "Architect III", status: .started, quiet: false, task: "Building Perch 0.2",
                  note: nil, run: 1, startedAt: ms - 1_260_000, updatedAt: ms - 30_000, finishedAt: nil),
            Agent(id: "researcher", name: "Researcher", status: .working, quiet: false, task: "Summer lab openings",
                  note: nil, run: 2, startedAt: ms - 420_000, updatedAt: ms - 60_000, finishedAt: nil),
            Agent(id: "architect-ii", name: "Architect II", status: .finished, quiet: false, task: "Letterhead 2.0.2",
                  note: "Updater fixed", run: 3, startedAt: ms - 3_600_000, updatedAt: ms - 20_000, finishedAt: ms - 20_000),
            Agent(id: "outreach", name: "Outreach", status: .failed, quiet: false, task: "Weekly digest",
                  note: "Gmail sign-in expired", run: 1, startedAt: ms - 9_000_000, updatedAt: ms - 5_400_000, finishedAt: ms - 5_400_000),
        ]
        let history = [
            AgentRun(name: "Architect II", task: "Letterhead 2.0.2", failed: false, seconds: 3580, at: now.addingTimeInterval(-20)),
            AgentRun(name: "Scout", task: "Price check: AirPods Pro", failed: false, seconds: 210, at: now.addingTimeInterval(-3000)),
            AgentRun(name: "Outreach", task: "Weekly digest", failed: true, seconds: 3600, at: now.addingTimeInterval(-5400)),
            AgentRun(name: "Researcher", task: "Scholarship deadlines", failed: false, seconds: 1320, at: now.addingTimeInterval(-9000)),
            AgentRun(name: "Tutor", task: "Chem flashcards", failed: false, seconds: 640, at: now.addingTimeInterval(-14000)),
        ]
        hub.board.setSample(agents, finished: ["architect-ii"], history: history)

        let blue = Color(red: 0.35, green: 0.6, blue: 1), green = Color(red: 0.35, green: 0.8, blue: 0.5), purple = Color(red: 0.7, green: 0.5, blue: 1)
        hub.calendar.preview([
            DayEvent(id: "1", title: "AP Chemistry", start: now.addingTimeInterval(8 * 60), end: now.addingTimeInterval(58 * 60), allDay: false,
                     location: "Room 214", calendarColor: green, meetingURL: nil),
            DayEvent(id: "2", title: "Lab interview", start: now.addingTimeInterval(3 * 3600), end: now.addingTimeInterval(3.5 * 3600), allDay: false,
                     location: nil, calendarColor: blue, meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")),
            DayEvent(id: "3", title: "Youth group", start: now.addingTimeInterval(6 * 3600), end: now.addingTimeInterval(8 * 3600), allDay: false,
                     location: "Fellowship hall", calendarColor: purple, meetingURL: nil),
        ])
        hub.weather.preview(WeatherNow(temp: 72, high: 78, low: 59, code: 1, isDay: true, rainChance: 10,
                                       hours: (1...6).map { i -> (Date, Double, Int) in
                                           let code: Int = i == 4 ? 61 : (i > 4 ? 3 : 1)
                                           return (now.addingTimeInterval(Double(i) * 3600), 70 + Double(i % 3) * 2, code)
                                       }))
        hub.gmail.preview([
            MailItem(id: "a", threadID: "a", from: "Common App", fromEmail: "", subject: "Your application checklist", snippet: "Three items are still open before the deadline", date: now.addingTimeInterval(-900), unread: true),
            MailItem(id: "b", threadID: "b", from: "Ms. Alvarez", fromEmail: "", subject: "Re: Lab poster", snippet: "Looks great. One small change to the abstract", date: now.addingTimeInterval(-3600 * 2), unread: true),
            MailItem(id: "c", threadID: "c", from: "GitHub", fromEmail: "", subject: "[perch-mac] Build passed", snippet: "All jobs have passed for main", date: now.addingTimeInterval(-3600 * 5), unread: true),
            MailItem(id: "d", threadID: "d", from: "Spotify", fromEmail: "", subject: "Your Release Radar is here", snippet: "New music from artists you follow", date: now.addingTimeInterval(-3600 * 9), unread: true),
        ], unread: 7, account: "you@gmail.com")

        let files = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("perch-shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let names = ["Lab poster final.pdf", "screenshot.png", "DBQ notes.docx", "Perch.dmg", "beat idea.m4a", "photos.zip"]
        for n in names { FileManager.default.createFile(atPath: files.appendingPathComponent(n).path, contents: Data("x".utf8)) }
        hub.shelf.preview(items: names.map { ShelfItem(path: files.appendingPathComponent($0).path) }, clips: [
            Clip(text: "https://github.com/BigBhubbha/perch-mac", copied: now.addingTimeInterval(-60), pinned: true),
            Clip(text: "#CDEF45", copied: now.addingTimeInterval(-300)),
            Clip(text: "The mitochondria is the powerhouse of the cell", copied: now.addingTimeInterval(-900)),
            Clip(text: "func bloom() { withAnimation(.spring) { open = true } }", copied: now.addingTimeInterval(-2000)),
            Clip(text: "Room 214, after 6th period", copied: now.addingTimeInterval(-4000)),
        ])
        let appPaths = ["/Applications/Safari.app", "/System/Applications/Music.app", "/System/Applications/Notes.app",
                        "/System/Applications/Calendar.app", "/System/Applications/Messages.app", "/System/Applications/Mail.app",
                        "/System/Applications/System Settings.app", "/System/Applications/Photos.app"]
        hub.launcher.preview(apps: appPaths.map { LaunchApp(path: $0) }, shortcuts: ["Study playlist", "Log water", "Text Mom I'm on my way", "Homework mode"])

        // MARK: Scenes

        let model = IslandModel()
        func scene(_ height: CGFloat = 150) -> AnyView {
            AnyView(ScreenSlice(height: height, g: prefs.geometry) {
                IslandView()
                    .frame(width: model.maxSize(prefs.geometry).width + 80,
                           height: prefs.geometry.topOffset + model.maxSize(prefs.geometry).height + 40)
            }.hub(hub, model))
        }

        model.state = .resting; model.wing = nil
        save(scene(), "rest-quiet", to: dir)
        model.wing = .music
        save(scene(), "rest-music", to: dir)
        hub.timers.preview(TimerCenter.Running(kind: .focus, label: "Focus", total: 1500, endsAt: now.addingTimeInterval(724), remainingWhenPaused: 724, round: 2), now: now)
        model.wing = .timer
        save(scene(), "rest-focus-timer", to: dir)
        model.wing = .event
        save(scene(), "rest-class-in-8m", to: dir)
        model.wing = .agents
        save(scene(), "rest-agents", to: dir)
        model.wing = .privacy(camera: true)
        save(scene(), "rest-camera-on", to: dir)

        model.wing = nil
        model.state = .moment(Moment(kind: .agent, symbol: "sparkle", title: "Architect II", detail: "Updater fixed", tint: Ink.accent, level: nil))
        save(scene(), "moment-agent-done", to: dir)
        model.state = .moment(Moment(kind: .agent, symbol: "sparkle", title: "Outreach", detail: "Gmail sign-in expired", tint: Ink.coral, level: nil))
        save(scene(), "moment-agent-failed", to: dir)
        model.state = .moment(Moment(kind: .volume, symbol: "speaker.wave.2.fill", title: "56", detail: nil, tint: Ink.accent, level: 0.56))
        save(scene(), "moment-volume", to: dir)
        model.state = .moment(Moment(kind: .brightness, symbol: "sun.max.fill", title: "80", detail: nil, tint: Ink.amber, level: 0.8))
        save(scene(), "moment-brightness", to: dir)
        model.state = .moment(Moment(kind: .charging, symbol: "bolt.fill", title: "64%", detail: "Charging", tint: Ink.mint, level: 0.64))
        save(scene(), "moment-charging", to: dir)
        model.state = .moment(Moment(kind: .device, symbol: "airpodspro", title: "AirPods Pro", detail: "Connected", tint: Ink.sky, level: nil))
        save(scene(), "moment-airpods", to: dir)
        model.state = .moment(Moment(kind: .timer, symbol: "timer", title: "Focus done", detail: "Take 5 minutes", tint: Ink.accent, level: nil))
        save(scene(), "moment-focus-done", to: dir)
        model.state = .moment(Moment(kind: .mail, symbol: "envelope.fill", title: "Ms. Alvarez", detail: "Re: Lab poster", tint: Ink.accent, level: nil))
        save(scene(), "moment-new-mail", to: dir)

        model.state = .open
        for tab in IslandTab.allCases {
            model.tab = tab
            save(scene(400), "open-\(tab.rawValue)", to: dir)
        }
        UserDefaults.standard.set("tasks", forKey: "notes.mode")
        model.tab = .notes
        save(scene(400), "open-homework", to: dir)
        UserDefaults.standard.set("notes", forKey: "notes.mode")

        // Empty and setup states.
        hub.timers.preview(nil, now: now)
        hub.music.clearSample()
        model.tab = .music
        save(scene(400), "open-music-nothing-playing", to: dir)
        model.tab = .today
        save(scene(400), "open-today-quiet", to: dir)
        hub.music.showSample(track, art: art, lyrics: lyrics)
        let readyMail = hub.gmail.items
        hub.gmail.preview([], unread: 0, account: "you@gmail.com")
        hub.gmail.previewState(.needsClient)
        model.tab = .mail
        save(scene(400), "open-mail-setup", to: dir)
        hub.gmail.preview(readyMail, unread: 7, account: "you@gmail.com")

        // Themes.
        for (theme, accent) in [(ThemeName.paper, AccentMode.art), (.graphite, .lime), (.ink, .lilac)] {
            prefs.theme = theme; prefs.accentMode = accent
            hub.music.showSample(track, art: art, lyrics: lyrics)
            model.tab = .today
            save(scene(400), "theme-\(theme.rawValue)-today", to: dir)
            model.tab = .music
            save(scene(400), "theme-\(theme.rawValue)-music", to: dir)
        }
        prefs.theme = .ink; prefs.accentMode = .art
        hub.music.showSample(track, art: art, lyrics: lyrics)

        let calModel = CalibrationModel(geometry: prefs.geometry, firstRun: true)
        save(ScreenSlice(height: 420, g: prefs.geometry, coverOnTop: true) {
            CalibrationView(model: calModel).frame(width: 1100, height: 420)
        }, "fit", to: dir)

        for page in SettingsPage.allCases {
            let tall: Set<SettingsPage> = [.extras, .mail, .look, .island]
            save(SettingsView(refit: {}, checkForUpdates: {}, autoUpdates: .constant(true),
                              height: tall.contains(page) ? 780 : SettingsView.size.height, page: page)
                    .hub(hub, model), "settings-\(page.rawValue)", to: dir)
        }
        prefs.lastTab = IslandTab.today.rawValue

        MotionClips.render(to: dir.appendingPathComponent("motion", isDirectory: true), hub: hub, model: model)
    }
}

/// A slice of a MacBook screen: wallpaper, menu bar, and the lime cover stuck over the camera.
struct ScreenSlice<Content: View>: View {
    let height: CGFloat
    let g: PillGeometry
    var coverOnTop = true
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.22, green: 0.30, blue: 0.42), Color(red: 0.42, green: 0.36, blue: 0.48)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 18) {
                Text("Chrome").fontWeight(.bold)
                Text("File"); Text("Edit"); Text("View"); Text("History"); Text("Window"); Text("Help")
                Spacer()
                Image(systemName: "wifi"); Image(systemName: "battery.75"); Text("Thu 9:41 PM")
            }
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 18)
            .frame(height: 37)
            .background(Color.black.opacity(0.18))

            content.frame(maxWidth: .infinity, alignment: .top)

            if coverOnTop {
                // Stand-in for the physical cover (it sits on the glass, above every pixel).
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.83, green: 0.95, blue: 0.30), Color(red: 0.74, green: 0.88, blue: 0.22)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        HStack(spacing: 6) {
                            Text("BU").font(.system(size: 17, weight: .black, design: .serif))
                            VStack(alignment: .leading, spacing: 0) {
                                Text("MISSIONS &"); Text("PUBLIC LIFE")
                            }
                            .font(.system(size: 7.5, weight: .bold))
                        }
                        .foregroundStyle(Color(red: 0.16, green: 0.42, blue: 0.20).opacity(0.85))
                    )
                    .frame(width: g.width - 8, height: g.height - 8)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(.top, g.topOffset + 3)
                    .offset(x: g.horizontalOffset)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 1100, height: height, alignment: .top)
        .clipped()
    }
}
