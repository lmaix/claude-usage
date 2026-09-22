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
    static let legacyService = "ClaudeUsageBar"

    static func claudeCodeCredentials() -> ClaudeCodeCredentials? {
        guard let data = read(service: claudeCodeService, account: NSUserName()) else { return nil }
        return ClaudeCodeCredentials.parse(data)
    }

    @discardableResult
    static func writeClaudeCodeCredentials(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: claudeCodeService,
            kSecAttrAccount as String: NSUserName(),
        ]
        return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
    }

    /// Removes the token item an earlier version of this app stored (setup-token, no longer used).
    static func deleteLegacyItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
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
