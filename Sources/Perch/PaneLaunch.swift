// Launch: pinned apps, your Shortcuts and a few one-tap Mac actions.
import SwiftUI
import AppKit

struct LaunchPane: View {
    @EnvironmentObject var launcher: LauncherStore
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var timers: TimerCenter
    @State private var showAllShortcuts = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Apps").eyebrow()
                    Spacer()
                    IconButton(symbol: "plus", help: "Add apps") { model.showingMenu = true; launcher.pickApps(); model.showingMenu = false }
                }
                HStack(spacing: 6) {
                    ForEach(launcher.apps.prefix(8)) { a in AppTile(app: a) }
                    if launcher.apps.count < 8 {
                        ForEach(0..<(8 - min(8, launcher.apps.count)), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
                Text("Mac").eyebrow().padding(.top, 4)
                HStack(spacing: 6) {
                    ForEach(LauncherStore.Action.allCases) { a in
                        ActionTile(title: a.title, symbol: a.symbol) { launcher.perform(a) { model.onQuickNote() } }
                    }
                    ActionTile(title: "Timer 10m", symbol: "timer") { timers.startCountdown(minutes: 10) }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Shortcuts").eyebrow()
                    Spacer()
                    Button { showAllShortcuts.toggle(); if showAllShortcuts { launcher.loadShortcuts() } } label: {
                        Text(showAllShortcuts ? "Done" : "Choose").font(.ui(10.5, .semibold)).foregroundStyle(Ink.text3)
                    }.buttonStyle(.plain)
                }
                let list = showAllShortcuts ? launcher.shortcuts : launcher.pinnedShortcuts
                if list.isEmpty {
                    Text(showAllShortcuts ? "Looking for your Shortcuts" : "Pin your Shortcuts here and run them with one click.")
                        .font(.serif(12.5).italic()).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                } else {
                    Scrolling {
                        VStack(spacing: 3) {
                            ForEach(list, id: \.self) { name in
                                ShortcutRow(name: name, choosing: showAllShortcuts)
                            }
                        }
                    }
                }
                if let r = launcher.lastResult, !showAllShortcuts {
                    Text(r).font(.ui(10)).foregroundStyle(Ink.text3).lineLimit(1)
                }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) { Rectangle().fill(Ink.hairline).frame(width: 1) }
            .frame(width: 236)
        }
        .padding(.vertical, 12)
    }
}

struct AppTile: View {
    let app: LaunchApp
    @EnvironmentObject var launcher: LauncherStore
    @State private var hover = false
    var body: some View {
        Button { launcher.launch(app) } label: {
            VStack(spacing: 4) {
                Image(nsImage: launcher.icon(app)).resizable().aspectRatio(contentMode: .fit).frame(width: 38, height: 38)
                    .scaleEffect(hover ? 1.08 : 1)
                Text(app.name).font(.ui(9.5, .medium)).foregroundStyle(Ink.text3).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover ? Ink.raised : .clear))
        }
        .buttonStyle(PressStyle())
        .onHover { h in withAnimation(Motion.snap) { hover = h } }
        .contextMenu { Button("Remove from Perch") { launcher.remove(app) } }
    }
}

struct ActionTile: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(hover ? Ink.accent : Ink.text2)
                Text(title).font(.ui(9.5, .medium)).foregroundStyle(Ink.text3).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover ? Ink.raisedHover : Ink.raised))
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
    }
}

struct ShortcutRow: View {
    let name: String
    let choosing: Bool
    @EnvironmentObject var launcher: LauncherStore
    @State private var hover = false
    var body: some View {
        let pinned = launcher.pinnedShortcuts.contains(name)
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 10)).foregroundStyle(NameColor.of(name))
            Text(name).font(.ui(11.5, .medium)).foregroundStyle(Ink.text).lineLimit(1)
            Spacer(minLength: 4)
            if choosing {
                Image(systemName: pinned ? "checkmark.circle.fill" : "plus.circle").font(.system(size: 12)).foregroundStyle(pinned ? Ink.accent : Ink.text3)
            } else if launcher.runningShortcut == name {
                ProgressView().controlSize(.mini)
            } else if hover {
                Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(Ink.accent)
            }
        }
        .padding(.horizontal, 8).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Ink.raisedHover : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { choosing ? launcher.togglePin(name) : launcher.runShortcut(name) }
    }
}
