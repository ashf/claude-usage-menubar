import Foundation

/// Codex rate limits, read live from the endpoint behind the CLI's `/status`
/// with the CLI's ChatGPT token. When that fails (API-key login, expired token,
/// network), the last `rate_limits` record from the CLI's session logs is used.
enum CodexUsage {
    /// `recordedAt` is nil for a live reading and the log record's time otherwise.
    struct Reading {
        let snapshot: UsageSnapshot
        let recordedAt: Date?
    }

    private static let codexHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex")
    private static let sessionsDirectory = codexHome.appendingPathComponent("sessions")
    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let logsScanned = 20

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func latest() async -> Reading? {
        if let live = await fetchLive() { return live }
        return await Task.detached(priority: .utility) { readLogs() }.value
    }

    private static func fetchLive() async -> Reading? {
        guard let data = try? Data(contentsOf: codexHome.appendingPathComponent("auth.json")),
              let tokens = try? decoder.decode(Auth.self, from: data).tokens else { return nil }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(tokens.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (body, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let snapshot = parseLive(body)
        else { return nil }
        return Reading(snapshot: snapshot, recordedAt: nil)
    }

    private static func readLogs() -> Reading? {
        for log in newestLogs() {
            guard let text = try? String(contentsOf: log, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
                if let reading = parse(Data(line.utf8)) { return reading }
            }
        }
        return nil
    }

    private static func newestLogs() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory, includingPropertiesForKeys: keys
        ) else { return [] }

        let logs = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
        }
        return Array(logs.sorted { modified($0) > modified($1) }.prefix(logsScanned))
    }

    static func parse(_ line: Data) -> Reading? {
        guard let event = try? decoder.decode(Event.self, from: line),
              let rateLimits = event.payload?.rateLimits,
              let snapshot = snapshot(rateLimits.primary, rateLimits.secondary) else { return nil }
        return Reading(snapshot: snapshot, recordedAt: event.timestamp.flatMap(UsageLimit.isoDate(from:)))
    }

    static func parseLive(_ body: Data) -> UsageSnapshot? {
        guard let status = try? decoder.decode(LiveStatus.self, from: body) else { return nil }
        return snapshot(status.rateLimit?.primaryWindow, status.rateLimit?.secondaryWindow)
    }

    private static func snapshot(_ primary: Window?, _ secondary: Window?) -> UsageSnapshot? {
        let limits = [
            primary?.limit(kind: "session", group: "session"),
            secondary?.limit(kind: "weekly", group: "weekly")
        ].compactMap { $0 }
        return limits.isEmpty ? nil : UsageSnapshot(limits: limits)
    }

    private struct Auth: Decodable {
        struct Tokens: Decodable {
            let accessToken: String
            let accountId: String
        }

        let tokens: Tokens?
    }

    private struct LiveStatus: Decodable {
        struct Details: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?
        }

        let rateLimit: Details?
    }

    private struct Event: Decodable {
        struct Payload: Decodable {
            let rateLimits: RateLimits?
        }

        let timestamp: String?
        let payload: Payload?
    }

    private struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    /// The logs spell the reset `resets_at` and the endpoint `reset_at`.
    private struct Window: Decodable {
        let usedPercent: Double
        let resetsAt: TimeInterval?
        let resetAt: TimeInterval?

        /// A window whose reset has passed since the reading was taken is empty again.
        func limit(kind: String, group: String) -> UsageLimit {
            let reset = (resetsAt ?? resetAt).map(Date.init(timeIntervalSince1970:))
            let expired = reset.map { $0 <= Date() } ?? false
            return UsageLimit(
                kind: kind,
                group: group,
                percent: expired ? 0 : Int(usedPercent.rounded()),
                resetsAt: expired ? nil : reset
            )
        }
    }
}
