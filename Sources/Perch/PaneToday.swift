// Today: the glance. What is playing, what is next, the timer, the weather, the agents and what is due.
import SwiftUI
import AppKit

struct TodayPane: View {
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: IslandModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 10) {
                DayCard()
                if prefs.isCardShown(.weather) { WeatherCard() }
            }
            .frame(width: 196)
            VStack(spacing: 10) {
                if prefs.isCardShown(.music) { MiniPlayerCard() }
                if prefs.isCardShown(.calendar) { UpNextCard() }
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 10) {
                if prefs.isCardShown(.timer) { TimerCard() }
                if prefs.isCardShown(.agents) { AgentsMiniCard() }
                if prefs.isCardShown(.tasks) { DueCard() }
            }
            .frame(width: 214)
        }
        .padding(.vertical, 12)
    }
}

private struct DayCard: View {
    @EnvironmentObject var notes: NotesStore
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 2) {
                Text(ctx.date, format: .dateTime.weekday(.wide)).eyebrow(Ink.accent)
                Text(ctx.date, format: .dateTime.month(.wide).day())
                    .font(.serif(22, .regular)).foregroundStyle(Ink.text)
                Spacer(minLength: 4)
                if let p = notes.pinned {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "pin.fill").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Ink.accent).padding(.top, 2)
                        Text(p.title).font(.serif(12.5).italic()).foregroundStyle(Ink.text2).lineLimit(2)
                    }
                } else {
                    Text(greeting(ctx.date)).font(.serif(12.5).italic()).foregroundStyle(Ink.text3)
                }
            }
            .card()
        }
    }

    private func greeting(_ d: Date) -> String {
        let h = Calendar.current.component(.hour, from: d)
        switch h {
        case 5..<12: return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default: return "Late one. Go to sleep soon."
        }
    }
}

private struct WeatherCard: View {
    @EnvironmentObject var weather: WeatherCenter
    @EnvironmentObject var prefs: Prefs
    var body: some View {
        Group {
            if let w = weather.now {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 20))
                        Text("\(Int(w.temp.rounded()))°").font(.round(24, .semibold)).monospacedDigit().foregroundStyle(Ink.text)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("H \(Int(w.high.rounded()))°  L \(Int(w.low.rounded()))°").font(.ui(10, .medium)).monospacedDigit().foregroundStyle(Ink.text2)
                            Text(w.rainChance > 0 ? "\(w.rainChance)% rain" : w.words).font(.ui(10)).foregroundStyle(Ink.text3)
                        }
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(w.hours.prefix(5).enumerated()), id: \.offset) { _, h in
                            VStack(spacing: 3) {
                                Text(h.0, format: .dateTime.hour(.defaultDigits(amPM: .narrow))).font(.ui(9, .medium)).foregroundStyle(Ink.text3)
                                Image(systemName: WeatherNow.symbol(h.2, day: true)).symbolRenderingMode(.multicolor).font(.system(size: 10))
                                Text("\(Int(h.1.rounded()))°").font(.ui(10, .semibold)).monospacedDigit().foregroundStyle(Ink.text2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .card(padding: 11)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weather").eyebrow()
                    Text(weather.failed ? "Offline right now" : "Checking \(prefs.weatherCity)")
                        .font(.serif(13).italic()).foregroundStyle(Ink.text3)
                }
                .card()
            }
        }
    }
}

private struct MiniPlayerCard: View {
    @EnvironmentObject var music: NowPlayingCenter
    @EnvironmentObject var model: IslandModel
    var body: some View {
        if let t = music.track {
            HStack(spacing: 12) {
                Artwork(image: music.artwork, accent: music.accent, radius: 11).frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title).font(.ui(13, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                    Text(t.artist).font(.ui(11.5)).foregroundStyle(Ink.text2).lineLimit(1)
                    if let d = t.duration, d > 0 {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            LevelBar(level: (t.elapsed(at: ctx.date) ?? 0) / d, tint: music.accent).padding(.top, 7)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ControlButton(symbol: "backward.fill", size: 11) { music.send(.previous) }
                    ControlButton(symbol: t.playing ? "pause.fill" : "play.fill", size: 14) { music.send(.toggle) }
                    ControlButton(symbol: "forward.fill", size: 11) { music.send(.next) }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 74)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.raised)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [music.accent.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing))
                }
            )
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Motion.tab) { model.tab = .music } }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "music.note").font(.system(size: 14)).foregroundStyle(Ink.text3)
                    .frame(width: 34, height: 34).background(Circle().fill(Ink.raised))
                Text("Nothing playing").font(.serif(14).italic()).foregroundStyle(Ink.text3)
                Spacer()
            }
            .padding(10).frame(height: 74).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.raised))
        }
    }
}

private struct UpNextCard: View {
    @EnvironmentObject var calendar: CalendarCenter
    @EnvironmentObject var gmail: GmailCenter
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Up next").eyebrow()
                Spacer()
                if prefs.isCardShown(.mail), gmail.state == .ready {
                    Button { withAnimation(Motion.tab) { model.tab = .mail } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope.fill").font(.system(size: 9))
                            Text(gmail.unreadCount == 0 ? "Inbox zero" : "\(gmail.unreadCount) unread").font(.ui(10.5, .semibold))
                        }
                        .foregroundStyle(gmail.unreadCount == 0 ? Ink.text3 : Ink.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !calendar.granted || !prefs.calendarOn {
                HStack(spacing: 10) {
                    Text("See your next class or meeting here.").font(.serif(13).italic()).foregroundStyle(Ink.text3)
                    Spacer()
                    Chip(title: "Allow Calendar", symbol: "calendar") { calendar.requestAccess() }
                }
                Spacer(minLength: 0)
            } else if calendar.events.isEmpty {
                Text("Nothing else today.").font(.serif(14).italic()).foregroundStyle(Ink.text3)
                Spacer(minLength: 0)
            } else {
                ForEach(calendar.events.prefix(3)) { e in EventRow(event: e) }
                Spacer(minLength: 0)
            }
        }
        .card()
    }
}

struct EventRow: View {
    let event: DayEvent
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let live = event.start <= ctx.date && event.end > ctx.date
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5).fill(event.calendarColor).frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title).font(.ui(12, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                    Text(event.allDay ? "All day" : timeRange).font(.ui(10.5)).foregroundStyle(Ink.text3).lineLimit(1)
                }
                Spacer(minLength: 6)
                if let u = event.meetingURL {
                    Chip(title: "Join", symbol: "video.fill", filled: live || event.start.timeIntervalSince(ctx.date) < 600) {
                        NSWorkspace.shared.open(u)
                    }
                } else if !event.allDay {
                    Text(live ? "now" : untilText(event.start.timeIntervalSince(ctx.date)))
                        .font(.round(11, .semibold)).monospacedDigit().foregroundStyle(live ? Ink.accent : Ink.text2)
                }
            }
        }
    }

    private var timeRange: String {
        let f = DateFormatter(); f.dateFormat = "h:mm"
        var s = f.string(from: event.start) + " to " + f.string(from: event.end)
        if let l = event.location, !l.isEmpty, !CalendarCenter.isMeeting(l) { s += "  ·  " + l }
        return s
    }
}

struct TimerCard: View {
    @EnvironmentObject var timers: TimerCenter
    var body: some View {
        Group {
            if let c = timers.current {
                let tint = c.kind == .rest ? Ink.sky : Ink.accent
                HStack(spacing: 12) {
                    ZStack {
                        ProgressRing(progress: timers.progress, color: tint, line: 3.5)
                        Image(systemName: c.kind == .countdown ? "timer" : (c.kind == .focus ? "brain.head.profile" : "cup.and.saucer.fill"))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(clock(timers.remaining)).font(.round(20, .semibold)).monospacedDigit().foregroundStyle(Ink.text)
                        Text(c.kind == .countdown ? c.label : "\(c.label), round \(c.round)").font(.ui(10.5)).foregroundStyle(Ink.text3)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        IconButton(symbol: timers.isPaused ? "play.fill" : "pause.fill", help: "Pause") { timers.togglePause() }
                        IconButton(symbol: "xmark", help: "Stop") { timers.cancel() }
                    }
                }
                .card(padding: 10)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Timer").eyebrow()
                        Spacer()
                        if timers.focusRoundsToday > 0 {
                            Text("\(timers.focusRoundsToday) focus today").font(.ui(10, .medium)).foregroundStyle(Ink.text3)
                        }
                    }
                    HStack(spacing: 5) {
                        Chip(title: "5m") { timers.startCountdown(minutes: 5) }
                        Chip(title: "15m") { timers.startCountdown(minutes: 15) }
                        Chip(title: "Focus", symbol: "brain.head.profile", filled: true) { timers.startFocus() }
                    }
                }
                .card(padding: 10)
            }
        }
        .frame(height: 64)
    }
}

private struct AgentsMiniCard: View {
    @EnvironmentObject var board: AgentBoard
    @EnvironmentObject var model: IslandModel
    var body: some View {
        HStack(spacing: 8) {
            if board.working.isEmpty {
                Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(Ink.text3)
                Text(board.finishedToday > 0 ? "\(board.finishedToday) jobs done today" : "No agents working")
                    .font(.ui(11.5)).foregroundStyle(Ink.text3).lineLimit(1)
            } else {
                HStack(spacing: -7) {
                    ForEach(board.working.prefix(4)) { a in Avatar(name: a.name, side: 24).background(Circle().fill(Ink.pill)) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(board.working.count) working").font(.ui(11.5, .semibold)).foregroundStyle(Ink.text)
                    Text(board.working.first?.task ?? "").font(.ui(10)).foregroundStyle(Ink.text3).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.raised))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Motion.tab) { model.tab = .agents } }
    }
}

private struct DueCard: View {
    @EnvironmentObject var tasks: TaskStore
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Due soon").eyebrow()
            if tasks.dueSoon.isEmpty {
                Text("Nothing due.").font(.serif(12.5).italic()).foregroundStyle(Ink.text3)
            } else {
                ForEach(tasks.dueSoon.prefix(2)) { t in
                    HStack(spacing: 6) {
                        Button { withAnimation(Motion.snap) { tasks.toggle(t) } } label: {
                            Image(systemName: t.done ? "checkmark.circle.fill" : "circle").font(.system(size: 11)).foregroundStyle(t.done ? Ink.accent : Ink.text3)
                        }.buttonStyle(.plain)
                        Text(t.title).font(.serif(12)).foregroundStyle(Ink.text).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(dueText(t.due)).font(.ui(9.5, .semibold)).foregroundStyle(dueText(t.due) == "Late" ? Ink.coral : Ink.text3)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 10)
    }
}
