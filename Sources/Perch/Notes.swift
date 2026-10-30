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

    /// Preview renderer only: fills the store without touching the real notes file.
    func setSample(_ sample: [Note]) { notes = sample; selectedID = sample.first?.id }
}
