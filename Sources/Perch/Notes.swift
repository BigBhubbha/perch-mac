// Quick notes, saved as one small JSON file in ~/Library/Application Support/Perch.
import Foundation
import Combine

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String = ""
    var pinned = false
    var created = Date()
    var updated = Date()

    var title: String {
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let t = first.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Empty note" : t
    }

    var preview: String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst()
        return lines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var selectedID: UUID?

    private let file: URL
    private var saveTask: Task<Void, Never>?

    init(file: URL? = nil) {
        if let file {
            self.file = file
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Perch", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.file = base.appendingPathComponent("notes.json")
        }
        load()
    }

    /// Pinned first, then the most recently touched.
    var sorted: [Note] {
        notes.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.updated > b.updated
        }
    }

    var pinned: Note? { sorted.first(where: \.pinned) }

    var selected: Note? {
        if let id = selectedID, let n = notes.first(where: { $0.id == id }) { return n }
        return sorted.first
    }

    @discardableResult
    func add(_ text: String = "") -> Note {
        let n = Note(text: text)
        notes.append(n)
        selectedID = n.id
        scheduleSave()
        return n
    }

    func update(_ id: UUID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].text != text else { return }
        notes[i].text = text
        notes[i].updated = Date()
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].pinned.toggle()
        scheduleSave()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedID == id { selectedID = sorted.first?.id }
        scheduleSave()
    }

    /// Empty notes do not survive being left.
    func dropEmpty(except keep: UUID? = nil) {
        let before = notes.count
        notes.removeAll { $0.id != keep && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if notes.count != before { scheduleSave() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        notes = (try? dec.decode([Note].self, from: data)) ?? []
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        guard let data = try? enc.encode(notes) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// Flips "- [ ]" and "- [x]" on one line of a note.
    func toggleCheck(_ id: UUID, line: Int) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var lines = notes[i].text.components(separatedBy: "\n")
        guard line < lines.count else { return }
        let l = lines[line]
        if let r = l.range(of: "[ ]") { lines[line] = l.replacingCharacters(in: r, with: "[x]") }
        else if let r = l.range(of: "[x]") ?? l.range(of: "[X]") { lines[line] = l.replacingCharacters(in: r, with: "[ ]") }
        notes[i].text = lines.joined(separator: "\n")
        notes[i].updated = Date()
        scheduleSave()
    }

    /// Preview renderer only: fills the store without touching the real notes file.
    func setSample(_ sample: [Note]) { notes = sample; selectedID = sample.first?.id }
}

// MARK: Tasks and homework

struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var subject: String = ""       // "Chem", "AP Lang"; empty for a plain to-do
    var due: Date?
    var done = false
    var created = Date()

    var isHomework: Bool { !subject.isEmpty }
}

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var items: [TaskItem] = []
    private let file: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        file = base.appendingPathComponent("tasks.json")
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: file), let v = try? dec.decode([TaskItem].self, from: d) { items = v }
    }

    /// Open first by due date (undated last), then the ones finished today.
    var sorted: [TaskItem] {
        let open = items.filter { !$0.done }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.created < b.created
            }
        }
        let doneToday = items.filter(\.done).prefix(4)
        return open + doneToday
    }

    var openCount: Int { items.filter { !$0.done }.count }
    var dueSoon: [TaskItem] { Array(sorted.filter { !$0.done }.prefix(3)) }
    var subjects: [String] { Array(Set(items.map(\.subject).filter { !$0.isEmpty })).sorted() }

    /// Understands a little shorthand: "chem: worksheet 4 fri" becomes Chem, due Friday.
    func add(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var subject = ""
        var title = text
        if let c = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: c) <= 14 {
            subject = String(text[..<c]).trimmingCharacters(in: .whitespaces)
            title = String(text[text.index(after: c)...]).trimmingCharacters(in: .whitespaces)
        }
        let (clean, due) = Self.parseDue(title)
        items.append(TaskItem(title: clean.isEmpty ? title : clean, subject: subject.capitalizedFirst, due: due))
        save()
    }

    func toggle(_ t: TaskItem) {
        guard let i = items.firstIndex(where: { $0.id == t.id }) else { return }
        items[i].done.toggle(); save()
    }

    func delete(_ t: TaskItem) { items.removeAll { $0.id == t.id }; save() }
    func clearDone() { items.removeAll(where: \.done); save() }

    static func parseDue(_ s: String) -> (String, Date?) {
        let words = s.split(separator: " ").map(String.init)
        guard let last = words.last?.lowercased() else { return (s, nil) }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func endOf(_ d: Date) -> Date { cal.date(bySettingHour: 23, minute: 59, second: 0, of: d) ?? d }
        var due: Date?
        let days = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
        if last == "today" || last == "tonight" { due = endOf(today) }
        else if last == "tomorrow" || last == "tmrw" { due = endOf(cal.date(byAdding: .day, value: 1, to: today)!) }
        else if let wd = days[String(last.prefix(3))], last.count <= 9 {
            var c = DateComponents(); c.weekday = wd
            due = cal.nextDate(after: today, matching: c, matchingPolicy: .nextTime).map(endOf)
        } else if last.contains("/"), let d = Self.slash(last) { due = d }
        guard let due else { return (s, nil) }
        return (words.dropLast().joined(separator: " "), due)
    }

    private static func slash(_ s: String) -> Date? {
        let p = s.split(separator: "/").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        var c = Calendar.current.dateComponents([.year], from: Date())
        c.month = p[0]; c.day = p[1]; c.hour = 23; c.minute = 59
        return Calendar.current.date(from: c)
    }

    private func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(items) { try? d.write(to: file, options: .atomic) }
    }

    func preview(_ v: [TaskItem]) { items = v }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// "Today", "Tomorrow", "Fri", "Nov 3", "Late".
func dueText(_ d: Date?) -> String {
    guard let d else { return "" }
    let cal = Calendar.current
    if d < Date() && !cal.isDateInToday(d) { return "Late" }
    if cal.isDateInToday(d) { return "Today" }
    if cal.isDateInTomorrow(d) { return "Tomorrow" }
    let f = DateFormatter()
    f.dateFormat = d.timeIntervalSinceNow < 6 * 86400 ? "EEE" : "MMM d"
    return f.string(from: d)
}
