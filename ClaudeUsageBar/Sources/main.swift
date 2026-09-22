import AppKit
import ServiceManagement

enum FetchError: Error {
    case noToken, unauthorized, http(Int), network(String), parse(String)

    var message: String {
        switch self {
        case .noToken: return "Aucun token : Configurer le token…"
        case .unauthorized: return "Token refusé ou expiré (401) : Configurer le token…"
        case .http(let c): return "Erreur serveur HTTP \(c)"
        case .network(let s): return "Réseau : \(s)"
        case .parse(let s): return "Réponse inattendue : \(s)"
        }
    }
}

final class UsageFetcher {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetch(token: String, completion: @escaping (Result<UsageSnapshot, FetchError>) -> Void) {
        var req = URLRequest(url: Self.endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let done: (Result<UsageSnapshot, FetchError>) -> Void = { r in DispatchQueue.main.async { completion(r) } }
            if let err = err { return done(.failure(.network(err.localizedDescription))) }
            guard let http = resp as? HTTPURLResponse, let data = data else { return done(.failure(.network("réponse vide"))) }
            if http.statusCode == 401 || http.statusCode == 403 { return done(.failure(.unauthorized)) }
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = BarRenderer.errorImage()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        timer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        timer?.tolerance = 10
        refresh()
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
    }

    @objc func refresh() {
        guard let token = Keychain.token() else { lastError = .noToken; render(); return }
        fetcher.fetch(token: token) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let s): self.snapshot = s; self.lastError = nil
            case .failure(let e): self.lastError = e
            }
            self.render()
        }
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
        menu.addItem(withTitle: "Configurer le token…", action: #selector(configureToken), keyEquivalent: "").target = self
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

    @objc private func configureToken() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Token Claude"
        alert.informativeText = "Dans un Terminal, lance « claude setup-token », copie le token (sk-ant-oat…), puis colle-le ici (⌘V) ou clique « Coller depuis le presse-papiers ». Il est stocké dans ton Trousseau, uniquement pour cette app."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "sk-ant-oat01-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Enregistrer")                       // 1st
        alert.addButton(withTitle: "Coller depuis le presse-papiers")  // 2nd
        alert.addButton(withTitle: "Annuler")                           // 3rd
        let hasToken = Keychain.token() != nil
        if hasToken { alert.addButton(withTitle: "Supprimer le token") } // 4th
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        let save: (String) -> Void = { [weak self] token in
            guard !token.isEmpty else { return }
            if !Keychain.save(token) {
                let a = NSAlert(); a.messageText = "Échec de l'enregistrement dans le Trousseau"; a.runModal()
            }
            self?.refresh()
        }
        switch response {
        case .alertFirstButtonReturn:
            save(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        case .alertSecondButtonReturn:
            let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if clip.hasPrefix("sk-ant-") { save(clip) }
            else { let a = NSAlert(); a.messageText = "Le presse-papiers ne contient pas de token sk-ant-…"; a.runModal() }
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1) where hasToken:
            Keychain.delete(); snapshot = nil; refresh()
        default: break
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in buildMenu().items { menu.addItem(item.copy() as! NSMenuItem) }
    }
}

/// LSUIElement apps have no main menu, so ⌘V/⌘C/⌘A do nothing in dialogs unless we install an Edit menu.
func installEditMenu() {
    let main = NSMenu()
    let editItem = NSMenuItem(title: "Édition", action: nil, keyEquivalent: "")
    let edit = NSMenu(title: "Édition")
    edit.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    main.addItem(editItem)
    NSApp.mainMenu = main
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
installEditMenu()
app.run()
