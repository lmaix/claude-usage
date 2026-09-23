import Foundation
import Security

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

enum Keychain {
    static let claudeCodeService = "Claude Code-credentials"
    static let ownService = "ClaudeUsageBar"
    static let ownAccount = "session"
    static let legacyService = "ClaudeUsageBar"   // old setup-token item used account "oauth-token"

    /// The app's own copy of the session. Claude Code's item is read once to bootstrap it and never written:
    /// modifying that item changes its access list and makes Claude Code's `security` tool prompt at every launch.
    static func credentials() -> ClaudeCodeCredentials? {
        if let data = read(service: ownService, account: ownAccount), let c = ClaudeCodeCredentials.parse(data) { return c }
        guard let data = read(service: claudeCodeService, account: NSUserName()),
              let c = ClaudeCodeCredentials.parse(data) else { return nil }
        writeCredentials(data)
        return c
    }

    @discardableResult
    static func writeCredentials(_ data: Data) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
            kSecAttrAccount as String: ownAccount,
        ]
        let st = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if st == errSecSuccess { return true }
        guard st == errSecItemNotFound else { return false }
        var add = base
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Drops the app's own copy so the next fetch re-bootstraps from Claude Code's login (after `claude auth login`).
    static func forgetOwnSession() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
            kSecAttrAccount as String: ownAccount,
        ]
        SecItemDelete(q as CFDictionary)
    }

    /// Removes the token item an earlier version of this app stored (setup-token, no longer used).
    static func deleteLegacyItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: "oauth-token",
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
