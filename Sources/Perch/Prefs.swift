// Everything Perch remembers, kept in UserDefaults.
import AppKit
import Combine

/// The resting island, measured in points from the top centre of the built-in screen.
struct PillGeometry: Codable, Equatable {
    var width: CGFloat = 212
    var height: CGFloat = 60
    var cornerRadius: CGFloat = 30
    /// Gap between the very top of the screen and the top of the island. 0 means it hangs from the bezel.
    var topOffset: CGFloat = 0
    /// Sideways shift, for a cover that is not stuck perfectly in the middle.
    var horizontalOffset: CGFloat = 0

    static let standard = PillGeometry()

    static let widthRange: ClosedRange<CGFloat> = 80...420
    static let heightRange: ClosedRange<CGFloat> = 20...140
    static let topRange: ClosedRange<CGFloat> = 0...60
    static let sideRange: ClosedRange<CGFloat> = -200...200

    func clamped() -> PillGeometry {
        var g = self
        g.width = min(max(g.width, Self.widthRange.lowerBound), Self.widthRange.upperBound).rounded()
        g.height = min(max(g.height, Self.heightRange.lowerBound), Self.heightRange.upperBound).rounded()
        g.cornerRadius = min(max(g.cornerRadius, 0), g.height / 2).rounded()
        g.topOffset = min(max(g.topOffset, Self.topRange.lowerBound), Self.topRange.upperBound).rounded()
        g.horizontalOffset = min(max(g.horizontalOffset, Self.sideRange.lowerBound), Self.sideRange.upperBound).rounded()
        return g
    }
}

@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var geometry: PillGeometry { didSet { saveGeometry() } }
    @Published var hasCalibrated: Bool { didSet { d.set(hasCalibrated, forKey: "hasCalibrated") } }
    @Published var openOnHover: Bool { didSet { d.set(openOnHover, forKey: "openOnHover") } }
    @Published var hoverDelay: Double { didSet { d.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var showWings: Bool { didSet { d.set(showWings, forKey: "showWings") } }
    @Published var chimeOnFinish: Bool { didSet { d.set(chimeOnFinish, forKey: "chimeOnFinish") } }
    @Published var useArtworkColor: Bool { didSet { d.set(useArtworkColor, forKey: "useArtworkColor") } }
    @Published var lastTab: String { didSet { d.set(lastTab, forKey: "lastTab") } }
    /// Optional overrides for the agent board. Empty means "use the one built into the app".
    @Published var boardURLOverride: String { didSet { d.set(boardURLOverride, forKey: "boardURLOverride") } }
    @Published var boardKeyOverride: String { didSet { d.set(boardKeyOverride, forKey: "boardKeyOverride") } }

    private init() {
        d.register(defaults: [
            "openOnHover": true, "hoverDelay": 0.12, "showWings": true, "chimeOnFinish": true,
            "useArtworkColor": true, "lastTab": "playing",
        ])
        if let data = d.data(forKey: "geometry.builtin"), let g = try? JSONDecoder().decode(PillGeometry.self, from: data) {
            geometry = g.clamped()
        } else {
            geometry = .standard
        }
        hasCalibrated = d.bool(forKey: "hasCalibrated")
        openOnHover = d.bool(forKey: "openOnHover")
        hoverDelay = d.double(forKey: "hoverDelay")
        showWings = d.bool(forKey: "showWings")
        chimeOnFinish = d.bool(forKey: "chimeOnFinish")
        useArtworkColor = d.bool(forKey: "useArtworkColor")
        lastTab = d.string(forKey: "lastTab") ?? "playing"
        boardURLOverride = d.string(forKey: "boardURLOverride") ?? ""
        boardKeyOverride = d.string(forKey: "boardKeyOverride") ?? ""
    }

    private func saveGeometry() {
        if let data = try? JSONEncoder().encode(geometry) { d.set(data, forKey: "geometry.builtin") }
    }

    var boardURL: String {
        let o = boardURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !o.isEmpty { return o }
        return (Bundle.main.object(forInfoDictionaryKey: "PerchBoardURL") as? String) ?? ""
    }

    var boardKey: String {
        let o = boardKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !o.isEmpty { return o }
        return (Bundle.main.object(forInfoDictionaryKey: "PerchBoardReadKey") as? String) ?? ""
    }

    static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }
}
