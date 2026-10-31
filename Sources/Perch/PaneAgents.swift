// Agents: every Grok Bot as its own avatar and color, live elapsed time, a bloom on finish, and history.
import SwiftUI

struct AgentsPane: View {
    @EnvironmentObject var board: AgentBoard

    var body: some View {
        switch board.link {
        case .notSetUp:
            EmptyState(drawing: AnyView(DotsDrawing(lit: false)), title: "No board connected",
                       line: "This copy of Perch has no agent board key. Add one in Settings, under Agents.")
        default:
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(summary).eyebrow()
                        Spacer()
                        if case .failing(let why) = board.link {
                            Text(why).font(.ui(10.5)).foregroundStyle(Ink.coral).lineLimit(1)
                        }
                    }
                    if board.agents.isEmpty {
                        EmptyState(drawing: AnyView(DotsDrawing(lit: true)), title: "All quiet",
                                   line: "When a Grok Bot starts a job it shows up here, and it blooms when the job is done.")
                    } else {
                        Scrolling {
                            VStack(spacing: 8) {
                                ForEach(Array(stride(from: 0, to: board.agents.count, by: 2)), id: \.self) { i in
                                    HStack(alignment: .top, spacing: 8) {
                                        AgentCard(agent: board.agents[i], blooming: board.justFinished.contains(board.agents[i].id))
                                        if i + 1 < board.agents.count {
                                            AgentCard(agent: board.agents[i + 1], blooming: board.justFinished.contains(board.agents[i + 1].id))
                                        } else {
                                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                HistoryColumn().frame(width: 196)
            }
            .padding(.vertical, 12)
        }
    }

    private var summary: String {
        let w = board.working.count, d = board.finished.count
        var parts: [String] = []
        if w > 0 { parts.append("\(w) working") }
        if d > 0 { parts.append("\(d) done") }
        return parts.isEmpty ? "Board" : parts.joined(separator: ", ")
    }
}

struct AgentCard: View {
    let agent: Agent
    let blooming: Bool

    var body: some View {
        let color = NameColor.of(agent.name)
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Avatar(name: agent.name, side: 30)
                StatusPip(agent: agent, blooming: blooming).offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(agent.name).font(.ui(12.5, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                    Spacer(minLength: 6)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(age(at: ctx.date)).font(.round(10.5, .semibold)).monospacedDigit()
                            .foregroundStyle(agent.isWorking ? color : Ink.text3)
                    }
                }
                Text(agent.task ?? (agent.isWorking ? "Working" : "Finished"))
                    .font(.ui(11.5)).foregroundStyle(Ink.text2).lineLimit(1)
                if let n = agent.note {
                    Text(n).font(.ui(10.5)).foregroundStyle(agent.status == .failed ? Ink.coral : color.opacity(0.9)).lineLimit(1)
                } else if agent.isWorking {
                    WorkingLine(color: color, quiet: agent.quiet == true).padding(.top, 5)
                }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(blooming ? color.opacity(0.12) : Ink.raised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(blooming ? color.opacity(0.45) : .clear, lineWidth: 1))
    }

    private func age(at now: Date) -> String {
        if agent.isWorking, let s = agent.startedDate { return clock(now.timeIntervalSince(s)) }
        if let f = agent.finishedDate {
            let a = shortAge(now.timeIntervalSince(f))
            return a == "just now" ? a : a + " ago"
        }
        return ""
    }
}

/// A thin line with a soft highlight travelling along it while the agent works.
private struct WorkingLine: View {
    let color: Color
    let quiet: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { ctx in
            let t = RenderMode.snapshot ? 0.4 : (ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8)) / 1.8
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.14))
                    if !quiet {
                        Capsule().fill(LinearGradient(colors: [color.opacity(0), color, color.opacity(0)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * 0.35)
                            .offset(x: (geo.size.width * 1.35) * CGFloat(t) - geo.size.width * 0.35)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 2.5)
        }
    }
}

private struct StatusPip: View {
    let agent: Agent
    let blooming: Bool
    var body: some View {
        ZStack {
            Circle().fill(Ink.pill).frame(width: 13, height: 13)
            switch agent.status {
            case .started, .working:
                Circle().fill(agent.quiet == true ? Ink.quiet : Ink.mint).frame(width: 7, height: 7)
            case .finished:
                if blooming { InkBloom(color: Ink.accent, size: 24) }
                Circle().fill(Ink.accent).frame(width: 9, height: 9)
                Image(systemName: "checkmark").font(.system(size: 5.5, weight: .black)).foregroundStyle(Ink.onAccent)
            case .failed:
                Circle().fill(Ink.coral).frame(width: 9, height: 9)
                Image(systemName: "exclamationmark").font(.system(size: 5.5, weight: .black)).foregroundStyle(Ink.onAccent)
            }
        }
    }
}

private struct HistoryColumn: View {
    @EnvironmentObject var board: AgentBoard
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("History").eyebrow()
                Spacer()
                Text("\(board.finishedToday) today").font(.round(10.5, .semibold)).foregroundStyle(Ink.accent)
            }
            if board.history.isEmpty {
                Text("Finished jobs collect here, kept on this Mac.").font(.serif(12.5).italic()).foregroundStyle(Ink.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Scrolling {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(board.history.prefix(12)) { r in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(r.failed ? Ink.coral : NameColor.of(r.name)).frame(width: 6, height: 6).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(r.name).font(.ui(11, .semibold)).foregroundStyle(Ink.text2).lineLimit(1)
                                    Text(r.task.isEmpty ? (r.failed ? "Stopped" : "Done") : r.task).font(.ui(10.5)).foregroundStyle(Ink.text3).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text(shortAge(Date().timeIntervalSince(r.at))).font(.ui(9.5, .medium)).foregroundStyle(Ink.text3)
                                    if let s = r.seconds { Text(Self.dur(s)).font(.ui(9.5)).monospacedDigit().foregroundStyle(Ink.text3) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) { Rectangle().fill(Ink.hairline).frame(width: 1) }
    }

    static func dur(_ s: Double) -> String {
        let m = Int(s / 60)
        if m < 1 { return "\(Int(s))s" }
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }
}
