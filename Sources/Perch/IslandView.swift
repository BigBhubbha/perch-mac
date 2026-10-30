// What the island looks like: still wings at rest, short moments, and the open deck with its tabs.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct IslandView: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var shelf: ShelfStore

    var body: some View {
        let g = prefs.geometry
        let wings = prefs.showWings && model.wing != nil
        let size = model.size(g, wings: wings)
        let open = model.isOpen
        let shape = IslandShape(radius: open ? 34 : g.cornerRadius, ear: g.topOffset > 0 ? 0 : (open ? 14 : 6))

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(Ink.pill)
                    .overlay(shape.stroke(Ink.palette.isLight ? Color.black.opacity(0.06) : Color.white.opacity(open ? 0.05 : 0), lineWidth: 1))
                    .shadow(color: .black.opacity(open ? 0.55 : 0), radius: open ? 28 : 0, x: 0, y: open ? 14 : 0)

                Group {
                    switch model.state {
                    case .resting:
                        if wings, let w = model.wing { RestingWings(g: g, kind: w).transition(.opacity) }
                    case .moment(let m):
                        MomentWings(g: g, moment: m).transition(.opacity)
                    case .open:
                        OpenDeck(g: g)
                            .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.26).delay(0.08)),
                                                    removal: .opacity.animation(.easeIn(duration: 0.08))))
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
            }
            .frame(width: size.width, height: size.height)
            .modifier(ShelfDrop(shelf: shelf, model: model))
            .padding(.top, g.topOffset)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.wing, value: model.wing)
        .environment(\.colorScheme, Ink.palette.isLight ? .light : .dark)
        .id(prefs.theme.rawValue + prefs.accentMode.rawValue)
    }
}

/// Files dropped anywhere on the island land on the shelf. (Skipped in previews, which cannot draw it.)
struct ShelfDrop: ViewModifier {
    let shelf: ShelfStore
    let model: IslandModel
    func body(content: Content) -> some View {
        if RenderMode.snapshot {
            content
        } else {
            content.onDrop(of: [.fileURL], isTargeted: Binding(get: { shelf.dropTargeted }, set: { shelf.dropTargeted = $0 })) { providers in
                if model.tab != .shelf { model.tab = .shelf }
                return shelf.accept(providers)
            }
        }
    }
}

// MARK: Resting wings

struct RestingWings: View {
    let g: PillGeometry
    let kind: WingKind
    @EnvironmentObject var music: NowPlayingCenter
    @EnvironmentObject var board: AgentBoard
    @EnvironmentObject var timers: TimerCenter
    @EnvironmentObject var calendar: CalendarCenter
    @EnvironmentObject var signals: SignalCenter

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: kind.width)
            Color.clear.frame(width: g.width)
            right.frame(width: kind.width)
        }
        .frame(height: g.height)
    }

    @ViewBuilder private var left: some View {
        switch kind {
        case .privacy(let camera):
            Image(systemName: camera ? "video.fill" : "mic.fill").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(camera ? Ink.mint : Ink.amber)
        case .timer:
            ProgressRing(progress: timers.progress, color: timers.current?.kind == .rest ? Ink.sky : Ink.accent, line: 2.6)
                .frame(width: 16, height: 16)
        case .event:
            RoundedRectangle(cornerRadius: 2).fill(calendar.next?.calendarColor ?? Ink.accent).frame(width: 4, height: 18)
        case .agents:
            Image(systemName: "sparkle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.accent)
        case .music:
            ArtThumb(image: music.artwork, accent: music.accent, side: 22)
        case .charging:
            Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Ink.mint)
        case .mail:
            Image(systemName: "envelope.fill").font(.system(size: 11)).foregroundStyle(Ink.accent)
        }
    }

    @ViewBuilder private var right: some View {
        switch kind {
        case .privacy(let camera):
            Circle().fill(camera ? Ink.mint : Ink.amber).frame(width: 6, height: 6)
        case .timer:
            Text(clock(timers.remaining)).font(.round(12.5, .semibold)).monospacedDigit()
                .foregroundStyle(timers.isPaused ? Ink.text3 : Ink.text)
        case .event:
            Text(calendar.next.map { untilText($0.start.timeIntervalSinceNow).replacingOccurrences(of: "in ", with: "") } ?? "")
                .font(.round(12.5, .semibold)).monospacedDigit().foregroundStyle(Ink.text)
        case .agents:
            StillDots(count: board.working.count)
        case .music:
            StillBars(color: music.accent)
        case .charging:
            Text("\(signals.battery.percent)%").font(.round(12, .semibold)).monospacedDigit().foregroundStyle(Ink.text)
        case .mail:
            EmptyView()
        }
    }
}

// MARK: Moments

struct MomentWings: View {
    let g: PillGeometry
    let moment: Moment

    var body: some View {
        let w = IslandModel.momentWidth(moment)
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                leftContent
            }
            .padding(.trailing, 14)
            .frame(width: w)
            Color.clear.frame(width: g.width)
            rightContent
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(width: w, alignment: .leading)
        }
        .frame(height: g.height)
    }

    @ViewBuilder private var leftContent: some View {
        switch moment.kind {
        case .agent:
            Text(moment.tint == Ink.coral ? "Stopped" : "Done").font(.round(12, .semibold)).foregroundStyle(moment.tint)
            BloomBurst(color: moment.tint).frame(width: 26, height: 26)
        case .volume, .brightness:
            Image(systemName: moment.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Ink.text)
                .contentTransition(.symbolEffect(.replace))
        case .charging:
            Text(moment.title).font(.round(12.5, .semibold)).monospacedDigit().foregroundStyle(moment.tint)
            BatteryGlyph(level: moment.level ?? 0, tint: moment.tint, charging: moment.symbol == "bolt.fill")
        default:
            Image(systemName: moment.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(moment.tint)
                .symbolRenderingMode(.hierarchical)
        }
    }

    @ViewBuilder private var rightContent: some View {
        switch moment.kind {
        case .volume, .brightness:
            HStack(spacing: 8) {
                LevelBar(level: moment.level ?? 0, tint: moment.tint)
                Text(moment.title).font(.round(11.5, .semibold)).monospacedDigit().foregroundStyle(Ink.text2)
                    .frame(width: 30, alignment: .trailing)
            }
        case .charging:
            Text(moment.detail ?? "").font(.ui(12, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(moment.title).font(.ui(12.5, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                if let d = moment.detail {
                    Text(d).font(.ui(10.5)).foregroundStyle(Ink.text2).lineLimit(1)
                }
            }
        }
    }
}

struct LevelBar: View {
    let level: Double
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.raisedHover)
                Capsule().fill(tint).frame(width: max(5, geo.size.width * CGFloat(min(max(level, 0), 1))))
            }
        }
        .frame(height: 5)
        .animation(Motion.snap, value: level)
    }
}

struct BatteryGlyph: View {
    let level: Double
    let tint: Color
    var charging: Bool
    @State private var shown: Double = 0
    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Ink.text3, lineWidth: 1.2)
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(tint)
                    .frame(width: max(3, 24 * CGFloat(RenderMode.snapshot ? level : shown)))
                    .padding(2)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 7.5, weight: .black)).foregroundStyle(Ink.pill)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 30, height: 14)
            RoundedRectangle(cornerRadius: 1).fill(Ink.text3).frame(width: 2, height: 5)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.2).delay(0.15)) { shown = level } }
    }
}

// MARK: The open deck

struct OpenDeck: View {
    let g: PillGeometry
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var board: AgentBoard
    @EnvironmentObject var gmail: GmailCenter
    @EnvironmentObject var signals: SignalCenter
    @EnvironmentObject var weather: WeatherCenter
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var shelf: ShelfStore
    @Namespace private var tabSpace

    var body: some View {
        VStack(spacing: 0) {
            // The top band sits beside the camera cover, so nothing important goes in the middle.
            HStack(spacing: 0) {
                tabBar
                Spacer(minLength: g.width + 24)
                headerRight
            }
            .padding(.horizontal, 18)
            .frame(height: g.height)

            ZStack {
                switch model.tab {
                case .today: TodayPane()
                case .music: MusicPane()
                case .notes: NotesPane()
                case .agents: AgentsPane()
                case .shelf: ShelfPane()
                case .mail: MailPane()
                case .launch: LaunchPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .frame(height: IslandModel.bodyHeight)
            .clipped()
            .transition(.opacity)
            .id(model.tab)

            footer.frame(height: IslandModel.footerHeight)
        }
        .overlay {
            if shelf.dropTargeted {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Ink.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 1) {
            ForEach(model.visibleTabs) { t in
                let active = model.tab == t
                Button {
                    withAnimation(Motion.tab) { model.tab = t }
                    if prefs.haptics { Haptics.tick() }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: t.symbol)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(active ? Ink.text : Ink.text3)
                            .frame(width: 32, height: 28)
                            .background {
                                if active {
                                    Capsule().fill(Ink.raisedHover).matchedGeometryEffect(id: "tab", in: tabSpace)
                                }
                            }
                        if badge(t) {
                            Circle().fill(Ink.accent).frame(width: 5, height: 5).offset(x: -6, y: 5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
        }
    }

    private func badge(_ t: IslandTab) -> Bool {
        switch t {
        case .agents: return !board.justFinished.isEmpty
        case .mail: return gmail.unreadCount > 0
        default: return false
        }
    }

    private var headerRight: some View {
        HStack(spacing: 12) {
            if signals.cameraOn || signals.micOn {
                Circle().fill(signals.cameraOn ? Ink.mint : Ink.amber).frame(width: 6, height: 6)
                    .help(signals.cameraOn ? "Camera in use" : "Microphone in use")
            }
            if let w = weather.now {
                HStack(spacing: 4) {
                    Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 11))
                    Text("\(Int(w.temp.rounded()))°").font(.round(12.5, .medium)).monospacedDigit().foregroundStyle(Ink.text2)
                }
            }
            if signals.battery.hasBattery {
                HStack(spacing: 3) {
                    if signals.battery.charging { Image(systemName: "bolt.fill").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Ink.mint) }
                    Text("\(signals.battery.percent)%").font(.round(12, .medium)).monospacedDigit()
                        .foregroundStyle(signals.battery.percent <= 20 && !signals.battery.pluggedIn ? Ink.coral : Ink.text2)
                }
            }
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.round(13, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.text)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(model.tab.title).eyebrow()
            Spacer()
            FooterButton(title: "Updates", action: model.onCheckForUpdates)
            FooterButton(title: "Refit", action: model.onRecalibrate)
            FooterButton(title: "Settings", action: model.onOpenSettings)
            FooterButton(title: "Quit", action: model.onQuit)
        }
        .padding(.horizontal, 24)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1).padding(.horizontal, 18) }
    }
}

// MARK: Shared pieces

struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.ui(11, .medium)).foregroundStyle(hover ? Ink.text : Ink.text3)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ControlButton: View {
    let symbol: String
    var size: CGFloat
    var prominent = false
    var tint: Color? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(prominent ? (tint == nil || tint == Ink.text ? Ink.pill : Ink.onAccent) : (tint ?? Ink.text))
                .frame(width: prominent ? 44 : 30, height: prominent ? 44 : 30)
                .background(Circle().fill(prominent ? (tint ?? Ink.text).opacity(hover ? 1 : 0.92) : Ink.text.opacity(hover ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

/// A small squeeze while pressed, springing back on release.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A rounded pill button. `filled` uses the accent.
struct Chip: View {
    let title: String
    var symbol: String? = nil
    var filled = false
    var tint: Color? = nil
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(.ui(11.5, .semibold)).lineLimit(1)
            }
            .foregroundStyle(filled ? Ink.onAccent : (tint ?? Ink.text))
            .padding(.horizontal, 11).frame(height: 26)
            .background(Capsule().fill(filled ? (tint ?? Ink.accent) : (hover ? Ink.raisedHover : Ink.raised)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    var on = false
    var help: String = ""
    var size: CGFloat = 11
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .foregroundStyle(on ? Ink.accent : (hover ? Ink.text : Ink.text3))
                .frame(width: 24, height: 24)
                .background(Circle().fill(hover ? Ink.raised : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct Artwork: View {
    let image: NSImage?
    let accent: Color
    var radius: CGFloat = 18
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
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
        .background(shape.fill(accent.opacity(0.45)).blur(radius: 24).offset(y: 10).scaleEffect(0.9))
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

struct ProgressRing: View {
    let progress: Double
    let color: Color
    var line: CGFloat = 3
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: line)
            Circle().trim(from: 0, to: CGFloat(min(max(progress, 0.001), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Avatar for an agent or a mail sender: initials on a color of their own.
struct Avatar: View {
    let name: String
    var side: CGFloat = 28
    var body: some View {
        let c = NameColor.of(name)
        ZStack {
            Circle().fill(c.opacity(0.18))
            Circle().strokeBorder(c.opacity(0.45), lineWidth: 1)
            Text(NameColor.initials(name)).font(.round(side * 0.38, .bold)).foregroundStyle(c)
        }
        .frame(width: side, height: side)
    }
}

struct EmptyState: View {
    let drawing: AnyView
    let title: String
    let line: String
    var action: (String, () -> Void)? = nil
    var body: some View {
        HStack(spacing: 22) {
            drawing
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.serif(20).italic()).foregroundStyle(Ink.text)
                Text(line).font(.ui(12)).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                if let action {
                    Chip(title: action.0, filled: true, action: action.1).padding(.top, 6)
                }
            }
            .frame(maxWidth: 330, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A quiet vertical scroller. Preview renders skip the scroll view, which ImageRenderer cannot draw.
struct Scrolling<Content: View>: View {
    var axis: Axis.Set = .vertical
    @ViewBuilder var content: Content
    var body: some View {
        if RenderMode.snapshot {
            content.frame(maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollView(axis, showsIndicators: false) { content }
        }
    }
}

/// A slider drawn by hand so it matches the island and renders in previews.
struct Scrubber: View {
    let value: Double
    var tint: Color
    var height: CGFloat = 4
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void
    @State private var dragging: Double?
    @State private var hover = false

    var body: some View {
        GeometryReader { geo in
            let v = dragging ?? value
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.text.opacity(0.13))
                Capsule().fill(tint).frame(width: max(height, w * CGFloat(min(max(v, 0), 1))))
                Circle().fill(Ink.text)
                    .frame(width: hover || dragging != nil ? 11 : 0, height: hover || dragging != nil ? 11 : 0)
                    .offset(x: w * CGFloat(min(max(v, 0), 1)) - 5.5)
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
            .frame(height: (hover || dragging != nil) ? height + 2 : height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let x = min(max(g.location.x / max(w, 1), 0), 1)
                    dragging = x; onChange(x)
                }
                .onEnded { g in
                    let x = min(max(g.location.x / max(w, 1), 0), 1)
                    dragging = nil; onCommit(x)
                })
        }
        .frame(height: 14)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// A text field that turns into plain text in previews.
struct InkField: View {
    let placeholder: String
    @Binding var text: String
    var serif = false
    var onSubmit: () -> Void = {}
    var body: some View {
        Group {
            if RenderMode.snapshot {
                Text(text.isEmpty ? placeholder : text)
                    .font(serif ? .serif(13.5) : .ui(12.5))
                    .foregroundStyle(text.isEmpty ? Ink.text3 : Ink.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(serif ? .serif(13.5) : .ui(12.5))
                    .foregroundStyle(Ink.text)
                    .onSubmit(onSubmit)
            }
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.raised))
    }
}

// MARK: Dots and drawings

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
            let t = RenderMode.snapshot ? 0.55 : ctx.date.timeIntervalSince(start)
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

/// The resting island never moves on its own: still dots and still bars, no breathing or bobbing.
struct StillDots: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(count, 3), id: \.self) { _ in Circle().fill(Ink.accent).frame(width: 5, height: 5) }
            if count > 3 { Text("+\(count - 3)").font(.round(9.5, .bold)).foregroundStyle(Ink.accent) }
        }
    }
}

struct StillBars: View {
    let color: Color
    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach([7.0, 13.0, 9.0, 5.0], id: \.self) { h in Capsule().fill(color).frame(width: 2.6, height: h) }
        }
        .frame(height: 16)
    }
}

struct DotsDrawing: View {
    let lit: Bool
    var body: some View {
        let cells: [(CGFloat, CGFloat, Double)] = [(0, 0, 1), (18, 0, 0.35), (36, 0, 0.6), (0, 18, 0.5), (18, 18, 1), (36, 18, 0.25)]
        ZStack(alignment: .topLeading) {
            ForEach(0..<cells.count, id: \.self) { i in
                Circle()
                    .fill(lit ? Ink.accent.opacity(cells[i].2) : Ink.text.opacity(0.14))
                    .frame(width: 10, height: 10)
                    .offset(x: cells[i].0, y: cells[i].1)
            }
        }
        .frame(width: 46, height: 28, alignment: .topLeading)
        .padding(6)
    }
}

struct RecordDrawing: View {
    var body: some View {
        ZStack {
            Circle().fill(Ink.text.opacity(0.05))
            ForEach(0..<4, id: \.self) { i in
                Circle().stroke(Ink.text.opacity(0.06), lineWidth: 1).padding(CGFloat(5 + i * 5))
            }
            Circle().fill(Ink.accent.opacity(0.85)).frame(width: 13, height: 13)
            Circle().fill(Ink.pill).frame(width: 3, height: 3)
        }
        .frame(width: 58, height: 58)
    }
}

struct EnvelopeDrawing: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Ink.text.opacity(0.22), lineWidth: 1.5)
                .frame(width: 56, height: 40)
            Path { p in
                p.move(to: CGPoint(x: 2, y: 3)); p.addLine(to: CGPoint(x: 28, y: 22)); p.addLine(to: CGPoint(x: 54, y: 3))
            }
            .stroke(Ink.text.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 56, height: 40)
            Circle().fill(Ink.accent).frame(width: 12, height: 12).offset(x: 27, y: -19)
        }
        .frame(width: 70, height: 58)
    }
}

struct TrayDrawing: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Ink.text.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: 60, height: 46)
            Image(systemName: "arrow.down").font(.system(size: 16, weight: .semibold)).foregroundStyle(Ink.accent)
        }
        .frame(width: 70, height: 58)
    }
}
