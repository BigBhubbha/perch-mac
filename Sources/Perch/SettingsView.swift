// Settings: a sidebar of sections. Everything here changes the island right away.
import SwiftUI
import AppKit
import CoreBluetooth
import EventKit
import Combine

enum SettingsPage: String, CaseIterable, Identifiable {
    case island, look, moments, extras, mail, agents, permissions, updates
    var id: String { rawValue }
    var title: String {
        switch self {
        case .island: return "Island"
        case .look: return "Look"
        case .moments: return "Moments"
        case .extras: return "Music and more"
        case .mail: return "Mail"
        case .agents: return "Agents"
        case .permissions: return "Permissions"
        case .updates: return "Updates"
        }
    }
    var symbol: String {
        switch self {
        case .island: return "capsule.fill"
        case .look: return "paintpalette.fill"
        case .moments: return "sparkles"
        case .extras: return "music.note"
        case .mail: return "envelope.fill"
        case .agents: return "person.2.fill"
        case .permissions: return "hand.raised.fill"
        case .updates: return "arrow.down.circle.fill"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var prefs: Prefs
    var refit: () -> Void
    var checkForUpdates: () -> Void
    var autoUpdates: Binding<Bool>
    var height: CGFloat = SettingsView.size.height
    @State var page: SettingsPage = .island

    static let size = NSSize(width: 780, height: 600)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Ink.hairline).frame(width: 1)
            Group {
                if RenderMode.snapshot {
                    pageContent.padding(28).frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView(.vertical, showsIndicators: false) { pageContent.padding(28) }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: Self.size.width, height: height)
        .background(Ink.window)
        .environment(\.colorScheme, Ink.palette.isLight ? .light : .dark)
        .id(prefs.theme.rawValue + prefs.accentMode.rawValue)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                MiniIsland(g: prefs.geometry)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Perch").font(.serif(20, .medium)).foregroundStyle(Ink.text)
                    Text("Version \(Prefs.appVersion)").font(.ui(10.5)).foregroundStyle(Ink.text3)
                }
            }
            .padding(.top, 38).padding(.bottom, 18).padding(.horizontal, 6)
            ForEach(SettingsPage.allCases) { p in
                let on = page == p
                Button { withAnimation(Motion.tab) { page = p } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.symbol).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(on ? Ink.onAccent : Ink.text2)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Ink.accent : Ink.raised))
                        Text(p.title).font(.ui(12.5, on ? .semibold : .regular)).foregroundStyle(on ? Ink.text : Ink.text2)
                        Spacer()
                    }
                    .padding(.horizontal, 8).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Ink.raised : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Made for one MacBook in particular.").font(.serif(11).italic()).foregroundStyle(Ink.text3)
                .padding(.horizontal, 8).padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
        .frame(width: 206)
        .background(Ink.palette.isLight ? Color.black.opacity(0.03) : Color.black.opacity(0.18))
    }

    @ViewBuilder var pageContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(page.title).font(.serif(26, .medium)).foregroundStyle(Ink.text).padding(.top, 10)
            switch page {
            case .island: IslandSettings(refit: refit)
            case .look: LookSettings()
            case .moments: MomentSettings()
            case .extras: ExtrasSettings()
            case .mail: MailSettings()
            case .agents: AgentSettings()
            case .permissions: PermissionSettings()
            case .updates: UpdateSettings(checkForUpdates: checkForUpdates, autoUpdates: autoUpdates)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Pages

private struct IslandSettings: View {
    @EnvironmentObject var prefs: Prefs
    var refit: () -> Void
    var body: some View {
        SettingsSection(title: "The fit", note: "Sized around your camera cover. Changes show on the island right away.") {
            SliderRow(label: "Width", value: binding(\.width), range: PillGeometry.widthRange)
            SliderRow(label: "Height", value: binding(\.height), range: PillGeometry.heightRange)
            SliderRow(label: "Corners", value: binding(\.cornerRadius), range: 0...70)
            SliderRow(label: "From top", value: binding(\.topOffset), range: PillGeometry.topRange)
            SliderRow(label: "Sideways", value: binding(\.horizontalOffset), range: PillGeometry.sideRange)
            HStack(spacing: 10) {
                PrimaryChip(title: "Fit it on screen", action: refit)
                PlainChip(title: "Reset") { prefs.geometry = .standard }
                Spacer()
            }
            .padding(.top, 4)
        }
        SettingsSection(title: "Opening", note: nil) {
            ToggleRow(title: "Open when the pointer rests on it", detail: "Otherwise, click the island.", isOn: $prefs.openOnHover)
            if prefs.openOnHover {
                SliderRow(label: "Wait", value: Binding(get: { CGFloat(prefs.hoverDelay * 1000) },
                                                        set: { prefs.hoverDelay = Double($0) / 1000 }),
                          range: 0...600, unit: "ms")
            }
            ToggleRow(title: "Swipe down on it to open", detail: "Two fingers on the trackpad, right over the island.", isOn: $prefs.swipeToOpen)
            PickerRow(title: "Keyboard shortcut", options: ShortcutPreset.allCases.map { ($0.rawValue, $0.title) },
                      selection: Binding(get: { prefs.shortcut.rawValue }, set: { prefs.shortcut = ShortcutPreset(rawValue: $0) ?? .off }))
            ToggleRow(title: "Trackpad taps", detail: "A light click as it opens and when you switch tabs.", isOn: $prefs.haptics)
        }
    }

    private func binding(_ key: WritableKeyPath<PillGeometry, CGFloat>) -> Binding<CGFloat> {
        Binding(get: { prefs.geometry[keyPath: key] },
                set: { v in var g = prefs.geometry; g[keyPath: key] = v; prefs.geometry = g.clamped() })
    }
}

private struct LookSettings: View {
    @EnvironmentObject var prefs: Prefs
    var body: some View {
        SettingsSection(title: "Theme", note: nil) {
            HStack(spacing: 12) {
                ForEach(ThemeName.allCases) { t in
                    ThemeSwatch(theme: t, selected: prefs.theme == t) { prefs.theme = t }
                }
            }
        }
        SettingsSection(title: "Accent", note: "From album art follows whatever you are playing, and falls back to the cover lime.") {
            HStack(spacing: 10) {
                ForEach(AccentMode.allCases) { a in
                    Button { prefs.accentMode = a } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                if a == .art {
                                    Circle().fill(AngularGradient(colors: [Ink.coral, Ink.amber, Ink.lime, Ink.sky, Color(red: 0.74, green: 0.62, blue: 1), Ink.coral], center: .center))
                                } else {
                                    Circle().fill(a.fixed)
                                }
                                if prefs.accentMode == a { Circle().strokeBorder(Ink.text, lineWidth: 2).padding(-4) }
                            }
                            .frame(width: 26, height: 26)
                            Text(a.title).font(.ui(10.5)).foregroundStyle(Ink.text2).lineLimit(1)
                        }
                        .frame(width: 84)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        SettingsSection(title: "Tabs", note: "Hide the tabs you never use.") {
            WrapRow(items: IslandTab.allCases.map { ($0.rawValue, $0.title, $0.symbol) }, isOn: { prefs.isTabShown($0) }, toggle: { prefs.toggleTab($0) })
        }
        SettingsSection(title: "Today cards", note: nil) {
            WrapRow(items: HomeCard.allCases.map { ($0.rawValue, $0.title, "") }, isOn: { prefs.isCardShown(HomeCard(rawValue: $0)!) },
                    toggle: { prefs.toggleCard(HomeCard(rawValue: $0)!) })
        }
        SettingsSection(title: "Resting", note: nil) {
            ToggleRow(title: "Show wings beside the cover", detail: "A timer, the next class, agent dots or album art.", isOn: $prefs.showWings)
        }
    }
}

private struct MomentSettings: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var signals: SignalCenter
    var body: some View {
        SettingsSection(title: "When something happens", note: "The island widens for a moment, then tucks back in.") {
            ToggleRow(title: "Volume", detail: "Shows the level whenever the volume changes.", isOn: $prefs.volumeHUD)
            ToggleRow(title: "Replace the big volume and brightness square",
                      detail: "Perch handles those keys itself. Needs Accessibility, asked when you turn this on.",
                      isOn: Binding(get: { prefs.replaceSystemHUD }, set: { on in
                          prefs.replaceSystemHUD = on
                          if on {
                              if MediaKeyTap.trusted { MediaKeyTap.shared.start() } else { MediaKeyTap.askForTrust() }
                          } else { MediaKeyTap.shared.stop() }
                      }))
            ToggleRow(title: "Charger plugged in", detail: "The battery fills up beside the cover. Also warns at 20%.", isOn: $prefs.chargingMoment)
            ToggleRow(title: "Headphones and Bluetooth", detail: "AirPods and friends say hello. macOS asks for Bluetooth once.",
                      isOn: Binding(get: { prefs.deviceMoments }, set: { on in
                          prefs.deviceMoments = on
                          if on { signals.startBluetooth() } else { signals.stopBluetooth() }
                      }))
            ToggleRow(title: "Camera and microphone", detail: "A green or amber dot while something is using them.", isOn: $prefs.privacyDots)
            ToggleRow(title: "Chime when an agent finishes", detail: "A soft two-note bell.", isOn: $prefs.chimeOnFinish)
        }
        Text("Focus modes are not shown. macOS only shares them with apps from Apple's paid developer program.")
            .font(.serif(12.5).italic()).foregroundStyle(Ink.text3)
    }
}

private struct ExtrasSettings: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var music: NowPlayingCenter
    @EnvironmentObject var weather: WeatherCenter
    @State private var city = ""
    @State private var looking = false

    var body: some View {
        SettingsSection(title: "Music", note: "Lyrics come from LRCLIB, a free open lyrics library. The little bars are decorative, not tied to the sound.") {
            StatusLine(color: music.source == .adapter ? Ink.mint : (music.source == .appleScript ? Ink.amber : Ink.quiet), text: musicLine)
            ToggleRow(title: "Synced lyrics", detail: nil, isOn: $prefs.lyricsOn)
        }
        SettingsSection(title: "Weather", note: "From Open-Meteo. No account, and no location permission: you pick the city.") {
            HStack(spacing: 10) {
                FieldRow(label: "City", text: $city, placeholder: prefs.weatherCity, secure: false)
                PlainChip(title: looking ? "Looking" : "Set") {
                    let q = city
                    guard !q.isEmpty else { return }
                    looking = true
                    Task {
                        if let r = await WeatherCenter.geocode(q) {
                            prefs.weatherCity = r.0; prefs.weatherLat = r.1; prefs.weatherLon = r.2
                            city = ""
                            weather.refresh()
                        }
                        looking = false
                    }
                }
            }
            ToggleRow(title: "Fahrenheit", detail: nil, isOn: Binding(get: { prefs.fahrenheit }, set: { prefs.fahrenheit = $0; weather.refresh() }))
        }
        SettingsSection(title: "Focus timer", note: nil) {
            SliderRow(label: "Focus", value: Binding(get: { CGFloat(prefs.pomodoroWork) }, set: { prefs.pomodoroWork = Double($0) }), range: 10...90, unit: "min")
            SliderRow(label: "Break", value: Binding(get: { CGFloat(prefs.pomodoroBreak) }, set: { prefs.pomodoroBreak = Double($0) }), range: 1...30, unit: "min")
        }
        SettingsSection(title: "Clipboard", note: "Kept on this Mac only. Anything a password manager marks as private is never saved.") {
            ToggleRow(title: "Remember what I copy", detail: "The last 40 things, plus anything you pin.", isOn: $prefs.clipboardOn)
        }
    }

    private var musicLine: String {
        switch music.source {
        case .adapter: return "Reading now playing from macOS directly. Works with any app."
        case .appleScript: return "Using the backup way: asking Spotify and Music. macOS may ask once to let Perch control them."
        case .starting: return "Starting up."
        }
    }
}

private struct MailSettings: View {
    @EnvironmentObject var gmail: GmailCenter
    @State private var clientID = ""
    @State private var secret = ""
    @State private var saved = false

    var body: some View {
        SettingsSection(title: "Gmail", note: nil) {
            StatusLine(color: statusColor, text: statusLine)
            HStack(spacing: 10) {
                switch gmail.state {
                case .ready:
                    PlainChip(title: "Sign out") { gmail.signOut() }
                case .needsClient:
                    EmptyView()
                default:
                    PrimaryChip(title: "Sign in with Google") { gmail.signIn() }
                }
                Spacer()
            }
        }
        SettingsSection(title: "Your Google client", note: "Stored in the macOS Keychain on this Mac. Never in a file, never sent anywhere but Google.") {
            FieldRow(label: "Client ID", text: $clientID, placeholder: gmail.hasClient ? "Saved" : "1234-abc.apps.googleusercontent.com", secure: false)
            FieldRow(label: "Client secret", text: $secret, placeholder: gmail.hasClient ? "Saved" : "GOCSPX-...", secure: true)
            HStack {
                PrimaryChip(title: saved ? "Saved" : "Save") {
                    gmail.saveClient(id: clientID, secret: secret)
                    clientID = ""; secret = ""; saved = true
                }
                Spacer()
            }
        }
        SettingsSection(title: "Making one takes five minutes", note: nil) {
            VStack(alignment: .leading, spacing: 7) {
                step(1, "Open console.cloud.google.com and make a project called Perch.")
                step(2, "APIs and Services, Library: turn on the Gmail API.")
                step(3, "OAuth consent screen: External, add your own address as a test user, then Publish app so sign-in does not expire every 7 days.")
                step(4, "Credentials, Create credentials, OAuth client ID, type Desktop app.")
                step(5, "Paste the client ID and secret above, Save, then Sign in.")
            }
        }
    }

    private func step(_ n: Int, _ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.round(11, .bold)).foregroundStyle(Ink.accent).frame(width: 14)
            Text(s).font(.ui(12)).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusColor: Color {
        switch gmail.state {
        case .ready: return Ink.mint
        case .failing: return Ink.coral
        default: return Ink.quiet
        }
    }

    private var statusLine: String {
        switch gmail.state {
        case .needsClient: return "Not set up. Add your Google client below."
        case .signedOut: return "Client saved. Sign in to connect."
        case .signingIn: return "Waiting for you in the browser."
        case .ready: return "Connected" + (gmail.account.map { " as \($0)" } ?? "") + ". Checks every 2 minutes."
        case .failing(let why): return why
        }
    }
}

private struct AgentSettings: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var board: AgentBoard
    var body: some View {
        SettingsSection(title: "The board", note: "Grok Bots report in with perch-signal on the shared box. Finished jobs fade off the board after 12 hours; Perch keeps its own history.") {
            StatusLine(color: boardColor, text: boardLine)
            FieldRow(label: "Board address", text: $prefs.boardURLOverride,
                     placeholder: (Bundle.main.object(forInfoDictionaryKey: "PerchBoardURL") as? String) ?? "", secure: false)
            FieldRow(label: "Read key", text: $prefs.boardKeyOverride, placeholder: "Built in", secure: true)
            HStack { PlainChip(title: "Clear history") { board.clearHistory() }; Spacer() }
        }
    }

    private var boardColor: Color {
        switch board.link {
        case .connected: return Ink.mint
        case .connecting: return Ink.quiet
        case .notSetUp, .failing: return Ink.coral
        }
    }

    private var boardLine: String {
        switch board.link {
        case .connected:
            let n = board.agents.count
            return "Connected. \(n == 0 ? "No agents on the board right now." : "\(n) on the board.")"
        case .connecting: return "Connecting to the board."
        case .notSetUp: return "No board key in this copy. Add one above."
        case .failing(let why): return why
        }
    }
}

private struct PermissionSettings: View {
    @EnvironmentObject var calendar: CalendarCenter
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var signals: SignalCenter
    @State private var tick = 0

    var body: some View {
        SettingsSection(title: "Asked once, only when you press the button", note: "Perch never asks on launch. Anything you skip simply stays off.") {
            PermissionRow(symbol: "calendar", title: "Calendar", why: "Your next class or meeting on Today and beside the cover.",
                          state: calendar.granted ? .granted : (calendar.access == .notDetermined ? .ask : .denied),
                          ask: { calendar.requestAccess() }, settingsPane: "Privacy_Calendars")
            PermissionRow(symbol: "keyboard", title: "Accessibility", why: "Only for replacing the volume and brightness square.",
                          state: MediaKeyTap.trusted ? .granted : .ask,
                          ask: { prefs.replaceSystemHUD = true; MediaKeyTap.askForTrust() }, settingsPane: "Privacy_Accessibility")
            PermissionRow(symbol: "dot.radiowaves.left.and.right", title: "Bluetooth", why: "To say hello when AirPods connect.",
                          state: btState, ask: { prefs.deviceMoments = true; signals.startBluetooth() }, settingsPane: "Privacy_Bluetooth")
            PermissionRow(symbol: "music.note", title: "Spotify and Music", why: "Only if the main way of reading music fails, or when you switch players. macOS asks the first time.",
                          state: .info, ask: {}, settingsPane: "Privacy_Automation")
        }
        .id(tick)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in if !RenderMode.snapshot { tick += 1 } }
        Text("No location, no screen recording, no full disk access. Weather uses the city you pick.")
            .font(.serif(12.5).italic()).foregroundStyle(Ink.text3)
    }

    private var btState: PermissionRow.Status {
        switch CBCentralManager.authorization {
        case .allowedAlways: return .granted
        case .notDetermined: return .ask
        default: return .denied
        }
    }
}

private struct UpdateSettings: View {
    var checkForUpdates: () -> Void
    var autoUpdates: Binding<Bool>
    var body: some View {
        SettingsSection(title: "Updates", note: "Updates install in place, so you never download Perch again or redo any permissions.") {
            ToggleRow(title: "Check every day", detail: nil, isOn: autoUpdates)
            HStack { PrimaryChip(title: "Check for updates", action: checkForUpdates); Spacer() }
        }
        SettingsSection(title: "Reinstall", note: nil) {
            Text("If Perch ever gets stuck bouncing in the Dock, paste this into Terminal:").font(.ui(12)).foregroundStyle(Ink.text2)
            Text("curl -fsSL https://raw.githubusercontent.com/BigBhubbha/perch-mac/main/scripts/install.sh | sh")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.text)
                .textSelection(.enabled)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Ink.raised))
        }
    }
}

// MARK: Pieces

struct PermissionRow: View {
    enum Status { case granted, ask, denied, info }
    let symbol: String
    let title: String
    let why: String
    let state: Status
    let ask: () -> Void
    let settingsPane: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.text2)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Ink.raised))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.ui(13)).foregroundStyle(Ink.text)
                Text(why).font(.ui(11)).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            switch state {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill").font(.ui(11.5, .semibold)).foregroundStyle(Ink.mint)
            case .ask:
                PrimaryChip(title: "Allow", action: ask)
            case .denied:
                PlainChip(title: "Open Settings") { open() }
            case .info:
                PlainChip(title: "Review") { open() }
            }
        }
    }

    private func open() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsPane)") { NSWorkspace.shared.open(u) }
    }
}

struct ThemeSwatch: View {
    let theme: ThemeName
    let selected: Bool
    let action: () -> Void
    var body: some View {
        let p = Palette.named(theme)
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.26, green: 0.33, blue: 0.45), Color(red: 0.44, green: 0.38, blue: 0.5)], startPoint: .top, endPoint: .bottom))
                    IslandShape(radius: 12, ear: 4).fill(p.pill).frame(width: 96, height: 40)
                    VStack(spacing: 4) {
                        Capsule().fill(Ink.accent).frame(width: 34, height: 12)
                        Capsule().fill(p.text.opacity(0.6)).frame(width: 50, height: 3)
                        Capsule().fill(p.text.opacity(0.3)).frame(width: 36, height: 3)
                    }
                    .padding(.top, 4)
                }
                .frame(width: 120, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Ink.accent : Ink.hairline, lineWidth: selected ? 2 : 1))
                Text(theme.title).font(.ui(11.5, selected ? .semibold : .regular)).foregroundStyle(selected ? Ink.text : Ink.text2)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Toggle chips in rows of four.
struct WrapRow: View {
    let items: [(String, String, String)]
    let isOn: (String) -> Bool
    let toggle: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(stride(from: 0, to: items.count, by: 4)), id: \.self) { i in
                HStack(spacing: 8) {
                    ForEach(items[i..<min(i + 4, items.count)], id: \.0) { it in
                        let on = isOn(it.0)
                        Button { withAnimation(Motion.snap) { toggle(it.0) } } label: {
                            HStack(spacing: 6) {
                                if !it.2.isEmpty { Image(systemName: it.2).font(.system(size: 10, weight: .semibold)) }
                                Text(it.1).font(.ui(11.5, .medium))
                            }
                            .foregroundStyle(on ? Ink.onAccent : Ink.text3)
                            .padding(.horizontal, 11).frame(height: 26)
                            .background(Capsule().fill(on ? Ink.accent : Ink.raised))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct PickerRow: View {
    let title: String
    let options: [(String, String)]
    @Binding var selection: String
    var body: some View {
        HStack {
            Text(title).font(.ui(13)).foregroundStyle(Ink.text)
            Spacer()
            if RenderMode.snapshot {
                label
            } else {
                Menu {
                    ForEach(options, id: \.0) { o in Button(o.1) { selection = o.0 } }
                } label: { label }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }
}

extension PickerRow {
    var label: some View {
        HStack(spacing: 6) {
            Text(options.first { $0.0 == selection }?.1 ?? "").font(.ui(12, .medium)).foregroundStyle(Ink.text)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Ink.text3)
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(Capsule().fill(Ink.raised))
    }
}

struct MiniIsland: View {
    let g: PillGeometry
    var body: some View {
        let scale = min(1, 40 / max(g.width, 1))
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.card).frame(width: 48, height: 36)
            IslandShape(radius: g.cornerRadius * scale, ear: 2)
                .fill(Color.black)
                .frame(width: g.width * scale, height: g.height * scale)
            Capsule().fill(Ink.lime).frame(width: g.width * scale * 0.86, height: g.height * scale * 0.8)
                .padding(.top, g.height * scale * 0.06)
        }
        .frame(width: 48, height: 36, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let note: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).eyebrow(Ink.accent)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.card))
            if let note {
                Text(note).font(.ui(11)).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var unit = "pt"
    var body: some View {
        HStack(spacing: 14) {
            Text(label).font(.ui(12.5)).foregroundStyle(Ink.text2).frame(width: 74, alignment: .leading)
            Scrubber(value: Double((value - range.lowerBound) / (range.upperBound - range.lowerBound)), tint: Ink.accent,
                     onChange: { f in value = (range.lowerBound + CGFloat(f) * (range.upperBound - range.lowerBound)).rounded() },
                     onCommit: { f in value = (range.lowerBound + CGFloat(f) * (range.upperBound - range.lowerBound)).rounded() })
            Text("\(Int(value)) \(unit)").font(.ui(11.5, .medium)).monospacedDigit().foregroundStyle(Ink.text3)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

struct ToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13)).foregroundStyle(Ink.text)
                if let detail { Text(detail).font(.ui(11)).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer()
            Button { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isOn.toggle() } } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? Ink.accent : Ink.text.opacity(0.14)).frame(width: 36, height: 21)
                    Circle().fill(isOn ? Ink.onAccent : Color.white.opacity(0.9)).frame(width: 15, height: 15).padding(3)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct StatusLine: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Circle().fill(color).frame(width: 7, height: 7).offset(y: -1)
            Text(text).font(.ui(12.5)).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FieldRow: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let secure: Bool
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.ui(12)).foregroundStyle(Ink.text3).frame(width: 96, alignment: .leading)
            Group {
                if RenderMode.snapshot {
                    Text(text.isEmpty ? placeholder : (secure ? String(repeating: "•", count: 12) : text))
                        .foregroundStyle(text.isEmpty ? Ink.text3 : Ink.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.ui(12))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Ink.raised))
        }
    }
}

struct PrimaryChip: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.ui(12, .semibold)).foregroundStyle(Ink.onAccent)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Ink.accent))
        }
        .buttonStyle(PressStyle())
    }
}
