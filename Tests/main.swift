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
 "seven_day_opus":null,
 "seven_day_overage_included":{"utilization":0,"resets_at":null},
 "nimbus_quill":{"utilization":0,"resets_at":"2026-09-24T18:59:59Z"},
 "limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"percent":48,"resets_at":1758740399},
           {"kind":"daily","percent":1}],
 "extra_usage":{"is_enabled":true,"used_credits":0,"monthly_limit":1000,"utilization":0}}
""".data(using: .utf8)!
let snap = try! UsageParser.parse(json, now: now)
check(snap.windows.map(\.key) == ["five_hour", "seven_day", "seven_day_fable"], "windows: 5h, weekly, fable (null, overage and unknown key ignored)")
check(snap.fiveHour?.percent == 2.0, "5h = 2%")
check(snap.weeklyFable?.percent == 48 && snap.weeklyFable?.label == "Weekly · Fable", "weekly Fable read from limits[] and labeled")
check(snap.fiveHour?.resetsAt != nil, "ISO date with fractions")
check(snap.weeklyFable?.resetsAt == Date(timeIntervalSince1970: 1758740399), "epoch-seconds date in limits[]")
check(snap.extra == ExtraUsage(enabled: true, usedCredits: 0, monthlyLimit: 1000), "extra usage")

let legacy = try! UsageParser.parse("{\"five_hour\":{\"utilization\":1},\"seven_day_fable\":{\"utilization\":45.5,\"resets_at\":\"2026-09-24T18:59:59Z\"}}".data(using: .utf8)!, now: now)
check(legacy.weeklyFable?.percent == 45.5 && legacy.weeklyFable?.resetsAt != nil, "top-level seven_day_fable key still accepted")

let noFable = try! UsageParser.parse("{\"five_hour\":{\"utilization\":5},\"seven_day\":{\"utilization\":30}}".data(using: .utf8)!, now: now)

// MARK: displayed bar pair
check(BarPair.default == .fiveHourFable, "default: 5-hour + Fable")
check(BarPair.allCases == [.fiveHourAll, .fiveHourFable, .allFable] && Set(BarPair.allCases.map(\.title)).count == 3, "bar choices in 5, W, F order")
check(BarPair(rawValue: "inconnu") == nil, "unknown stored value rejected")
let p1 = BarPair.fiveHourFable.windows(in: snap), p2 = BarPair.fiveHourAll.windows(in: snap), p3 = BarPair.allFable.windows(in: snap)
check(p1.top?.key == "five_hour" && p1.bottom?.key == "seven_day_fable", "5-hour + Fable")
check(p2.top?.key == "five_hour" && p2.bottom?.key == "seven_day", "5-hour + all models")
check(p3.top?.key == "seven_day" && p3.bottom?.key == "seven_day_fable", "all models + Fable")
let q1 = BarPair.fiveHourFable.windows(in: noFable), q3 = BarPair.allFable.windows(in: noFable)
check(q1.top?.key == "five_hour" && q1.bottom?.key == "seven_day", "no Fable: 5-hour + all models")
check(q3.top?.key == "seven_day" && q3.bottom?.key == "five_hour", "no Fable: never the same bar twice")

// MARK: ring style
check(BarStyle.default == .rings && BarStyle.allCases.map(\.title) == ["Rings", "Bars"], "styles: Rings (default), Bars")
check(BarStyle(rawValue: "unknown") == nil, "unknown stored style rejected")
check(RingSet.default == .all && RingSet.allCases == [.all, .fiveHourAll, .fiveHourFable, .allFable], "ring choices: all three (default), 5+W, 5+F, W+F")
check(Set(RingSet.allCases.map(\.title)).count == 4, "ring choices have distinct titles")
let r1 = RingSet.all.rings(in: snap)
check(r1.map(\.letter) == ["5", "W", "F"] && r1.map(\.percent) == [2, 28, 48], "rings: 5, W, F with their percentages")
check(RingSet.fiveHourAll.rings(in: snap).map(\.letter) == ["5", "W"], "5 + W")
check(RingSet.fiveHourFable.rings(in: snap).map(\.letter) == ["5", "F"], "5 + F")
check(RingSet.allFable.rings(in: snap).map(\.letter) == ["W", "F"], "W + F")
check(RingSet.all.rings(in: noFable).map(\.letter) == ["5", "W"], "no Fable: F ring dropped")
let ringsImg = BarRenderer.ringsImage(r1)
check(ringsImg.size.height <= 22 && ringsImg.size.width > BarRenderer.ringsImage(Array(r1.prefix(2))).size.width, "ring image grows with ring count")

// MARK: gradients
for p in [10.0, 70, 95] {
    let (a, b) = BarRenderer.gradient(for: p)
    check(a != b, "two-color gradient at \(Int(p))%")
}
check(BarRenderer.gradient(for: 10).0 != BarRenderer.gradient(for: 95).0, "gradient depends on level")

check((try? UsageParser.parse("nope".data(using: .utf8)!)) == nil, "invalid JSON -> error")
do { _ = try UsageParser.parse("{\"a\":1}".data(using: .utf8)!); check(false, "no window -> error") }
catch let e as UsageParseError { check(e == .noWindows, "no window -> noWindows") }
catch { check(false, "wrong error type") }

check(UsageLevel(percent: 59.9) == .ok && UsageLevel(percent: 60) == .warn && UsageLevel(percent: 85) == .critical, "color thresholds")
check(TimeFormat.remaining(until: now.addingTimeInterval(3*3600 + 40*60), from: now) == "3h 40m", "3h 40m")
check(TimeFormat.remaining(until: now.addingTimeInterval(2*86400 + 9*3600), from: now) == "2d 9h", "2d 9h")
check(TimeFormat.remaining(until: now.addingTimeInterval(-5), from: now) == "now", "past -> now")

let img = BarRenderer.statusImage(top: 2, bottom: 45.5)
check(img.size.width > 40 && img.size.height <= 22, "menu bar image \(Int(img.size.width))x\(Int(img.size.height))")

// MARK: Claude Code credentials round-trip (fake values)
let credsJSON = """
{"claudeAiOauth":{"accessToken":"fake-access-old","refreshToken":"fake-refresh-old","expiresAt":1758540000000,
 "scopes":["user:inference","user:profile"],"subscriptionType":"max"},"other":{"keep":true}}
""".data(using: .utf8)!
let creds = ClaudeCodeCredentials.parse(credsJSON)!
check(creds.accessToken == "fake-access-old" && creds.refreshToken == "fake-refresh-old", "credentials read")
check(creds.hasProfileScope, "user:profile scope detected")
let inferenceOnly = ClaudeCodeCredentials.parse("{\"claudeAiOauth\":{\"accessToken\":\"x\",\"scopes\":[\"user:inference\"]}}".data(using: .utf8)!)!
check(!inferenceOnly.hasProfileScope, "setup-token (inference only) rejected")
check(ClaudeCodeCredentials.parse("{\"claudeAiOauth\":{\"accessToken\":\"\"}}".data(using: .utf8)!) == nil, "empty token -> nil")
let t0 = Date(timeIntervalSince1970: 1758540000 - 30)
check(creds.isExpiring(within: 60, now: t0) && !creds.isExpiring(within: 10, now: t0), "upcoming expiry detected")
let rotated = creds.updated(accessToken: "fake-access-new", refreshToken: "fake-refresh-new", expiresIn: 3600, now: t0)!
let rot = ClaudeCodeCredentials.parse(rotated)!
let rotObj = try! JSONSerialization.jsonObject(with: rotated) as! [String: Any]
check(rot.accessToken == "fake-access-new" && rot.refreshToken == "fake-refresh-new", "tokens replaced")
check(rot.expiresAt == t0.addingTimeInterval(3600), "expiresAt recomputed")
let keptOther = (rotObj["other"] as? [String: Any])?["keep"] as? Bool == true
let keptSub = ((rot.raw["claudeAiOauth"] as? [String: Any])?["subscriptionType"] as? String) == "max"
check(keptOther && keptSub, "other fields kept")

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
