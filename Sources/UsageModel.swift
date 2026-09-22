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
    /// Bottom bar: weekly Fable when the API reports it, else weekly all models.
    var secondBar: UsageWindow? { weeklyFable ?? weeklyAll }
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
        "five_hour": "5 h",
        "seven_day": "Hebdo · tous modèles",
        "seven_day_oauth_apps": "Hebdo · apps OAuth",
    ]
    static let ignoredKeys: Set<String> = ["extra_usage", "seven_day_overage_included"]

    static func label(for key: String) -> String {
        if let l = labels[key] { return l }
        if key.hasPrefix("seven_day_") {
            let model = String(key.dropFirst("seven_day_".count))
            return "Hebdo · " + model.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else {
            throw UsageParseError.invalidJSON
        }
        var windows: [UsageWindow] = []
        for (key, value) in dict where !ignoredKeys.contains(key) {
            guard let w = value as? [String: Any],
                  let util = number(w["utilization"]) ?? number(w["used_percentage"]) else { continue }
            let resets = (w["resets_at"] as? String).flatMap(parseDate)
            windows.append(UsageWindow(key: key, label: label(for: key), percent: util, resetsAt: resets))
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

    static func parseDate(_ s: String) -> Date? {
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
    /// "3h 40m", "2j 9h", "12m", "maintenant"
    static func remaining(until date: Date, from now: Date = Date()) -> String {
        let secs = Int(date.timeIntervalSince(now))
        if secs <= 0 { return "maintenant" }
        let days = secs / 86400
        let hours = (secs % 86400) / 3600
        let mins = (secs % 3600) / 60
        if days > 0 { return "\(days)j \(hours)h" }
        if hours > 0 { return "\(hours)h \(String(format: "%02d", mins))m" }
        return "\(max(mins, 1))m"
    }
}
