// Mail: your Gmail unread, with archive, mark read and open.
import SwiftUI

struct MailPane: View {
    @EnvironmentObject var gmail: GmailCenter
    @EnvironmentObject var model: IslandModel

    var body: some View {
        switch gmail.state {
        case .needsClient:
            EmptyState(drawing: AnyView(EnvelopeDrawing()), title: "Connect Gmail",
                       line: "Perch signs in with your own Google client, so nobody else ever holds your mail. Paste its ID in Settings, under Mail.",
                       action: ("Open Mail settings", model.onOpenSettings))
        case .signedOut:
            EmptyState(drawing: AnyView(EnvelopeDrawing()), title: "Sign in to Gmail",
                       line: "Your browser opens Google's sign-in. Perch keeps the key in your Keychain.",
                       action: ("Sign in with Google", { gmail.signIn() }))
        case .signingIn:
            EmptyState(drawing: AnyView(EnvelopeDrawing()), title: "Finish in your browser",
                       line: "Approve Perch on Google's page, then come back. This waits for 5 minutes.")
        case .failing(let why):
            EmptyState(drawing: AnyView(EnvelopeDrawing()), title: "Gmail needs a hand", line: why,
                       action: ("Sign in again", { gmail.signIn() }))
        case .ready:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(gmail.unreadCount == 0 ? "Inbox" : "\(gmail.unreadCount) unread").eyebrow(gmail.unreadCount > 0 ? Ink.accent : nil)
                    if let a = gmail.account { Text(a).font(.ui(10.5)).foregroundStyle(Ink.text3) }
                    Spacer()
                    IconButton(symbol: "arrow.clockwise", help: "Refresh") { Task { await gmail.refresh() } }
                    Chip(title: "Open Gmail", symbol: "arrow.up.right") { gmail.openInbox() }
                }
                if gmail.items.isEmpty {
                    EmptyState(drawing: AnyView(EnvelopeDrawing()), title: "Inbox zero", line: "Nothing unread. Go outside.")
                } else {
                    Scrolling {
                        VStack(spacing: 3) {
                            ForEach(gmail.items) { m in MailRow(mail: m) }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }
}

private struct MailRow: View {
    let mail: MailItem
    @EnvironmentObject var gmail: GmailCenter
    @State private var hover = false
    var body: some View {
        HStack(spacing: 11) {
            Avatar(name: mail.from, side: 30)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(mail.from).font(.ui(12.5, .semibold)).foregroundStyle(Ink.text).lineLimit(1)
                    Circle().fill(Ink.accent).frame(width: 5, height: 5)
                }
                HStack(spacing: 6) {
                    Text(mail.subject).font(.ui(11.5, .medium)).foregroundStyle(Ink.text2).lineLimit(1).layoutPriority(1)
                    Text(mail.snippet).font(.ui(11.5)).foregroundStyle(Ink.text3).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if hover {
                HStack(spacing: 0) {
                    IconButton(symbol: "envelope.open", help: "Mark read") { withAnimation { gmail.markRead(mail) } }
                    IconButton(symbol: "archivebox", help: "Archive") { withAnimation { gmail.archive(mail) } }
                    IconButton(symbol: "arrow.up.right", help: "Open in Gmail") { gmail.open(mail) }
                }
            } else {
                Text(shortAge(Date().timeIntervalSince(mail.date))).font(.ui(10.5, .medium)).foregroundStyle(Ink.text3)
            }
        }
        .padding(.horizontal, 10).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hover ? Ink.raisedHover : Ink.raised))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { gmail.open(mail) }
        .pourable { .mail(mail) }
    }
}
