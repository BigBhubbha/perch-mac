// Shelf: files you dropped on the island, and what you copied lately.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfPane: View {
    @EnvironmentObject var shelf: ShelfStore
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(shelf.items.isEmpty ? "Shelf" : "\(shelf.items.count) on the shelf").eyebrow()
                    Spacer()
                    if !shelf.items.isEmpty {
                        Chip(title: "AirDrop all", symbol: "dot.radiowaves.left.and.right") { shelf.airdrop(shelf.items) }
                        IconButton(symbol: "xmark", help: "Clear the shelf") { withAnimation { shelf.clearShelf() } }
                    }
                }
                if shelf.items.isEmpty {
                    EmptyState(drawing: AnyView(TrayDrawing()), title: "Drop files here",
                               line: "Drag anything up to the island to keep it close. Drag it back out, AirDrop it, or open it.")
                } else {
                    Scrolling {
                        LazyGridish(items: shelf.items, columns: 6) { item in FileTile(item: item) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            ClipColumn().frame(width: 258)
        }
        .padding(.vertical, 12)
    }
}

/// A simple grid that ImageRenderer can draw (LazyVGrid cannot).
struct LazyGridish<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let columns: Int
    @ViewBuilder let cell: (Item) -> Cell
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { i in
                HStack(spacing: 8) {
                    ForEach(items[i..<min(i + columns, items.count)]) { cell($0) }
                    if items.count - i < columns {
                        ForEach(0..<(columns - (items.count - i)), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                    }
                }
            }
        }
    }
}

private struct FileTile: View {
    let item: ShelfItem
    @EnvironmentObject var shelf: ShelfStore
    @State private var hover = false
    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: shelf.icon(for: item)).resizable().aspectRatio(contentMode: .fit).frame(width: 44, height: 44)
                if hover {
                    Button { withAnimation { shelf.remove(item) } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(Ink.text2, Ink.card)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -4)
                }
            }
            Text(item.name).font(.ui(10.5, .medium)).foregroundStyle(Ink.text2).lineLimit(1).truncationMode(.middle)
            HStack(spacing: 0) {
                IconButton(symbol: "dot.radiowaves.left.and.right", help: "AirDrop", size: 10) { shelf.airdrop([item]) }
                IconButton(symbol: "magnifyingglass", help: "Show in Finder", size: 10) { shelf.reveal(item) }
            }
            .opacity(hover ? 1 : 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover ? Ink.raisedHover : Ink.raised))
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .pourable { .file(item.url) }
        .help(item.path)
    }
}

private struct ClipColumn: View {
    @EnvironmentObject var shelf: ShelfStore
    @EnvironmentObject var prefs: Prefs
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Clipboard").eyebrow()
                Spacer()
                if !shelf.clips.isEmpty {
                    Button { withAnimation { shelf.clearClips() } } label: {
                        Text("Clear").font(.ui(10.5, .medium)).foregroundStyle(Ink.text3)
                    }.buttonStyle(.plain)
                }
            }
            if !prefs.clipboardOn {
                Text("Clipboard history is off. Turn it on in Settings.").font(.serif(12.5).italic()).foregroundStyle(Ink.text3)
                Spacer(minLength: 0)
            } else if shelf.clips.isEmpty {
                Text("Copy something and it lands here. Passwords from password managers are skipped.")
                    .font(.serif(12.5).italic()).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Scrolling {
                    VStack(spacing: 3) {
                        ForEach(shelf.sortedClips.prefix(14)) { c in ClipRow(clip: c) }
                    }
                }
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) { Rectangle().fill(Ink.hairline).frame(width: 1) }
    }
}

private struct ClipRow: View {
    let clip: Clip
    @EnvironmentObject var shelf: ShelfStore
    @State private var hover = false
    @State private var copied = false
    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 16)
            Text(clip.text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "))
                .font(clip.kind == "code" ? .system(size: 11, design: .monospaced) : .ui(11.5))
                .foregroundStyle(Ink.text).lineLimit(1)
            Spacer(minLength: 4)
            if copied {
                Text("Copied").font(.ui(10, .semibold)).foregroundStyle(Ink.accent)
            } else if hover || clip.pinned {
                IconButton(symbol: clip.pinned ? "pin.fill" : "pin", on: clip.pinned, help: "Pin", size: 9.5) { shelf.togglePin(clip) }
            } else {
                Text(shortAge(Date().timeIntervalSince(clip.copied))).font(.ui(9.5)).foregroundStyle(Ink.text3)
            }
        }
        .padding(.horizontal, 8).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Ink.raisedHover : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .pourable { .clip(clip) }
        .onTapGesture {
            shelf.copy(clip)
            withAnimation { copied = true }
            Task { @MainActor in try? await Task.sleep(nanoseconds: 1_200_000_000); withAnimation { copied = false } }
        }
        .help("Click to copy")
    }

    @ViewBuilder private var icon: some View {
        switch clip.kind {
        case "link": Image(systemName: "link").font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.sky)
        case "color":
            Circle().fill(Color(hex: clip.text.trimmingCharacters(in: CharacterSet(charactersIn: "# \n"))) ?? Ink.text3).frame(width: 10, height: 10)
        case "code": Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Ink.amber)
        default: Image(systemName: "text.quote").font(.system(size: 10)).foregroundStyle(Ink.text3)
        }
    }
}

extension Color {
    init?(hex: String) {
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
