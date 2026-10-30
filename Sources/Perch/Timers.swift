// A countdown and a pomodoro that live in the island. They survive a relaunch.
import Foundation
import Combine

@MainActor
final class TimerCenter: ObservableObject {
    enum Kind: String, Codable { case countdown, focus, rest }

    struct Running: Codable, Equatable {
        var kind: Kind
        var label: String
        var total: TimeInterval
        var endsAt: Date?          // nil while paused
        var remainingWhenPaused: TimeInterval
        var round: Int             // pomodoro round, 1 based
    }

    @Published private(set) var current: Running?
    @Published private(set) var now = Date()
    @Published private(set) var focusRoundsToday = 0

    var onFinish: (Running) -> Void = { _ in }

    private var ticker: Timer?
    private let key = "timer.current"
    private let roundsKey = "timer.rounds"

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let r = try? JSONDecoder().decode(Running.self, from: data) {
            current = r
        }
        if let rec = UserDefaults.standard.dictionary(forKey: roundsKey),
           let day = rec["day"] as? String, day == Self.today, let n = rec["n"] as? Int {
            focusRoundsToday = n
        }
        if current != nil { startTicking() }
    }

    static var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    var remaining: TimeInterval {
        guard let c = current else { return 0 }
        if let end = c.endsAt { return max(0, end.timeIntervalSince(now)) }
        return c.remainingWhenPaused
    }

    var progress: Double {
        guard let c = current, c.total > 0 else { return 0 }
        return 1 - remaining / c.total
    }

    var isPaused: Bool { current != nil && current?.endsAt == nil }

    func startCountdown(minutes: Double, label: String = "Timer") {
        let t = minutes * 60
        current = Running(kind: .countdown, label: label, total: t, endsAt: Date().addingTimeInterval(t), remainingWhenPaused: t, round: 1)
        save(); startTicking()
    }

    func startFocus(round: Int = 1) {
        let t = Prefs.shared.pomodoroWork * 60
        current = Running(kind: .focus, label: "Focus", total: t, endsAt: Date().addingTimeInterval(t), remainingWhenPaused: t, round: round)
        save(); startTicking()
    }

    func startRest(round: Int) {
        let t = Prefs.shared.pomodoroBreak * 60
        current = Running(kind: .rest, label: "Break", total: t, endsAt: Date().addingTimeInterval(t), remainingWhenPaused: t, round: round)
        save(); startTicking()
    }

    func add(minutes: Double) {
        guard var c = current else { return }
        if let end = c.endsAt { c.endsAt = end.addingTimeInterval(minutes * 60) } else { c.remainingWhenPaused += minutes * 60 }
        c.total += minutes * 60
        current = c; save()
    }

    func togglePause() {
        guard var c = current else { return }
        if let end = c.endsAt {
            c.remainingWhenPaused = max(0, end.timeIntervalSinceNow)
            c.endsAt = nil
        } else {
            c.endsAt = Date().addingTimeInterval(c.remainingWhenPaused)
        }
        current = c; save()
    }

    func cancel() {
        current = nil; save(); ticker?.invalidate(); ticker = nil
    }

    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker?.tolerance = 0.1
        tick()
    }

    private func tick() {
        now = Date()
        guard let c = current, let end = c.endsAt, end <= now else { return }
        // Finished.
        onFinish(c)
        switch c.kind {
        case .countdown:
            cancel()
        case .focus:
            focusRoundsToday += 1
            UserDefaults.standard.set(["day": Self.today, "n": focusRoundsToday] as [String: Any], forKey: roundsKey)
            startRest(round: c.round)
        case .rest:
            startFocus(round: c.round + 1)
        }
    }

    private func save() {
        if let c = current, let data = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// For previews.
    func preview(_ r: Running?, now: Date) {
        current = r; self.now = now
    }
}
