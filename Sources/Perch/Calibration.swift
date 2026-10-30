// First-run fitting: a bright pill you drag and stretch until a thin, even ring shows all the way
// around the camera cover. Saved to Settings and redoable any time ("Refit").
import AppKit
import SwiftUI

@MainActor
final class CalibrationModel: ObservableObject {
    @Published var g: PillGeometry
    @Published var previewBlack = false
    let original: PillGeometry
    let firstRun: Bool
    var onDone: (PillGeometry) -> Void = { _ in }
    var onCancel: () -> Void = {}

    init(geometry: PillGeometry, firstRun: Bool) {
        g = geometry
        original = geometry
        self.firstRun = firstRun
    }

    func nudge(dx: CGFloat = 0, dy: CGFloat = 0, dw: CGFloat = 0, dh: CGFloat = 0, dr: CGFloat = 0) {
        var n = g
        n.horizontalOffset += dx
        n.topOffset += dy
        n.width += dw
        n.height += dh
        // Keep a full pill shape while the height changes, unless the corners were set by hand.
        if dh != 0 && abs(g.cornerRadius - g.height / 2) < 1 { n.cornerRadius = n.height / 2 }
        n.cornerRadius += dr
        g = n.clamped()
    }

    /// Arrow keys move, Option + arrows resize, [ and ] round the corners, Shift makes every step 5 points.
    func handle(_ e: NSEvent) -> Bool {
        let step: CGFloat = e.modifierFlags.contains(.shift) ? 5 : 1
        let resize = e.modifierFlags.contains(.option)
        switch e.keyCode {
        case 123: resize ? nudge(dw: -2 * step) : nudge(dx: -step); return true
        case 124: resize ? nudge(dw: 2 * step) : nudge(dx: step); return true
        case 125: resize ? nudge(dh: step) : nudge(dy: step); return true
        case 126: resize ? nudge(dh: -step) : nudge(dy: -step); return true
        case 33: nudge(dr: -step); return true
        case 30: nudge(dr: step); return true
        case 36, 76: onDone(g); return true
        case 53: onCancel(); return true
        default: return false
        }
    }
}

@MainActor
final class CalibrationController {
    private var panel: IslandPanel?
    private(set) var isOpen = false

    func start(on screen: NSScreen, geometry: PillGeometry, firstRun: Bool,
               done: @escaping (PillGeometry) -> Void, cancelled: @escaping () -> Void) {
        close()
        let model = CalibrationModel(geometry: geometry, firstRun: firstRun)
        let f = screen.frame
        let height: CGFloat = 420
        let p = IslandPanel(contentRect: NSRect(x: f.minX, y: f.maxY - height, width: f.width, height: height))
        p.allowsKey = true
        p.onKey = { e in model.handle(e) }
        model.onDone = { [weak self] g in self?.close(); done(g) }
        model.onCancel = { [weak self] in self?.close(); cancelled() }
        p.contentView = FirstClickHostingView(rootView: CalibrationView(model: model))
        p.setFrame(NSRect(x: f.minX, y: f.maxY - height, width: f.width, height: height), display: true)
        panel = p
        isOpen = true
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        isOpen = false
    }
}

struct CalibrationView: View {
    @ObservedObject var model: CalibrationModel
    @State private var dragStart: PillGeometry?

    var body: some View {
        GeometryReader { geo in
            let g = model.g
            let cx = geo.size.width / 2 + g.horizontalOffset
            let fill = model.previewBlack ? Ink.pill : Ink.coral
            ZStack(alignment: .topLeading) {
                // Dim the band a little so the pill stands out against any wallpaper.
                LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
                    .allowsHitTesting(false)

                IslandShape(radius: g.cornerRadius, ear: g.topOffset > 0 ? 0 : 6)
                    .fill(fill)
                    .frame(width: g.width, height: g.height)
                    .contentShape(Rectangle())
                    .gesture(drag { s, t in
                        var n = s; n.horizontalOffset += t.width; n.topOffset += t.height; return n
                    })
                    .onHover { inside in if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() } }
                    .position(x: cx, y: g.topOffset + g.height / 2)

                // Side handles stretch the width evenly, the bottom handle sets the height.
                Handle(vertical: true)
                    .gesture(drag { s, t in var n = s; n.width += t.width * 2; return n })
                    .position(x: cx + g.width / 2 + 9, y: g.topOffset + g.height / 2)
                Handle(vertical: true)
                    .gesture(drag { s, t in var n = s; n.width -= t.width * 2; return n })
                    .position(x: cx - g.width / 2 - 9, y: g.topOffset + g.height / 2)
                Handle(vertical: false)
                    .gesture(drag { s, t in
                        var n = s; n.height += t.height
                        if abs(s.cornerRadius - s.height / 2) < 1 { n.cornerRadius = n.height / 2 }
                        return n
                    })
                    .position(x: cx, y: g.topOffset + g.height + 9)
                // Corner knob: drag toward the corner for squarer, away for rounder.
                Circle().fill(Color.white).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .gesture(drag { s, t in var n = s; n.cornerRadius -= (t.width + t.height) / 2; return n })
                    .position(x: cx + g.width / 2 + 9, y: g.topOffset + g.height + 9)
                    .help("Corner roundness")

                hud
                    .frame(width: 460)
                    .position(x: geo.size.width / 2, y: g.topOffset + g.height + 140)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func drag(_ apply: @escaping (PillGeometry, CGSize) -> PillGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragStart == nil { dragStart = model.g }
                if let s = dragStart { model.g = apply(s, v.translation).clamped() }
            }
            .onEnded { _ in dragStart = nil }
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.firstRun ? "Welcome to Perch" : "Refit the island").eyebrow(Ink.lime)
            Text("Fit it around your camera cover")
                .font(.serif(22, .medium))
                .foregroundStyle(Ink.text)
            Text("Drag the coral pill and its handles until a thin, even sliver of coral peeks out all the way around the cover. That is exactly where the island will rest.")
                .font(.ui(12.5))
                .foregroundStyle(Ink.text2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                Readout(label: "Width", value: model.g.width)
                Readout(label: "Height", value: model.g.height)
                Readout(label: "Corners", value: model.g.cornerRadius)
                Readout(label: "From top", value: model.g.topOffset)
                Readout(label: "Sideways", value: model.g.horizontalOffset)
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.raised))

            Text("Arrows move it. Option + arrows resize. [ and ] round the corners. Hold Shift for bigger steps.")
                .font(.ui(11))
                .foregroundStyle(Ink.text3)

            HStack(spacing: 10) {
                PlainChip(title: "Reset") { model.g = .standard }
                PlainChip(title: model.previewBlack ? "Show coral" : "Preview in black") { model.previewBlack.toggle() }
                Spacer()
                if !model.firstRun { PlainChip(title: "Cancel") { model.onCancel() } }
                Button { model.onDone(model.g) } label: {
                    Text("Done").font(.ui(13, .semibold)).foregroundStyle(Ink.pill)
                        .padding(.horizontal, 18).padding(.vertical, 7)
                        .background(Capsule().fill(Ink.lime))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Ink.window))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Ink.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
    }
}

private struct Handle: View {
    let vertical: Bool
    var body: some View {
        Capsule().fill(Color.white)
            .frame(width: vertical ? 6 : 26, height: vertical ? 26 : 6)
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
            .padding(8)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set() } else { NSCursor.arrow.set() }
            }
    }
}

private struct Readout: View {
    let label: String
    let value: CGFloat
    var body: some View {
        VStack(spacing: 3) {
            Text("\(Int(value))").font(.round(16, .semibold)).monospacedDigit().foregroundStyle(Ink.text)
            Text(label).font(.ui(9.5, .medium)).foregroundStyle(Ink.text3)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PlainChip: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.ui(12, .medium)).foregroundStyle(Ink.text)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(hover ? Ink.raisedHover : Ink.raised))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
