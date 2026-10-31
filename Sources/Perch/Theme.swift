// Colors, type and motion, all from one idea: ink in water. Sumi ink with a blue undertone, deep water,
// or washi paper with ink on it, and one bright note of dye: the lime of the camera cover or the album art.
import SwiftUI
import AppKit

enum ThemeName: String, CaseIterable, Identifiable {
    case ink, graphite, paper
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ink: return "Sumi ink"
        case .graphite: return "Deep water"
        case .paper: return "Washi paper"
        }
    }
}

enum AccentMode: String, CaseIterable, Identifiable {
    case art, lime, coral, sky, lilac
    var id: String { rawValue }
    var title: String {
        switch self {
        case .art: return "Dye from album art"
        case .lime: return "Cover lime"
        case .coral: return "Koi"
        case .sky: return "Tide"
        case .lilac: return "Indigo"
        }
    }
    var fixed: Color {
        switch self {
        case .art, .lime: return Color(red: 0.80, green: 0.94, blue: 0.27)
        case .coral: return Color(red: 1.0, green: 0.50, blue: 0.40)
        case .sky: return Color(red: 0.36, green: 0.80, blue: 0.92)
        case .lilac: return Color(red: 0.55, green: 0.60, blue: 1.0)
        }
    }
}

struct Palette {
    var pill: Color
    var raised: Color
    var raisedHover: Color
    var hairline: Color
    var text: Color
    var text2: Color
    var text3: Color
    var window: Color
    var card: Color
    var isLight: Bool

    /// Sumi ink: almost black, with the blue that real ink has where it pools.
    static let ink = Palette(pill: Color(red: 0.018, green: 0.022, blue: 0.034),
                             raised: Color(red: 0.62, green: 0.72, blue: 1.0).opacity(0.06),
                             raisedHover: Color(red: 0.62, green: 0.72, blue: 1.0).opacity(0.11),
                             hairline: Color(red: 0.70, green: 0.80, blue: 1.0).opacity(0.09),
                             text: Color(red: 0.95, green: 0.96, blue: 0.98),
                             text2: Color(red: 0.86, green: 0.89, blue: 0.96).opacity(0.62),
                             text3: Color(red: 0.80, green: 0.85, blue: 0.96).opacity(0.38),
                             window: Color(red: 0.050, green: 0.058, blue: 0.078),
                             card: Color(red: 0.082, green: 0.094, blue: 0.122), isLight: false)
    /// Deep water: dark teal navy, like looking down into a lake.
    static let graphite = Palette(pill: Color(red: 0.030, green: 0.082, blue: 0.106),
                                  raised: Color(red: 0.55, green: 0.90, blue: 1.0).opacity(0.07),
                                  raisedHover: Color(red: 0.55, green: 0.90, blue: 1.0).opacity(0.12),
                                  hairline: Color(red: 0.60, green: 0.92, blue: 1.0).opacity(0.10),
                                  text: Color(red: 0.93, green: 0.98, blue: 0.99),
                                  text2: Color(red: 0.80, green: 0.93, blue: 0.96).opacity(0.64),
                                  text3: Color(red: 0.72, green: 0.90, blue: 0.95).opacity(0.40),
                                  window: Color(red: 0.045, green: 0.095, blue: 0.118),
                                  card: Color(red: 0.070, green: 0.135, blue: 0.165), isLight: false)
    /// Washi paper: warm and soft, with text the color of dried ink.
    static let paper = Palette(pill: Color(red: 0.958, green: 0.938, blue: 0.898),
                               raised: Color(red: 0.10, green: 0.12, blue: 0.20).opacity(0.05),
                               raisedHover: Color(red: 0.10, green: 0.12, blue: 0.20).opacity(0.09),
                               hairline: Color(red: 0.10, green: 0.12, blue: 0.20).opacity(0.09),
                               text: Color(red: 0.075, green: 0.085, blue: 0.12),
                               text2: Color(red: 0.075, green: 0.085, blue: 0.12).opacity(0.62),
                               text3: Color(red: 0.075, green: 0.085, blue: 0.12).opacity(0.40),
                               window: Color(red: 0.945, green: 0.925, blue: 0.885),
                               card: Color(red: 0.99, green: 0.982, blue: 0.962), isLight: true)

    /// The thin bright edge of the drop, where light catches the surface.
    var meniscus: Color {
        isLight ? Color.white.opacity(0.95) : Color(red: 0.62, green: 0.74, blue: 1.0).opacity(0.30)
    }

    static func named(_ n: ThemeName) -> Palette {
        switch n {
        case .ink: return .ink
        case .graphite: return .graphite
        case .paper: return .paper
        }
    }
}

/// The current look. Views read these; the root view re-renders everything when the theme changes.
enum Ink {
    static var palette = Palette.ink
    static var accent = Color(red: 0.80, green: 0.94, blue: 0.27)

    static var pill: Color { palette.pill }
    static var raised: Color { palette.raised }
    static var raisedHover: Color { palette.raisedHover }
    static var hairline: Color { palette.hairline }
    static var text: Color { palette.text }
    static var text2: Color { palette.text2 }
    static var text3: Color { palette.text3 }
    static var window: Color { palette.window }
    static var card: Color { palette.card }
    /// Text on top of an accent-filled button.
    static var onAccent: Color { Color(red: 0.03, green: 0.03, blue: 0.035) }

    static let lime = Color(red: 0.80, green: 0.94, blue: 0.27)
    static let coral = Color(red: 1.0, green: 0.46, blue: 0.38)
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.25)
    static let mint = Color(red: 0.40, green: 0.88, blue: 0.62)
    static let sky = Color(red: 0.36, green: 0.80, blue: 0.92)
    static var meniscus: Color { palette.meniscus }
    static var quiet: Color { palette.text3 }
    static let limeNS = NSColor(red: 0.80, green: 0.94, blue: 0.27, alpha: 1)
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func round(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    /// New York, for what you wrote yourself and for quiet empty states.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension View {
    func eyebrow(_ color: Color? = nil) -> some View {
        self.font(.ui(9.5, .semibold)).tracking(1.4).textCase(.uppercase).foregroundStyle(color ?? Ink.text3)
    }

    /// A soft card used across the deck.
    func card(_ radius: CGFloat = 14, padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Ink.raised))
    }
}

/// Preview PNGs are drawn with ImageRenderer, which cannot draw AppKit-backed controls or scroll views.
enum RenderMode {
    static var snapshot = false
}

/// Viscous springs: heavier than the usual UI spring, so things flow, overshoot a little, and settle like a liquid.
enum Motion {
    static let openSpring = ViscousSpring(stiffness: 150, damping: 17.5)
    static let closeSpring = ViscousSpring(stiffness: 210, damping: 27)
    static let wingSpring = ViscousSpring(stiffness: 170, damping: 15.5)
    static let bloomSpring = ViscousSpring(stiffness: 160, damping: 15)
    static let tabSpring = ViscousSpring(stiffness: 230, damping: 27)
    static let levelSpring = ViscousSpring(stiffness: 120, damping: 15)

    static let open = openSpring.animation
    static let close = closeSpring.animation
    static let wing = wingSpring.animation
    static let bloom = bloomSpring.animation
    static let tab = tabSpring.animation
    static let viscous = levelSpring.animation
    static let snap = Animation.spring(response: 0.25, dampingFraction: 0.8)
}

/// A light tap on the trackpad as the island opens, the way a real button would click.
enum Haptics {
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    static func level() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

/// "just now", "4m", "2h", "3d".
func shortAge(_ seconds: TimeInterval) -> String {
    let s = max(0, seconds)
    if s < 45 { return "just now" }
    if s < 3600 { return "\(Int((s / 60).rounded()))m" }
    if s < 86400 { return "\(Int(s / 3600))h" }
    return "\(Int(s / 86400))d"
}

/// "12:04" or "1:02:09".
func clock(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let t = Int(seconds.rounded(.down))
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
                     : String(format: "%d:%02d", t / 60, t % 60)
}

/// "in 8m", "in 1h 20m", "now".
func untilText(_ seconds: TimeInterval) -> String {
    if seconds <= 30 { return "now" }
    let m = Int((seconds / 60).rounded(.up))
    if m < 60 { return "in \(m)m" }
    let h = m / 60, r = m % 60
    return r == 0 ? "in \(h)h" : "in \(h)h \(r)m"
}

/// A stable, pleasant color for a name (agent avatars, class tags).
enum NameColor {
    static let palette: [Color] = [
        Color(red: 0.80, green: 0.94, blue: 0.27), Color(red: 1.0, green: 0.56, blue: 0.43),
        Color(red: 0.45, green: 0.75, blue: 1.0), Color(red: 0.74, green: 0.62, blue: 1.0),
        Color(red: 1.0, green: 0.78, blue: 0.32), Color(red: 0.40, green: 0.88, blue: 0.70),
        Color(red: 1.0, green: 0.55, blue: 0.75), Color(red: 0.62, green: 0.85, blue: 0.95),
    ]
    static func of(_ name: String) -> Color {
        var h: UInt64 = 1469598103934665603
        for b in name.lowercased().utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return palette[Int(h % UInt64(palette.count))]
    }
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
        let letters = words.prefix(2).compactMap { $0.first.map(String.init) }
        let numerals = ["II": "2", "III": "3", "IV": "4", "V": "5", "VI": "6"]
        if words.count > 1, let first = words.first?.first, let n = words.last.flatMap({ numerals[String($0)] }) {
            return String(first).uppercased() + n
        }
        return letters.joined().uppercased()
    }
}
