// Pour: everything in Perch is a droplet you can pick up and pour somewhere else.
// Drag a note, a song, a lyric, a clip, a mail or a file out of the island and drop it on a tab
// (or on any other app). Drag text or files up from another app and the island offers places to pour it.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Droplet: Equatable, Identifiable {
    enum Kind: String { case text, link, file, song, mail, note }
    var id = UUID()
    var kind: Kind
    var title: String
    var body: String?
    var url: URL?
    var source: String

    var symbol: String {
        switch kind {
        case .text: return "text.quote"
        case .link: return "link"
        case .file: return "doc"
        case .song: return "music.note"
        case .mail: return "envelope"
        case .note: return "note.text"
        }
    }

    /// The plain words of the droplet, for notes, tasks and the agent queue.
    var plain: String {
        [title, body, url.map { $0.isFileURL ? $0.lastPathComponent : $0.absoluteString }]
            .compactMap { $0 }.filter { !$0.isEmpty }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: "\n")
    }

    /// What other apps get when you pour it outside Perch.
    func provider() -> NSItemProvider {
        if kind == .file, let url, let p = NSItemProvider(contentsOf: url) { return p }
        if let url, !url.isFileURL {
            let p = NSItemProvider(object: url as NSURL)
            p.registerObject(plain as NSString, visibility: .all)
            return p
        }
        return NSItemProvider(object: plain as NSString)
    }

    static func note(_ n: Note) -> Droplet {
        Droplet(kind: .note, title: Markdown.plain(n.title), body: n.text, url: nil, source: "Notes")
    }
    static func clip(_ c: Clip) -> Droplet {
        let t = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: t), u.scheme?.hasPrefix("http") == true {
            return Droplet(kind: .link, title: u.host ?? t, body: nil, url: u, source: "Clipboard")
        }
        return Droplet(kind: .text, title: String(t.prefix(60)), body: t.count > 60 ? t : nil, url: nil, source: "Clipboard")
    }
    static func mail(_ m: MailItem) -> Droplet {
        Droplet(kind: .mail, title: m.subject, body: "From \(m.from)\n\(m.snippet)",
                url: URL(string: "https://mail.google.com/mail/u/0/#all/\(m.threadID)"), source: "Mail")
    }
    static func file(_ url: URL) -> Droplet {
        Droplet(kind: .file, title: url.lastPathComponent, body: nil, url: url, source: "Shelf")
    }
    static func lyric(_ line: String, track: Track) -> Droplet {
        Droplet(kind: .text, title: line, body: "\(track.title), \(track.artist)", url: nil, source: "Lyrics")
    }
    /// A song is poured as a search link for it in the player it came from.
    static func song(_ t: Track) -> Droplet {
        let q = "\(t.title) \(t.artist)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let link = t.bundleID == "com.spotify.client"
            ? URL(string: "https://open.spotify.com/search/\(q)")
            : URL(string: "https://music.apple.com/search?term=\(q)")
        return Droplet(kind: .song, title: "\(t.title), \(t.artist)", body: nil, url: link, source: "Music")
    }
}

/// Places a droplet can be poured.
enum PourTarget: String, CaseIterable, Identifiable {
    case note, task, shelf, agent, mail, copy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .note: return "Note"
        case .task: return "To-do"
        case .shelf: return "Shelf"
        case .agent: return "Agent"
        case .mail: return "Email"
        case .copy: return "Copy"
        }
    }
    var symbol: String {
        switch self {
        case .note: return "note.text"
        case .task: return "checklist"
        case .shelf: return "tray.full"
        case .agent: return "sparkle"
        case .mail: return "envelope"
        case .copy: return "doc.on.doc"
        }
    }
    var done: String {
        switch self {
        case .note: return "Poured into Notes"
        case .task: return "Added to your list"
        case .shelf: return "Saved on the shelf"
        case .agent: return "Handed to your agents"
        case .mail: return "Email started"
        case .copy: return "Copied"
        }
    }
    /// Dropping straight onto a tab.
    static func of(_ tab: IslandTab) -> PourTarget? {
        switch tab {
        case .notes: return .note
        case .shelf: return .shelf
        case .agents: return .agent
        case .mail: return .mail
        default: return nil
        }
    }
}

@MainActor
final class PourCenter: ObservableObject {
    /// Something dragged into the island from outside, waiting for you to pick where it goes.
    @Published var offer: Droplet?
    /// A short line in the footer after a pour.
    @Published private(set) var toast: String?
    @Published private(set) var toastFailed = false

    private unowned let notes: NotesStore
    private unowned let tasks: TaskStore
    private unowned let shelf: ShelfStore
    private unowned let board: AgentBoard
    private var toastTask: Task<Void, Never>?

    init(notes: NotesStore, tasks: TaskStore, shelf: ShelfStore, board: AgentBoard) {
        self.notes = notes; self.tasks = tasks; self.shelf = shelf; self.board = board
    }

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Perch/Poured", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func pour(_ d: Droplet, into t: PourTarget) {
        offer = nil
        switch t {
        case .note:
            var text = d.kind == .note ? (d.body ?? d.title) : d.plain
            if d.kind == .text, d.source == "Lyrics" { text = "> \(d.title)\n\(d.body ?? "")" }
            _ = notes.add(text)
            done(t)
        case .task:
            tasks.add(d.title)
            done(t)
        case .shelf:
            if d.kind == .file, let u = d.url {
                shelf.add([u])
            } else if let file = writeFile(d) {
                shelf.add([file])
            }
            done(t)
        case .agent:
            Task {
                let ok = await board.sendRequest(kind: d.kind.rawValue, title: d.title, body: agentBody(d), source: d.source)
                if ok { done(t) } else { fail("The board did not take it. Check Settings > Agents.") }
            }
        case .mail:
            var c = URLComponents(string: "mailto:")!
            c.queryItems = [URLQueryItem(name: "subject", value: d.title), URLQueryItem(name: "body", value: d.plain)]
            if let u = c.url { NSWorkspace.shared.open(u) }
            done(t)
        case .copy:
            let pb = NSPasteboard.general
            pb.clearContents()
            if d.kind == .file, let u = d.url { pb.writeObjects([u as NSURL]) } else { pb.setString(d.plain, forType: .string) }
            done(t)
        }
    }

    /// Files stay on this Mac; the agent gets the name and, for small text files, what is inside.
    private func agentBody(_ d: Droplet) -> String? {
        guard d.kind == .file, let u = d.url else { return d.body ?? d.url?.absoluteString }
        let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 0, size <= 4000, let text = try? String(contentsOf: u, encoding: .utf8) { return text }
        return "A file on the Mac: \(u.lastPathComponent). The file itself was not uploaded."
    }

    /// Links become .webloc files and text becomes a .txt, so the shelf can hold them like anything else.
    private func writeFile(_ d: Droplet) -> URL? {
        let safe = String(d.title.map { "/:\\".contains($0) ? "-" : $0 }.prefix(48)).trimmingCharacters(in: .whitespaces)
        let name = safe.isEmpty ? "Poured" : safe
        if let u = d.url, !u.isFileURL {
            let file = Self.folder.appendingPathComponent(name + ".webloc")
            let plist: [String: Any] = ["URL": u.absoluteString]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return nil }
            try? data.write(to: file, options: .atomic)
            return file
        }
        let file = Self.folder.appendingPathComponent(name + ".txt")
        try? d.plain.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private func done(_ t: PourTarget) { show(t.done, failed: false) }
    private func fail(_ s: String) { show(s, failed: true) }

    private func show(_ s: String, failed: Bool) {
        if Prefs.shared.waterSounds { WaterSound.play(failed ? .sink : .plip, volume: 0.3) }
        withAnimation(Motion.snap) { toast = s; toastFailed = failed }
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { self?.toast = nil }
        }
    }

    /// Previews only.
    func previewToast(_ s: String?) { toast = s; toastFailed = false }

    // MARK: Reading drops

    static let types: [UTType] = [.fileURL, .url, .utf8PlainText, .plainText]

    /// The droplet picked up inside Perch, so a pour back into Perch keeps its kind and source.
    static var inFlight: (droplet: Droplet, at: Date)?

    /// Reads a drop, and if it is the droplet picked up inside Perch a moment ago, uses that instead.
    static func resolve(_ providers: [NSItemProvider]) async -> Droplet? {
        let read = await read(providers)
        defer { inFlight = nil }
        if let f = inFlight, Date().timeIntervalSince(f.at) < 120, let r = read,
           r.plain == f.droplet.plain || (r.url != nil && r.url == f.droplet.url) || r.title == f.droplet.title {
            return f.droplet
        }
        return read
    }

    /// Reads the first useful thing from a drop: a file, then a link, then text.
    static func read(_ providers: [NSItemProvider], source: String = "Another app") async -> Droplet? {
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let u = await load(URL.self, from: p), u.isFileURL { return .file(u) }
        }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let u = await load(URL.self, from: p), !u.isFileURL {
                return Droplet(kind: .link, title: u.host ?? u.absoluteString, body: nil, url: u, source: source)
            }
        }
        for p in providers where p.canLoadObject(ofClass: NSString.self) {
            if let s = await load(String.self, from: p) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { continue }
                let first = t.split(separator: "\n").first.map(String.init) ?? t
                return Droplet(kind: .text, title: String(first.prefix(80)), body: t == first ? nil : t, url: nil, source: source)
            }
        }
        return nil
    }

    private static func load(_ type: URL.Type, from p: NSItemProvider) async -> URL? {
        await withCheckedContinuation { c in
            _ = p.loadObject(ofClass: URL.self) { v, _ in c.resume(returning: v) }
        }
    }

    private static func load(_ type: String.Type, from p: NSItemProvider) async -> String? {
        await withCheckedContinuation { c in
            _ = p.loadObject(ofClass: NSString.self) { v, _ in c.resume(returning: v as? String) }
        }
    }
}

// MARK: Views

/// The droplet that follows your pointer while you pour.
struct DropletChip: View {
    let droplet: Droplet
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: droplet.symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Ink.onAccent)
            Text(droplet.title).font(.ui(11.5, .semibold)).foregroundStyle(Ink.onAccent).lineLimit(1)
        }
        .padding(.leading, 10).padding(.trailing, 13).frame(height: 28)
        .frame(maxWidth: 240)
        .background(Capsule().fill(Ink.accent))
        .overlay(alignment: .bottomTrailing) {
            Circle().fill(Ink.accent).frame(width: 8, height: 9).offset(x: -6, y: 7)
        }
        .padding(.bottom, 8)
    }
}

extension View {
    /// Makes a view something you can pick up and pour. (Previews skip it; they cannot draw drag sources.)
    @MainActor @ViewBuilder func pourable(_ make: @escaping () -> Droplet) -> some View {
        if RenderMode.snapshot {
            self
        } else {
            let d = make()
            self.onDrag {
                PourCenter.inFlight = (d, Date())
                return d.provider()
            } preview: { DropletChip(droplet: d) }
        }
    }
}

/// Shown when something is dropped on the island itself: it splits into droplets, one per place it could go.
struct PourOffer: View {
    let droplet: Droplet
    @EnvironmentObject var pour: PourCenter
    @Environment(\.liquidTime) private var fixedTime
    @State private var shown = RenderMode.snapshot

    /// How far droplet i has budded off, 0 to about 1.
    private func grown(_ i: Int) -> CGFloat {
        guard let t = fixedTime else { return shown ? 1 : 0 }
        return CGFloat(Motion.wingSpring.value(t - Double(i) * 0.04))
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Pour it somewhere").eyebrow()
                HStack(spacing: 8) {
                    Image(systemName: droplet.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.accent)
                    Text(droplet.title).font(.serif(17)).foregroundStyle(Ink.text).lineLimit(1)
                }
                .frame(maxWidth: 520)
            }
            HStack(spacing: 14) {
                ForEach(Array(targets.enumerated()), id: \.element) { i, t in
                    Button { pour.pour(droplet, into: t) } label: {
                        VStack(spacing: 7) {
                            Image(systemName: t.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Ink.text)
                                .frame(width: 50, height: 50)
                                .background(Circle().fill(Ink.raisedHover))
                            Text(t.title).font(.ui(11, .medium)).foregroundStyle(Ink.text2)
                        }
                    }
                    .buttonStyle(PressStyle())
                    // Each droplet buds off the one before it.
                    .scaleEffect(0.2 + 0.8 * grown(i))
                    .offset(x: (1 - grown(i)) * CGFloat(targets.count / 2 - i) * 64)
                    .opacity(Double(min(1, grown(i) * 1.5)))
                    .animation(fixedTime == nil ? Motion.wingSpring.animation.delay(Double(i) * 0.04) : nil, value: shown)
                }
            }
            Button("Never mind") { withAnimation(Motion.snap) { pour.offer = nil } }
                .buttonStyle(.plain).font(.ui(11, .medium)).foregroundStyle(Ink.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.pill.opacity(0.94))
        .onAppear { shown = true }
    }

    private var targets: [PourTarget] {
        droplet.kind == .file ? [.shelf, .agent, .note, .mail, .copy] : [.note, .task, .shelf, .agent, .mail, .copy]
    }
}

/// Finished things evaporate: they rise a little, blur and thin out.
struct Evaporate: ViewModifier {
    var p: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: 7 * p).opacity(Double(1 - p)).offset(y: -12 * p).scaleEffect(1 + 0.06 * p)
    }
}

extension AnyTransition {
    /// Heavy things sink in from below; finished things evaporate.
    static var sinkAndEvaporate: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)),
                    removal: .modifier(active: Evaporate(p: 1), identity: Evaporate(p: 0)).animation(.easeOut(duration: 0.6)))
    }
}

// MARK: Tabs

/// One tab. It swells when something is held over it that it can take.
struct TabDroplet: View {
    let tab: IslandTab
    let active: Bool
    let badge: Bool
    let select: () -> Void
    let poured: () -> Void
    @EnvironmentObject var pour: PourCenter
    @State private var targeted = false

    var body: some View {
        Button(action: select) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(active || targeted ? Ink.text : Ink.text3)
                    .frame(width: 32, height: 28)
                    .background(Circle().fill(Ink.accent.opacity(targeted ? 0.30 : 0)).frame(width: 30, height: 30))
                    .scaleEffect(targeted ? 1.3 : 1)
                    .animation(Motion.wingSpring.animation, value: targeted)
                if badge {
                    Circle().fill(Ink.accent).frame(width: 5, height: 5).offset(x: -6, y: 5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(PourTarget.of(tab).map { "\(tab.title). Drop something here to pour it into \($0.title == "Agent" ? "your agents" : tab.title)." } ?? tab.title)
        .modifier(PourDrop(target: PourTarget.of(tab), targeted: $targeted, pour: pour, poured: poured))
    }
}

struct PourDrop: ViewModifier {
    let target: PourTarget?
    @Binding var targeted: Bool
    let pour: PourCenter
    let poured: () -> Void
    func body(content: Content) -> some View {
        if RenderMode.snapshot || target == nil {
            content
        } else {
            content.onDrop(of: PourCenter.types, isTargeted: $targeted) { providers in
                Task { @MainActor in
                    if let d = await PourCenter.resolve(providers), let target {
                        pour.pour(d, into: target)
                        poured()
                    }
                }
                return true
            }
        }
    }
}

/// The selected tab as liquid: a leading bead runs ahead, the rest follows, and they merge where it lands.
struct GooTabs: View, Animatable {
    var from: CGFloat
    var to: CGFloat
    var progress: CGFloat
    var color: Color

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let p = max(0, progress)
            let c = min(1, p)
            let lead = from + (to - from) * (1 - pow(1 - c, 3) + max(0, p - 1))
            let tail = from + (to - from) * (c * c)
            let thin = sin(.pi * c)
            ctx.addFilter(.alphaThreshold(min: 0.5, color: color))
            ctx.addFilter(.blur(radius: 4))
            var beads: [(CGFloat, CGFloat, CGFloat)] = [(lead, 33, 29)]
            if abs(lead - tail) > 0.01 { beads.append((tail, 33 * (1 - 0.4 * thin), 29 * (1 - 0.3 * thin))) }
            for (i, w, h) in beads {
                let x = 12 + i * 33 + 16
                let r = CGRect(x: x - w / 2, y: size.height / 2 - h / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: h / 2, style: .continuous), with: .color(.black))
            }
        }
    }
}

// MARK: The pool

/// When the island spills, everything that matters right now settles beside the pane, heaviest first.
/// Urgent things sink to the front; finished things evaporate.
struct PoolColumn: View {
    @EnvironmentObject var tasks: TaskStore
    @EnvironmentObject var calendar: CalendarCenter
    @EnvironmentObject var gmail: GmailCenter
    @EnvironmentObject var board: AgentBoard
    @EnvironmentObject var timers: TimerCenter
    @EnvironmentObject var model: IslandModel

    struct Item: Identifiable {
        let id: String
        let weight: Double
        let symbol: String
        let title: String
        let detail: String
        let tint: Color
        var task: TaskItem? = nil
        var droplet: Droplet? = nil
        var tab: IslandTab? = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pool").eyebrow()
                Spacer()
                Text("heaviest first").font(.ui(9.5)).foregroundStyle(Ink.text3)
            }
            if items.isEmpty {
                Spacer()
                Text("Nothing heavy right now.").font(.serif(14)).foregroundStyle(Ink.text3).frame(maxWidth: .infinity)
                Spacer()
            } else {
                Scrolling {
                    VStack(spacing: 4) {
                        ForEach(items.prefix(RenderMode.snapshot ? 5 : 12)) { item in
                            row(item).transition(.sinkAndEvaporate)
                        }
                    }
                    .animation(Motion.wing, value: items.map(\.id))
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, 20).padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .overlay(alignment: .leading) { Rectangle().fill(Ink.hairline).frame(width: 1).padding(.vertical, 6) }
    }

    @ViewBuilder private func row(_ item: Item) -> some View {
        HStack(spacing: 10) {
            // Heavier droplets are bigger.
            ZStack {
                Circle().fill(item.tint.opacity(0.18))
                Image(systemName: item.symbol).font(.system(size: 9 + 3 * item.weight, weight: .semibold)).foregroundStyle(item.tint)
            }
            .frame(width: 16 + 10 * item.weight, height: 16 + 10 * item.weight)
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.ui(12, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                Text(item.detail).font(.ui(10.5)).foregroundStyle(Ink.text3).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let t = item.task {
                Button { withAnimation(Motion.snap) { tasks.toggle(t) } } label: {
                    Image(systemName: "circle").font(.system(size: 13)).foregroundStyle(Ink.text3)
                }
                .buttonStyle(.plain)
                .help("Done. It evaporates.")
            }
        }
        .padding(.horizontal, 8).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.raised))
        .contentShape(Rectangle())
        .onTapGesture { if let tab = item.tab { withAnimation(Motion.tab) { model.tab = tab } } }
        .pourable { item.droplet ?? Droplet(kind: .text, title: item.title, body: item.detail, url: nil, source: "Pool") }
    }

    var items: [Item] {
        var out: [Item] = []
        let now = Date()
        for t in tasks.items where !t.done {
            let w: Double
            if let due = t.due {
                let h = due.timeIntervalSince(now) / 3600
                w = h < 0 ? 1 : (h < 12 ? 0.85 : (h < 48 ? 0.6 : 0.35))
            } else { w = 0.25 }
            let due = dueText(t.due)
            out.append(Item(id: "t" + t.id.uuidString, weight: w, symbol: "checklist", title: t.title,
                            detail: [t.subject, due].filter { !$0.isEmpty }.joined(separator: " · "),
                            tint: w >= 1 ? Ink.coral : (w > 0.8 ? Ink.amber : Ink.text2), task: t, tab: .notes))
        }
        for e in calendar.events where e.start > now.addingTimeInterval(-300) {
            let m = e.start.timeIntervalSince(now) / 60
            guard m < 240 else { continue }
            out.append(Item(id: "e" + e.id, weight: m < 15 ? 0.95 : (m < 60 ? 0.7 : 0.4), symbol: "calendar", title: e.title,
                            detail: untilText(e.start.timeIntervalSince(now)).capitalizedFirst, tint: e.calendarColor, tab: .today))
        }
        for a in board.agents {
            if a.status == .failed {
                out.append(Item(id: "a" + a.id, weight: 0.8, symbol: "exclamationmark.triangle", title: a.name, detail: a.note ?? "Stopped",
                                tint: Ink.coral, tab: .agents))
            } else if a.isWorking {
                out.append(Item(id: "a" + a.id, weight: 0.4, symbol: "sparkle", title: a.name, detail: a.task ?? "Working",
                                tint: Ink.accent, tab: .agents))
            }
            // Finished agents evaporate: they are not in the pool.
        }
        for r in board.requests where r.status != "done" {
            out.append(Item(id: "r" + r.id, weight: 0.3, symbol: "drop", title: r.title ?? "Poured request",
                            detail: r.status == "claimed" ? "Picked up by \(r.claimedBy ?? "an agent")" : "Waiting for an agent",
                            tint: Ink.text2, tab: .agents))
        }
        for m in gmail.items.prefix(3) where m.unread {
            out.append(Item(id: "m" + m.id, weight: 0.5, symbol: "envelope", title: m.from, detail: m.subject, tint: Ink.accent,
                            droplet: .mail(m), tab: .mail))
        }
        if let r = timers.current {
            out.append(Item(id: "timer", weight: 0.65, symbol: "timer", title: r.label.isEmpty ? "Timer" : r.label,
                            detail: clock(timers.remaining) + " left", tint: Ink.accent, tab: .today))
        }
        return out.sorted { $0.weight > $1.weight }
    }
}
