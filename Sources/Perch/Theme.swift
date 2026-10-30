// Colors, type and motion. Ink black with one bright note, the lime of the camera cover,
// or a color lifted from the album art. Three themes: Ink, Graphite and Paper.
import SwiftUI
import AppKit

enum ThemeName: String, CaseIterable, Identifiable {
    case ink, graphite, paper
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ink: return "Ink"
        case .graphite: return "Graphite"
        case .paper: return "Paper"
        }
    }
}

enum AccentMode: String, CaseIterable, Identifiable {
    case art, lime, coral, sky, lilac
    var id: String { rawValue }
    var title: String {
        switch self {
        case .art: return "From album art"
        case .lime: return "Cover lime"
        case .coral: return "Coral"
        case .sky: return "Sky"
        case .lilac: return "Lilac"
        }
    }
    var fixed: Color {
        switch self {
        case .art, .lime: return Color(red: 0.80, green: 0.94, blue: 0.27)
        case .coral: return Color(red: 1.0, green: 0.52, blue: 0.42)
        case .sky: return Color(red: 0.45, green: 0.75, blue: 1.0)
        case .lilac: return Color(red: 0.74, green: 0.62, blue: 1.0)
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

    static let ink = Palette(pill: Color(red: 0.027, green: 0.027, blue: 0.031),
                             raised: Color.white.opacity(0.055), raisedHover: Color.white.opacity(0.10),
                             hairline: Color.white.opacity(0.08), text: Color.white.opacity(0.94),
                             text2: Color.white.opacity(0.60), text3: Color.white.opacity(0.36),
                             window: Color(red: 0.067, green: 0.067, blue: 0.075),
                             card: Color(red: 0.10, green: 0.10, blue: 0.11), isLight: false)
    static let graphite = Palette(pill: Color(red: 0.13, green: 0.13, blue: 0.145),
                                  raised: Color.white.opacity(0.07), raisedHover: Color.white.opacity(0.12),
                                  hairline: Color.white.opacity(0.09), text: Color.white.opacity(0.95),
                                  text2: Color.white.opacity(0.64), text3: Color.white.opacity(0.40),
                                  window: Color(red: 0.11, green: 0.11, blue: 0.12),
                                  card: Color(red: 0.16, green: 0.16, blue: 0.175), isLight: false)
    static let paper = Palette(pill: Color(red: 0.965, green: 0.945, blue: 0.905),
                               raised: Color.black.opacity(0.05), raisedHover: Color.black.opacity(0.09),
                               hairline: Color.black.opacity(0.08), text: Color(red: 0.11, green: 0.10, blue: 0.09),
                               text2: Color(red: 0.11, green: 0.10, blue: 0.09).opacity(0.62),
                               text3: Color(red: 0.11, green: 0.10, blue: 0.09).opacity(0.40),
                               window: Color(red: 0.95, green: 0.93, blue: 0.89),
                               card: Color(red: 0.99, green: 0.98, blue: 0.96), isLight: true)

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
    static let sky = Color(red: 0.45, green: 0.75, blue: 1.0)
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

enum Motion {
    static let open = Animation.spring(response: 0.40, dampingFraction: 0.80)
    static let close = Animation.spring(response: 0.36, dampingFraction: 0.95)
    static let wing = Animation.spring(response: 0.45, dampingFraction: 0.82)
    static let bloom = Animation.spring(response: 0.50, dampingFraction: 0.70)
    static let tab = Animation.spring(response: 0.32, dampingFraction: 0.86)
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
