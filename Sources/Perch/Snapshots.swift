// `Perch --perch-snapshots <folder>` renders the main surfaces to PNGs and quits.
// CI uses it so the design can be reviewed without a Mac. The scenes include a drawn stand-in for
// the lime camera cover, since on the real screen the cover sits on top of the island.
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

    private static func save<V: View>(_ view: V, _ name: String, to dir: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { print("snapshot failed: \(name)"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: dir.appendingPathComponent(name + ".png"))
            print("snapshot: \(name).png \(cg.width)x\(cg.height)")
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

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("perch-snap-notes.json")
        let notes = NotesStore(file: tmp)
        let now = Date()
        notes.setSample([
            Note(text: "Email the lab\nAsk about the summer spot, mention the poster", pinned: true,
                 created: now, updated: now.addingTimeInterval(-600)),
            Note(text: "APUSH\nUnit 6 DBQ outline due Friday", created: now, updated: now.addingTimeInterval(-7200)),
            Note(text: "Perch ideas\nWeather on the left wing? Calendar peek", created: now, updated: now.addingTimeInterval(-86400)),
        ])

        let music = NowPlayingCenter()
        let art = sampleArtwork()
        music.showSample(Track(title: "Pink + White", artist: "Frank Ocean", album: "Blonde", bundleID: "com.spotify.client",
                               playing: true, duration: 184, elapsed: 71, measuredAt: now), art: art)

        let ms = now.timeIntervalSince1970 * 1000
        let board = AgentBoard()
        board.setSample([
            Agent(id: "architect-iii", name: "Architect III", status: .started, quiet: false, task: "Building Perch v1",
                  note: nil, run: 1, startedAt: ms - 1_260_000, updatedAt: ms - 30_000, finishedAt: nil),
            Agent(id: "researcher", name: "Researcher", status: .started, quiet: false, task: "Summer lab openings",
                  note: nil, run: 2, startedAt: ms - 420_000, updatedAt: ms - 60_000, finishedAt: nil),
            Agent(id: "architect-ii", name: "Architect II", status: .finished, quiet: false, task: "Letterhead 2.0.2",
                  note: "Updater fixed", run: 3, startedAt: ms - 3_600_000, updatedAt: ms - 20_000, finishedAt: ms - 20_000),
            Agent(id: "outreach", name: "Outreach", status: .failed, quiet: false, task: "Weekly digest",
                  note: "Gmail sign-in expired", run: 1, startedAt: ms - 9_000_000, updatedAt: ms - 5_400_000, finishedAt: ms - 5_400_000),
        ], finished: ["architect-ii"])

        let quietMusic = NowPlayingCenter()
        let emptyBoard = AgentBoard()
        emptyBoard.setSample([])

        func scene(_ model: IslandModel, music m: NowPlayingCenter, board b: AgentBoard, height: CGFloat) -> AnyView {
            AnyView(ScreenSlice(height: height, g: prefs.geometry) {
                IslandView(model: model, prefs: prefs, music: m, notes: notes, board: b)
                    .frame(width: model.maxSize(prefs.geometry).width + 72,
                           height: prefs.geometry.topOffset + model.maxSize(prefs.geometry).height + 36)
            })
        }

        let resting = IslandModel()
        resting.state = .resting
        save(scene(resting, music: quietMusic, board: emptyBoard, height: 150), "1-resting", to: dir)
        save(scene(resting, music: music, board: board, height: 150), "2-resting-wings", to: dir)

        let bloom = IslandModel()
        bloom.state = .bloom(BloomInfo(name: "Architect II", success: true, line: "Updater fixed"))
        save(scene(bloom, music: music, board: board, height: 150), "3-bloom", to: dir)

        for (i, tab) in IslandTab.allCases.enumerated() {
            let open = IslandModel()
            open.state = .open
            open.tab = tab
            save(scene(open, music: music, board: board, height: 360), "\(4 + i)-open-\(tab.rawValue)", to: dir)
        }
        let emptyOpen = IslandModel()
        emptyOpen.state = .open
        emptyOpen.tab = .playing
        save(scene(emptyOpen, music: quietMusic, board: emptyBoard, height: 360), "8-open-nothing-playing", to: dir)
        emptyOpen.tab = .agents
        save(scene(emptyOpen, music: quietMusic, board: emptyBoard, height: 360), "9-open-agents-empty", to: dir)

        let cal = CalibrationModel(geometry: prefs.geometry, firstRun: true)
        save(ScreenSlice(height: 420, g: prefs.geometry, coverOnTop: true) {
            CalibrationView(model: cal).frame(width: 1100, height: 420)
        }, "10-fit", to: dir)

        save(SettingsView(prefs: prefs, board: board, music: music, refit: {}, checkForUpdates: {},
                          autoUpdates: .constant(true)).content
                .padding(28).frame(width: SettingsView.size.width).background(Ink.window), "11-settings", to: dir)
        prefs.lastTab = IslandTab.playing.rawValue
    }
}

/// A slice of a MacBook screen: wallpaper, menu bar, and the lime cover stuck over the camera.
private struct ScreenSlice<Content: View>: View {
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
