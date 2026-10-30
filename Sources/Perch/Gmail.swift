// Gmail, the real thing. Google sign-in in your browser (OAuth for desktop apps, with PKCE and a
// one-time loopback page on 127.0.0.1). The client ID you create, the client secret and the refresh
// token are kept in the macOS Keychain, never in a file or in the app itself.
import AppKit
import Foundation
import Network
import Security
import CryptoKit

enum Keychain {
    static let service = "com.bigbhubbha.perch"

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func set(_ account: String, _ value: String?) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

struct MailItem: Identifiable, Equatable {
    var id: String
    var threadID: String
    var from: String
    var fromEmail: String
    var subject: String
    var snippet: String
    var date: Date
    var unread: Bool
}

@MainActor
final class GmailCenter: ObservableObject {
    enum State: Equatable { case needsClient, signedOut, signingIn, ready, failing(String) }

    @Published private(set) var state: State = .needsClient
    @Published private(set) var items: [MailItem] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var account: String?
    @Published private(set) var lastSync: Date?

    var onNewMail: (MailItem) -> Void = { _ in }

    private var accessToken: String?
    private var accessExpires = Date.distantPast
    private var timer: Timer?
    private var seen = Set<String>()
    private var primed = false
    private var listener: NWListener?

    private static let scope = "https://www.googleapis.com/auth/gmail.modify"

    var clientID: String { Keychain.get("gmail.client_id") ?? "" }
    var hasClient: Bool { !clientID.isEmpty }

    func start() {
        account = UserDefaults.standard.string(forKey: "gmail.account")
        if !hasClient { state = .needsClient; return }
        if Keychain.get("gmail.refresh_token") == nil { state = .signedOut; return }
        state = .ready
        schedule()
        Task { await refresh() }
    }

    func saveClient(id: String, secret: String) {
        Keychain.set("gmail.client_id", id.trimmingCharacters(in: .whitespacesAndNewlines))
        Keychain.set("gmail.client_secret", secret.trimmingCharacters(in: .whitespacesAndNewlines))
        state = hasClient ? (Keychain.get("gmail.refresh_token") == nil ? .signedOut : .ready) : .needsClient
    }

    func signOut() {
        if let t = Keychain.get("gmail.refresh_token") {
            var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke?token=\(t)")!)
            r.httpMethod = "POST"
            URLSession.shared.dataTask(with: r).resume()
        }
        Keychain.set("gmail.refresh_token", nil)
        accessToken = nil; items = []; unreadCount = 0; account = nil
        UserDefaults.standard.removeObject(forKey: "gmail.account")
        timer?.invalidate()
        state = hasClient ? .signedOut : .needsClient
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { Task { await self?.refresh() } }
        }
        timer?.tolerance = 20
    }

    // MARK: Sign in

    func signIn() {
        guard hasClient else { state = .needsClient; return }
        state = .signingIn
        let verifier = Self.randomURLSafe(48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let stateToken = Self.randomURLSafe(24)
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
            let l = try NWListener(using: params)
            listener = l
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    let req = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let ok = req.contains("code=")
                    let body = ok ? "<h2 style='font-family:-apple-system'>Perch is connected to Gmail.</h2><p style='font-family:-apple-system'>You can close this tab.</p>"
                                  : "<h2 style='font-family:-apple-system'>Sign-in was cancelled.</h2>"
                    let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
                    conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
                    MainActor.assumeIsolated { self?.handleRedirect(req, verifier: verifier, expectedState: stateToken) }
                }
            }
            l.stateUpdateHandler = { [weak self] st in
                guard case .ready = st, let port = l.port?.rawValue else { return }
                MainActor.assumeIsolated { self?.openConsent(port: port, challenge: challenge, state: stateToken) }
            }
            l.start(queue: .main)
            // Give up after 5 minutes.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                if self?.state == .signingIn { self?.listener?.cancel(); self?.state = .signedOut }
            }
        } catch {
            state = .failing("Could not open a sign-in port")
        }
    }

    private var redirectURI = ""

    private func openConsent(port: UInt16, challenge: String, state: String) {
        redirectURI = "http://127.0.0.1:\(port)"
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: Self.scope + " email"),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state), .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"),
        ]
        if let u = c.url { NSWorkspace.shared.open(u) }
    }

    private func handleRedirect(_ request: String, verifier: String, expectedState: String) {
        listener?.cancel(); listener = nil
        guard let line = request.split(separator: "\r\n").first, let pathPart = line.split(separator: " ").dropFirst().first,
              let comps = URLComponents(string: "http://x" + pathPart) else { state = .signedOut; return }
        let q = Dictionary((comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard q["state"] == expectedState, let code = q["code"], !code.isEmpty else { state = .signedOut; return }
        Task {
            let body = [
                "code": code, "client_id": clientID, "client_secret": Keychain.get("gmail.client_secret") ?? "",
                "redirect_uri": redirectURI, "grant_type": "authorization_code", "code_verifier": verifier,
            ]
            guard let tok = await self.tokenRequest(body), let refresh = tok["refresh_token"] as? String else {
                self.state = .failing("Google did not return a token. Check the client ID and secret."); return
            }
            Keychain.set("gmail.refresh_token", refresh)
            self.accessToken = tok["access_token"] as? String
            self.accessExpires = Date().addingTimeInterval((tok["expires_in"] as? Double ?? 3000) - 60)
            self.state = .ready
            NSApp.activate()
            self.schedule()
            await self.refresh()
        }
    }

    private func tokenRequest(_ fields: [String: String]) async -> [String: Any]? {
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        r.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        guard let res = try? await URLSession.shared.data(for: r), (res.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: res.0) as? [String: Any]
    }

    private func token() async -> String? {
        if let t = accessToken, Date() < accessExpires { return t }
        guard let refresh = Keychain.get("gmail.refresh_token") else { return nil }
        let tok = await tokenRequest(["client_id": clientID, "client_secret": Keychain.get("gmail.client_secret") ?? "",
                                      "refresh_token": refresh, "grant_type": "refresh_token"])
        guard let t = tok?["access_token"] as? String else {
            state = .failing("Gmail sign-in expired. Sign in again.")
            return nil
        }
        accessToken = t
        accessExpires = Date().addingTimeInterval((tok?["expires_in"] as? Double ?? 3000) - 60)
        return t
    }

    // MARK: API

    private func api(_ path: String, method: String = "GET", json: [String: Any]? = nil) async -> [String: Any]? {
        guard let t = await token(), let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/" + path) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        if let json { r.httpBody = try? JSONSerialization.data(withJSONObject: json); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        guard let res = try? await URLSession.shared.data(for: r) else { return nil }
        let d = res.0
        let code = (res.1 as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { accessToken = nil }
        guard code == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }

    func refresh() async {
        guard canSync else { return }
        if account == nil, let p = await api("profile"), let e = p["emailAddress"] as? String {
            account = e; UserDefaults.standard.set(e, forKey: "gmail.account")
        }
        guard let list = await api("messages?q=" + "in:inbox is:unread".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! + "&maxResults=8") else {
            return
        }
        unreadCount = (list["resultSizeEstimate"] as? Int) ?? 0
        let ids = ((list["messages"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        var out: [MailItem] = []
        for id in ids {
            guard let m = await api("messages/\(id)?format=metadata&metadataHeaders=From&metadataHeaders=Subject") else { continue }
            let headers = ((m["payload"] as? [String: Any])?["headers"] as? [[String: Any]]) ?? []
            func h(_ n: String) -> String { headers.first { ($0["name"] as? String)?.lowercased() == n.lowercased() }?["value"] as? String ?? "" }
            let (name, email) = Self.splitFrom(h("From"))
            let ms = Double((m["internalDate"] as? String) ?? "0") ?? 0
            out.append(MailItem(id: id, threadID: (m["threadId"] as? String) ?? id, from: name, fromEmail: email,
                                subject: h("Subject").isEmpty ? "(no subject)" : h("Subject"),
                                snippet: Self.decodeEntities((m["snippet"] as? String) ?? ""),
                                date: Date(timeIntervalSince1970: ms / 1000), unread: true))
        }
        if primed, let newest = out.first(where: { !seen.contains($0.id) }) { onNewMail(newest) }
        seen.formUnion(out.map(\.id))
        primed = true
        items = out
        lastSync = Date()
        state = .ready
    }

    private var canSync: Bool {
        switch state {
        case .ready, .failing: return true
        default: return false
        }
    }

    func markRead(_ m: MailItem) {
        items.removeAll { $0.id == m.id }; unreadCount = max(0, unreadCount - 1)
        Task { _ = await api("messages/\(m.id)/modify", method: "POST", json: ["removeLabelIds": ["UNREAD"]]) }
    }

    func archive(_ m: MailItem) {
        items.removeAll { $0.id == m.id }; unreadCount = max(0, unreadCount - 1)
        Task { _ = await api("messages/\(m.id)/modify", method: "POST", json: ["removeLabelIds": ["UNREAD", "INBOX"]]) }
    }

    func open(_ m: MailItem) {
        let u = account.map { "https://mail.google.com/mail/u/\($0)/#inbox/\(m.threadID)" } ?? "https://mail.google.com/mail/#inbox/\(m.threadID)"
        if let url = URL(string: u) { NSWorkspace.shared.open(url) }
    }

    func openInbox() {
        if let url = URL(string: "https://mail.google.com/mail/") { NSWorkspace.shared.open(url) }
    }

    // MARK: Helpers

    static func splitFrom(_ s: String) -> (String, String) {
        if let lt = s.firstIndex(of: "<"), let gt = s.firstIndex(of: ">"), lt < gt {
            let name = s[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            let email = String(s[s.index(after: lt)..<gt])
            return (name.isEmpty ? email : name, email)
        }
        return (s, s)
    }

    static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }

    static func randomURLSafe(_ n: Int) -> String {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return Data(b).base64URL
    }

    func previewState(_ s: State) { state = s }

    func preview(_ list: [MailItem], unread: Int, account: String) {
        items = list; unreadCount = unread; self.account = account; state = .ready; lastSync = Date()
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
