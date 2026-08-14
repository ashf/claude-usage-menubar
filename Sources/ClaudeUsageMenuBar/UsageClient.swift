import Foundation
import Security

enum UsageError: Error {
    case noCredentials
    case keychainDenied
    case malformedCredentials
    case keychainFailure(OSStatus)
    case signedOut
    case rateLimited(retryAfter: TimeInterval?)
    case badResponse(Int)
    case network(String)
    case decoding(String)
}

/// Fetches the usage windows backing the Claude desktop app's Usage panel.
struct UsageClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        session = URLSession(configuration: configuration)
    }

    func fetch() async throws -> UsageSnapshot {
        do {
            return try await fetchOnce()
        } catch UsageError.signedOut {
            // Claude Code may have rotated the token between reads, so the
            // Keychain is consulted again before giving up.
            return try await fetchOnce()
        }
    }

    private func fetchOnce() async throws -> UsageSnapshot {
        let credentials: ClaudeCredentials
        do {
            credentials = try Keychain.claudeCredentials()
        } catch KeychainError.itemNotFound {
            throw UsageError.noCredentials
        } catch KeychainError.malformedCredentials {
            throw UsageError.malformedCredentials
        } catch KeychainError.unhandled(let status) {
            switch status {
            case errSecAuthFailed, errSecInteractionNotAllowed, errSecInteractionRequired, errSecUserCanceled:
                throw UsageError.keychainDenied
            default:
                throw UsageError.keychainFailure(status)
            }
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("Bearer \(credentials.claudeAiOauth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.network("Unexpected response")
        }

        if http.statusCode == 401 { throw UsageError.signedOut }
        if http.statusCode == 429 {
            throw UsageError.rateLimited(retryAfter: Self.retryAfter(from: http))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UsageError.badResponse(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(UsageSnapshot.self, from: data)
        } catch {
            throw UsageError.decoding(error.localizedDescription)
        }
    }

    /// `Retry-After` as seconds or an HTTP date. This endpoint often sends `0`,
    /// which carries no delay, so anything non-positive is reported as absent
    /// and the caller falls back to its own backoff.
    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }

        if let seconds = TimeInterval(value) {
            return seconds > 0 ? seconds : nil
        }

        guard let date = httpDateFormatter.date(from: value) else { return nil }
        let delay = date.timeIntervalSinceNow
        return delay > 0 ? delay : nil
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}
