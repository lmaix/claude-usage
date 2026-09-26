import Foundation

/// Claude Code's own login, stored by `claude auth login` in the macOS Keychain.
/// We read it, and write it back after a refresh so the CLI stays in sync.
struct ClaudeCodeCredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let scopes: [String]
    /// Full JSON as stored, so a write-back preserves every other field.
    let raw: [String: Any]

    var hasProfileScope: Bool { scopes.contains("user:profile") }

    func isExpiring(within seconds: TimeInterval, now: Date = Date()) -> Bool {
        guard let e = expiresAt else { return false }
        return e.timeIntervalSince(now) < seconds
    }

    static func parse(_ data: Data) -> ClaudeCodeCredentials? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        var expires: Date? = nil
        if let ms = oauth["expiresAt"] as? Double, ms > 0 { expires = Date(timeIntervalSince1970: ms / 1000) }
        return ClaudeCodeCredentials(accessToken: token,
                                     refreshToken: oauth["refreshToken"] as? String,
                                     expiresAt: expires,
                                     scopes: (oauth["scopes"] as? [String]) ?? [],
                                     raw: obj)
    }

    /// New JSON with rotated tokens, everything else untouched.
    func updated(accessToken: String, refreshToken: String?, expiresIn: TimeInterval, now: Date = Date()) -> Data? {
        var obj = raw
        var oauth = (obj["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = accessToken
        if let r = refreshToken { oauth["refreshToken"] = r }
        oauth["expiresAt"] = Int((now.timeIntervalSince1970 + expiresIn) * 1000)
        obj["claudeAiOauth"] = oauth
        return try? JSONSerialization.data(withJSONObject: obj)
    }
}

/// All Keychain access goes through `/usr/bin/security`, the tool Claude Code itself uses: its login item trusts that
/// tool, so reading it never shows a password prompt. The app's own copy is stored the same way, so it stays readable
/// across rebuilds and updates (an item created through SecItem is tied to the app's signature and prompts when it changes).
enum Keychain {
    static let claudeCodeService = "Claude Code-credentials"
    static let ownService = "ClaudeUsage"
    static let ownAccount = "session"
    static let legacyService = "ClaudeUsageBar"   // items stored before the app was renamed ClaudeUsage

    /// The app's own copy of the session. Claude Code's item is read once to bootstrap it and never written:
    /// modifying that item changes its access list and makes Claude Code's `security` tool prompt at every launch.
    static func credentials() -> ClaudeCodeCredentials? {
        if let data = read(service: ownService, account: ownAccount), let c = ClaudeCodeCredentials.parse(data) { return c }
        guard let data = read(service: claudeCodeService, account: NSUserName()),
              let c = ClaudeCodeCredentials.parse(data) else { return nil }
        writeCredentials(data)
        return c
    }

    /// Replaces the app's copy. Delete-then-add so an item left by an older SecItem-based version gets the new access list.
    @discardableResult
    static func writeCredentials(_ data: Data) -> Bool {
        forgetOwnSession()
        // Sent on stdin (interactive mode), hex-encoded, so the secret never appears in a process's arguments.
        let hex = data.map { String(format: "%02x", $0) }.joined()
        _ = security(["-i"], stdin: "add-generic-password -s \(ownService) -a \(ownAccount) -X \(hex)\n")
        return read(service: ownService, account: ownAccount) == data   // interactive mode exits 0 even when a command fails
    }

    /// Drops the app's own copy so the next fetch re-bootstraps from Claude Code's login (after `claude auth login`).
    static func forgetOwnSession() {
        _ = security(["delete-generic-password", "-s", ownService, "-a", ownAccount])
    }

    /// Removes items stored by earlier versions: the setup-token item and the session copy from before the rename.
    static func deleteLegacyItem() {
        for account in ["oauth-token", "session"] {
            _ = security(["delete-generic-password", "-s", legacyService, "-a", account])
        }
    }

    private static func read(service: String, account: String) -> Data? {
        guard let out = security(["find-generic-password", "-s", service, "-a", account, "-w"]) else { return nil }
        let text = out.trimmingCharacters(in: .newlines)
        return text.isEmpty ? nil : Data(text.utf8)
    }

    /// Runs /usr/bin/security; returns stdout on success, nil on a non-zero exit (e.g. item not found).
    private static func security(_ args: [String], stdin: String? = nil) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe(), input = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        if stdin != nil { p.standardInput = input }
        do { try p.run() } catch { return nil }
        if let s = stdin { input.fileHandleForWriting.write(Data(s.utf8)); try? input.fileHandleForWriting.close() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
