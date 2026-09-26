import Foundation

struct UsageWindow: Equatable {
    let key: String
    let label: String
    let percent: Double
    let resetsAt: Date?

    var isFiveHour: Bool { key == "five_hour" }
    var isWeeklyAll: Bool { key == "seven_day" }
    var isFable: Bool { key.hasPrefix("seven_day") && key.lowercased().contains("fable") }
}

struct ExtraUsage: Equatable {
    let enabled: Bool
    let usedCredits: Double
    let monthlyLimit: Double
}

struct UsageSnapshot: Equatable {
    let windows: [UsageWindow]
    let extra: ExtraUsage?
    let fetchedAt: Date

    var fiveHour: UsageWindow? { windows.first { $0.isFiveHour } }
    var weeklyAll: UsageWindow? { windows.first { $0.isWeeklyAll } }
    var weeklyFable: UsageWindow? { windows.first { $0.isFable } }
}

/// Which two windows the menu bar shows, top then bottom. Chosen in the menu, stored in UserDefaults.
enum BarPair: String, CaseIterable {
    case fiveHourAll, fiveHourFable, allFable   // menu order: 5, W, F

    static let `default` = BarPair.fiveHourFable

    var title: String {
        switch self {
        case .fiveHourFable: return "5-hour + Weekly Fable"
        case .fiveHourAll: return "5-hour + Weekly all models"
        case .allFable: return "Weekly all models + Weekly Fable"
        }
    }

    /// Missing Fable falls back to weekly all models, or to 5 h when weekly all is already shown.
    func windows(in s: UsageSnapshot) -> (top: UsageWindow?, bottom: UsageWindow?) {
        switch self {
        case .fiveHourFable: return (s.fiveHour, s.weeklyFable ?? s.weeklyAll)
        case .fiveHourAll: return (s.fiveHour, s.weeklyAll)
        case .allFable: return (s.weeklyAll, s.weeklyFable ?? s.fiveHour)
        }
    }
}

/// How the menu bar draws usage: two stacked bars (see BarPair) or one ring per limit.
enum BarStyle: String, CaseIterable {
    case rings, bars

    static let `default` = BarStyle.rings

    var title: String {
        switch self {
        case .bars: return "Bars"
        case .rings: return "Rings"
        }
    }

}

/// Which limits the Rings style shows, always in 5, W, F order. Chosen in the menu, stored in UserDefaults.
enum RingSet: String, CaseIterable {
    case all, fiveHourAll, fiveHourFable, allFable

    static let `default` = RingSet.all

    var title: String {
        switch self {
        case .all: return "5-hour + Weekly all models + Weekly Fable"
        case .fiveHourAll: return "5-hour + Weekly all models"
        case .fiveHourFable: return "5-hour + Weekly Fable"
        case .allFable: return "Weekly all models + Weekly Fable"
        }
    }

    /// Skips any limit the plan does not report.
    func rings(in s: UsageSnapshot) -> [(letter: String, percent: Double)] {
        let all: [(String, UsageWindow?)] = [("5", s.fiveHour), ("W", s.weeklyAll), ("F", s.weeklyFable)]
        let letters: Set<String>
        switch self {
        case .all: letters = ["5", "W", "F"]
        case .fiveHourAll: letters = ["5", "W"]
        case .fiveHourFable: letters = ["5", "F"]
        case .allFable: letters = ["W", "F"]
        }
        return all.compactMap { letter, w in letters.contains(letter) ? w.map { (letter, $0.percent) } : nil }
    }
}

enum UsageLevel {
    case ok, warn, critical

    init(percent: Double) {
        switch percent {
        case ..<60: self = .ok
        case ..<85: self = .warn
        default: self = .critical
        }
    }
}

enum UsageParseError: Error, Equatable {
    case invalidJSON
    case noWindows
}

/// Parses the response of GET https://api.anthropic.com/api/oauth/usage.
enum UsageParser {
    static let labels: [String: String] = [
        "five_hour": "5-hour session",
        "seven_day": "Weekly · all models",
        "seven_day_oauth_apps": "Weekly · OAuth apps",
    ]
    static let ignoredKeys: Set<String> = ["extra_usage", "seven_day_overage_included"]

    static func label(for key: String) -> String {
        if let l = labels[key] { return l }
        if key.hasPrefix("seven_day_") {
            let model = String(key.dropFirst("seven_day_".count))
            return "Weekly · " + model.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else {
            throw UsageParseError.invalidJSON
        }
        var windows: [UsageWindow] = []
        // Top-level windows: five_hour, seven_day, seven_day_<model>. Anything else (internal keys) is ignored.
        for (key, value) in dict where key == "five_hour" || key.hasPrefix("seven_day") {
            guard !ignoredKeys.contains(key), let w = value as? [String: Any],
                  let util = number(w["utilization"]) ?? number(w["used_percentage"]) else { continue }
            windows.append(UsageWindow(key: key, label: label(for: key), percent: util, resetsAt: parseDate(w["resets_at"])))
        }
        // Per-model weekly limits: "limits": [{kind: "weekly_scoped", scope: {model: {display_name}}, percent, resets_at}]
        for item in (dict["limits"] as? [[String: Any]]) ?? [] {
            guard item["kind"] as? String == "weekly_scoped",
                  let model = ((item["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String,
                  let pct = number(item["percent"]) ?? number(item["utilization"]) else { continue }
            let key = "seven_day_" + model.lowercased().replacingOccurrences(of: " ", with: "_")
            windows.append(UsageWindow(key: key, label: "Weekly · \(model)", percent: pct, resetsAt: parseDate(item["resets_at"])))
        }
        guard !windows.isEmpty else { throw UsageParseError.noWindows }
        let order = ["five_hour": 0, "seven_day": 1]
        windows.sort { (order[$0.key] ?? 2, $0.key) < (order[$1.key] ?? 2, $1.key) }

        var extra: ExtraUsage? = nil
        if let e = dict["extra_usage"] as? [String: Any] {
            extra = ExtraUsage(enabled: (e["is_enabled"] as? Bool) ?? false,
                               usedCredits: number(e["used_credits"]) ?? 0,
                               monthlyLimit: number(e["monthly_limit"]) ?? 0)
        }
        return UsageSnapshot(windows: windows, extra: extra, fetchedAt: now)
    }

    /// Accepts an ISO 8601 string or a Unix timestamp in seconds (the `limits` array uses the latter).
    static func parseDate(_ v: Any?) -> Date? {
        if let n = number(v) { return n > 0 ? Date(timeIntervalSince1970: n) : nil }
        guard let s = v as? String else { return nil }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }

    private static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }
}

enum TimeFormat {
    /// "3h 40m", "2d 9h", "12m", "now"
    static func remaining(until date: Date, from now: Date = Date()) -> String {
        let secs = Int(date.timeIntervalSince(now))
        if secs <= 0 { return "now" }
        let days = secs / 86400
        let hours = (secs % 86400) / 3600
        let mins = (secs % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(String(format: "%02d", mins))m" }
        return "\(max(mins, 1))m"
    }
}
