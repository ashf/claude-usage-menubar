import Foundation

/// One row of the Usage panel, as returned in the response's `limits` array.
/// `kind` and `severity` stay plain strings so values the server adds later
/// still decode and render.
struct UsageLimit: Decodable {
    struct Scope: Decodable {
        struct Model: Decodable {
            let id: String?
            let displayName: String?

            private enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
            }
        }

        let model: Model?
    }

    let kind: String
    let group: String
    let percent: Int
    let severity: String
    let resetsAt: Date?
    let scope: Scope?
    let isActive: Bool

    private enum CodingKeys: String, CodingKey {
        case kind
        case group
        case percent
        case severity
        case resetsAt = "resets_at"
        case scope
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        group = try container.decode(String.self, forKey: .group)
        percent = try container.decodeIfPresent(Int.self, forKey: .percent) ?? 0
        severity = try container.decodeIfPresent(String.self, forKey: .severity) ?? "normal"
        scope = try container.decodeIfPresent(Scope.self, forKey: .scope)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false

        if let text = try container.decodeIfPresent(String.self, forKey: .resetsAt) {
            resetsAt = Self.isoDate(from: text)
        } else {
            resetsAt = nil
        }
    }

    private static func isoDate(from text: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: text) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    var label: String {
        switch kind {
        case "session": return "Current session"
        case "weekly_all": return "All models"
        case "weekly_scoped": return scope?.model?.displayName ?? "Scoped"
        default: return UsageFormat.humanize(kind)
        }
    }

    var timeRemaining: TimeInterval? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }
}

struct UsageSnapshot: Decodable {
    let limits: [UsageLimit]

    var sessionLimit: UsageLimit? {
        limits.first { $0.kind == "session" } ?? limits.first { $0.group == "session" }
    }

    func limits(inGroup group: String) -> [UsageLimit] {
        limits.filter { $0.group == group }
    }

    var otherGroups: [String] {
        var seen = Set(["session", "weekly"])
        var ordered: [String] = []
        for limit in limits where seen.insert(limit.group).inserted {
            ordered.append(limit.group)
        }
        return ordered
    }
}

enum UsageFormat {
    /// Menu bar form: `2h31m`, or `47m` under an hour.
    static func compactRemaining(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
    }

    /// Dropdown form: `2 hr 31 min`, or `47 min` under an hour.
    static func spelledRemaining(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
    }

    static func resetLine(for limit: UsageLimit) -> String? {
        guard let remaining = limit.timeRemaining else { return nil }
        return "Resets in \(spelledRemaining(remaining))"
    }

    static func ringGlyph(forPercent percent: Int) -> String {
        switch percent {
        case ..<13: return "○"
        case ..<38: return "◔"
        case ..<63: return "◑"
        case ..<88: return "◕"
        default: return "●"
        }
    }

    static func humanize(_ identifier: String) -> String {
        let spaced = identifier.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    static func relativeUpdated(_ date: Date) -> String {
        let elapsed = Int(max(Date().timeIntervalSince(date), 0))
        if elapsed < 10 { return "just now" }
        if elapsed < 60 { return "\(elapsed)s ago" }
        let minutes = elapsed / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}
