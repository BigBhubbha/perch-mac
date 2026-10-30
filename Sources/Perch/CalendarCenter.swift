// Your next few events from the Calendar app (iCloud, Google, Exchange, anything you added there).
// Asks for calendar access once, when you press the button.
import EventKit
import AppKit
import SwiftUI

struct DayEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var location: String?
    var calendarColor: Color
    var meetingURL: URL?
}

@MainActor
final class CalendarCenter: ObservableObject {
    @Published private(set) var events: [DayEvent] = []
    @Published private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    var onSoon: (DayEvent) -> Void = { _ in }

    private let store = EKEventStore()
    private var timer: Timer?
    private var announced = Set<String>()
    private var observer: NSObjectProtocol?

    var granted: Bool {
        if #available(macOS 14.0, *) { return access == .fullAccess }
        return access == .authorized
    }

    func start() {
        guard Prefs.shared.calendarOn, granted else { return }
        reload()
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSoon() }
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] ok, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.access = EKEventStore.authorizationStatus(for: .event)
                    if ok { Prefs.shared.calendarOn = true; self.start() }
                }
            }
        }
    }

    func reload() {
        guard granted else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: 36, to: now) ?? now
        let pred = store.predicateForEvents(withStart: Calendar.current.startOfDay(for: now), end: end, calendars: nil)
        events = store.events(matching: pred)
            .filter { $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { e in
                DayEvent(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "Untitled", start: e.startDate, end: e.endDate,
                         allDay: e.isAllDay, location: e.location, calendarColor: Color(nsColor: e.calendar.color ?? .systemBlue),
                         meetingURL: Self.meetingLink(e))
            }
        checkSoon()
    }

    /// The next timed event that has not ended.
    var next: DayEvent? { events.first { !$0.allDay } }

    private func checkSoon() {
        let now = Date()
        if let n = next, n.start > now, n.start.timeIntervalSince(now) < 5 * 60, !announced.contains(n.id) {
            announced.insert(n.id)
            onSoon(n)
        }
    }

    static func meetingLink(_ e: EKEvent) -> URL? {
        if let u = e.url, isMeeting(u.absoluteString) { return u }
        let hay = [e.location ?? "", e.notes ?? ""].joined(separator: " ")
        let pattern = #"https://[^\s<>"]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com|facetime\.apple\.com)[^\s<>"]*"#
        if let r = hay.range(of: pattern, options: .regularExpression) { return URL(string: String(hay[r])) }
        return nil
    }

    static func isMeeting(_ s: String) -> Bool {
        ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com", "facetime.apple.com"].contains { s.contains($0) }
    }

    func preview(_ e: [DayEvent]) { events = e; access = .fullAccess }
}
