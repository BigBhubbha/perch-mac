// The big Music view's data: what Music.app is playing from (the playlist and its tracks), your library
// playlists, and what you played recently. Read with AppleScript, only while the spilled Music view is open,
// and only if Music is already running. Missing album art comes from the public iTunes Search API.
import AppKit
import Combine

struct QueueTrack: Identifiable, Equatable {
    var id: String          // Music's persistent ID
    var index: Int
    var title: String
    var artist: String
    var album: String
    var duration: Double
}

struct LibraryPlaylist: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var count: Int
}

struct PlayedTrack: Codable, Identifiable, Equatable {
    var id: String { title + "|" + artist }
    var title: String
    var artist: String
    var album: String
    var at: Date
    var bundleID: String?
}

@MainActor
final class MusicLibrary: ObservableObject {
    enum Source: Equatable { case music, spotify, none }

    @Published private(set) var source: Source = .none
    @Published private(set) var playlistName: String?
    @Published private(set) var queue: [QueueTrack] = []
    @Published private(set) var currentID: String?
    @Published private(set) var playlists: [LibraryPlaylist] = []
    @Published private(set) var recent: [PlayedTrack] = []
    @Published private(set) var art: [String: NSImage] = [:]   // keyed by "artist|album"
    @Published private(set) var loading = false

    private let queueRunner = DispatchQueue(label: "perch.music.library")
    private var watch: AnyCancellable?
    private let recentKey = "music.recent"

    init() {
        if let d = UserDefaults.standard.data(forKey: recentKey), let v = try? JSONDecoder().decode([PlayedTrack].self, from: d) { recent = v }
    }

    /// Keeps a short history of what played while Perch was running.
    func watch(_ music: NowPlayingCenter) {
        watch = music.$track.removeDuplicates { $0?.title == $1?.title && $0?.artist == $1?.artist }.sink { [weak self] t in
            guard let self, let t, !t.title.isEmpty else { return }
            if self.recent.first?.title == t.title && self.recent.first?.artist == t.artist { return }
            self.recent.removeAll { $0.title == t.title && $0.artist == t.artist }
            self.recent.insert(PlayedTrack(title: t.title, artist: t.artist, album: t.album, at: Date(), bundleID: t.bundleID), at: 0)
            if self.recent.count > 30 { self.recent.removeLast(self.recent.count - 30) }
            if let d = try? JSONEncoder().encode(self.recent) { UserDefaults.standard.set(d, forKey: self.recentKey) }
        }
    }

    static func running(_ id: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }

    /// Reads the current playlist and library from Music. Never launches Music just to look.
    func refresh(preferring bundleID: String?) {
        if RenderMode.snapshot { return }
        let useMusic = Self.running(ScriptPoller.music) && (bundleID != ScriptPoller.spotify || !Self.running(ScriptPoller.spotify))
        guard useMusic else {
            source = Self.running(ScriptPoller.spotify) ? .spotify : .none
            queue = []; playlists = []; playlistName = nil
            return
        }
        loading = true
        queueRunner.async { [weak self] in
            let out = Self.run(Self.libraryScript)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(out) }
            }
        }
    }

    private func apply(_ text: String?) {
        loading = false
        source = .music
        guard let text else { return }
        var name: String?, tracks: [QueueTrack] = [], lists: [LibraryPlaylist] = [], current: String?
        for line in text.components(separatedBy: "\n") {
            let f = line.components(separatedBy: "\t")
            switch f.first {
            case "P" where f.count > 1: name = f[1]
            case "C" where f.count > 1: current = f[1].isEmpty ? nil : f[1]
            case "T" where f.count > 6:
                tracks.append(QueueTrack(id: f[6], index: Int(f[1]) ?? tracks.count + 1, title: f[2], artist: f[3], album: f[4],
                                         duration: Double(f[5].replacingOccurrences(of: ",", with: ".")) ?? 0))
            case "L" where f.count > 2: lists.append(LibraryPlaylist(name: f[1], count: Int(f[2]) ?? 0))
            default: break
            }
        }
        playlistName = name; queue = tracks; currentID = current; playlists = lists
        if let first = tracks.first(where: { $0.id == current }) ?? tracks.first { fetchArt(artist: first.artist, album: first.album) }
        for r in recent.prefix(6) { fetchArt(artist: r.artist, album: r.album) }
    }

    func play(_ t: QueueTrack) {
        let script = "tell application \"Music\" to play (first track of current playlist whose persistent ID is \"\(Self.escape(t.id))\")"
        queueRunner.async { _ = Self.run(script) }
        currentID = t.id
    }

    func play(_ p: LibraryPlaylist) {
        let script = "tell application \"Music\" to play playlist \"\(Self.escape(p.name))\""
        queueRunner.async { [weak self] in
            _ = Self.run(script)
            Thread.sleep(forTimeInterval: 0.6)
            let out = Self.run(Self.libraryScript)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(out) } }
        }
    }

    /// Album art for anything Music did not hand us, from the iTunes Search API (no account, no key).
    func fetchArt(artist: String, album: String) {
        let key = artist + "|" + album
        guard art[key] == nil, !artist.isEmpty else { return }
        let term = "\(artist) \(album)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?media=music&entity=album&limit=1&term=\(term)") else { return }
        art[key] = NSImage(size: .zero) // mark as in flight
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (obj["results"] as? [[String: Any]])?.first,
                  let small = first["artworkUrl100"] as? String,
                  let big = URL(string: small.replacingOccurrences(of: "100x100", with: "600x600")) else { return }
            URLSession.shared.dataTask(with: big) { d, _, _ in
                guard let d, let img = NSImage(data: d) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.art[key] = img } }
            }.resume()
        }.resume()
    }

    func artwork(artist: String, album: String) -> NSImage? {
        guard let i = art[artist + "|" + album], i.size.width > 0 else { return nil }
        return i
    }

    // MARK: AppleScript

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func run(_ source: String) -> String? {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return err == nil ? r?.stringValue : nil
    }

    /// One round trip per property list, not per track, so a long playlist still reads quickly.
    static let libraryScript = """
    tell application "Music"
        set out to ""
        set TB to tab
        set LF to linefeed
        try
            set p to current playlist
            set out to out & "P" & TB & (name of p) & LF
            set n to count of tracks of p
            if n > 300 then set n to 300
            if n > 0 then
                set ns to name of tracks 1 thru n of p
                set ars to artist of tracks 1 thru n of p
                set als to album of tracks 1 thru n of p
                set ds to duration of tracks 1 thru n of p
                set ps to persistent ID of tracks 1 thru n of p
                repeat with i from 1 to n
                    set out to out & "T" & TB & i & TB & (item i of ns) & TB & (item i of ars) & TB & (item i of als) & TB & (item i of ds) & TB & (item i of ps) & LF
                end repeat
            end if
            try
                set out to out & "C" & TB & (persistent ID of current track) & LF
            end try
        end try
        try
            repeat with pl in (every user playlist whose special kind is none)
                try
                    set out to out & "L" & TB & (name of pl) & TB & (count of tracks of pl) & LF
                end try
            end repeat
        end try
        return out
    end tell
    """

    // MARK: Previews

    func preview(name: String, tracks: [QueueTrack], current: String?, playlists: [LibraryPlaylist], recent: [PlayedTrack], art: [String: NSImage]) {
        source = .music; playlistName = name; queue = tracks; currentID = current; self.playlists = playlists; self.recent = recent; self.art = art
    }
}
