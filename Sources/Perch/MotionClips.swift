// Motion previews: the key liquid motions drawn frame by frame with the same springs the app uses,
// so the design can be reviewed as video without a Mac. Frames go to <snapshots>/motion/<clip>/f000.png.
// All sample data here is made up.
import AppKit
import SwiftUI

@MainActor
enum MotionClips {
    static let fps = 30.0

    /// One still frame of the island with every liquid number set by hand.
    struct Stage<Content: View>: View {
        let g: PillGeometry
        let pose: LiquidPose
        var drip: CGFloat = 0
        var dripX: CGFloat = 0
        var rim: CGFloat
        var shadow: Double
        let contentSize: CGSize
        var contentOpacity: Double = 1
        var ripple: (CGPoint, CGFloat)? = nil
        @ViewBuilder var content: Content

        var body: some View {
            let clipW = pose.width + pose.bud * 2
            ZStack(alignment: .top) {
                LiquidSurface(width: pose.width, height: pose.height, radius: pose.radius, budL: pose.bud, budR: pose.bud,
                              drip: drip, dripX: dripX, ear: 4 + 3 * CGFloat(shadow), rimAlpha: rim,
                              color: Ink.pill, rim: Ink.meniscus)
                    .shadow(color: .black.opacity(0.5 * shadow), radius: 26 * shadow, x: 0, y: 14 * shadow)
                content
                    .frame(width: contentSize.width, height: contentSize.height, alignment: .top)
                    .opacity(contentOpacity)
                    .overlay {
                        if let r = ripple { RippleLayer(origin: r.0, progress: r.1, color: Ink.text) }
                    }
                    .frame(width: clipW, height: pose.height, alignment: .top)
                    .clipShape(IslandShape(radius: pose.radius, ear: 6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
    static func lerp(_ a: LiquidPose, _ b: LiquidPose, _ t: Double) -> LiquidPose {
        LiquidPose(width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t),
                   radius: lerp(a.radius, b.radius, t), bud: max(0, lerp(a.bud, b.bud, t)))
    }
    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    static func render(to root: URL, hub: Hub, model: IslandModel) {
        let prefs = Prefs.shared
        let g = prefs.geometry
        let openSize = model.openSize(g)
        let rest = LiquidPose(width: g.width, height: g.height, radius: g.cornerRadius, bud: 0)
        let opened = LiquidPose(width: openSize.width, height: openSize.height, radius: 34, bud: 0)
        let stageSize = CGSize(width: model.maxSize(g).width + 80, height: model.maxSize(g).height + 40)

        func frame<V: View>(_ clip: String, _ i: Int, height: CGFloat, time: Double? = nil, @ViewBuilder _ v: () -> V) {
            let dir = root.appendingPathComponent(clip, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let view = ScreenSlice(height: height, g: g) {
                v().frame(width: stageSize.width, height: stageSize.height)
            }
            .environment(\.liquidTime, time)
            .hub(hub, model)
            let r = ImageRenderer(content: view)
            r.scale = 1
            guard let cg = r.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                print("motion frame failed: \(clip) \(i)"); return
            }
            try? data.write(to: dir.appendingPathComponent(String(format: "f%03d.png", i)))
        }

        // 1. Opening: the drop stretches out of the notch, overshoots a little, and settles; a ripple spreads from the pointer.
        model.state = .open; model.tab = .today; model.wing = nil
        for i in 0..<36 {
            let t = Double(i) / fps
            let s = Motion.openSpring.value(t)
            frame("open", i, height: 400) {
                Stage(g: g, pose: lerp(rest, opened, s), rim: lerp(0.45, 1, clamp(s)), shadow: clamp(s), contentSize: openSize,
                      contentOpacity: clamp((t - 0.12) / 0.28),
                      ripple: (CGPoint(x: openSize.width / 2 + 70, y: 38), CGFloat(1 - pow(1 - clamp(t / 1.15), 2)))) {
                    OpenDeck(g: g)
                }
            }
        }
        print("motion: open")

        // 2. Closing: it draws back up into the notch like a drop being pulled in.
        for i in 0..<26 {
            let t = Double(i) / fps
            let s = Motion.closeSpring.value(t)
            frame("close", i, height: 400) {
                Stage(g: g, pose: lerp(opened, rest, s), rim: lerp(1, 0.45, clamp(s)), shadow: 1 - clamp(s), contentSize: openSize,
                      contentOpacity: 1 - clamp(t / 0.08)) {
                    OpenDeck(g: g)
                }
            }
        }
        print("motion: close")

        // 3. A wing buds out of the pill when music starts.
        model.state = .resting; model.wing = .music
        for i in 0..<26 {
            let t = Double(i) / fps
            let s = Motion.wingSpring.value(t)
            frame("wing-bud", i, height: 150) {
                Stage(g: g, pose: LiquidPose(width: g.width, height: g.height, radius: g.cornerRadius, bud: lerp(0, WingKind.music.width, s)),
                      rim: 0.45, shadow: 0, contentSize: CGSize(width: g.width + WingKind.music.width * 2, height: g.height),
                      contentOpacity: clamp((t - 0.08) / 0.2)) {
                    RestingWings(g: g, kind: .music)
                }
            }
        }
        print("motion: wing-bud")

        // 4. An agent finishes: wings bloom out, ink unfurls in the left wing, a bead swells, pinches off and falls.
        let done = Moment(kind: .agent, symbol: "sparkle", title: "Architect II", detail: "Updater fixed", tint: Ink.accent, level: nil)
        model.state = .moment(done)
        let mw = IslandModel.momentWidth(done)
        let dripSpring = ViscousSpring(stiffness: 90, damping: 9)
        for i in 0..<78 {
            let t = Double(i) / fps
            let s = Motion.bloomSpring.value(t)
            var drip: CGFloat = 0
            if t > 0.25 && t <= 1.5 { drip = CGFloat(dripSpring.value(t - 0.25)) }
            if t > 1.5 { let u = clamp((t - 1.5) / 0.42); drip = u >= 1 ? 0 : CGFloat(1 + 1.1 * u * u) }
            frame("agent-drip", i, height: 150, time: max(0, t - 0.1)) {
                Stage(g: g, pose: LiquidPose(width: g.width, height: g.height, radius: g.cornerRadius, bud: lerp(0, mw, s)),
                      drip: drip, dripX: -(g.width / 2 + mw * 0.42), rim: 0.45, shadow: 0,
                      contentSize: CGSize(width: g.width + mw * 2, height: g.height), contentOpacity: clamp((t - 0.1) / 0.22)) {
                    MomentWings(g: g, moment: done)
                }
            }
        }
        print("motion: agent-drip")

        // 5. Switching tabs: the new pane flows in behind a soft wave front.
        model.state = .open; model.tab = .music
        for i in 0..<22 {
            let t = Double(i) / fps
            let s = CGFloat(Motion.tabSpring.value(t))
            frame("tab-wipe", i, height: 400) {
                Stage(g: g, pose: opened, rim: 1, shadow: 1, contentSize: openSize) {
                    OpenDeck(g: g, previewWipe: (.today, s))
                }
            }
        }
        print("motion: tab-wipe")

        // 6. Volume: the level is a liquid in a tube and sloshes past where it lands.
        for i in 0..<30 {
            let t = Double(i) / fps
            let level = 0.30 + 0.42 * Motion.levelSpring.value(t)
            let m = Moment(kind: .volume, symbol: "speaker.wave.2.fill", title: "\(Int((level * 100).rounded()))", detail: nil, tint: Ink.accent, level: level)
            model.state = .moment(m)
            frame("volume", i, height: 150) {
                Stage(g: g, pose: LiquidPose(width: g.width, height: g.height, radius: g.cornerRadius, bud: IslandModel.hudWing),
                      rim: 0.45, shadow: 0, contentSize: CGSize(width: g.width + IslandModel.hudWing * 2, height: g.height)) {
                    MomentWings(g: g, moment: m)
                }
            }
        }
        print("motion: volume")

        // 7. Charging: wings bloom and the battery fills like a glass of water, then the surface goes flat.
        let charge = Moment(kind: .charging, symbol: "bolt.fill", title: "64%", detail: "Charging", tint: Ink.mint, level: 0.64)
        model.state = .moment(charge)
        for i in 0..<66 {
            let t = Double(i) / fps
            let s = Motion.bloomSpring.value(t)
            frame("charging", i, height: 150, time: max(0, t - 0.15)) {
                Stage(g: g, pose: LiquidPose(width: g.width, height: g.height, radius: g.cornerRadius, bud: lerp(0, mw, s)),
                      rim: 0.45, shadow: 0, contentSize: CGSize(width: g.width + mw * 2, height: g.height),
                      contentOpacity: clamp((t - 0.1) / 0.22)) {
                    MomentWings(g: g, moment: charge)
                }
            }
        }
        print("motion: charging")

        // 8. A new song: its color seeps into the music pane like dye.
        model.state = .open; model.tab = .music
        for i in 0..<70 {
            let t = Double(i) / fps
            frame("dye", i, height: 400, time: t) {
                Stage(g: g, pose: opened, rim: 1, shadow: 1, contentSize: openSize) { OpenDeck(g: g) }
            }
        }
        print("motion: dye")

        // 9. Spill: a hard flick down and the island spreads sideways into a workspace with the pool.
        model.tab = .today; model.spilled = true
        let spilledSize = model.openSize(g, spilled: true)
        let spilledPose = LiquidPose(width: spilledSize.width, height: spilledSize.height, radius: 34, bud: 0)
        for i in 0..<34 {
            let t = Double(i) / fps
            let s = Motion.openSpring.value(t)
            frame("spill", i, height: 400) {
                Stage(g: g, pose: lerp(opened, spilledPose, s), rim: 1, shadow: 1, contentSize: spilledSize) { OpenDeck(g: g) }
            }
        }
        model.spilled = false
        print("motion: spill")

        // 10. Pouring text in from another app: it splits into droplets, one per place it could go.
        hub.pour.offer = Droplet(kind: .text, title: "Mitochondria make ATP through oxidative phosphorylation", body: nil, url: nil, source: "Safari")
        for i in 0..<30 {
            let t = Double(i) / fps
            frame("pour-offer", i, height: 400, time: t) {
                Stage(g: g, pose: opened, rim: 1, shadow: 1, contentSize: openSize) { OpenDeck(g: g) }
            }
        }
        hub.pour.offer = nil
        print("motion: pour-offer")
        model.state = .resting; model.wing = nil; model.tab = .today
    }
}
