// Everything Perch remembers, kept in UserDefaults. Secrets (Gmail tokens) live in the Keychain instead.
import AppKit
import Combine
import SwiftUI

/// The resting island, measured in points from the top centre of the built-in screen.
struct PillGeometry: Codable, Equatable {
    var width: CGFloat = 212
    var height: CGFloat = 60
    var cornerRadius: CGFloat = 30
    var topOffset: CGFloat = 0
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

enum HomeCard: String, CaseIterable, Identifiable {
    case music, calendar, timer, weather, agents, tasks, mail
    var id: String { rawValue }
    var title: String {
        switch self {
        case .music: return "Now playing"
        case .calendar: return "Up next"
        case .timer: return "Timer"
        case .weather: return "Weather"
        case .agents: return "Agents"
        case .tasks: return "Due soon"
        case .mail: return "Mail"
        }
    }
}

enum ShortcutPreset: String, CaseIterable, Identifiable {
    case off, ctrlOptSpace, cmdShiftSpace, ctrlOptP
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "None"
        case .ctrlOptSpace: return "Control Option Space"
        case .cmdShiftSpace: return "Command Shift Space"
        case .ctrlOptP: return "Control Option P"
        }
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
    @Published var swipeToOpen: Bool { didSet { d.set(swipeToOpen, forKey: "swipeToOpen") } }
    @Published var showWings: Bool { didSet { d.set(showWings, forKey: "showWings") } }
    @Published var chimeOnFinish: Bool { didSet { d.set(chimeOnFinish, forKey: "chimeOnFinish") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    @Published var liquidSurface: Bool { didSet { d.set(liquidSurface, forKey: "liquidSurface") } }
    @Published var waterSounds: Bool { didSet { d.set(waterSounds, forKey: "waterSounds") } }
    @Published var pourHintSeen: Bool { didSet { d.set(pourHintSeen, forKey: "pourHintSeen") } }
    @Published var theme: ThemeName { didSet { d.set(theme.rawValue, forKey: "theme"); applyLook() } }
    @Published var accentMode: AccentMode { didSet { d.set(accentMode.rawValue, forKey: "accentMode"); applyLook() } }
    @Published var lastTab: String { didSet { d.set(lastTab, forKey: "lastTab") } }
    @Published var hiddenTabs: Set<String> { didSet { d.set(Array(hiddenTabs), forKey: "hiddenTabs") } }
    @Published var hiddenCards: Set<String> { didSet { d.set(Array(hiddenCards), forKey: "hiddenCards") } }
    @Published var shortcut: ShortcutPreset { didSet { d.set(shortcut.rawValue, forKey: "shortcut") } }

    // Moments and integrations. Anything that needs a macOS permission starts off.
    @Published var volumeHUD: Bool { didSet { d.set(volumeHUD, forKey: "volumeHUD") } }
    @Published var replaceSystemHUD: Bool { didSet { d.set(replaceSystemHUD, forKey: "replaceSystemHUD") } }
    @Published var chargingMoment: Bool { didSet { d.set(chargingMoment, forKey: "chargingMoment") } }
    @Published var deviceMoments: Bool { didSet { d.set(deviceMoments, forKey: "deviceMoments") } }
    @Published var privacyDots: Bool { didSet { d.set(privacyDots, forKey: "privacyDots") } }
    @Published var calendarOn: Bool { didSet { d.set(calendarOn, forKey: "calendarOn") } }
    @Published var clipboardOn: Bool { didSet { d.set(clipboardOn, forKey: "clipboardOn") } }
    @Published var lyricsOn: Bool { didSet { d.set(lyricsOn, forKey: "lyricsOn") } }
    @Published var weatherCity: String { didSet { d.set(weatherCity, forKey: "weatherCity") } }
    @Published var weatherLat: Double { didSet { d.set(weatherLat, forKey: "weatherLat") } }
    @Published var weatherLon: Double { didSet { d.set(weatherLon, forKey: "weatherLon") } }
    @Published var fahrenheit: Bool { didSet { d.set(fahrenheit, forKey: "fahrenheit") } }
    @Published var pomodoroWork: Double { didSet { d.set(pomodoroWork, forKey: "pomodoroWork") } }
    @Published var pomodoroBreak: Double { didSet { d.set(pomodoroBreak, forKey: "pomodoroBreak") } }

    @Published var boardURLOverride: String { didSet { d.set(boardURLOverride, forKey: "boardURLOverride") } }
    @Published var boardKeyOverride: String { didSet { d.set(boardKeyOverride, forKey: "boardKeyOverride") } }

    private init() {
        d.register(defaults: [
            "openOnHover": true, "hoverDelay": 0.12, "swipeToOpen": true, "showWings": true, "chimeOnFinish": true,
            "haptics": true, "liquidSurface": true, "waterSounds": false, "pourHintSeen": false, "theme": "ink", "accentMode": "art", "lastTab": "today", "shortcut": "ctrlOptSpace",
            "volumeHUD": true, "replaceSystemHUD": false, "chargingMoment": true, "deviceMoments": false,
            "privacyDots": true, "calendarOn": false, "clipboardOn": true, "lyricsOn": true,
            "weatherCity": "Shreveport", "weatherLat": 32.5252, "weatherLon": -93.7502, "fahrenheit": true,
            "pomodoroWork": 25.0, "pomodoroBreak": 5.0,
        ])
        if let data = d.data(forKey: "geometry.builtin"), let g = try? JSONDecoder().decode(PillGeometry.self, from: data) {
            geometry = g.clamped()
        } else {
            geometry = .standard
        }
        hasCalibrated = d.bool(forKey: "hasCalibrated")
        openOnHover = d.bool(forKey: "openOnHover")
        hoverDelay = d.double(forKey: "hoverDelay")
        swipeToOpen = d.bool(forKey: "swipeToOpen")
        showWings = d.bool(forKey: "showWings")
        chimeOnFinish = d.bool(forKey: "chimeOnFinish")
        haptics = d.bool(forKey: "haptics")
        liquidSurface = d.bool(forKey: "liquidSurface")
        waterSounds = d.bool(forKey: "waterSounds")
        pourHintSeen = d.bool(forKey: "pourHintSeen")
        theme = ThemeName(rawValue: d.string(forKey: "theme") ?? "") ?? .ink
        accentMode = AccentMode(rawValue: d.string(forKey: "accentMode") ?? "") ?? .art
        lastTab = d.string(forKey: "lastTab") ?? "today"
        hiddenTabs = Set(d.stringArray(forKey: "hiddenTabs") ?? [])
        hiddenCards = Set(d.stringArray(forKey: "hiddenCards") ?? [])
        shortcut = ShortcutPreset(rawValue: d.string(forKey: "shortcut") ?? "") ?? .ctrlOptSpace
        volumeHUD = d.bool(forKey: "volumeHUD")
        replaceSystemHUD = d.bool(forKey: "replaceSystemHUD")
        chargingMoment = d.bool(forKey: "chargingMoment")
        deviceMoments = d.bool(forKey: "deviceMoments")
        privacyDots = d.bool(forKey: "privacyDots")
        calendarOn = d.bool(forKey: "calendarOn")
        clipboardOn = d.bool(forKey: "clipboardOn")
        lyricsOn = d.bool(forKey: "lyricsOn")
        weatherCity = d.string(forKey: "weatherCity") ?? "Shreveport"
        weatherLat = d.double(forKey: "weatherLat")
        weatherLon = d.double(forKey: "weatherLon")
        fahrenheit = d.bool(forKey: "fahrenheit")
        pomodoroWork = d.double(forKey: "pomodoroWork")
        pomodoroBreak = d.double(forKey: "pomodoroBreak")
        boardURLOverride = d.string(forKey: "boardURLOverride") ?? ""
        boardKeyOverride = d.string(forKey: "boardKeyOverride") ?? ""
        applyLook()
    }

    private func saveGeometry() {
        if let data = try? JSONEncoder().encode(geometry) { d.set(data, forKey: "geometry.builtin") }
    }

    /// The accent when no album art color applies.
    var fixedAccent: Color { accentMode.fixed }

    func applyLook() {
        Ink.palette = Palette.named(theme)
        if accentMode != .art { Ink.accent = accentMode.fixed }
        objectWillChange.send()
    }

    func isTabShown(_ t: String) -> Bool { !hiddenTabs.contains(t) }
    func isCardShown(_ c: HomeCard) -> Bool { !hiddenCards.contains(c.rawValue) }

    func toggleTab(_ t: String) {
        if hiddenTabs.contains(t) { hiddenTabs.remove(t) } else { hiddenTabs.insert(t) }
    }
    func toggleCard(_ c: HomeCard) {
        if hiddenCards.contains(c.rawValue) { hiddenCards.remove(c.rawValue) } else { hiddenCards.insert(c.rawValue) }
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
