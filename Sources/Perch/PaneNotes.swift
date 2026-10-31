// Notes with light markdown and tickable checklists, plus tasks and homework by class.
import SwiftUI
import AppKit

struct NotesPane: View {
    @EnvironmentObject var notes: NotesStore
    @EnvironmentObject var tasks: TaskStore
    @AppStorage("notes.mode") private var mode = "notes"

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 2) {
                    seg("notes", "Notes", count: notes.notes.count)
                    seg("tasks", "Homework", count: tasks.openCount)
                }
                .padding(2)
                .background(Capsule().fill(Ink.raised))
                if mode == "notes" {
                    NoteList()
                } else {
                    SubjectList()
                }
            }
            .frame(width: 196)

            Rectangle().fill(Ink.hairline).frame(width: 1)

            if mode == "notes" { NoteDetail() } else { TaskBoard() }
        }
        .padding(.vertical, 12)
    }

    private func seg(_ id: String, _ title: String, count: Int) -> some View {
        let on = mode == id
        return Button { withAnimation(Motion.tab) { mode = id } } label: {
            HStack(spacing: 5) {
                Text(title).font(.ui(11, .semibold))
                if count > 0 { Text("\(count)").font(.round(9.5, .bold)).foregroundStyle(on ? Ink.accent : Ink.text3) }
            }
            .foregroundStyle(on ? Ink.text : Ink.text3)
            .frame(maxWidth: .infinity).frame(height: 22)
            .background(Capsule().fill(on ? Ink.raisedHover : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Notes

private struct NoteList: View {
    @EnvironmentObject var notes: NotesStore
    @EnvironmentObject var model: IslandModel
    var body: some View {
        VStack(spacing: 6) {
            Scrolling {
                VStack(spacing: 2) {
                    ForEach(notes.sorted) { n in
                        NoteRow(note: n, selected: notes.selected?.id == n.id) { notes.selectedID = n.id }
                    }
                }
            }
            Button { notes.add(); model.noteFocus = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text("New note").font(.ui(11.5, .semibold))
                    Spacer()
                }
                .foregroundStyle(Ink.text2)
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Ink.raised))
            }
            .buttonStyle(.plain)
        }
    }
}

struct NoteRow: View {
    let note: Note
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if note.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(Ink.accent)
                    }
                    Text(Markdown.plain(note.title)).font(.ui(12, .medium)).foregroundStyle(selected ? Ink.text : Ink.text2).lineLimit(1)
                }
                Text(note.preview.isEmpty ? shortAge(Date().timeIntervalSince(note.updated)) : Markdown.plainLines(note.text))
                    .font(.ui(10.5)).foregroundStyle(Ink.text3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Ink.raisedHover : (hover ? Ink.raised : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .pourable { .note(note) }
    }
}

private struct NoteDetail: View {
    @EnvironmentObject var notes: NotesStore
    @EnvironmentObject var model: IslandModel
    @AppStorage("notes.reading") private var reading = true

    var body: some View {
        if let n = notes.selected {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(n.updated, format: .dateTime.weekday(.wide).hour().minute()).eyebrow()
                    Spacer()
                    IconButton(symbol: reading && !model.noteFocus ? "pencil" : "eye", help: reading ? "Edit" : "Read") {
                        model.noteFocus = false
                        reading.toggle()
                    }
                    IconButton(symbol: n.pinned ? "pin.fill" : "pin", on: n.pinned, help: n.pinned ? "Unpin" : "Pin to Today") {
                        withAnimation(Motion.snap) { notes.togglePin(n.id) }
                    }
                    IconButton(symbol: "doc.on.doc", help: "Copy") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(n.text, forType: .string)
                    }
                    IconButton(symbol: "trash", help: "Delete") { withAnimation(.easeOut(duration: 0.2)) { notes.delete(n.id) } }
                }
                if (reading && !model.noteFocus) || RenderMode.snapshot {
                    Scrolling { MarkdownNote(note: n).padding(.trailing, 6) }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { reading = false }
                } else {
                    TextEditor(text: Binding(get: { notes.notes.first(where: { $0.id == n.id })?.text ?? "" },
                                             set: { notes.update(n.id, text: $0) }))
                        .font(.serif(14.5))
                        .foregroundStyle(Ink.text)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .background(Color.clear)
                        .tint(Ink.accent)
                        .lineSpacing(3)
                        .id(n.id)
                }
            }
        } else {
            EmptyState(drawing: AnyView(Image(systemName: "text.alignleft").font(.system(size: 30)).foregroundStyle(Ink.text3).frame(width: 60)),
                       title: "A blank page",
                       line: "Write in plain text. # makes a heading, **bold** works, and - [ ] makes a box you can tick.",
                       action: ("Start a note", { notes.add(); model.noteFocus = true }))
        }
    }
}

/// A tiny markdown reader: headings, bullets, checklists, bold and italics, links.
private struct MarkdownNote: View {
    let note: Note
    @EnvironmentObject var notes: NotesStore

    var body: some View {
        let lines = note.text.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, raw in
                line(raw, index: i)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func line(_ raw: String, index: Int) -> some View {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            Color.clear.frame(height: 4)
        } else if t.hasPrefix("- [ ]") || t.hasPrefix("- [x]") || t.hasPrefix("- [X]") {
            let done = !t.hasPrefix("- [ ]")
            Button { withAnimation(Motion.snap) { notes.toggleCheck(note.id, line: index) } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: done ? "checkmark.square.fill" : "square").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(done ? Ink.accent : Ink.text3)
                    Text(Markdown.attributed(String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)))
                        .font(.serif(14.5)).foregroundStyle(done ? Ink.text3 : Ink.text)
                        .strikethrough(done, color: Ink.text3)
                }
            }
            .buttonStyle(.plain)
        } else if t.hasPrefix("# ") {
            Text(Markdown.attributed(String(t.dropFirst(2)))).font(.serif(19, .semibold)).foregroundStyle(Ink.text).padding(.top, index == 0 ? 0 : 4)
        } else if t.hasPrefix("## ") {
            Text(Markdown.attributed(String(t.dropFirst(3)))).font(.ui(12, .semibold)).foregroundStyle(Ink.accent).padding(.top, 4)
        } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(Ink.text3).frame(width: 4, height: 4).offset(y: -3)
                Text(Markdown.attributed(String(t.dropFirst(2)))).font(.serif(14.5)).foregroundStyle(Ink.text)
            }
        } else if index == 0 {
            Text(Markdown.attributed(t)).font(.serif(17, .semibold)).foregroundStyle(Ink.text)
        } else {
            Text(Markdown.attributed(t)).font(.serif(14.5)).foregroundStyle(Ink.text2).lineSpacing(2)
        }
    }
}

enum Markdown {
    static func attributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
    /// Everything after the first line, without markdown marks.
    static func plainLines(_ s: String) -> String {
        s.components(separatedBy: "\n").dropFirst().map { plain($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }

    static func plain(_ s: String) -> String {
        var t = s
        for p in ["## ", "# ", "- [ ] ", "- [x] ", "- [X] ", "- ", "* "] where t.hasPrefix(p) { t = String(t.dropFirst(p.count)) }
        return t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
    }
}

// MARK: Homework

private struct SubjectList: View {
    @EnvironmentObject var tasks: TaskStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let subjects = tasks.subjects
            if subjects.isEmpty {
                Text("Type a class, a colon, then the task. Add a day at the end and it becomes the due date.")
                    .font(.ui(11)).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                Text("chem: lab report fri").font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.text2)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Ink.raised))
            } else {
                ForEach(subjects, id: \.self) { s in
                    let open = tasks.items.filter { $0.subject == s && !$0.done }.count
                    HStack(spacing: 8) {
                        Circle().fill(NameColor.of(s)).frame(width: 7, height: 7)
                        Text(s).font(.ui(12, .medium)).foregroundStyle(Ink.text2)
                        Spacer()
                        Text(open == 0 ? "done" : "\(open)").font(.round(10.5, .semibold)).foregroundStyle(open == 0 ? Ink.text3 : Ink.text2)
                    }
                    .padding(.horizontal, 8).frame(height: 24)
                }
            }
            Spacer(minLength: 0)
            if tasks.items.contains(where: \.done) {
                Button { withAnimation { tasks.clearDone() } } label: {
                    Text("Clear finished").font(.ui(11, .medium)).foregroundStyle(Ink.text3)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
        }
    }
}

private struct TaskBoard: View {
    @EnvironmentObject var tasks: TaskStore
    @State private var draft = ""
    var body: some View {
        VStack(spacing: 8) {
            InkField(placeholder: "Add homework or a to-do, like  apush: dbq outline thu", text: $draft, serif: true) {
                tasks.add(draft); draft = ""
            }
            if tasks.items.isEmpty {
                Text("Nothing due. Enjoy it.").font(.serif(16).italic()).foregroundStyle(Ink.text3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Scrolling {
                    VStack(spacing: 3) {
                        ForEach(tasks.sorted) { t in TaskRow(task: t) }
                    }
                }
            }
        }
    }
}

private struct TaskRow: View {
    let task: TaskItem
    @EnvironmentObject var tasks: TaskStore
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            Button { withAnimation(Motion.snap) { tasks.toggle(task) } } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle").font(.system(size: 14))
                    .foregroundStyle(task.done ? Ink.accent : Ink.text3)
            }
            .buttonStyle(.plain)
            if task.isHomework {
                Text(task.subject).font(.ui(10, .bold)).foregroundStyle(NameColor.of(task.subject))
                    .padding(.horizontal, 7).frame(height: 18)
                    .background(Capsule().fill(NameColor.of(task.subject).opacity(0.14)))
            }
            Text(task.title).font(.serif(14)).foregroundStyle(task.done ? Ink.text3 : Ink.text).strikethrough(task.done, color: Ink.text3).lineLimit(1)
            Spacer(minLength: 6)
            if hover {
                IconButton(symbol: "trash", help: "Delete") { withAnimation { tasks.delete(task) } }
            }
            let due = dueText(task.due)
            if !due.isEmpty && !task.done {
                Text(due).font(.ui(10.5, .semibold))
                    .foregroundStyle(due == "Late" ? Ink.coral : (due == "Today" ? Ink.accent : Ink.text3))
            }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hover ? Ink.raised : .clear))
        .onHover { hover = $0 }
        .pourable { Droplet(kind: .text, title: task.title, body: task.subject.isEmpty ? nil : task.subject, url: nil, source: "Homework") }
    }
}
