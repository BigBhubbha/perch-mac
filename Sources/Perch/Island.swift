// The island: a black pill hiding behind the camera cover. Quiet wings at rest, short moments when
// something happens, and a full deck when you reach for it.
import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

enum IslandTab: String, CaseIterable, Identifiable {
    case today, music, notes, agents, shelf, mail, launch
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .music: return "Music"
        case .notes: return "Notes"
        case .agents: return "Agents"
        case .shelf: return "Shelf"
        case .mail: return "Mail"
        case .launch: return "Launch"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "square.grid.2x2"
        case .music: return "music.note"
        case .notes: return "text.alignleft"
        case .agents: return "sparkles"
        case .shelf: return "tray"
        case .mail: return "envelope"
        case .launch: return "command"
        }
    }
}

/// What the wings show while resting. Ordered by how much it matters right now.
enum WingKind: Equatable {
    case privacy(camera: Bool)
    case timer
    case event
    case agents
    case music
    case charging
    case mail

    var width: CGFloat {
        switch self {
        case .timer, .event, .charging: return 60
        case .privacy, .agents, .music, .mail: return 44
        }
    }
}

/// Every store the island draws from, handed to the views as environment objects.
@MainActor
final class Hub {
    let music = NowPlayingCenter()
    let notes: NotesStore
    let tasks = TaskStore()
    let board = AgentBoard()
    let signals = SignalCenter()
    let timers = TimerCenter()
    let calendar = CalendarCenter()
    let weather = WeatherCenter()
    let shelf = ShelfStore()
    let launcher = LauncherStore()
    let gmail = GmailCenter()
    let pour: PourCenter

    /// Previews pass a scratch notes file so they never touch real notes.
    init(notesFile: URL? = nil) {
        notes = NotesStore(file: notesFile)
        pour = PourCenter(notes: notes, tasks: tasks, shelf: shelf, board: board)
    }
}

extension View {
    @MainActor func hub(_ h: Hub, _ model: IslandModel) -> some View {
        self.environmentObject(model).environmentObject(Prefs.shared)
            .environmentObject(h.music).environmentObject(h.notes).environmentObject(h.tasks)
            .environmentObject(h.board).environmentObject(h.signals).environmentObject(h.timers)
            .environmentObject(h.calendar).environmentObject(h.weather).environmentObject(h.shelf)
            .environmentObject(h.launcher).environmentObject(h.gmail).environmentObject(h.pour)
    }
}

@MainActor
final class IslandModel: ObservableObject {
    enum State: Equatable { case resting, open, moment(Moment) }

    @Published var state: State = .resting
    @Published var tab: IslandTab = .today { didSet { Prefs.shared.lastTab = tab.rawValue } }
    @Published var showingMenu = false
    @Published var wing: WingKind?
    @Published var dropHover = false
    @Published var noteFocus = false
    /// Where the pointer touched the island as it opened, in island coordinates, for the ripple.
    @Published var rippleOrigin: CGPoint?
    @Published var rippleTick = 0
    /// Flicked down hard: the island spills into a wider workspace with the pool beside the pane.
    @Published var spilled = false
    /// Bumps every time a new moment starts, so the surface can grow a drip.
    @Published var momentSerial = 0

    var onCheckForUpdates: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onRecalibrate: () -> Void = {}
    var onQuit: () -> Void = {}
    var onQuickNote: () -> Void = {}

    static let momentWing: CGFloat = 150
    static let hudWing: CGFloat = 118
    static let openWidth: CGFloat = 780
    static let bodyHeight: CGFloat = 232
    static let footerHeight: CGFloat = 34
    static let poolWidth: CGFloat = 290

    init() {
        tab = IslandTab(rawValue: Prefs.shared.lastTab) ?? .today
    }

    var isOpen: Bool { state == .open }

    func openSize(_ g: PillGeometry, spilled: Bool? = nil) -> CGSize {
        CGSize(width: max(IslandModel.openWidth, g.width + 480) + ((spilled ?? self.spilled) ? IslandModel.poolWidth : 0),
               height: g.height + IslandModel.bodyHeight + IslandModel.footerHeight)
    }

    /// The width of the pane area, which stays the same when the island spills.
    func paneWidth(_ g: PillGeometry) -> CGFloat { openSize(g, spilled: false).width }

    static func momentWidth(_ m: Moment) -> CGFloat {
        switch m.kind {
        case .volume, .brightness: return hudWing
        default: return momentWing
        }
    }

    func size(_ g: PillGeometry, wings: Bool, in st: State? = nil) -> CGSize {
        switch st ?? state {
        case .resting: return CGSize(width: g.width + (wings ? (wing?.width ?? 0) * 2 : 0), height: g.height)
        case .moment(let m): return CGSize(width: g.width + Self.momentWidth(m) * 2, height: g.height)
        case .open: return openSize(g)
        }
    }

    /// The largest the island ever gets, so the window never clips the spring.
    func maxSize(_ g: PillGeometry) -> CGSize {
        let o = openSize(g, spilled: true)
        return CGSize(width: max(o.width, g.width + IslandModel.momentWing * 2), height: o.height)
    }

    var visibleTabs: [IslandTab] {
        let shown = IslandTab.allCases.filter { Prefs.shared.isTabShown($0.rawValue) }
        return shown.isEmpty ? [.today] : shown
    }
}

// MARK: Window

/// Transparent, non-activating panel that sits above the menu bar on every Space.
class IslandPanel: NSPanel {
    var allowsKey = false
    var onEscape: (() -> Void)?
    var onKey: ((NSEvent) -> Bool)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if let onKey, onKey(event) { return }
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

/// Buttons work on the first click even though Perch never becomes the active app.
final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: Controller

@MainActor
final class IslandController {
    let model = IslandModel()
    let prefs = Prefs.shared
    let hub: Hub

    private let panel: IslandPanel
    private var bag = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var momentTask: Task<Void, Never>?
    private var watchTimer: Timer?
    private var wingTimer: Timer?
    private var momentQueue: [Moment] = []
    /// Hover hysteresis: after the island closes, the pointer has to leave the resting area once
    /// before hovering can open it again. This stops open, close, open loops at the top edge.
    private var hoverArmed = true
    private var closedAt = Date.distantPast
    private var wingQuietSince: Date?
    private var dragChangeAtDown = NSPasteboard(name: .drag).changeCount
    private var openedForDrop = false
    private var scrollAccum: CGFloat = 0
    private var lastScrollAt = Date.distantPast
    var suspended = false { didSet { panel.alphaValue = suspended ? 0 : 1 } }

    private let shadowRoom: CGFloat = 40

    init(hub: Hub) {
        self.hub = hub
        panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10))
        let root = IslandView().hub(hub, model)
        let host = FirstClickHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        panel.contentView = host
        panel.ignoresMouseEvents = true
        panel.onEscape = { [weak self] in self?.close() }

        prefs.$geometry.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.place() }
        }.store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        model.onQuickNote = { [weak self] in
            guard let self else { return }
            self.hub.notes.add()
            self.model.tab = .notes
            self.model.noteFocus = true
        }
    }

    func show() {
        place()
        panel.orderFrontRegardless()
        installMonitors()
        wingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateWing() }
        }
        wingTimer?.tolerance = 0.2
        updateWing()
    }

    // MARK: Placement

    /// The built-in display (the one with the notch), else the main display.
    var homeScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// The window is one fixed size (big enough for the open island) and never moves or resizes while
    /// you use it. Only the drawing inside changes, so nothing shifts under the pointer.
    func place() {
        guard let screen = homeScreen else { return }
        let g = prefs.geometry
        let m = model.maxSize(g)
        let w = (m.width + shadowRoom * 2).rounded()
        let h = (g.topOffset + m.height + shadowRoom).rounded()
        let f = screen.frame
        let target = NSRect(x: (f.midX + g.horizontalOffset - w / 2).rounded(), y: f.maxY - h, width: w, height: h)
        if panel.frame != target { panel.setFrame(target, display: true) }
    }

    // MARK: Wings

    /// What deserves the wings right now. Turns on at once, and only goes quiet after 4 calm seconds,
    /// so a track change or a flicker never makes the island twitch.
    private func desiredWing() -> WingKind? {
        let s = hub.signals
        if prefs.privacyDots && (s.cameraOn || s.micOn) { return .privacy(camera: s.cameraOn) }
        if hub.timers.current != nil { return .timer }
        if let n = hub.calendar.next, n.start > Date(), n.start.timeIntervalSinceNow < 10 * 60 { return .event }
        if !hub.board.working.isEmpty { return .agents }
        if hub.music.isPlaying { return .music }
        if s.battery.hasBattery && s.battery.charging && s.battery.percent < 100 { return .charging }
        return nil
    }

    private func updateWing() {
        guard prefs.showWings else { if model.wing != nil { withAnimation(Motion.wing) { model.wing = nil } }; return }
        let want = desiredWing()
        if let want {
            wingQuietSince = nil
            if model.wing != want { withAnimation(Motion.wing) { model.wing = want } }
        } else if model.wing != nil {
            if wingQuietSince == nil { wingQuietSince = Date() }
            if let q = wingQuietSince, Date().timeIntervalSince(q) > 4 {
                withAnimation(Motion.wing) { model.wing = nil }
                wingQuietSince = nil
            }
        }
    }

    /// Where the island is on screen right now, in screen coordinates.
    private func islandRect(for state: IslandModel.State) -> NSRect {
        guard let screen = homeScreen else { return .zero }
        let g = prefs.geometry
        let s = model.size(g, wings: prefs.showWings && model.wing != nil, in: state)
        let f = screen.frame
        return NSRect(x: f.midX + g.horizontalOffset - s.width / 2, y: f.maxY - g.topOffset - s.height,
                      width: s.width, height: s.height)
    }

    // MARK: Mouse

    private func installMonitors() {
        removeMonitors()
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] e in
            let dragging = e.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.mouseMoved(NSEvent.mouseLocation, dragging: dragging) }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] e in
            let dragging = e.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.mouseMoved(NSEvent.mouseLocation, dragging: dragging) }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseClicked(NSEvent.mouseLocation) }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.mouseClicked(NSEvent.mouseLocation) }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] e in
            let dy = e.scrollingDeltaY, precise = e.hasPreciseScrollingDeltas
            MainActor.assumeIsolated { self?.scrolled(dy: dy, precise: precise) }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] e in
            let dy = e.scrollingDeltaY, precise = e.hasPreciseScrollingDeltas
            MainActor.assumeIsolated { self?.scrolled(dy: dy, precise: precise) }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dragEnded() }
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func mouseMoved(_ p: NSPoint, dragging: Bool) {
        guard !suspended else { return }
        switch model.state {
        case .resting, .moment:
            let hot = islandRect(for: model.state).insetBy(dx: -6, dy: -4)
            // Dragging a file up to the island opens the shelf so you can drop it.
            // Dragging a file up to the island opens the shelf; dragging text or a link opens it to pour.
            if dragging, hot.insetBy(dx: -30, dy: -12).contains(p), let files = draggingPourable() {
                openedForDrop = true
                if files { model.tab = .shelf }
                open()
                return
            }
            if !hoverArmed {
                // Re-arm only once the pointer has really left the island and a moment has passed.
                if !hot.insetBy(dx: -10, dy: -10).contains(p) && Date().timeIntervalSince(closedAt) > 0.35 { hoverArmed = true }
                return
            }
            guard prefs.openOnHover, !dragging, hot.contains(p) else { hoverTask?.cancel(); hoverTask = nil; return }
            guard hoverTask == nil else { return }
            let delay = UInt64(max(0, prefs.hoverDelay) * 1_000_000_000)
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard let self, !Task.isCancelled else { return }
                self.hoverTask = nil
                if self.islandRect(for: self.model.state).insetBy(dx: -6, dy: -4).contains(NSEvent.mouseLocation) { self.open() }
            }
        case .open:
            checkLeave(p)
        }
    }

    /// nil when nothing pourable is being dragged; true for files, false for text or links.
    private func draggingPourable() -> Bool? {
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != dragChangeAtDown else { return nil }
        let types = pb.types ?? []
        if types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) { return true }
        if types.contains(.string) || types.contains(.URL) { return false }
        return nil
    }

    private func dragEnded() {
        dragChangeAtDown = NSPasteboard(name: .drag).changeCount
        if openedForDrop {
            openedForDrop = false
            // Give the drop a moment to land, then behave like a normal hover.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000)
                self?.checkLeave(NSEvent.mouseLocation)
            }
        }
    }

    /// Two fingers down on the island opens it; two fingers up closes it.
    private func scrolled(dy: CGFloat, precise: Bool) {
        guard prefs.swipeToOpen, !suspended, precise else { return }
        let p = NSEvent.mouseLocation
        switch model.state {
        case .resting, .moment:
            guard islandRect(for: model.state).insetBy(dx: -8, dy: -6).contains(p) else { scrollAccum = 0; return }
            scrollAccum = max(0, scrollAccum + dy)
            if scrollAccum > 18 { scrollAccum = 0; open() }
        case .open:
            // A hard flick down on the top band spills the island into the wider workspace; flick up to gather it.
            let r = islandRect(for: .open)
            let band = NSRect(x: r.minX, y: r.maxY - prefs.geometry.height - 12, width: r.width, height: prefs.geometry.height + 12)
            guard band.contains(p) else { scrollAccum = 0; return }
            if Date().timeIntervalSince(lastScrollAt) > 0.35 { scrollAccum = 0 }
            lastScrollAt = Date()
            scrollAccum += dy
            if scrollAccum > 42, !model.spilled { scrollAccum = 0; spill(true) }
            if scrollAccum < -30, model.spilled { scrollAccum = 0; spill(false) }
        }
    }

    func spill(_ on: Bool) {
        guard model.isOpen, model.spilled != on else { return }
        if prefs.haptics { Haptics.level() }
        if on, prefs.waterSounds { WaterSound.play(.fill, volume: 0.22) }
        withAnimation(on ? Motion.open : Motion.close) { model.spilled = on }
        if on { hub.board.refreshSoon() }
    }

    private func checkLeave(_ p: NSPoint) {
        let keep = islandRect(for: .open).insetBy(dx: -16, dy: -16)
        if keep.contains(p) || isEditing || model.showingMenu || openedForDrop {
            leaveTask?.cancel(); leaveTask = nil
            return
        }
        guard leaveTask == nil else { return }
        leaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard let self, !Task.isCancelled else { return }
            self.leaveTask = nil
            if !self.islandRect(for: .open).insetBy(dx: -16, dy: -16).contains(NSEvent.mouseLocation) && !self.isEditing {
                self.close()
            }
        }
    }

    private func mouseClicked(_ p: NSPoint) {
        guard !suspended else { return }
        dragChangeAtDown = NSPasteboard(name: .drag).changeCount
        switch model.state {
        case .resting, .moment:
            if islandRect(for: model.state).contains(p) { open() }
        case .open:
            if !islandRect(for: .open).contains(p) { close() }
        }
    }

    /// Typing keeps the island open even if the pointer wanders off.
    private var isEditing: Bool {
        panel.isKeyWindow && panel.firstResponder is NSTextView
    }

    // MARK: Open and close

    func toggle() { model.isOpen ? close() : open(keyboard: true) }

    func open(keyboard: Bool = false) {
        hoverTask?.cancel(); hoverTask = nil
        leaveTask?.cancel(); leaveTask = nil
        momentTask?.cancel()
        guard !model.isOpen else { return }
        if !model.visibleTabs.contains(model.tab) { model.tab = model.visibleTabs[0] }
        panel.ignoresMouseEvents = false
        panel.allowsKey = true
        if keyboard { panel.makeKey() }
        if prefs.haptics { Haptics.tick() }
        if !keyboard, let screen = homeScreen {
            let g = prefs.geometry, p = NSEvent.mouseLocation, f = screen.frame, o = model.openSize(g)
            model.rippleOrigin = CGPoint(x: p.x - (f.midX + g.horizontalOffset - o.width / 2),
                                         y: max(8, min(g.height, f.maxY - g.topOffset - p.y)))
            model.rippleTick += 1
        }
        if prefs.waterSounds { WaterSound.play(.plip, volume: 0.22) }
        withAnimation(Motion.open) { model.state = .open }
        hub.board.refreshSoon()
        hub.weather.refreshIfStale()
        hub.calendar.reload()
        // A slow safety net for leaving the island, in case a mouse event is missed.
        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.isOpen else { return }
                self.checkLeave(NSEvent.mouseLocation)
            }
        }
    }

    func close() {
        guard model.isOpen else { return }
        leaveTask?.cancel(); leaveTask = nil
        watchTimer?.invalidate(); watchTimer = nil
        model.showingMenu = false
        model.noteFocus = false
        hub.notes.dropEmpty(except: nil)
        panel.allowsKey = false
        if panel.isKeyWindow {
            // Hand the keyboard back to whatever you were using.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        panel.ignoresMouseEvents = true
        hoverArmed = false
        closedAt = Date()
        withAnimation(Motion.close) { model.state = .resting; model.spilled = false }
        hub.pour.offer = nil
        playNextMoment()
    }

    // MARK: Moments

    /// A short, wide flash: an agent finished, the charger went in, the volume changed.
    func flash(_ m: Moment) {
        if model.isOpen { return }
        // Volume and brightness replace each other at once instead of queueing.
        if m.kind == .volume || m.kind == .brightness {
            momentQueue.removeAll { $0.kind == m.kind }
            if case .moment(let cur) = model.state, cur.kind == m.kind {
                model.state = .moment(m)
                scheduleMomentEnd(m.duration)
                return
            }
            momentQueue.insert(m, at: 0)
        } else {
            momentQueue.append(m)
            if momentQueue.count > 6 { momentQueue.removeFirst() }
        }
        if case .moment = model.state {
            if m.kind == .volume || m.kind == .brightness { playNextMoment() }
            return
        }
        playNextMoment()
    }

    private func playNextMoment() {
        guard !model.isOpen, !momentQueue.isEmpty else { return }
        let next = momentQueue.removeFirst()
        withAnimation(next.kind == .volume || next.kind == .brightness ? Motion.wing : Motion.bloom) { model.state = .moment(next) }
        model.momentSerial += 1
        scheduleMomentEnd(next.duration)
    }

    private func scheduleMomentEnd(_ seconds: TimeInterval) {
        momentTask?.cancel()
        momentTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if case .moment = self.model.state {
                withAnimation(Motion.close) { self.model.state = .resting }
                try? await Task.sleep(nanoseconds: 450_000_000)
                self.playNextMoment()
            }
        }
    }
}

// MARK: Shape

/// Flat top that tucks under the bezel, small outward curves where it meets the top edge,
/// and round bottom corners. When it floats (top gap > 0) it becomes a plain rounded pill.
struct IslandShape: Shape {
    var radius: CGFloat
    var ear: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, ear) }
        set { radius = newValue.first; ear = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let br = max(0, min(radius, r.height / 2, r.width / 2))
        let e = max(0, min(ear, r.height / 2))
        if e < 0.5 {
            return Path(roundedRect: r, cornerRadius: br, style: .continuous)
        }
        var p = Path()
        p.move(to: CGPoint(x: r.minX - e, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX + e, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + e), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addCurve(to: CGPoint(x: r.maxX - br, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.maxY - br * 0.45),
                   control2: CGPoint(x: r.maxX - br * 0.45, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + br, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - br),
                   control1: CGPoint(x: r.minX + br * 0.45, y: r.maxY),
                   control2: CGPoint(x: r.minX, y: r.maxY - br * 0.45))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.minX - e, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}
