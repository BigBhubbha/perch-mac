// What is playing, from any app.
//
// First choice: ungive/mediaremote-adapter (BSD-3-Clause). It runs Apple's own /usr/bin/perl, which is
// still allowed to read MediaRemote on macOS 15.4 and later, and streams JSON lines to us.
// Fallback: ask Spotify and Music directly with AppleScript, but only when they are already open.
//
// The helper always dies with Perch: we stop it on quit, on SIGTERM, and a tiny shell watchdog kills it
// if Perch ever crashes (the bug Boring Notch has, issue #1728).
import AppKit
import SwiftUI
import Combine

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var bundleID: String?
    var playing: Bool
    var duration: Double?
    var elapsed: Double?
    /// When `elapsed` was measured.
    var measuredAt: Date
    var rate: Double = 1
    var shuffle: Bool? = nil
    /// 0 off, 1 one, 2 all (MediaRemote's numbering, roughly).
    var repeatMode: Int? = nil

    func elapsed(at now: Date) -> Double? {
        guard let e = elapsed else { return nil }
        let live = playing ? e + now.timeIntervalSince(measuredAt) * max(rate, 0) : e
        if let d = duration, d > 0 { return min(max(0, live), d) }
        return max(0, live)
    }

    var appName: String {
        switch bundleID {
        case "com.spotify.client": return "Spotify"
        case "com.apple.Music": return "Music"
        case "com.apple.Safari": return "Safari"
        case "com.google.Chrome": return "Chrome"
        case "com.apple.podcasts": return "Podcasts"
        case .some(let id):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            }
            return "Now playing"
        case .none: return "Now playing"
        }
    }
}

enum MediaCommand: Int {
    case play = 0, pause = 1, toggle = 2, next = 4, previous = 5, shuffle = 6, repeatMode = 7
}

struct LyricLine: Equatable {
    var time: Double
    var text: String
}

/// Synced lyrics from LRCLIB, a free open lyrics database. No key.
enum Lyrics {
    static func fetch(_ t: Track) async -> [LyricLine]? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [URLQueryItem(name: "track_name", value: t.title), URLQueryItem(name: "artist_name", value: t.artist)]
        if !t.album.isEmpty { c.queryItems?.append(URLQueryItem(name: "album_name", value: t.album)) }
        if let d = t.duration, d > 0 { c.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(d.rounded())))) }
        guard let url = c.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Perch (https://github.com/BigBhubbha/perch-mac)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8
        guard let res = try? await URLSession.shared.data(for: req), (res.1 as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any],
              let synced = obj["syncedLyrics"] as? String else { return nil }
        return parse(synced)
    }

    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in lrc.split(separator: "\n") {
            let line = String(raw)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let stamp = line[line.index(after: line.startIndex)..<close]
            let parts = stamp.split(separator: ":")
            guard parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) else { continue }
            let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            out.append(LyricLine(time: m * 60 + sec, text: text))
        }
        return out.sorted { $0.time < $1.time }
    }
}

@MainActor
final class NowPlayingCenter: ObservableObject {
    enum Source: String { case starting, adapter, appleScript }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = Ink.lime
    @Published private(set) var source: Source = .starting
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var lyricsState: LyricsState = .none
    /// The darker partner of the accent, for gradients behind the art.
    @Published private(set) var shade: Color = Color(red: 0.1, green: 0.12, blue: 0.04)

    enum LyricsState: Equatable { case none, loading, found, missing }
    private var lyricsKey = ""

    private let prefs = Prefs.shared
    private var adapter: AdapterStream?
    private var scripts: ScriptPoller?
    private var artworkKey = ""
    private var restarts = 0

    var isPlaying: Bool { track?.playing == true }

    func start() {
        guard source == .starting else { return }
        guard let paths = AdapterPaths.inBundle() else { useAppleScript(); return }
        AdapterStream.selfTest(paths) { [weak self] ok in
            Task { @MainActor in
                guard let self else { return }
                if ok { self.useAdapter(paths) } else { self.useAppleScript() }
            }
        }
    }

    func stop() {
        adapter?.stop()
        adapter = nil
        scripts?.stop()
        scripts = nil
    }

    func send(_ command: MediaCommand) {
        // Feels instant: flip the button now, the real state follows a moment later.
        if command == .toggle, var t = track {
            t.elapsed = t.elapsed(at: Date()); t.measuredAt = Date(); t.playing.toggle(); track = t
        }
        switch source {
        case .adapter: adapter?.send(command)
        case .appleScript: scripts?.send(command, to: track?.bundleID)
        case .starting: break
        }
    }

    func seek(to seconds: Double) {
        guard var t = track else { return }
        t.elapsed = max(0, seconds); t.measuredAt = Date(); track = t
        switch source {
        case .adapter: adapter?.seek(seconds)
        case .appleScript: scripts?.seek(seconds, in: t.bundleID)
        case .starting: break
        }
    }

    func skip(by delta: Double) {
        guard let e = track?.elapsed(at: Date()) else { return }
        seek(to: e + delta)
    }

    /// Hands playback to another player: pause this one, press play on the other.
    func switchTo(_ bundleID: String) {
        if isPlaying { send(.pause) }
        let launch = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        DispatchQueue.global(qos: .userInitiated).async {
            if launch, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: cfg)
                Thread.sleep(forTimeInterval: 2.5)
            }
            var err: NSDictionary?
            NSAppleScript(source: "tell application id \"\(bundleID)\" to play")?.executeAndReturnError(&err)
        }
    }

    static func installed(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    func openPlayer() {
        guard let id = track?.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The lyric line at a moment, and its index.
    func lyricIndex(at seconds: Double) -> Int? {
        guard !lyrics.isEmpty else { return nil }
        var lo = 0, hi = lyrics.count - 1, best: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lyrics[mid].time <= seconds + 0.25 { best = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return best
    }

    private func loadLyrics(for t: Track) {
        let key = "\(t.title)|\(t.artist)"
        guard key != lyricsKey else { return }
        lyricsKey = key
        lyrics = []
        guard prefs.lyricsOn else { lyricsState = .none; return }
        lyricsState = .loading
        Task { [weak self] in
            let found = await Lyrics.fetch(t)
            guard let self, self.lyricsKey == key else { return }
            self.lyrics = found ?? []
            self.lyricsState = (found?.isEmpty == false) ? .found : .missing
        }
    }

    // MARK: Sources

    private func useAdapter(_ paths: AdapterPaths) {
        source = .adapter
        let stream = AdapterStream(paths: paths)
        stream.onUpdate = { [weak self] payload in
            Task { @MainActor in self?.applyAdapter(payload) }
        }
        stream.onExit = { [weak self] in
            Task { @MainActor in
                guard let self, self.adapter === stream else { return }
                self.restarts += 1
                if self.restarts <= 3 {
                    let wait = UInt64(self.restarts) * 2_000_000_000
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: wait)
                        guard let self, self.source == .adapter else { return }
                        self.adapter?.start()
                    }
                } else {
                    self.adapter = nil
                    self.useAppleScript()
                }
            }
        }
        adapter = stream
        stream.start()
    }

    private func useAppleScript() {
        adapter?.stop()
        adapter = nil
        source = .appleScript
        let poller = ScriptPoller()
        poller.onUpdate = { [weak self] track, art in
            Task { @MainActor in self?.applyScript(track, art) }
        }
        scripts = poller
        poller.start()
    }

    private func applyAdapter(_ p: [String: Any]) {
        guard let title = p["title"] as? String, !title.isEmpty else {
            track = nil; setArtwork(nil, key: ""); return
        }
        func seconds(_ micros: String, _ plain: String) -> Double? {
            if let m = p[micros] as? Double { return m / 1_000_000 }
            if let m = p[micros] as? Int { return Double(m) / 1_000_000 }
            return p[plain] as? Double
        }
        var measured = Date()
        if let ts = p["timestampEpochMicros"] as? Double { measured = Date(timeIntervalSince1970: ts / 1_000_000) }
        let t = Track(title: title,
                      artist: (p["artist"] as? String) ?? "",
                      album: (p["album"] as? String) ?? "",
                      bundleID: (p["parentApplicationBundleIdentifier"] as? String) ?? (p["bundleIdentifier"] as? String),
                      playing: (p["playing"] as? Bool) ?? false,
                      duration: seconds("durationMicros", "duration"),
                      elapsed: seconds("elapsedTimeMicros", "elapsedTime"),
                      measuredAt: measured,
                      rate: (p["playbackRate"] as? Double) ?? 1,
                      shuffle: (p["shuffleMode"] as? Int).map { $0 > 1 } ?? (p["shuffleMode"] as? Bool),
                      repeatMode: (p["repeatMode"] as? Int))
        if t != track { track = t }
        loadLyrics(for: t)
        let key = "\(t.title)|\(t.artist)|\(t.album)"
        if let b64 = p["artworkData"] as? String, let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
            if key != artworkKey || artwork == nil { setArtwork(img, key: key) }
        } else if key != artworkKey {
            setArtwork(nil, key: key)
        }
    }

    private func applyScript(_ t: Track?, _ art: NSImage?) {
        if t != track { track = t }
        guard let t else { setArtwork(nil, key: ""); return }
        loadLyrics(for: t)
        let key = "\(t.title)|\(t.artist)|\(t.album)"
        if let art { setArtwork(art, key: key) } else if key != artworkKey { setArtwork(nil, key: key) }
    }

    private func setArtwork(_ image: NSImage?, key: String) {
        artworkKey = key
        artwork = image
        let art = prefs.accentMode == .art
        let c = (art ? image.flatMap(ArtworkColor.accent) : nil)
        let chosen = c.map { Color(nsColor: $0) } ?? prefs.fixedAccent
        let dark = c.map { Color(nsColor: $0.blended(withFraction: 0.78, of: .black) ?? $0) } ?? Color(red: 0.1, green: 0.12, blue: 0.04)
        if art { Ink.accent = chosen }
        withAnimation(.easeInOut(duration: 0.6)) { accent = chosen; shade = dark }
    }

    /// Used by the preview renderer.
    func showSample(_ t: Track, art: NSImage?, lyrics: [LyricLine] = []) {
        track = t
        source = .adapter
        lyricsKey = "\(t.title)|\(t.artist)"
        self.lyrics = lyrics
        lyricsState = lyrics.isEmpty ? .none : .found
        setArtwork(art, key: t.title)
    }

    func clearSample() { track = nil; artwork = nil; lyrics = [] }
}

// MARK: mediaremote-adapter

struct AdapterPaths {
    let script: String
    let framework: String
    let testClient: String

    static func inBundle() -> AdapterPaths? {
        let b = Bundle.main.bundleURL
        let p = AdapterPaths(script: b.appendingPathComponent("Contents/Resources/mediaremote-adapter.pl").path,
                             framework: b.appendingPathComponent("Contents/Frameworks/MediaRemoteAdapter.framework").path,
                             testClient: b.appendingPathComponent("Contents/Helpers/MediaRemoteAdapterTestClient").path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: p.script), fm.fileExists(atPath: p.framework) else { return nil }
        return p
    }
}

final class AdapterStream {
    private let paths: AdapterPaths
    private var process: Process?
    private var buffer = Data()
    private var state: [String: Any] = [:]
    private let queue = DispatchQueue(label: "perch.nowplaying.adapter")
    var onUpdate: (([String: Any]) -> Void)?
    var onExit: (() -> Void)?
    private var stopping = false

    /// Every live helper, so the SIGTERM handler can kill them even mid-launch.
    static var livePIDs = Set<Int32>()
    static let pidLock = NSLock()

    init(paths: AdapterPaths) { self.paths = paths }

    /// Runs the adapter's own self-test. Exit 0 means MediaRemote still works on this macOS.
    static func selfTest(_ paths: AdapterPaths, done: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            p.arguments = [paths.script, paths.framework, paths.testClient, "test"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { done(false); return }
            let deadline = Date().addingTimeInterval(6)
            while p.isRunning && Date() < deadline { usleep(50_000) }
            if p.isRunning { p.terminate(); done(false); return }
            done(p.terminationStatus == 0)
        }
    }

    func start() {
        stop()
        stopping = false
        let p = Process()
        // A small shell keeps watch over Perch: if Perch's process id disappears, the helper is killed too.
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        let watchdog = """
        /usr/bin/perl "$1" "$2" stream --micros --debounce=80 &
        child=$!
        trap 'kill "$child" 2>/dev/null; exit 0' TERM INT HUP
        while kill -0 "$3" 2>/dev/null && kill -0 "$child" 2>/dev/null; do sleep 1 & wait $!; done
        kill "$child" 2>/dev/null
        """
        p.arguments = ["-c", watchdog, "perch-nowplaying", paths.script, paths.framework,
                       String(ProcessInfo.processInfo.processIdentifier)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self else { return }
            if chunk.isEmpty { h.readabilityHandler = nil; return }
            self.queue.async { self.consume(chunk) }
        }
        p.terminationHandler = { [weak self] proc in
            AdapterStream.pidLock.lock(); AdapterStream.livePIDs.remove(proc.processIdentifier); AdapterStream.pidLock.unlock()
            guard let self, !self.stopping else { return }
            self.onExit?()
        }
        do {
            try p.run()
            AdapterStream.pidLock.lock(); AdapterStream.livePIDs.insert(p.processIdentifier); AdapterStream.pidLock.unlock()
            process = p
        } catch {
            onExit?()
        }
    }

    func stop() {
        stopping = true
        if let p = process, p.isRunning {
            p.terminate() // SIGTERM to the watchdog shell, whose trap kills perl
        }
        process = nil
    }

    static func killAll() {
        pidLock.lock(); let pids = livePIDs; pidLock.unlock()
        for pid in pids { kill(pid, SIGTERM) }
    }

    func send(_ c: MediaCommand) {
        let paths = self.paths
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            p.arguments = [paths.script, paths.framework, "send", String(c.rawValue)]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }

    func seek(_ seconds: Double) {
        let paths = self.paths
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            p.arguments = [paths.script, paths.framework, "seek", String(Int64(seconds * 1_000_000))]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any] else { continue }
            if (obj["diff"] as? Bool) == true {
                for (k, v) in payload {
                    if v is NSNull { state.removeValue(forKey: k) } else { state[k] = v }
                }
            } else {
                state = payload
            }
            onUpdate?(state)
        }
        if buffer.count > 8_000_000 { buffer.removeAll() } // never let a broken stream eat memory
    }
}

// MARK: AppleScript fallback

final class ScriptPoller {
    var onUpdate: ((Track?, NSImage?) -> Void)?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "perch.nowplaying.applescript")
    private var lastKey = ""
    private var lastArt: NSImage?

    static let spotify = "com.spotify.client"
    static let music = "com.apple.Music"

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.5, leeway: .milliseconds(300))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    private static func isRunning(_ id: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return err == nil ? result : nil
    }

    private func poll() {
        // Prefer whichever is actually playing; never launch an app just to ask it.
        var found: Track?
        for id in [Self.spotify, Self.music] where Self.isRunning(id) {
            if let t = read(id) {
                if t.playing { found = t; break }
                if found == nil { found = t }
            }
        }
        guard let t = found else {
            lastKey = ""; lastArt = nil
            onUpdate?(nil, nil); return
        }
        let key = "\(t.title)|\(t.artist)|\(t.album)"
        if key != lastKey {
            lastKey = key
            lastArt = artwork(for: t)
        }
        onUpdate?(t, lastArt)
    }

    private func read(_ id: String) -> Track? {
        let src: String
        if id == Self.spotify {
            src = """
            tell application id "com.spotify.client"
              if player state is stopped then return ""
              set t to current track
              return (player state as text) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) / 1000 as text) & linefeed & (player position as text)
            end tell
            """
        } else {
            src = """
            tell application id "com.apple.Music"
              if player state is stopped then return ""
              set t to current track
              return (player state as text) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (duration of t as text) & linefeed & (player position as text)
            end tell
            """
        }
        guard let s = run(src)?.stringValue, !s.isEmpty else { return nil }
        let f = s.components(separatedBy: "\n")
        guard f.count >= 6, !f[1].isEmpty else { return nil }
        func num(_ x: String) -> Double? { Double(x.replacingOccurrences(of: ",", with: ".")) }
        return Track(title: f[1], artist: f[2], album: f[3], bundleID: id, playing: f[0] == "playing",
                     duration: num(f[4]), elapsed: num(f[5]), measuredAt: Date())
    }

    private func artwork(for t: Track) -> NSImage? {
        if t.bundleID == Self.spotify {
            guard let u = run("tell application id \"com.spotify.client\" to return artwork url of current track")?.stringValue,
                  let url = URL(string: u), let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        }
        if let d = run("tell application id \"com.apple.Music\" to return raw data of artwork 1 of current track")?.data,
           !d.isEmpty {
            return NSImage(data: d)
        }
        return nil
    }

    func send(_ c: MediaCommand, to bundleID: String?) {
        let id = bundleID == Self.music ? Self.music : (Self.isRunning(Self.spotify) ? Self.spotify : Self.music)
        let verb: String
        switch c {
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .toggle: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .shuffle:
            verb = id == Self.spotify ? "set shuffling to not shuffling" : "set shuffle enabled to not shuffle enabled"
        case .repeatMode:
            verb = id == Self.spotify ? "set repeating to not repeating" : "if song repeat is off then\nset song repeat to all\nelse\nset song repeat to off\nend if"
        }
        queue.async { [weak self] in
            _ = self?.run("tell application id \"\(id)\"\n\(verb)\nend tell")
            self?.poll()
        }
    }
}

extension ScriptPoller {
    func seek(_ seconds: Double, in bundleID: String?) {
        let id = bundleID == Self.music ? Self.music : Self.spotify
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            NSAppleScript(source: "tell application id \"\(id)\" to set player position to \(seconds)")?.executeAndReturnError(&err)
        }
    }
}

// MARK: Accent color from album art

enum ArtworkColor {
    /// The most vivid color in the artwork, lifted so it reads on black. Nil for grey artwork.
    static func accent(from image: NSImage) -> NSColor? {
        let side = 16
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var best: (score: CGFloat, color: NSColor)?
        for x in 0..<side {
            for y in 0..<side {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                guard b > 0.22, s > 0.22 else { continue }
                let score = s * 0.7 + b * 0.3
                if best == nil || score > best!.score { best = (score, c) }
            }
        }
        guard let c = best?.color else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(s, 0.78), brightness: max(b, 0.86), alpha: 1)
    }
}
