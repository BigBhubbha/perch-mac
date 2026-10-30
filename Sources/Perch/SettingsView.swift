// Settings: the fit, how the island behaves, the agent board, and updates.
import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var board: AgentBoard
    @ObservedObject var music: NowPlayingCenter
    var refit: () -> Void
    var checkForUpdates: () -> Void
    var autoUpdates: Binding<Bool>

    static let size = NSSize(width: 560, height: 700)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content.padding(28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Ink.window)
        .environment(\.colorScheme, .dark)
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 14) {
                MiniIsland(g: prefs.geometry)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Perch").font(.serif(26, .medium)).foregroundStyle(Ink.text)
                    Text("Version \(Prefs.appVersion). Made for one MacBook in particular.")
                        .font(.ui(12)).foregroundStyle(Ink.text3)
                }
            }
            .padding(.top, 14)

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

            SettingsSection(title: "Behavior", note: nil) {
                ToggleRow(title: "Open when the pointer rests on it", detail: "Otherwise, click the island.", isOn: $prefs.openOnHover)
                if prefs.openOnHover {
                    SliderRow(label: "Wait", value: Binding(get: { CGFloat(prefs.hoverDelay * 1000) },
                                                            set: { prefs.hoverDelay = Double($0) / 1000 }),
                              range: 0...600, unit: "ms")
                }
                ToggleRow(title: "Show little wings", detail: "Album art and agent dots peek out beside the cover.", isOn: $prefs.showWings)
                ToggleRow(title: "Chime when an agent finishes", detail: "A soft two-note bell.", isOn: $prefs.chimeOnFinish)
                ToggleRow(title: "Color from album art", detail: "Otherwise everything stays lime.", isOn: $prefs.useArtworkColor)
            }

            SettingsSection(title: "Music", note: nil) {
                StatusLine(color: music.source == .adapter ? Ink.lime : (music.source == .appleScript ? Color.orange : Ink.quiet),
                           text: musicLine)
            }

            SettingsSection(title: "Agents", note: "Grok Bots report in with perch-signal on the shared box. Finished jobs fade off the board after 12 hours.") {
                StatusLine(color: boardColor, text: boardLine)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldRow(label: "Board address", text: $prefs.boardURLOverride,
                                 placeholder: (Bundle.main.object(forInfoDictionaryKey: "PerchBoardURL") as? String) ?? "", secure: false)
                        FieldRow(label: "Read key", text: $prefs.boardKeyOverride, placeholder: "Built in", secure: true)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("For tinkering").font(.ui(12, .medium)).foregroundStyle(Ink.text2)
                }
                .tint(Ink.text3)
            }

            SettingsSection(title: "Updates", note: "Updates install in place, so you never download Perch again or redo any permissions.") {
                ToggleRow(title: "Check every day", detail: nil, isOn: autoUpdates)
                HStack { PrimaryChip(title: "Check for updates", action: checkForUpdates); Spacer() }
            }

            Text("Gmail arrives in version 2.")
                .font(.serif(13).italic())
                .foregroundStyle(Ink.text3)
                .padding(.bottom, 8)
        }
    }

    private func binding(_ key: WritableKeyPath<PillGeometry, CGFloat>) -> Binding<CGFloat> {
        Binding(get: { prefs.geometry[keyPath: key] },
                set: { v in var g = prefs.geometry; g[keyPath: key] = v; prefs.geometry = g.clamped() })
    }

    private var musicLine: String {
        switch music.source {
        case .adapter: return "Reading now playing from macOS directly. Works with any app."
        case .appleScript: return "Using the backup way: asking Spotify and Music. macOS may ask once to let Perch control them."
        case .starting: return "Starting up."
        }
    }

    private var boardColor: Color {
        switch board.link {
        case .connected: return Ink.lime
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
        case .notSetUp: return "No board key in this copy. Add one under For tinkering."
        case .failing(let why): return why
        }
    }
}

struct MiniIsland: View {
    let g: PillGeometry
    var body: some View {
        let scale = min(1, 64 / max(g.width, 1))
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.card).frame(width: 76, height: 52)
            IslandShape(radius: g.cornerRadius * scale, ear: 2)
                .fill(Color.black)
                .frame(width: g.width * scale, height: g.height * scale)
            Capsule().fill(Ink.lime).frame(width: g.width * scale * 0.86, height: g.height * scale * 0.8)
                .padding(.top, g.height * scale * 0.06)
        }
        .frame(width: 76, height: 52, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let note: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).eyebrow(Ink.lime.opacity(0.9))
            VStack(alignment: .leading, spacing: 12) { content }
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
            if RenderMode.snapshot {
                GeometryReader { geo in
                    let f = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                        Capsule().fill(Ink.lime).frame(width: geo.size.width * f, height: 4)
                        Circle().fill(Color.white).frame(width: 14, height: 14).offset(x: geo.size.width * f - 7)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 18)
            } else {
                Slider(value: $value, in: range, step: 1).tint(Ink.lime)
            }
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13)).foregroundStyle(Ink.text)
                if let detail { Text(detail).font(.ui(11)).foregroundStyle(Ink.text3) }
            }
            Spacer()
            Button { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isOn.toggle() } } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? Ink.lime : Color.white.opacity(0.14)).frame(width: 36, height: 21)
                    Circle().fill(isOn ? Ink.pill : Color.white.opacity(0.85)).frame(width: 15, height: 15).padding(3)
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
                if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
            }
            .textFieldStyle(.plain)
            .font(.ui(12))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
        }
    }
}

struct PrimaryChip: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.ui(12, .semibold)).foregroundStyle(Ink.pill)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Ink.lime))
        }
        .buttonStyle(.plain)
    }
}
