import Foundation

enum UsageError: Error {
    case noCredentials
    case signedOut
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
        } catch {
            throw UsageError.noCredentials
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
        guard (200..<300).contains(http.statusCode) else {
            throw UsageError.badResponse(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(UsageSnapshot.self, from: data)
        } catch {
            throw UsageError.decoding(error.localizedDescription)
        }
    }
}
