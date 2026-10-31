// Spill: flick the island down hard and the tab you are on spreads into its own big view.
// Mail becomes a whole inbox, Music becomes your Music library and what it is playing from, and so on.
// Flick up (or press Escape) to gather it back into the island.
import SwiftUI
import AppKit

struct SpillView: View {
    let tab: IslandTab
    var body: some View {
        Group {
            switch tab {
            case .today: TodaySpill()
            case .music: MusicSpill()
            case .notes: NotesSpill()
            case .agents: AgentsSpill()
            case .shelf: ShelfSpill()
            case .mail: MailSpill()
            case .launch: LaunchSpill()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

/// A titled column used by the spill views.
private struct SpillColumn<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).eyebrow()
                Spacer()
                if let trailing { Text(trailing).font(.ui(10.5, .medium)).foregroundStyle(Ink.text3) }
            }
            content
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct Divide: View {
    var body: some View { Rectangle().fill(Ink.hairline).frame(width: 1).padding(.vertical, 4) }
}

// MARK: Today

/// The day as a timeline, with homework and weather beside it and the pool on the right.
private struct TodaySpill: View {
    @EnvironmentObject var calendar: CalendarCenter
    @EnvironmentObject var tasks: TaskStore
    @EnvironmentObject var weather: WeatherCenter

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            SpillColumn(title: Date().formatted(.dateTime.weekday(.wide).month().day()), trailing: "\(calendar.events.count) events") {
                DayTimeline(events: calendar.events)
            }
            .frame(width: 420)
            Divide()
            VStack(alignment: .leading, spacing: 14) {
                if let w = weather.now {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 26))
                            Text("\(Int(w.temp.rounded()))°").font(.serif(30)).foregroundStyle(Ink.text)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(WeatherNow.words(w.code)).font(.ui(11.5, .semibold)).foregroundStyle(Ink.text)
                                Text("H \(Int(w.high.rounded()))°  L \(Int(w.low.rounded()))°").font(.ui(10.5)).foregroundStyle(Ink.text3)
                            }
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 0) {
                            ForEach(Array(w.hours.prefix(6).enumerated()), id: \.offset) { _, h in
                                VStack(spacing: 4) {
                                    Text(h.0.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))).font(.ui(9.5)).foregroundStyle(Ink.text3).lineLimit(1).fixedSize()
                                    Image(systemName: WeatherNow.symbol(h.2, day: true)).symbolRenderingMode(.multicolor).font(.system(size: 12)).frame(height: 14)
                                    Text("\(Int(h.1.rounded()))°").font(.round(10.5, .medium)).foregroundStyle(Ink.text2)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .card(14, padding: 14)
                    .fixedSize(horizontal: false, vertical: true)
                }
                SpillColumn(title: "Homework and to-dos", trailing: "\(tasks.openCount) open") {
                    Scrolling {
                        VStack(spacing: 2) {
                            ForEach(tasks.sorted.prefix(RenderMode.snapshot ? 7 : 40)) { t in TaskRow(task: t).transition(.sinkAndEvaporate) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Divide()
            PoolColumn().frame(width: IslandModel.poolWidth)
        }
    }
}

/// Hours down the side, events as blocks of ink, and a line for now.
struct DayTimeline: View {
    let events: [DayEvent]
    private let hourHeight: CGFloat = 46

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        let startHour = max(0, min(cal.component(.hour, from: now) - 1, 15))
        let hours = Array(startHour..<(startHour + 9))
        let dayStart = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: now) ?? now
        func y(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(dayStart) / 3600) * hourHeight }

        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { h in
                    HStack(alignment: .top, spacing: 10) {
                        Text(cal.date(bySettingHour: h, minute: 0, second: 0, of: now)?.formatted(.dateTime.hour()) ?? "")
                            .font(.round(10, .medium)).foregroundStyle(Ink.text3).frame(width: 40, alignment: .trailing)
                        Rectangle().fill(Ink.hairline).frame(height: 1).padding(.top, 6)
                    }
                    .frame(height: hourHeight, alignment: .top)
                }
            }
            ForEach(events.filter { !$0.allDay }) { e in
                let top = max(0, y(e.start)), bottom = min(CGFloat(hours.count) * hourHeight, y(e.end))
                if bottom > top {
                    EventBlock(event: e)
                        .frame(height: max(26, bottom - top - 3))
                        .padding(.leading, 52)
                        .offset(y: top + 6)
                }
            }
            if now >= dayStart {
                HStack(spacing: 0) {
                    Circle().fill(Ink.accent).frame(width: 7, height: 7)
                    Rectangle().fill(Ink.accent).frame(height: 1.5)
                }
                .padding(.leading, 46)
                .offset(y: y(now) + 3)
            }
        }
        .frame(height: CGFloat(hours.count) * hourHeight, alignment: .top)
        .clipped()
    }
}

private struct EventBlock: View {
    let event: DayEvent
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(event.calendarColor).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.ui(12, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                Text([event.start.formatted(.dateTime.hour().minute()) + " to " + event.end.formatted(.dateTime.hour().minute()), event.location]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.ui(10.5)).foregroundStyle(Ink.text2).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let u = event.meetingURL {
                Chip(title: "Join", symbol: "video.fill") { NSWorkspace.shared.open(u) }
            }
        }
        .padding(.vertical, 5).padding(.trailing, 8).padding(.leading, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(event.calendarColor.opacity(0.16)))
    }
}

// MARK: Music

/// Your Music library: the playlist you are playing from with every track, your playlists, and what you played lately.
private struct MusicSpill: View {
    @EnvironmentObject var music: NowPlayingCenter
    @EnvironmentObject var library: MusicLibrary

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            nowColumn.frame(width: 230)
            Divide()
            queueColumn.frame(maxWidth: .infinity)
            Divide()
            VStack(alignment: .leading, spacing: 16) {
                SpillColumn(title: "Your playlists", trailing: library.playlists.isEmpty ? nil : "\(library.playlists.count)") {
                    if library.playlists.isEmpty {
                        Text(library.source == .music ? "No playlists of your own yet." : "Open Music to see your playlists.")
                            .font(.serif(13).italic()).foregroundStyle(Ink.text3)
                    } else {
                        Scrolling {
                            VStack(spacing: 2) {
                                ForEach(library.playlists.prefix(RenderMode.snapshot ? 5 : 80)) { p in PlaylistRow(playlist: p) }
                            }
                        }
                    }
                }
                .frame(height: 190)
                SpillColumn(title: "Recently played") {
                    VStack(spacing: 4) {
                        ForEach(library.recent.prefix(4)) { r in
                            HStack(spacing: 9) {
                                ArtThumb(image: library.artwork(artist: r.artist, album: r.album), accent: music.accent, side: 28)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(r.title).font(.ui(11.5, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                                    Text(r.artist).font(.ui(10.5)).foregroundStyle(Ink.text3).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Text(shortAge(Date().timeIntervalSince(r.at))).font(.ui(9.5)).foregroundStyle(Ink.text3)
                            }
                            .pourable { Droplet(kind: .song, title: "\(r.title), \(r.artist)", body: nil, url: nil, source: "Music") }
                        }
                    }
                }
            }
            .frame(width: 250)
        }
        .onAppear { library.refresh(preferring: music.track?.bundleID) }
        .onChange(of: music.track?.title) { _ in library.refresh(preferring: music.track?.bundleID) }
    }

    private var nowColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(library.source == .spotify ? "Playing in Spotify" : "Playing from").eyebrow(music.accent)
            Artwork(image: music.artwork ?? library.queue.first.flatMap { library.artwork(artist: $0.artist, album: $0.album) },
                    accent: music.accent, radius: 18)
                .frame(width: 200, height: 200)
                .pourable { music.track.map { Droplet.song($0) } ?? Droplet(kind: .text, title: "Music", body: nil, url: nil, source: "Music") }
            VStack(alignment: .leading, spacing: 3) {
                Text(library.playlistName ?? music.track?.album ?? "Nothing playing").font(.serif(20)).foregroundStyle(Ink.text).lineLimit(2)
                if library.source == .music, !library.queue.isEmpty {
                    let mins = Int(library.queue.reduce(0) { $0 + $1.duration } / 60)
                    Text("\(library.queue.count) songs · \(mins / 60 > 0 ? "\(mins / 60) hr " : "")\(mins % 60) min").font(.ui(11)).foregroundStyle(Ink.text3)
                }
            }
            HStack(spacing: 6) {
                ControlButton(symbol: "backward.fill", size: 13) { music.send(.previous) }
                ControlButton(symbol: music.track?.playing == true ? "pause.fill" : "play.fill", size: 15, prominent: true) { music.send(.toggle) }
                ControlButton(symbol: "forward.fill", size: 13) { music.send(.next) }
            }
        }
    }

    @ViewBuilder private var queueColumn: some View {
        switch library.source {
        case .music:
            SpillColumn(title: "Tracks", trailing: library.loading ? "Reading Music" : nil) {
                if library.queue.isEmpty {
                    Text("Start a playlist or album in Music and its tracks show up here.").font(.serif(14).italic()).foregroundStyle(Ink.text3)
                } else {
                    Scrolling {
                        VStack(spacing: 1) {
                            ForEach(visibleQueue) { t in TrackRow(track: t, current: t.id == library.currentID) }
                        }
                    }
                }
            }
        case .spotify:
            SpillColumn(title: "Tracks") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Spotify does not share its playlists with other apps, so Perch can only see the song that is playing.")
                        .font(.serif(14)).foregroundStyle(Ink.text2).fixedSize(horizontal: false, vertical: true)
                    Chip(title: "Open in Spotify", symbol: "arrow.up.right") { music.openPlayer() }
                }
            }
        case .none:
            SpillColumn(title: "Tracks") {
                Text("Open Music and play something. Perch never opens it for you.").font(.serif(14).italic()).foregroundStyle(Ink.text3)
            }
        }
    }

    /// In previews the list cannot scroll, so start a little before the current track.
    private var visibleQueue: [QueueTrack] {
        guard RenderMode.snapshot, let i = library.queue.firstIndex(where: { $0.id == library.currentID }) else { return Array(library.queue.prefix(200)) }
        return Array(library.queue.dropFirst(max(0, i - 2)).prefix(10))
    }
}

private struct TrackRow: View {
    let track: QueueTrack
    let current: Bool
    @EnvironmentObject var library: MusicLibrary
    @EnvironmentObject var music: NowPlayingCenter
    @State private var hover = false
    var body: some View {
        Button { library.play(track) } label: {
            HStack(spacing: 10) {
                Group {
                    if current { StillBars(color: music.accent) } else {
                        Text("\(track.index)").font(.round(10.5, .medium)).monospacedDigit().foregroundStyle(Ink.text3)
                    }
                }
                .frame(width: 24, alignment: .trailing)
                VStack(alignment: .leading, spacing: 0) {
                    Text(track.title).font(.ui(12, current ? .bold : .medium)).foregroundStyle(current ? music.accent : Ink.text).lineLimit(1)
                    Text(track.artist).font(.ui(10.5)).foregroundStyle(Ink.text3).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(track.album).font(.ui(10.5)).foregroundStyle(Ink.text3).lineLimit(1).frame(maxWidth: 150, alignment: .trailing)
                Text(clock(track.duration)).font(.round(10.5)).monospacedDigit().foregroundStyle(Ink.text3).frame(width: 38, alignment: .trailing)
            }
            .padding(.horizontal, 8).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(current ? music.accent.opacity(0.10) : (hover ? Ink.raised : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Play \(track.title)")
        .pourable { Droplet(kind: .song, title: "\(track.title), \(track.artist)", body: track.album, url: nil, source: "Music") }
    }
}

private struct PlaylistRow: View {
    let playlist: LibraryPlaylist
    @EnvironmentObject var library: MusicLibrary
    @State private var hover = false
    var body: some View {
        Button { library.play(playlist) } label: {
            HStack(spacing: 9) {
                Image(systemName: "music.note.list").font(.system(size: 11)).foregroundStyle(Ink.text3).frame(width: 18)
                Text(playlist.name).font(.ui(12, playlist.name == library.playlistName ? .bold : .medium))
                    .foregroundStyle(playlist.name == library.playlistName ? Ink.accent : Ink.text).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(playlist.count)").font(.round(10)).foregroundStyle(Ink.text3)
                if hover { Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(Ink.text2) }
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Ink.raised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Mail

/// The inbox: search, every thread with its sender, subject and snippet, and a reading pane.
private struct MailSpill: View {
    @EnvironmentObject var gmail: GmailCenter
    @State private var selectedID: String?

    var body: some View {
        if gmail.state != .ready {
            MailPane()
        } else {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Ink.text3)
                        InkField(placeholder: "Search your inbox", text: $gmail.inboxQuery) { Task { await gmail.loadInbox() } }
                        if !gmail.inboxQuery.isEmpty {
                            IconButton(symbol: "xmark.circle.fill", help: "Clear") { gmail.inboxQuery = ""; Task { await gmail.loadInbox() } }
                        }
                    }
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Capsule().fill(Ink.raised))
                    HStack {
                        Text(gmail.inboxQuery.isEmpty ? "Inbox" : "Results").eyebrow()
                        Spacer()
                        Text(gmail.inboxLoading ? "Loading" : "\(gmail.unreadCount) unread").font(.ui(10.5, .medium)).foregroundStyle(Ink.text3)
                    }
                    Scrolling {
                        VStack(spacing: 3) {
                            ForEach(gmail.inbox.prefix(RenderMode.snapshot ? 6 : 25)) { m in
                                ThreadRow(mail: m, selected: m.id == selected?.id) {
                                    selectedID = m.id
                                    Task { await gmail.loadBody(m) }
                                }
                            }
                        }
                    }
                }
                .frame(width: 400)
                Divide()
                reading.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .task { if gmail.inbox.isEmpty { await gmail.loadInbox() } }
        }
    }

    private var selected: MailItem? { gmail.inbox.first { $0.id == selectedID } ?? gmail.inbox.first }

    @ViewBuilder private var reading: some View {
        if let m = selected {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Avatar(name: m.from, side: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.from).font(.ui(13, .semibold)).foregroundStyle(Ink.text)
                        Text(m.fromEmail).font(.ui(10.5)).foregroundStyle(Ink.text3)
                    }
                    Spacer()
                    Text(m.date.formatted(.dateTime.weekday().hour().minute())).font(.ui(10.5)).foregroundStyle(Ink.text3)
                }
                Text(m.subject).font(.serif(21)).foregroundStyle(Ink.text).lineLimit(2)
                Scrolling {
                    Text(gmail.bodies[m.id] ?? m.snippet)
                        .font(.ui(12.5)).foregroundStyle(Ink.text2).lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    if m.unread { Chip(title: "Mark read", symbol: "envelope.open") { withAnimation { gmail.markRead(m) } } }
                    Chip(title: "Archive", symbol: "archivebox") { withAnimation { gmail.archive(m); selectedID = nil } }
                    Chip(title: "Open in Gmail", symbol: "arrow.up.right") { gmail.open(m) }
                    Spacer()
                }
            }
            .onAppear { if !RenderMode.snapshot { Task { await gmail.loadBody(m) } } }
        } else {
            EmptyState(drawing: AnyView(EmptyView()), title: gmail.inboxLoading ? "Loading your inbox" : "Inbox zero",
                       line: gmail.inboxQuery.isEmpty ? "Nothing in your inbox." : "Nothing matches that search.")
        }
    }
}

private struct ThreadRow: View {
    let mail: MailItem
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(mail.unread ? Ink.accent : .clear).frame(width: 6, height: 6).padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(mail.from).font(.ui(12, mail.unread ? .bold : .medium)).foregroundStyle(Ink.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(shortAge(Date().timeIntervalSince(mail.date))).font(.ui(10)).foregroundStyle(Ink.text3)
                    }
                    Text(mail.subject).font(.ui(11.5, mail.unread ? .semibold : .regular)).foregroundStyle(mail.unread ? Ink.text : Ink.text2).lineLimit(1)
                    Text(mail.snippet).font(.ui(10.5)).foregroundStyle(Ink.text3).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Ink.raisedHover : (hover ? Ink.raised : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .pourable { .mail(mail) }
    }
}

// MARK: Notes

/// Notes list, a big editor, and homework on the side.
private struct NotesSpill: View {
    @EnvironmentObject var tasks: TaskStore
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            SpillColumn(title: "Notes") { NoteList() }.frame(width: 240)
            Divide()
            NoteDetail().frame(maxWidth: .infinity)
            Divide()
            SpillColumn(title: "Homework", trailing: "\(tasks.openCount) open") {
                Scrolling {
                    VStack(spacing: 2) { ForEach(tasks.sorted.prefix(RenderMode.snapshot ? 9 : 60)) { t in TaskRow(task: t).transition(.sinkAndEvaporate) } }
                }
            }
            .frame(width: 290)
        }
    }
}

// MARK: Agents

/// The whole board: every agent, what you poured for them, and the history.
private struct AgentsSpill: View {
    @EnvironmentObject var board: AgentBoard
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            SpillColumn(title: "Board", trailing: "\(board.working.count) working, \(board.finished.count) done") {
                if board.agents.isEmpty {
                    EmptyState(drawing: AnyView(DotsDrawing(lit: true)), title: "All quiet",
                               line: "When a Grok Bot starts a job it shows up here. Drop anything on the Agents tab to hand it to one.")
                } else {
                    Scrolling {
                        LazyGridish(items: board.agents, columns: 2) { a in
                            AgentCard(agent: a, blooming: board.justFinished.contains(a.id))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Divide()
            SpillColumn(title: "Poured for agents", trailing: "\(board.requests.filter { $0.status != "done" }.count) waiting") {
                if board.requests.isEmpty {
                    Text("Drop a note, a file or an email on the Agents tab and it waits here until a bot picks it up.")
                        .font(.serif(13).italic()).foregroundStyle(Ink.text3).fixedSize(horizontal: false, vertical: true)
                } else {
                    Scrolling {
                        VStack(spacing: 4) {
                            ForEach(board.requests) { r in RequestRow(request: r).transition(.sinkAndEvaporate) }
                        }
                    }
                }
            }
            .frame(width: 270)
            Divide()
            HistoryColumn().frame(width: 220)
        }
        .onAppear { board.fetchRequests() }
    }
}

private struct RequestRow: View {
    let request: PourRequest
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: request.status == "done" ? "checkmark.circle.fill" : (request.status == "claimed" ? "drop.halffull" : "drop"))
                .font(.system(size: 12)).foregroundStyle(request.status == "open" ? Ink.text3 : Ink.accent).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(request.title ?? "Poured request").font(.ui(12, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                Text(status).font(.ui(10.5)).foregroundStyle(Ink.text3).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.raised))
        .opacity(request.status == "done" ? 0.6 : 1)
    }

    private var status: String {
        let age = shortAge(Date().timeIntervalSince1970 - request.createdAt / 1000)
        switch request.status {
        case "claimed": return "\(request.claimedBy ?? "An agent") is on it"
        case "done": return request.note ?? "Done"
        default: return "From \(request.source ?? "Perch") · waiting \(age)"
        }
    }
}

// MARK: Shelf

/// Every file on the shelf as a big grid, and the whole clipboard history beside it.
private struct ShelfSpill: View {
    @EnvironmentObject var shelf: ShelfStore
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            SpillColumn(title: "Shelf", trailing: "\(shelf.items.count) files") {
                if shelf.items.isEmpty {
                    EmptyState(drawing: AnyView(EmptyView()), title: "Nothing on the shelf", line: "Drop files on the island to keep them here.")
                } else {
                    Scrolling {
                        LazyGridish(items: shelf.items, columns: 6) { FileTile(item: $0) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Divide()
            ClipColumn().frame(width: 330)
        }
    }
}

// MARK: Launch

/// A bigger launcher: all your apps, the Mac actions, and every Shortcut.
private struct LaunchSpill: View {
    @EnvironmentObject var launcher: LauncherStore
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var timers: TimerCenter
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                SpillColumn(title: "Apps", trailing: "\(launcher.apps.count)") {
                    LazyGridish(items: Array(launcher.apps.prefix(16)), columns: 8) { a in AppTile(app: a).scaleEffect(1.12).padding(.vertical, 4) }
                }
                .frame(height: 200)
                SpillColumn(title: "Mac") {
                    HStack(spacing: 8) {
                        ForEach(LauncherStore.Action.allCases) { a in
                            ActionTile(title: a.title, symbol: a.symbol) { launcher.perform(a) { model.onQuickNote() } }
                        }
                        ActionTile(title: "Timer 10m", symbol: "timer") { timers.startCountdown(minutes: 10) }
                        ActionTile(title: "Focus 25m", symbol: "brain.head.profile") { timers.startFocus() }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Divide()
            SpillColumn(title: "Shortcuts", trailing: launcher.shortcuts.isEmpty ? nil : "\(launcher.shortcuts.count)") {
                Scrolling {
                    VStack(spacing: 3) {
                        ForEach((launcher.shortcuts.isEmpty ? launcher.pinnedShortcuts : launcher.shortcuts).prefix(RenderMode.snapshot ? 9 : 200), id: \.self) { name in
                            ShortcutRow(name: name, choosing: true)
                        }
                    }
                }
            }
            .frame(width: 300)
        }
        .onAppear { if launcher.shortcuts.isEmpty, !RenderMode.snapshot { launcher.loadShortcuts() } }
    }
}
