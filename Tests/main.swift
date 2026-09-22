import Foundation

var failures = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { print("  ok   \(msg)") } else { failures += 1; print("  FAIL \(msg) (line \(line))") }
}
let now = ISO8601DateFormatter().date(from: "2026-09-22T09:00:00Z")!

// MARK: usage API parsing
let json = """
{"five_hour":{"utilization":2.0,"resets_at":"2026-09-22T12:59:59.651Z"},
 "seven_day":{"utilization":28,"resets_at":"2026-09-24T18:59:59.651Z"},
 "seven_day_fable":{"utilization":45.5,"resets_at":"2026-09-24T18:59:59Z"},
 "seven_day_opus":null,
 "seven_day_overage_included":{"utilization":0,"resets_at":null},
 "extra_usage":{"is_enabled":true,"used_credits":0,"monthly_limit":1000,"utilization":0}}
""".data(using: .utf8)!
let snap = try! UsageParser.parse(json, now: now)
check(snap.windows.map(\.key) == ["five_hour", "seven_day", "seven_day_fable"], "fenêtres : 5h, hebdo, fable (null et overage ignorés)")
check(snap.fiveHour?.percent == 2.0, "5h = 2 %")
check(snap.weeklyFable?.percent == 45.5 && snap.weeklyFable?.label == "Hebdo · Fable", "hebdo Fable détectée et libellée")
check(snap.secondBar?.key == "seven_day_fable", "2e barre = Fable quand disponible")
check(snap.fiveHour?.resetsAt != nil && snap.weeklyFable?.resetsAt != nil, "dates avec et sans fractions")
check(snap.extra == ExtraUsage(enabled: true, usedCredits: 0, monthlyLimit: 1000), "extra usage")

let noFable = try! UsageParser.parse("{\"five_hour\":{\"utilization\":5},\"seven_day\":{\"utilization\":30}}".data(using: .utf8)!, now: now)
check(noFable.secondBar?.key == "seven_day", "2e barre = hebdo global sans Fable")

check((try? UsageParser.parse("nope".data(using: .utf8)!)) == nil, "JSON invalide -> erreur")
do { _ = try UsageParser.parse("{\"a\":1}".data(using: .utf8)!); check(false, "sans fenêtre -> erreur") }
catch let e as UsageParseError { check(e == .noWindows, "sans fenêtre -> noWindows") }
catch { check(false, "mauvais type d'erreur") }

check(UsageLevel(percent: 59.9) == .ok && UsageLevel(percent: 60) == .warn && UsageLevel(percent: 85) == .critical, "seuils de couleur")
check(TimeFormat.remaining(until: now.addingTimeInterval(3*3600 + 40*60), from: now) == "3h 40m", "3h 40m")
check(TimeFormat.remaining(until: now.addingTimeInterval(2*86400 + 9*3600), from: now) == "2j 9h", "2j 9h")
check(TimeFormat.remaining(until: now.addingTimeInterval(-5), from: now) == "maintenant", "passé -> maintenant")

let img = BarRenderer.statusImage(fiveHour: 2, weekly: 45.5)
check(img.size.width > 40 && img.size.height <= 22, "image barre de menus \(Int(img.size.width))x\(Int(img.size.height))")

// MARK: Claude Code credentials round-trip (fake values)
let credsJSON = """
{"claudeAiOauth":{"accessToken":"fake-access-old","refreshToken":"fake-refresh-old","expiresAt":1758540000000,
 "scopes":["user:inference","user:profile"],"subscriptionType":"max"},"other":{"keep":true}}
""".data(using: .utf8)!
let creds = ClaudeCodeCredentials.parse(credsJSON)!
check(creds.accessToken == "fake-access-old" && creds.refreshToken == "fake-refresh-old", "credentials lues")
check(creds.hasProfileScope, "scope user:profile détecté")
let inferenceOnly = ClaudeCodeCredentials.parse("{\"claudeAiOauth\":{\"accessToken\":\"x\",\"scopes\":[\"user:inference\"]}}".data(using: .utf8)!)!
check(!inferenceOnly.hasProfileScope, "setup-token (inference seul) refusé")
check(ClaudeCodeCredentials.parse("{\"claudeAiOauth\":{\"accessToken\":\"\"}}".data(using: .utf8)!) == nil, "token vide -> nil")
let t0 = Date(timeIntervalSince1970: 1758540000 - 30)
check(creds.isExpiring(within: 60, now: t0) && !creds.isExpiring(within: 10, now: t0), "expiration proche détectée")
let rotated = creds.updated(accessToken: "fake-access-new", refreshToken: "fake-refresh-new", expiresIn: 3600, now: t0)!
let rot = ClaudeCodeCredentials.parse(rotated)!
let rotObj = try! JSONSerialization.jsonObject(with: rotated) as! [String: Any]
check(rot.accessToken == "fake-access-new" && rot.refreshToken == "fake-refresh-new", "tokens remplacés")
check(rot.expiresAt == t0.addingTimeInterval(3600), "expiresAt recalculé")
let keptOther = (rotObj["other"] as? [String: Any])?["keep"] as? Bool == true
let keptSub = ((rot.raw["claudeAiOauth"] as? [String: Any])?["subscriptionType"] as? String) == "max"
check(keptOther && keptSub, "autres champs conservés")

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
