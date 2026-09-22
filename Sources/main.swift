import AppKit
import ServiceManagement

enum FetchError: Error {
    case notLoggedIn, missingScope, unauthorized, refreshFailed(String), rateLimited(TimeInterval), http(Int), network(String), parse(String)

    var message: String {
        switch self {
        case .notLoggedIn: return "Non connecté : « Se connecter dans le Terminal… »"
        case .missingScope: return "Connexion sans accès au profil : reconnecte-toi via le Terminal"
        case .unauthorized: return "Session refusée (401) : reconnecte-toi via le Terminal"
        case .refreshFailed(let s): return "Renouvellement de session impossible : \(s)"
        case .rateLimited(let s): return "Trop de requêtes (429), nouvel essai dans \(Int(s / 60)) min"
        case .http(let c): return "Erreur serveur HTTP \(c)"
        case .network(let s): return "Réseau : \(s)"
        case .parse(let s): return "Réponse inattendue : \(s)"
        }
    }
}

/// Talks to the Anthropic OAuth API with Claude Code's own login, refreshing it when it expires.
final class UsageFetcher {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"   // Claude Code's public OAuth client id

    func fetch(completion: @escaping (Result<UsageSnapshot, FetchError>) -> Void) {
        guard let creds = Keychain.claudeCodeCredentials() else { return completion(.failure(.notLoggedIn)) }
        guard creds.hasProfileScope else { return completion(.failure(.missingScope)) }
        if creds.isExpiring(within: 120), creds.refreshToken != nil {
            refresh(creds) { [weak self] r in
                switch r {
                case .success(let fresh): self?.get(token: fresh.accessToken, retryWith: nil, completion: completion)
                case .failure(let e): completion(.failure(e))
                }
            }
        } else {
            get(token: creds.accessToken, retryWith: creds, completion: completion)
        }
    }

    /// GET usage; on 401 with a refresh token available, refresh once and retry.
    private func get(token: String, retryWith creds: ClaudeCodeCredentials?,
                     completion: @escaping (Result<UsageSnapshot, FetchError>) -> Void) {
        var req = URLRequest(url: Self.usageURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let done: (Result<UsageSnapshot, FetchError>) -> Void = { r in DispatchQueue.main.async { completion(r) } }
            if let err = err { return done(.failure(.network(err.localizedDescription))) }
            guard let http = resp as? HTTPURLResponse, let data = data else { return done(.failure(.network("réponse vide"))) }
            if http.statusCode == 401 || http.statusCode == 403 {
                Log.write("HTTP \(http.statusCode) on usage: \(String(data: data, encoding: .utf8) ?? "")")
                if let creds = creds, creds.refreshToken != nil {
                    return self.refresh(creds) { r in
                        switch r {
                        case .success(let fresh): self.get(token: fresh.accessToken, retryWith: nil, completion: completion)
                        case .failure(let e): completion(.failure(e))
                        }
                    }
                }
                return done(.failure(.unauthorized))
            }
            if http.statusCode == 429 {
                let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap { Double($0) } ?? 0
                Log.write("HTTP 429 (Retry-After: \(Int(retry)) s)")
                return done(.failure(.rateLimited(retry)))
            }
            guard (200..<300).contains(http.statusCode) else {
                Log.write("HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
                return done(.failure(.http(http.statusCode)))
            }
            do { done(.success(try UsageParser.parse(data))) }
            catch {
                Log.write("Parse error \(error): \(String(data: data, encoding: .utf8) ?? "")")
                done(.failure(.parse("\(error)")))
            }
        }.resume()
    }

    /// OAuth refresh_token grant, then write the rotated tokens back to Claude Code's Keychain item.
    private func refresh(_ creds: ClaudeCodeCredentials,
                         completion: @escaping (Result<ClaudeCodeCredentials, FetchError>) -> Void) {
        guard let refreshToken = creds.refreshToken else { return completion(.failure(.unauthorized)) }
        var req = URLRequest(url: Self.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": Self.clientID,
        ])
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let done: (Result<ClaudeCodeCredentials, FetchError>) -> Void = { r in DispatchQueue.main.async { completion(r) } }
            if let err = err { return done(.failure(.network(err.localizedDescription))) }
            guard let http = resp as? HTTPURLResponse, let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return done(.failure(.refreshFailed("réponse vide")))
            }
            guard (200..<300).contains(http.statusCode), let access = obj["access_token"] as? String else {
                Log.write("Refresh HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
                return done(.failure(.refreshFailed("HTTP \(http.statusCode)")))
            }
            let expiresIn = (obj["expires_in"] as? Double) ?? 3600
            guard let json = creds.updated(accessToken: access, refreshToken: obj["refresh_token"] as? String, expiresIn: expiresIn),
                  Keychain.writeClaudeCodeCredentials(json),
                  let fresh = ClaudeCodeCredentials.parse(json) else {
                return done(.failure(.refreshFailed("écriture Trousseau")))
            }
            Log.write("Session renouvelée, expire dans \(Int(expiresIn / 60)) min")
            done(.success(fresh))
        }.resume()
    }
}

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ClaudeUsageBar.log")
    static func write(_ s: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let fetcher = UsageFetcher()
    private var timer: Timer?
    private var snapshot: UsageSnapshot?
    private var lastError: FetchError?
    private var nextAllowedFetch = Date.distantPast
    private var backoff: TimeInterval = 5 * 60
    static let pollInterval: TimeInterval = 5 * 60
    static let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ClaudeUsageBar/last-usage.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = BarRenderer.errorImage()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        Keychain.deleteLegacyItem()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        timer = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer?.tolerance = 5
        loadCache()
        refresh()
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
    }

    /// Every 30 s: fetch only when the poll interval (or a 429 backoff) has elapsed.
    @objc private func tick() {
        if Date() >= nextAllowedFetch { refresh() }
    }

    @objc func refresh() {
        nextAllowedFetch = Date().addingTimeInterval(Self.pollInterval)
        fetcher.fetch { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let s):
                self.snapshot = s; self.lastError = nil; self.backoff = 5 * 60
                self.saveCache(s)
            case .failure(.rateLimited(let retryAfter)):
                // Google-style backoff: honor Retry-After, else 5, 10, 20… minutes up to 30.
                let wait = retryAfter > 0 ? retryAfter : self.backoff
                self.backoff = min(self.backoff * 2, 30 * 60)
                self.nextAllowedFetch = Date().addingTimeInterval(wait)
                self.lastError = .rateLimited(wait)
            case .failure(let e):
                self.lastError = e
            }
            self.render()
        }
    }

    // MARK: - Cache (so a restart shows the last known bars instead of "C!")

    private func saveCache(_ s: UsageSnapshot) {
        let obj: [String: Any] = [
            "fetchedAt": s.fetchedAt.timeIntervalSince1970,
            "windows": s.windows.map { ["key": $0.key, "label": $0.label, "percent": $0.percent, "resetsAt": $0.resetsAt?.timeIntervalSince1970 ?? 0] },
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: Self.cacheURL, options: .atomic)
    }

    private func loadCache() {
        guard let d = try? Data(contentsOf: Self.cacheURL),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let fetched = obj["fetchedAt"] as? Double,
              let ws = obj["windows"] as? [[String: Any]] else { return }
        let windows = ws.compactMap { w -> UsageWindow? in
            guard let key = w["key"] as? String, let label = w["label"] as? String, let pct = w["percent"] as? Double else { return nil }
            let r = (w["resetsAt"] as? Double) ?? 0
            return UsageWindow(key: key, label: label, percent: pct, resetsAt: r > 0 ? Date(timeIntervalSince1970: r) : nil)
        }
        guard !windows.isEmpty else { return }
        snapshot = UsageSnapshot(windows: windows, extra: nil, fetchedAt: Date(timeIntervalSince1970: fetched))
        render()
    }

    private func render() {
        guard let button = statusItem.button else { return }
        if let s = snapshot {
            button.image = BarRenderer.statusImage(fiveHour: s.fiveHour?.percent ?? 0, weekly: s.secondBar?.percent ?? 0)
            button.toolTip = s.windows.map { "\($0.label) : \(Int($0.percent.rounded())) %" }.joined(separator: "\n")
        } else {
            button.image = BarRenderer.errorImage()
            button.toolTip = lastError?.message
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        if let s = snapshot {
            for w in s.windows {
                let reset = w.resetsAt.map { " · reset dans \(TimeFormat.remaining(until: $0))" } ?? ""
                let item = NSMenuItem(title: "\(w.label) : \(Int(w.percent.rounded())) %\(reset)", action: nil, keyEquivalent: "")
                item.image = swatch(for: w.percent)
                menu.addItem(item)
            }
            if let e = s.extra, e.enabled {
                let used = String(format: "%.2f", e.usedCredits / 100), limit = String(format: "%.2f", e.monthlyLimit / 100)
                menu.addItem(NSMenuItem(title: "Usage extra : \(used) / \(limit) ce mois", action: nil, keyEquivalent: ""))
            }
            menu.addItem(.separator())
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            menu.addItem(NSMenuItem(title: "Mis à jour à \(f.string(from: s.fetchedAt))", action: nil, keyEquivalent: ""))
        }
        if let e = lastError {
            menu.addItem(NSMenuItem(title: "⚠︎ \(e.message)", action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        if lastError != nil {
            menu.addItem(withTitle: "Se connecter dans le Terminal…", action: #selector(loginInTerminal), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func swatch(for percent: Double) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { _ in
            BarRenderer.color(for: percent).setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 10, height: 10)).fill()
            return true
        }
    }

    /// Opens Terminal and runs `claude auth login`; the CLI stores the login in the Keychain, which we then read.
    @objc private func loginInTerminal() {
        let script = """
        tell application "Terminal"
            activate
            do script "claude auth login"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error = error {
            let a = NSAlert(); a.messageText = "Impossible d'ouvrir le Terminal"
            a.informativeText = "Lance toi-même dans un Terminal : claude auth login\n\n\(error)"; a.runModal()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in buildMenu().items { menu.addItem(item.copy() as! NSMenuItem) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
