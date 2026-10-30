// The Grok Bot board. Agents report "started" and "finished" to a small Cloudflare Worker
// (see cloudflare/worker.mjs and scripts/perch-signal); Perch polls it every few seconds.
import AppKit
import Combine

struct Agent: Decodable, Identifiable, Equatable {
    enum Status: String, Decodable { case started, working, finished, failed }
    let id: String
    let name: String
    let status: Status
    let quiet: Bool?
    let task: String?
    let note: String?
    let run: Int?
    let startedAt: Double?
    let updatedAt: Double
    let finishedAt: Double?

    var isWorking: Bool { status == .started || status == .working }
    var startedDate: Date? { startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var finishedDate: Date? { finishedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

/// A finished run, kept on this Mac so the board has a memory past the Worker's 12 hours.
struct AgentRun: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var task: String
    var failed: Bool
    var seconds: Double?
    var at: Date
}

private struct BoardReply: Decodable {
    let agents: [Agent]
    let now: Double
}

@MainActor
final class AgentBoard: ObservableObject {
    enum Link: Equatable { case notSetUp, connecting, connected, failing(String) }

    @Published private(set) var agents: [Agent] = []
    @Published private(set) var link: Link = .connecting
    @Published private(set) var lastSync: Date?
    /// Agents that finished in the last few seconds, for the bloom.
    @Published private(set) var justFinished: Set<String> = []

    @Published private(set) var history: [AgentRun] = []

    var onFinish: (Agent) -> Void = { _ in }
    private let historyKey = "agents.history"

    init() {
        if let d = UserDefaults.standard.data(forKey: historyKey), let v = try? JSONDecoder().decode([AgentRun].self, from: d) {
            history = v
        }
    }

    var finishedToday: Int { history.filter { Calendar.current.isDateInToday($0.at) && !$0.failed }.count }

    private func remember(_ a: Agent) {
        let secs: Double? = {
            guard let s = a.startedAt, let f = a.finishedAt ?? Optional(a.updatedAt) else { return nil }
            return max(0, (f - s) / 1000)
        }()
        history.insert(AgentRun(name: a.name, task: a.task ?? a.note ?? "", failed: a.status == .failed, seconds: secs, at: Date()), at: 0)
        if history.count > 40 { history.removeLast(history.count - 40) }
        if let d = try? JSONEncoder().encode(history) { UserDefaults.standard.set(d, forKey: historyKey) }
    }

    func clearHistory() { history.removeAll(); UserDefaults.standard.removeObject(forKey: historyKey) }

    private let prefs = Prefs.shared
    private var timer: Timer?
    private var inFlight = false
    private var seenRuns: [String: (run: Int, done: Bool)] = [:]
    private var primed = false
    private var failures = 0
    private var paused = false
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    var working: [Agent] { agents.filter(\.isWorking) }
    var finished: [Agent] { agents.filter { !$0.isWorking } }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.paused = true }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.paused = false; self?.poll() }
        }
        schedule(every: 5)
        poll()
    }

    func refreshSoon() { poll() }

    private func schedule(every seconds: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 1
    }

    func poll() {
        guard !paused, !inFlight else { return }
        let base = prefs.boardURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let key = prefs.boardKey
        guard !base.isEmpty, !key.isEmpty, let url = URL(string: base + "/v1/agents") else {
            link = .notSetUp; return
        }
        inFlight = true
        var req = URLRequest(url: url)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        session.dataTask(with: req) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let reply = data.flatMap { try? JSONDecoder().decode(BoardReply.self, from: $0) }
            let message = error?.localizedDescription
            Task { @MainActor in self?.handle(reply: reply, code: code, error: message) }
        }.resume()
    }

    private func handle(reply: BoardReply?, code: Int, error: String?) {
        inFlight = false
        guard let reply, code == 200 else {
            failures += 1
            link = code == 401 ? .failing("The board key was not accepted") : .failing(error ?? "Board did not answer (\(code))")
            if failures == 3 { schedule(every: 30) } // back off quietly
            return
        }
        if failures >= 3 { schedule(every: 5) }
        failures = 0
        link = .connected
        lastSync = Date()
        detectFinishes(reply.agents)
        if reply.agents != agents { agents = reply.agents }
    }

    private func detectFinishes(_ list: [Agent]) {
        defer { primed = true }
        for a in list {
            let run = a.run ?? 1
            let done = !a.isWorking
            let before = seenRuns[a.id]
            seenRuns[a.id] = (run, done)
            guard primed, done else { continue }
            // New finish: we saw it working, or it started and finished between two polls.
            let wasWorking = before.map { !$0.done || $0.run < run } ?? true
            if wasWorking {
                justFinished.insert(a.id)
                remember(a)
                onFinish(a)
                let id = a.id
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    self?.justFinished.remove(id)
                }
            }
        }
    }

    /// Preview renderer only.
    func setSample(_ list: [Agent], finished: Set<String> = [], history: [AgentRun] = []) {
        self.history = history
        agents = list; link = .connected; lastSync = Date(); justFinished = finished
    }
}

enum Chime {
    private static var sound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "bloom", withExtension: "wav", subdirectory: "Sounds") else { return nil }
        let s = NSSound(contentsOf: url, byReference: true)
        s?.volume = 0.55
        return s
    }()
    private static var low: NSSound? = {
        guard let url = Bundle.main.url(forResource: "fall", withExtension: "wav", subdirectory: "Sounds") else { return nil }
        let s = NSSound(contentsOf: url, byReference: true)
        s?.volume = 0.5
        return s
    }()

    static func play(success: Bool) {
        let s = success ? sound : (low ?? sound)
        s?.stop()
        if s?.play() != true { NSSound.beep() }
    }
}
