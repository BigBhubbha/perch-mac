// Colors and type. Perch is ink black with one bright note: the lime of Shabd's camera cover.
import SwiftUI
import AppKit

enum Ink {
    static let pill = Color(red: 0.027, green: 0.027, blue: 0.031)
    static let raised = Color.white.opacity(0.055)
    static let raisedHover = Color.white.opacity(0.10)
    static let hairline = Color.white.opacity(0.08)
    static let text = Color.white.opacity(0.94)
    static let text2 = Color.white.opacity(0.60)
    static let text3 = Color.white.opacity(0.36)
    /// Sampled from the cover in Shabd's photo, nudged a touch so it glows on black.
    static let lime = Color(red: 0.80, green: 0.94, blue: 0.27)
    static let coral = Color(red: 1.0, green: 0.46, blue: 0.38)
    static let quiet = Color.white.opacity(0.28)
    static let window = Color(red: 0.067, green: 0.067, blue: 0.075)
    static let card = Color(red: 0.10, green: 0.10, blue: 0.11)

    static let limeNS = NSColor(red: 0.80, green: 0.94, blue: 0.27, alpha: 1)
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func round(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    /// New York, for the notes, so they read like your own handwriting rather than an interface.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension View {
    /// Small caps style label used for section names.
    func eyebrow(_ color: Color = Ink.text3) -> some View {
        self.font(.ui(9.5, .semibold)).tracking(1.4).textCase(.uppercase).foregroundStyle(color)
    }
}

/// Set when rendering preview PNGs: text editors and sliders are swapped for plain drawings,
/// because SwiftUI's ImageRenderer cannot draw AppKit-backed controls.
enum RenderMode {
    static var snapshot = false
}

enum Motion {
    static let open = Animation.spring(response: 0.40, dampingFraction: 0.80)
    static let close = Animation.spring(response: 0.36, dampingFraction: 0.95)
    static let wing = Animation.spring(response: 0.45, dampingFraction: 0.78)
    static let bloom = Animation.spring(response: 0.50, dampingFraction: 0.68)
}

/// "just now", "4m", "2h", "3d".
func shortAge(_ seconds: TimeInterval) -> String {
    let s = max(0, seconds)
    if s < 45 { return "just now" }
    if s < 3600 { return "\(Int((s / 60).rounded()))m" }
    if s < 86400 { return "\(Int(s / 3600))h" }
    return "\(Int(s / 86400))d"
}

func clock(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let t = Int(seconds.rounded(.down))
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
                     : String(format: "%d:%02d", t / 60, t % 60)
}
