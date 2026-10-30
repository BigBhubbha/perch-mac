// What the island looks like: resting wings, the finish bloom, and the open panel with its four tabs.
import SwiftUI
import AppKit

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var prefs: Prefs
    @ObservedObject var music: NowPlayingCenter
    @ObservedObject var notes: NotesStore
    @ObservedObject var board: AgentBoard

    var body: some View {
        let g = prefs.geometry
        let wings = prefs.showWings && (music.isPlaying || !board.working.isEmpty)
        let size = model.size(g, wings: wings)
        let open = model.isOpen
        let shape = IslandShape(radius: open ? 32 : g.cornerRadius, ear: g.topOffset > 0 ? 0 : (open ? 12 : 6))

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(Ink.pill)
                    .shadow(color: .black.opacity(open ? 0.5 : 0), radius: open ? 24 : 0, x: 0, y: open ? 12 : 0)

                Group {
                    switch model.state {
                    case .resting:
                        if wings { RestingWings(g: g, music: music, board: board).transition(.opacity) }
                    case .bloom(let info):
                        BloomWings(g: g, info: info).transition(.opacity)
                    case .open:
                        OpenIsland(g: g, model: model, music: music, notes: notes, board: board)
                            .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.24).delay(0.07)),
                                                    removal: .opacity.animation(.easeIn(duration: 0.08))))
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
            }
            .frame(width: size.width, height: size.height)
            .padding(.top, g.topOffset)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.wing, value: wings)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: Resting and bloom

struct RestingWings: View {
    let g: PillGeometry
    @ObservedObject var music: NowPlayingCenter
    @ObservedObject var board: AgentBoard

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if music.isPlaying {
                    ArtThumb(image: music.artwork, accent: music.accent, side: 22)
                } else if !board.working.isEmpty {
                    Image(systemName: "sparkle").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.lime.opacity(0.9))
                }
            }
            .frame(width: IslandModel.wing)
            Color.clear.frame(width: g.width)
            ZStack {
                if !board.working.isEmpty {
                    MiniDots(count: board.working.count)
                } else if music.isPlaying {
                    EqualizerBars(color: music.accent)
                }
            }
            .frame(width: IslandModel.wing)
        }
        .frame(height: g.height)
    }
}

struct BloomWings: View {
    let g: PillGeometry
    let info: BloomInfo

    var body: some View {
        let color = info.success ? Ink.lime : Ink.coral
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(info.success ? "Done" : "Stopped")
                    .font(.round(12, .semibold))
                    .foregroundStyle(color)
                BloomBurst(color: color).frame(width: 26, height: 26)
            }
            .padding(.trailing, 14)
            .frame(width: IslandModel.bloomWing)
            Color.clear.frame(width: g.width)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.name).font(.ui(12.5, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                Text(info.line ?? (info.success ? "finished its job" : "ran into trouble"))
                    .font(.ui(10.5)).foregroundStyle(Ink.text2).lineLimit(1)
            }
            .padding(.leading, 14)
            .frame(width: IslandModel.bloomWing, alignment: .leading)
        }
        .frame(height: g.height)
    }
}

// MARK: Open island

struct OpenIsland: View {
    let g: PillGeometry
    @ObservedObject var model: IslandModel
    @ObservedObject var music: NowPlayingCenter
    @ObservedObject var notes: NotesStore
    @ObservedObject var board: AgentBoard
    @Namespace private var tabSpace

    var body: some View {
        VStack(spacing: 0) {
            // The top band sits beside the camera cover, so nothing important goes in the middle.
            HStack(spacing: 0) {
                tabBar
                Spacer(minLength: g.width + 28)
                headerRight
            }
            .padding(.horizontal, 20)
            .frame(height: g.height)

            ZStack {
                switch model.tab {
                case .playing: PlayingPane(music: music)
                case .notes: NotesPane(notes: notes)
                case .agents: AgentsPane(board: board)
                case .mail: MailPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .frame(height: IslandModel.bodyHeight)

            footer.frame(height: IslandModel.footerHeight)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(IslandTab.allCases) { t in
                let active = model.tab == t
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { model.tab = t }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: t.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(active ? Ink.text : Ink.text3)
                            .frame(width: 36, height: 28)
                            .background {
                                if active {
                                    Capsule().fill(Ink.raisedHover).matchedGeometryEffect(id: "tab", in: tabSpace)
                                }
                            }
                        if t == .agents && !board.justFinished.isEmpty {
                            Circle().fill(Ink.lime).frame(width: 6, height: 6).offset(x: -6, y: 4)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
        }
    }

    private var headerRight: some View {
        HStack(spacing: 12) {
            if !board.working.isEmpty { MiniDots(count: board.working.count) }
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.round(13, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Ink.text2)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(model.tab.title).eyebrow()
            Spacer()
            FooterButton(title: "Check for updates", action: model.onCheckForUpdates)
            FooterButton(title: "Refit", action: model.onRecalibrate)
            FooterButton(title: "Settings", action: model.onOpenSettings)
            FooterButton(title: "Quit", action: model.onQuit)
        }
        .padding(.horizontal, 24)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1).padding(.horizontal, 18) }
    }
}

struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(11, .medium))
                .foregroundStyle(hover ? Ink.text : Ink.text3)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Playing

struct PlayingPane: View {
    @ObservedObject var music: NowPlayingCenter

    var body: some View {
        if let t = music.track {
            HStack(alignment: .center, spacing: 22) {
                Artwork(image: music.artwork, accent: music.accent).frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.appName).eyebrow(music.accent.opacity(0.95))
                    Text(t.title)
                        .font(.ui(18, .semibold))
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                        .padding(.top, 5)
                    Text(t.artist.isEmpty ? t.album : t.artist)
                        .font(.ui(13))
                        .foregroundStyle(Ink.text2)
                        .lineLimit(1)
                        .padding(.top, 1)
                    Spacer(minLength: 8)
                    if let d = t.duration, d > 0 {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            ProgressRow(elapsed: t.elapsed(at: ctx.date) ?? 0, duration: d, accent: music.accent)
                        }
                    }
                    HStack(spacing: 30) {
                        ControlButton(symbol: "backward.fill", size: 15) { music.send(.previous) }
                        ControlButton(symbol: t.playing ? "pause.fill" : "play.fill", size: 21, prominent: true) { music.send(.toggle) }
                        ControlButton(symbol: "forward.fill", size: 15) { music.send(.next) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.vertical, 18)
        } else {
            EmptyState(drawing: AnyView(RecordDrawing()),
                       title: "Nothing playing",
                       line: music.source == .appleScript
                           ? "Start something in Spotify or Music and it shows up here."
                           : "Play something anywhere and it shows up here.")
        }
    }
}

struct ProgressRow: View {
    let elapsed: Double
    let duration: Double
    let accent: Color
    var body: some View {
        HStack(spacing: 10) {
            Text(clock(elapsed)).font(.ui(10.5, .medium)).monospacedDigit().foregroundStyle(Ink.text3)
                .frame(width: 34, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(accent).frame(width: max(3, geo.size.width * CGFloat(min(1, elapsed / duration))))
                }
            }
            .frame(height: 3)
            Text("-" + clock(max(0, duration - elapsed))).font(.ui(10.5, .medium)).monospacedDigit().foregroundStyle(Ink.text3)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

struct ControlButton: View {
    let symbol: String
    var size: CGFloat
    var prominent = false
    let action: () -> Void
    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Ink.text)
                .frame(width: prominent ? 42 : 32, height: prominent ? 42 : 32)
                .background(Circle().fill(Color.white.opacity(prominent ? (hover ? 0.16 : 0.10) : (hover ? 0.08 : 0))))
                .contentShape(Circle())
                .scaleEffect(pressed ? 0.9 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in withAnimation(.easeOut(duration: 0.08)) { pressed = true } }
            .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pressed = false } })
    }
}

struct Artwork: View {
    let image: NSImage?
    let accent: Color
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 30, weight: .medium)).foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 1))
        .background(shape.fill(accent.opacity(0.42)).blur(radius: 22).offset(y: 8).scaleEffect(0.9))
    }
}

struct ArtThumb: View {
    let image: NSImage?
    let accent: Color
    var side: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                accent.opacity(0.5)
                Image(systemName: "music.note").font(.system(size: side * 0.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
    }
}

/// Three bars that breathe while music plays. Driven at 12 frames a second to stay light on the battery.
struct EqualizerBars: View {
    let color: Color
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    let speeds = [5.1, 7.3, 4.2, 6.4]
                    let v = (sin(t * speeds[i] + Double(i) * 1.7) + 1) / 2
                    Capsule().fill(color).frame(width: 2.6, height: 4 + 11 * v)
                }
            }
            .frame(height: 16)
        }
    }
}

struct RecordDrawing: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.05))
            ForEach(0..<4, id: \.self) { i in
                Circle().stroke(Color.white.opacity(0.06), lineWidth: 1).padding(CGFloat(5 + i * 5))
            }
            Circle().fill(Ink.lime.opacity(0.85)).frame(width: 13, height: 13)
            Circle().fill(Ink.pill).frame(width: 3, height: 3)
        }
        .frame(width: 58, height: 58)
    }
}

struct EmptyState: View {
    let drawing: AnyView
    let title: String
    let line: String
    var body: some View {
        HStack(spacing: 20) {
            drawing
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.serif(19).italic()).foregroundStyle(Ink.text)
                Text(line).font(.ui(12)).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 300, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Notes

struct NotesPane: View {
    @ObservedObject var notes: NotesStore

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(notes.notes.count) \(notes.notes.count == 1 ? "note" : "notes")").eyebrow()
                    Spacer()
                    Button { notes.add() } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(Ink.pill)
                            .frame(width: 20, height: 20).background(Circle().fill(Ink.lime))
                    }
                    .buttonStyle(.plain)
                    .help("New note")
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(notes.sorted) { n in
                            NoteRow(note: n, selected: notes.selected?.id == n.id) { notes.selectedID = n.id }
                        }
                    }
                }
            }
            .frame(width: 184)

            Rectangle().fill(Ink.hairline).frame(width: 1)

            if let n = notes.selected {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text(n.updated, format: .dateTime.weekday(.wide).hour().minute()).eyebrow()
                        Spacer()
                        IconToggle(symbol: n.pinned ? "pin.fill" : "pin", on: n.pinned, help: n.pinned ? "Unpin" : "Pin to the top") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { notes.togglePin(n.id) }
                        }
                        IconToggle(symbol: "trash", on: false, help: "Delete") {
                            withAnimation(.easeOut(duration: 0.2)) { notes.delete(n.id) }
                        }
                    }
                    NoteEditor(note: n, notes: notes)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A blank page").font(.serif(19).italic()).foregroundStyle(Ink.text)
                    Text("Jot something down. Pin the ones you want at the top.").font(.ui(12)).foregroundStyle(Ink.text3)
                    Button { notes.add() } label: {
                        Text("Start a note").font(.ui(12, .semibold)).foregroundStyle(Ink.pill)
                            .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Ink.lime))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 14)
    }
}

struct NoteRow: View {
    let note: Note
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if note.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(Ink.lime)
                    }
                    Text(note.title).font(.ui(12, .medium)).foregroundStyle(selected ? Ink.text : Ink.text2).lineLimit(1)
                }
                Text(note.preview.isEmpty ? shortAge(Date().timeIntervalSince(note.updated)) : note.preview)
                    .font(.ui(10.5)).foregroundStyle(Ink.text3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Ink.raisedHover : (hover ? Ink.raised : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct NoteEditor: View {
    let note: Note
    @ObservedObject var notes: NotesStore
    var body: some View {
        if RenderMode.snapshot {
            Text(note.text).font(.serif(15)).foregroundStyle(Ink.text).lineSpacing(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 5)
        } else {
            TextEditor(text: Binding(get: { notes.notes.first(where: { $0.id == note.id })?.text ?? "" },
                                     set: { notes.update(note.id, text: $0) }))
                .font(.serif(15))
                .foregroundStyle(Ink.text)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .background(Color.clear)
                .tint(Ink.lime)
                .lineSpacing(3)
                .id(note.id)
        }
    }
}

struct IconToggle: View {
    let symbol: String
    let on: Bool
    let help: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Ink.lime : (hover ? Ink.text : Ink.text3))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: Agents

struct AgentsPane: View {
    @ObservedObject var board: AgentBoard

    var body: some View {
        switch board.link {
        case .notSetUp:
            EmptyState(drawing: AnyView(DotsDrawing(lit: false)), title: "No board connected",
                       line: "This copy of Perch has no agent board key. Add one in Settings, under Agents.")
        default:
            if board.agents.isEmpty {
                EmptyState(drawing: AnyView(DotsDrawing(lit: true)), title: "All quiet",
                           line: linkLine ?? "When a Grok Bot starts a job its dot shows up here, and it blooms when the job is done.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(summary).eyebrow()
                        Spacer()
                        if let linkLine {
                            Text(linkLine).font(.ui(10.5)).foregroundStyle(Ink.coral).lineLimit(1)
                        }
                    }
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(board.agents) { a in
                                AgentCard(agent: a, blooming: board.justFinished.contains(a.id))
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
            }
        }
    }

    private var summary: String {
        let w = board.working.count, d = board.finished.count
        var parts: [String] = []
        if w > 0 { parts.append("\(w) working") }
        if d > 0 { parts.append("\(d) done") }
        return parts.joined(separator: ", ")
    }

    private var linkLine: String? {
        if case .failing(let why) = board.link { return why }
        return nil
    }
}

struct AgentCard: View {
    let agent: Agent
    let blooming: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            AgentDot(agent: agent, blooming: blooming).frame(width: 16, height: 16).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(agent.name).font(.ui(12.5, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                    Spacer(minLength: 6)
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(age(at: ctx.date)).font(.ui(10.5, .medium)).monospacedDigit().foregroundStyle(Ink.text3)
                    }
                }
                Text(agent.task ?? (agent.isWorking ? "Working" : "Finished"))
                    .font(.ui(11.5)).foregroundStyle(Ink.text2).lineLimit(1)
                if let n = agent.note {
                    Text(n).font(.ui(10.5)).foregroundStyle(agent.status == .failed ? Ink.coral : Ink.lime.opacity(0.85)).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(blooming ? Ink.lime.opacity(0.10) : Ink.raised))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(blooming ? Ink.lime.opacity(0.35) : .clear, lineWidth: 1))
    }

    private func age(at now: Date) -> String {
        if agent.isWorking, let s = agent.startedDate { return shortAge(now.timeIntervalSince(s)) }
        if let f = agent.finishedDate {
            let a = shortAge(now.timeIntervalSince(f))
            return a == "just now" ? a : a + " ago"
        }
        return ""
    }
}

struct AgentDot: View {
    let agent: Agent
    let blooming: Bool
    var body: some View {
        switch agent.status {
        case .started, .working:
            if agent.quiet == true {
                Circle().fill(Ink.quiet).frame(width: 8, height: 8)
            } else {
                PulseDot(color: Ink.lime, diameter: 8)
            }
        case .finished:
            ZStack {
                if blooming { BloomBurst(color: Ink.lime) }
                Circle().fill(Ink.lime).frame(width: 8, height: 8)
                Image(systemName: "checkmark").font(.system(size: 5, weight: .black)).foregroundStyle(Ink.pill)
            }
        case .failed:
            Circle().fill(Ink.coral).frame(width: 8, height: 8)
        }
    }
}

/// A dot that breathes, with a faint ring drifting out of it.
struct PulseDot: View {
    let color: Color
    var diameter: CGFloat
    var phaseShift: Double = 0
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate + phaseShift
            let p = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6
            let breathe = 0.82 + 0.18 * (sin(t * .pi * 2 / 1.6) + 1) / 2
            ZStack {
                Circle().stroke(color.opacity(0.55 * (1 - p)), lineWidth: 1.2)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(1 + p * 1.2)
                Circle().fill(color).frame(width: diameter, height: diameter).scaleEffect(breathe)
            }
        }
        .frame(width: diameter * 2.4, height: diameter * 2.4)
    }
}

/// Rings opening outward like a flower, for a finished job.
struct BloomBurst: View {
    let color: Color
    @State private var start = Date()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let local = (t - Double(i) * 0.22).truncatingRemainder(dividingBy: 1.8)
                    let p = max(0, min(1, local / 1.2))
                    Circle().stroke(color.opacity((1 - p) * 0.7), lineWidth: 1.4).scaleEffect(0.35 + p * 0.9)
                }
                ForEach(0..<6, id: \.self) { i in
                    let p = max(0, min(1, (t.truncatingRemainder(dividingBy: 1.8)) / 0.9))
                    Capsule().fill(color.opacity(1 - p))
                        .frame(width: 2, height: 4)
                        .offset(y: -6 - p * 7)
                        .rotationEffect(.degrees(Double(i) * 60))
                }
                Circle().fill(color).frame(width: 9, height: 9)
            }
        }
    }
}

struct MiniDots: View {
    let count: Int
    var body: some View {
        HStack(spacing: -4) {
            ForEach(0..<min(count, 4), id: \.self) { i in
                PulseDot(color: Ink.lime, diameter: 5, phaseShift: Double(i) * 0.4)
            }
            if count > 4 {
                Text("+\(count - 4)").font(.round(9.5, .bold)).foregroundStyle(Ink.lime).padding(.leading, 6)
            }
        }
    }
}

struct DotsDrawing: View {
    let lit: Bool
    var body: some View {
        let cells: [(CGFloat, CGFloat, Double)] = [(0, 0, 1), (18, 0, 0.35), (36, 0, 0.6), (0, 18, 0.5), (18, 18, 1), (36, 18, 0.25)]
        ZStack(alignment: .topLeading) {
            ForEach(0..<cells.count, id: \.self) { i in
                Circle()
                    .fill(lit ? Ink.lime.opacity(cells[i].2) : Color.white.opacity(0.14))
                    .frame(width: 10, height: 10)
                    .offset(x: cells[i].0, y: cells[i].1)
            }
        }
        .frame(width: 46, height: 28, alignment: .topLeading)
        .padding(6)
    }
}

// MARK: Mail (v2)

struct MailPane: View {
    var body: some View {
        EmptyState(drawing: AnyView(EnvelopeDrawing()), title: "Gmail lands here next",
                   line: "Version 2 brings your inbox in here, with quick replies and an unread count on the island.")
    }
}

struct EnvelopeDrawing: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1.5)
                .frame(width: 56, height: 40)
            Path { p in
                p.move(to: CGPoint(x: 2, y: 3)); p.addLine(to: CGPoint(x: 28, y: 22)); p.addLine(to: CGPoint(x: 54, y: 3))
            }
            .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 56, height: 40)
            Circle().fill(Ink.lime).frame(width: 12, height: 12).offset(x: 27, y: -19)
        }
        .frame(width: 70, height: 58)
    }
}
