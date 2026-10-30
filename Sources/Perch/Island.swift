// The island: a black pill hiding behind the camera cover. Hover it and it grows into the full panel.
import AppKit
import SwiftUI
import Combine

enum IslandTab: String, CaseIterable, Identifiable {
    case playing, notes, agents, mail
    var id: String { rawValue }
    var title: String {
        switch self {
        case .playing: return "Playing"
        case .notes: return "Notes"
        case .agents: return "Agents"
        case .mail: return "Mail"
        }
    }
    var symbol: String {
        switch self {
        case .playing: return "music.note"
        case .notes: return "square.and.pencil"
        case .agents: return "circle.grid.2x2"
        case .mail: return "envelope"
        }
    }
}

struct BloomInfo: Equatable {
    let name: String
    let success: Bool
    let line: String?
}

@MainActor
final class IslandModel: ObservableObject {
    enum State: Equatable { case resting, open, bloom(BloomInfo) }

    @Published var state: State = .resting
    @Published var tab: IslandTab = .playing { didSet { Prefs.shared.lastTab = tab.rawValue } }
    @Published var showingMenu = false
    /// Debounced "something to show beside the cover". Turns on at once, turns off only after a few
    /// quiet seconds, so a track change or a flickering play state never makes the island twitch.
    @Published var wingsOn = false

    var onCheckForUpdates: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onRecalibrate: () -> Void = {}
    var onQuit: () -> Void = {}

    static let wing: CGFloat = 42
    static let bloomWing: CGFloat = 150
    static let openWidth: CGFloat = 620
    static let bodyHeight: CGFloat = 178
    static let footerHeight: CGFloat = 34

    init() {
        tab = IslandTab(rawValue: Prefs.shared.lastTab) ?? .playing
    }

    var isOpen: Bool { state == .open }

    func openSize(_ g: PillGeometry) -> CGSize {
        CGSize(width: max(IslandModel.openWidth, g.width + 380),
               height: g.height + IslandModel.bodyHeight + IslandModel.footerHeight)
    }

    func size(_ g: PillGeometry, wings: Bool, in st: State? = nil) -> CGSize {
        switch st ?? state {
        case .resting: return CGSize(width: g.width + (wings ? IslandModel.wing * 2 : 0), height: g.height)
        case .bloom: return CGSize(width: g.width + IslandModel.bloomWing * 2, height: g.height)
        case .open: return openSize(g)
        }
    }

    /// The largest the island ever gets, so the window never clips the spring.
    func maxSize(_ g: PillGeometry) -> CGSize {
        let o = openSize(g)
        return CGSize(width: max(o.width, g.width + IslandModel.bloomWing * 2), height: o.height)
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
    let music: NowPlayingCenter
    let notes: NotesStore
    let board: AgentBoard

    private let panel: IslandPanel
    private var bag = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var bloomTask: Task<Void, Never>?
    private var watchTimer: Timer?
    private var bloomQueue: [BloomInfo] = []
    /// Hover hysteresis: after the island closes, the pointer has to leave the resting area once
    /// before hovering can open it again. This stops open, close, open loops at the top edge.
    private var hoverArmed = true
    private var closedAt = Date.distantPast
    private var wingsOffTask: Task<Void, Never>?
    var suspended = false { didSet { panel.alphaValue = suspended ? 0 : 1 } }

    private let shadowRoom: CGFloat = 36

    init(music: NowPlayingCenter, notes: NotesStore, board: AgentBoard) {
        self.music = music
        self.notes = notes
        self.board = board
        panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10))
        let root = IslandView(model: model, prefs: prefs, music: music, notes: notes, board: board)
        let host = FirstClickHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        panel.ignoresMouseEvents = true
        panel.onEscape = { [weak self] in self?.close() }

        // Wings: on immediately, off after 4 quiet seconds.
        music.$track.map { $0?.playing == true }.removeDuplicates()
            .combineLatest(board.$agents.map { $0.contains(where: \.isWorking) }.removeDuplicates())
            .map { $0 || $1 }
            .removeDuplicates()
            .sink { [weak self] on in
                MainActor.assumeIsolated { self?.setWings(on) }
            }
            .store(in: &bag)

        prefs.$geometry.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.place() }
        }.store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
    }

    func show() {
        place()
        panel.orderFrontRegardless()
        installMonitors()
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

    private func setWings(_ on: Bool) {
        wingsOffTask?.cancel()
        if on {
            if !model.wingsOn { withAnimation(Motion.wing) { model.wingsOn = true } }
            return
        }
        wingsOffTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            withAnimation(Motion.wing) { self.model.wingsOn = false }
        }
    }

    /// Where the island is on screen right now, in screen coordinates.
    private func islandRect(for state: IslandModel.State) -> NSRect {
        guard let screen = homeScreen else { return .zero }
        let g = prefs.geometry
        let s = model.size(g, wings: wingsVisible, in: state)
        let f = screen.frame
        return NSRect(x: f.midX + g.horizontalOffset - s.width / 2, y: f.maxY - g.topOffset - s.height,
                      width: s.width, height: s.height)
    }

    private var wingsVisible: Bool { prefs.showWings && model.wingsOn }

    // MARK: Mouse

    private func installMonitors() {
        removeMonitors()
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved(NSEvent.mouseLocation) }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.mouseMoved(NSEvent.mouseLocation) }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseClicked(NSEvent.mouseLocation, inPanel: false) }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] e in
            let mine = e.window === self?.panel
            MainActor.assumeIsolated { self?.mouseClicked(NSEvent.mouseLocation, inPanel: mine) }
            return e
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func mouseMoved(_ p: NSPoint) {
        guard !suspended else { return }
        switch model.state {
        case .resting, .bloom:
            let hot = islandRect(for: model.state).insetBy(dx: -6, dy: -4)
            if !hoverArmed {
                // Re-arm only once the pointer has really left the island and a moment has passed.
                if !hot.insetBy(dx: -10, dy: -10).contains(p) && Date().timeIntervalSince(closedAt) > 0.35 { hoverArmed = true }
                return
            }
            guard prefs.openOnHover, hot.contains(p) else { hoverTask?.cancel(); hoverTask = nil; return }
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

    private func checkLeave(_ p: NSPoint) {
        let keep = islandRect(for: .open).insetBy(dx: -16, dy: -16)
        if keep.contains(p) || isEditing || model.showingMenu {
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

    private func mouseClicked(_ p: NSPoint, inPanel: Bool) {
        guard !suspended else { return }
        switch model.state {
        case .resting, .bloom:
            if islandRect(for: model.state).contains(p) { open() }
        case .open:
            if !islandRect(for: .open).contains(p) { close() }
        }
    }

    /// Typing a note keeps the island open even if the pointer wanders off.
    private var isEditing: Bool {
        panel.isKeyWindow && panel.firstResponder is NSTextView
    }

    // MARK: Open and close

    func toggle() { model.isOpen ? close() : open() }

    func open() {
        hoverTask?.cancel(); hoverTask = nil
        leaveTask?.cancel(); leaveTask = nil
        bloomTask?.cancel()
        guard !model.isOpen else { return }
        panel.ignoresMouseEvents = false
        panel.allowsKey = true
        withAnimation(Motion.open) { model.state = .open }
        board.refreshSoon()
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
        notes.dropEmpty(except: nil)
        panel.allowsKey = false
        if panel.isKeyWindow {
            // Hand the keyboard back to whatever you were using.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        panel.ignoresMouseEvents = true
        hoverArmed = false
        closedAt = Date()
        withAnimation(Motion.close) { model.state = .resting }
        playNextBloom()
    }

    // MARK: Bloom

    /// A short, wide flash when an agent finishes: the dot blooms and the name slides out from behind the cover.
    func bloom(_ info: BloomInfo) {
        if model.isOpen { return } // the open panel shows the bloom on the agent's own row
        bloomQueue.append(info)
        if case .bloom = model.state { return }
        playNextBloom()
    }

    private func playNextBloom() {
        guard !model.isOpen, !bloomQueue.isEmpty else { return }
        let next = bloomQueue.removeFirst()
        withAnimation(Motion.bloom) { model.state = .bloom(next) }
        bloomTask?.cancel()
        bloomTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            guard let self, !Task.isCancelled else { return }
            if case .bloom = self.model.state {
                withAnimation(Motion.close) { self.model.state = .resting }
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.playNextBloom()
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
