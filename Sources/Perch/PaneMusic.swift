// Music: big art over its own blurred glow, a real scrub bar, shuffle and repeat, volume, synced lyrics.
import SwiftUI
import AppKit

struct MusicPane: View {
    @EnvironmentObject var music: NowPlayingCenter
    @EnvironmentObject var signals: SignalCenter
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        if let t = music.track {
            Group {
                HStack(alignment: .center, spacing: 22) {
                    Artwork(image: music.artwork, accent: music.accent, radius: 20)
                        .frame(width: 168, height: 168)
                        .onTapGesture { music.openPlayer() }
                        .help("Open \(t.appName)")
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text(t.appName).eyebrow(music.accent)
                            if t.playing { Visualizer(color: music.accent).frame(width: 22, height: 10) }
                            Spacer()
                            PlayerSwitch()
                        }
                        Text(t.title).font(.ui(20, .semibold)).foregroundStyle(Ink.text).lineLimit(1).padding(.top, 6)
                        Text([t.artist, t.album].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                            .font(.ui(13)).foregroundStyle(Ink.text2).lineLimit(1).padding(.top, 1)
                        Spacer(minLength: 8)
                        if let d = t.duration, d > 0 {
                            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                                SeekRow(elapsed: t.elapsed(at: ctx.date) ?? 0, duration: d, accent: music.accent) { music.seek(to: $0) }
                            }
                        }
                        HStack(spacing: 0) {
                            ControlButton(symbol: "shuffle", size: 12, tint: t.shuffle == true ? music.accent : Ink.text3) { music.send(.shuffle) }
                            Spacer()
                            ControlButton(symbol: "gobackward.15", size: 14) { music.skip(by: -15) }
                            ControlButton(symbol: "backward.fill", size: 16) { music.send(.previous) }
                            ControlButton(symbol: t.playing ? "pause.fill" : "play.fill", size: 20, prominent: true, tint: Ink.text) { music.send(.toggle) }
                                .padding(.horizontal, 8)
                            ControlButton(symbol: "forward.fill", size: 16) { music.send(.next) }
                            ControlButton(symbol: "goforward.15", size: 14) { music.skip(by: 15) }
                            Spacer()
                            ControlButton(symbol: t.repeatMode == 1 ? "repeat.1" : "repeat", size: 12,
                                          tint: (t.repeatMode ?? 0) > 0 ? music.accent : Ink.text3) { music.send(.repeatMode) }
                        }
                        .padding(.top, 6)
                        VolumeRow()
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if prefs.lyricsOn {
                        LyricsColumn(track: t).frame(width: 214)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { Backdrop(image: music.artwork, accent: music.accent, shade: music.shade) }
            }
        } else {
            VStack(spacing: 14) {
                EmptyState(drawing: AnyView(RecordDrawing()),
                           title: "Nothing playing",
                           line: music.source == .appleScript
                               ? "Start something in Spotify or Music and it shows up here."
                               : "Play something anywhere and it shows up here, with lyrics when they exist.")
                HStack(spacing: 8) {
                    if NowPlayingCenter.installed(ScriptPoller.spotify) {
                        Chip(title: "Play Spotify", symbol: "play.fill") { music.switchTo(ScriptPoller.spotify) }
                    }
                    if NowPlayingCenter.installed(ScriptPoller.music) {
                        Chip(title: "Play Music", symbol: "play.fill") { music.switchTo(ScriptPoller.music) }
                    }
                }
                .padding(.bottom, 18)
            }
        }
    }
}

/// The album art, blown up and blurred into a soft glow behind everything.
private struct Backdrop: View {
    let image: NSImage?
    let accent: Color
    let shade: Color
    var body: some View {
        ZStack {
            LinearGradient(colors: [shade.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 360, height: 360)
                    .blur(radius: 60)
                    .opacity(Ink.palette.isLight ? 0.35 : 0.5)
                    .offset(x: -220)
            } else {
                Circle().fill(accent.opacity(0.25)).frame(width: 260).blur(radius: 70).offset(x: -220)
            }
            LinearGradient(colors: [Ink.pill.opacity(0), Ink.pill.opacity(0.85)], startPoint: .leading, endPoint: .trailing)
        }
        .padding(.horizontal, -20)
        .allowsHitTesting(false)
        .clipped()
    }
}

struct SeekRow: View {
    let elapsed: Double
    let duration: Double
    let accent: Color
    let seek: (Double) -> Void
    @State private var preview: Double?

    var body: some View {
        HStack(spacing: 10) {
            Text(clock(preview.map { $0 * duration } ?? elapsed)).font(.ui(10.5, .medium)).monospacedDigit().foregroundStyle(Ink.text3)
                .frame(width: 34, alignment: .leading)
            Scrubber(value: min(1, elapsed / duration), tint: accent,
                     onChange: { preview = $0 }, onCommit: { preview = nil; seek($0 * duration) })
            Text("-" + clock(max(0, duration - (preview.map { $0 * duration } ?? elapsed)))).font(.ui(10.5, .medium)).monospacedDigit()
                .foregroundStyle(Ink.text3).frame(width: 38, alignment: .trailing)
        }
    }
}

private struct VolumeRow: View {
    @EnvironmentObject var signals: SignalCenter
    var body: some View {
        HStack(spacing: 10) {
            Button { SystemVolume.isMuted.toggle() } label: {
                Image(systemName: signals.muted ? "speaker.slash.fill" : "speaker.fill").font(.system(size: 10)).foregroundStyle(Ink.text3)
                    .frame(width: 34, alignment: .leading)
            }
            .buttonStyle(.plain)
            Scrubber(value: signals.muted ? 0 : Double(signals.volume), tint: Ink.text.opacity(0.7), height: 3,
                     onChange: { signals.setVolume(Float($0)) }, onCommit: { signals.setVolume(Float($0)) })
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(Ink.text3).frame(width: 38, alignment: .trailing)
        }
    }
}

/// When both Spotify and Music are open, a tiny switch to hand playback from one to the other.
private struct PlayerSwitch: View {
    @EnvironmentObject var music: NowPlayingCenter
    var body: some View {
        let current = music.track?.bundleID
        let options: [(String, String)] = [(ScriptPoller.spotify, "Spotify"), (ScriptPoller.music, "Music")]
            .filter { RenderMode.snapshot || NowPlayingCenter.installed($0.0) }
        if options.count == 2 {
            HStack(spacing: 2) {
                ForEach(options, id: \.0) { o in
                    let on = current == o.0
                    Button { if !on { music.switchTo(o.0) } } label: {
                        Text(o.1).font(.ui(10, .semibold)).foregroundStyle(on ? Ink.text : Ink.text3)
                            .padding(.horizontal, 8).frame(height: 20)
                            .background(Capsule().fill(on ? Ink.raisedHover : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Capsule().fill(Ink.raised))
        }
    }
}

private struct LyricsColumn: View {
    let track: Track
    @EnvironmentObject var music: NowPlayingCenter

    var body: some View {
        Group {
            switch music.lyricsState {
            case .found:
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                    let at = track.elapsed(at: ctx.date) ?? 0
                    let i = music.lyricIndex(at: at) ?? -1
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(max(0, i - 1)...min(music.lyrics.count - 1, max(0, i) + 2), id: \.self) { j in
                            let line = music.lyrics[j].text
                            Text(line.isEmpty ? "♪" : line)
                                .font(.ui(j == i ? 15 : 13, j == i ? .bold : .semibold))
                                .foregroundStyle(j == i ? Ink.text : Ink.text.opacity(j < i ? 0.22 : 0.38))
                                .lineLimit(2)
                                .onTapGesture { music.seek(to: music.lyrics[j].time) }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .clipped()
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: i)
                }
            case .loading:
                note("Finding lyrics")
            case .missing:
                note("No synced lyrics for this one")
            case .none:
                note("")
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) { Rectangle().fill(Ink.hairline).frame(width: 1) }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.serif(13).italic()).foregroundStyle(Ink.text3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Five bars tinted from the art. These are decorative: macOS does not let an app hear other apps'
/// audio without a screen recording permission, so they move to a rhythm, not to the song.
struct Visualizer: View {
    let color: Color
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 14.0)) { ctx in
            let t = RenderMode.snapshot ? 1.3 : ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let speeds = [5.1, 7.3, 4.2, 6.4, 5.7]
                    let v = (sin(t * speeds[i] + Double(i) * 1.7) + 1) / 2
                    Capsule().fill(color).frame(width: 2.4, height: 3 + 7 * v)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
