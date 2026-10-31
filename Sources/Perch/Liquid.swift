// Perch's one idea: it is liquid. The island is a drop of ink hanging from the top of the screen.
// It buds, stretches, pinches and drips; it never moves on its own while resting.
//
// The surface is drawn with the classic metaball trick: blur the shapes together, then cut the blur at a
// threshold so they merge like surface tension. Drawing it twice at two thresholds leaves a thin bright rim,
// the meniscus. The Canvas only redraws while something is animating, so a resting island costs nothing.
import SwiftUI
import AppKit

// MARK: Time for previews

private struct LiquidTimeKey: EnvironmentKey { static let defaultValue: Double? = nil }

extension EnvironmentValues {
    /// Preview renders set this so time-based motion (ink, waves) can be drawn at an exact moment.
    var liquidTime: Double? {
        get { self[LiquidTimeKey.self] }
        set { self[LiquidTimeKey.self] = newValue }
    }
}

/// The damped spring behind every Perch motion, solved by hand so preview frames match the app.
struct ViscousSpring {
    var stiffness: Double
    var damping: Double
    var mass: Double = 1

    var animation: Animation { .interpolatingSpring(mass: mass, stiffness: stiffness, damping: damping) }

    /// Progress from 0 to 1 (with overshoot) at time t seconds.
    func value(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        let w0 = sqrt(stiffness / mass)
        let zeta = damping / (2 * sqrt(stiffness * mass))
        if zeta < 1 {
            let wd = w0 * sqrt(1 - zeta * zeta)
            return 1 - exp(-zeta * w0 * t) * (cos(wd * t) + zeta * w0 / wd * sin(wd * t))
        }
        return 1 - exp(-w0 * t) * (1 + w0 * t)
    }
}

// MARK: The surface

struct LiquidSurface: View, Animatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var budL: CGFloat
    var budR: CGFloat
    var drip: CGFloat
    var dripX: CGFloat
    var ear: CGFloat
    var rimAlpha: CGFloat
    var color: Color
    var rim: Color
    /// Floating below the menu bar (no notch to hang from): the top is rounded too.
    var floating = false

    typealias Pair = AnimatablePair<CGFloat, CGFloat>
    var animatableData: AnimatablePair<AnimatablePair<Pair, Pair>, AnimatablePair<Pair, Pair>> {
        get {
            AnimatablePair(AnimatablePair(Pair(width, height), Pair(radius, budL)),
                           AnimatablePair(Pair(budR, drip), Pair(ear, rimAlpha)))
        }
        set {
            width = newValue.first.first.first; height = newValue.first.first.second
            radius = newValue.first.second.first; budL = newValue.first.second.second
            budR = newValue.second.first.first; drip = newValue.second.first.second
            ear = newValue.second.second.first; rimAlpha = newValue.second.second.second
        }
    }

    /// Extra room drawn above the shapes when floating, so the blur is not cut off.
    static let floatInset: CGFloat = 18

    static let blur: CGFloat = 5.5

    var body: some View {
        Canvas { ctx, size in
            ctx.drawLayer { l in
                l.addFilter(.alphaThreshold(min: 0.5, color: rim.opacity(Double(rimAlpha))))
                l.addFilter(.blur(radius: Self.blur))
                drawBlobs(&l, size)
            }
            ctx.drawLayer { l in
                l.addFilter(.alphaThreshold(min: 0.6, color: color))
                l.addFilter(.blur(radius: Self.blur))
                drawBlobs(&l, size)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawBlobs(_ c: inout GraphicsContext, _ size: CGSize) {
        let cx = size.width / 2
        // Hanging from the bezel, shapes start above the canvas so the top edge stays flat against it.
        let y0: CGFloat = floating ? Self.floatInset : -40
        let extra: CGFloat = floating ? 0 : 40
        let ink = GraphicsContext.Shading.color(.black)
        // The body.
        let top: CGFloat = floating ? Self.floatInset : 0
        let body = CGRect(x: cx - width / 2, y: y0, width: width, height: height + extra)
        c.fill(Path(roundedRect: body, cornerRadius: min(radius, height / 2) + 1, style: .continuous), with: ink)
        // Buds: slightly shorter than the body, so a soft waist forms where they meet it.
        let bh = max(0, height * 0.9)
        let overlap = min(radius, 26)
        if budL > 0.5 {
            let r = CGRect(x: cx - width / 2 - budL, y: y0, width: budL + overlap, height: bh + extra)
            c.fill(Path(roundedRect: r, cornerRadius: min(bh / 2, max(4, budL / 2)), style: .continuous), with: ink)
        }
        if budR > 0.5 {
            let r = CGRect(x: cx + width / 2 - overlap, y: y0, width: budR + overlap, height: bh + extra)
            c.fill(Path(roundedRect: r, cornerRadius: min(bh / 2, max(4, budR / 2)), style: .continuous), with: ink)
        }
        // The meniscus where the drop meets the top of the screen.
        if ear > 0, !floating {
            let total = width + budL + budR
            let left = cx - width / 2 - budL - ear * 2.2
            c.fill(Path(CGRect(x: left, y: y0, width: total + ear * 4.4, height: ear + extra)), with: ink)
        }
        // A bead that swells under the wing, pinches off and falls. It has to be fairly big to survive the threshold.
        if drip > 0.02 {
            let rd: CGFloat = 10 * min(1, drip * 1.5) * max(0, min(1, 2.1 - drip))
            // Hanging: the bead overlaps the wing so the blur pulls a neck between them. Falling: it lets go.
            let y = top + bh - 10 + min(drip, 1) * 6 + max(0, drip - 1) * 46
            let x = cx + dripX
            if rd > 0.3 { c.fill(Path(ellipseIn: CGRect(x: x - rd, y: y - rd, width: rd * 2, height: rd * 2.2)), with: ink) }
        }
    }
}

// MARK: Ink in water

/// Ink dropped into water: clouds unfurl from a point and thin out. Draws for about 2.6 seconds, then holds.
struct InkBloom: View {
    let color: Color
    var size: CGFloat = 30
    @Environment(\.liquidTime) private var fixedTime
    @State private var start = Date()
    @State private var settled = false

    static let length = 2.6

    var body: some View {
        Group {
            if let t = fixedTime ?? (RenderMode.snapshot ? 1.1 : nil) {
                InkCloud(color: color, t: t, size: size)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: settled)) { ctx in
                    InkCloud(color: color, t: min(Self.length, ctx.date.timeIntervalSince(start)), size: size)
                }
                .task {
                    try? await Task.sleep(nanoseconds: UInt64(Self.length * 1_000_000_000))
                    settled = true
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct InkCloud: View {
    let color: Color
    let t: Double
    let size: CGFloat

    // Fixed, hand-picked puffs so every bloom looks alike and nothing random flickers.
    private static let puffs: [(angle: Double, reach: Double, r: Double, delay: Double)] = [
        (0.2, 0.62, 0.30, 0.00), (1.3, 0.55, 0.26, 0.10), (2.3, 0.70, 0.22, 0.05), (3.1, 0.48, 0.28, 0.16),
        (4.0, 0.66, 0.24, 0.08), (5.0, 0.58, 0.27, 0.13), (5.8, 0.40, 0.20, 0.20),
    ]

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let half = Double(min(sz.width, sz.height)) / 2
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: size * 0.07))
                for p in Self.puffs {
                    let local = max(0, t - p.delay)
                    let grow = 1 - exp(-local * 1.4)
                    let swirl = p.angle + grow * 0.5
                    let d = half * p.reach * 1.2 * grow
                    let r = half * p.r * (0.4 + grow * 0.9)
                    let alpha = pow(1 - grow, 0.8) * min(1, local * 6)
                    let pt = CGPoint(x: c.x + CGFloat(cos(swirl) * d), y: c.y + CGFloat(sin(swirl) * d))
                    l.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                             with: .color(color.opacity(alpha * 0.85)))
                }
            }
            // What is left once the ink has spread: one clean dot.
            let core = half * (0.34 - 0.08 * min(1, t / 1.2))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core, width: core * 2, height: core * 2)), with: .color(color))
        }
    }
}

// MARK: Dye

/// The album color diffusing into the island like dye into water. `progress` runs 0 to 1 when the track changes.
struct DyeLayer: View, Animatable {
    var color: Color
    var progress: CGFloat
    var strength: Double

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                cloud(at: CGPoint(x: w * 0.16, y: h * 0.58), radius: w * 0.42 * ease(progress), a: 1)
                cloud(at: CGPoint(x: w * 0.34, y: h * 0.86), radius: w * 0.30 * ease(max(0, progress - 0.15) / 0.85), a: 0.7)
                cloud(at: CGPoint(x: w * 0.05, y: h * 0.20), radius: w * 0.26 * ease(max(0, progress - 0.3) / 0.7), a: 0.55)
            }
        }
        .allowsHitTesting(false)
    }

    private func ease(_ x: CGFloat) -> CGFloat { 1 - pow(1 - min(max(x, 0), 1), 2.2) }

    private func cloud(at p: CGPoint, radius: CGFloat, a: Double) -> some View {
        RadialGradient(colors: [color.opacity(strength * a), color.opacity(strength * a * 0.35), .clear],
                       center: .center, startRadius: 0, endRadius: max(1, radius))
            .frame(width: max(2, radius * 2), height: max(2, radius * 2))
            .position(p)
    }
}

// MARK: Ripples

/// Rings spreading from where you touched the island.
struct RippleLayer: View, Animatable {
    var origin: CGPoint
    var progress: CGFloat
    var color: Color

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, _ in
            guard progress > 0.001, progress < 0.999 else { return }
            for (i, lag) in [0.0, 0.18, 0.34].enumerated() {
                let p = max(0, (Double(progress) - lag) / (1 - lag))
                guard p > 0 else { continue }
                let r = CGFloat(10 + p * 230)
                let alpha = (1 - p) * (i == 0 ? 0.15 : 0.08)
                ctx.stroke(Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r * 0.82, width: r * 2, height: r * 1.64)),
                           with: .color(color.opacity(alpha)), lineWidth: CGFloat(1.3 - p * 0.6))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: Liquid level

/// A tube of liquid for volume and brightness. The front edge bulges like a meniscus and sloshes when it moves.
struct LiquidLevel: View {
    let level: Double
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.text.opacity(0.10))
                LiquidFront(level: CGFloat(min(max(level, 0), 1)))
                    .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom))
                    .clipShape(Capsule())
                Capsule().stroke(Ink.text.opacity(0.06), lineWidth: 1)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 7)
        .animation(Motion.viscous, value: level)
    }
}

struct LiquidFront: Shape {
    var level: CGFloat
    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }
    func path(in r: CGRect) -> Path {
        let x = r.minX + r.width * level
        let bulge = min(3.5, r.width * level)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: x - bulge, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: x - bulge, y: r.maxY), control: CGPoint(x: x + bulge, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Liquid rising inside a small tank (the battery), with a gentle wave on top while it fills.
struct WaveFill: Shape {
    var level: CGFloat
    var phase: CGFloat
    var amplitude: CGFloat
    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }
    func path(in r: CGRect) -> Path {
        let top = r.maxY - r.height * min(max(level, 0), 1)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: top))
        let steps = 24
        for i in 0...steps {
            let f = CGFloat(i) / CGFloat(steps)
            let x = r.minX + r.width * f
            p.addLine(to: CGPoint(x: x, y: top + sin(f * .pi * 2.4 + phase) * amplitude))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: Tab wipe

/// New tabs flow in from the left behind a soft wave front.
struct LiquidWipe: ViewModifier, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.mask(WaveEdge(progress: progress))
    }
}

struct WaveEdge: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in r: CGRect) -> Path {
        if progress >= 0.999 { return Path(r.insetBy(dx: -40, dy: -40)) }
        let amp: CGFloat = 14
        let edge = r.minX - amp * 2 + (r.width + amp * 4) * progress
        var p = Path()
        p.move(to: CGPoint(x: r.minX - 40, y: r.minY - 40))
        p.addLine(to: CGPoint(x: edge, y: r.minY - 40))
        let steps = 28
        for i in 0...steps {
            let f = CGFloat(i) / CGFloat(steps)
            let y = r.minY + r.height * f
            p.addLine(to: CGPoint(x: edge + sin(f * .pi * 1.6 + progress * 4) * amp, y: y))
        }
        p.addLine(to: CGPoint(x: edge, y: r.maxY + 40))
        p.addLine(to: CGPoint(x: r.minX - 40, y: r.maxY + 40))
        p.closeSubpath()
        return p
    }
}

extension AnyTransition {
    static var liquidWipe: AnyTransition {
        .asymmetric(insertion: .modifier(active: LiquidWipe(progress: 0), identity: LiquidWipe(progress: 1)),
                    removal: .opacity.animation(.easeIn(duration: 0.12)))
    }
}

// MARK: Sounds

/// Water sounds, synthesized for Perch (scripts/make_sounds.py). Soft, and optional.
enum WaterSound: String {
    case drop, sink, plip, fill

    private static var cache: [String: NSSound] = [:]

    static func play(_ s: WaterSound, volume: Float = 0.5) {
        let sound: NSSound? = cache[s.rawValue] ?? {
            guard let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav", subdirectory: "Sounds") else { return nil }
            let n = NSSound(contentsOf: url, byReference: true)
            cache[s.rawValue] = n
            return n
        }()
        guard let sound else { return }
        sound.stop()
        sound.volume = volume
        sound.play()
    }
}

/// Whether to draw the liquid surface or the plain shape (Low Power Mode, or turned off in Settings).
@MainActor
enum LiquidMode {
    static var enabled: Bool {
        Prefs.shared.liquidSurface && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
