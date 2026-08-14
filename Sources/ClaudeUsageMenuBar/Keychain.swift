import Foundation
import Security

/// The Claude Code CLI stores its OAuth credentials as a generic password
/// under this service name.
private let credentialsService = "Claude Code-credentials"

struct ClaudeCredentials: Decodable {
    struct OAuth: Decodable {
        let accessToken: String
    }

    let claudeAiOauth: OAuth
}

enum KeychainError: Error {
    case itemNotFound
    case unhandled(OSStatus)
    case malformedCredentials
}

enum Keychain {
    /// `security` exits 44 when no matching item exists.
    private static let itemNotFoundExitCode: Int32 = 44

    static func claudeCredentials() async throws -> ClaudeCredentials {
        try await Task.detached(priority: .utility) { try readCredentials() }.value
    }

    /// The read is delegated to `/usr/bin/security` rather than performed with
    /// SecItemCopyMatching. Claude Code rewrites this item whenever it refreshes
    /// the OAuth token, and that invalidates the stored authorization for every
    /// other application, so an in-process read asks for the login password
    /// again after each refresh no matter how the app is signed or which ACL
    /// entries it holds. `security` belongs to the item's `apple-tool:`
    /// partition, which is not invalidated that way.
    ///
    /// The token is read from the pipe, never passed as an argument, so it does
    /// not appear in the process list.
    private static func readCredentials() throws -> ClaudeCredentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", credentialsService,
            "-a", NSUserName(),
            "-w"
        ]

        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
        } catch {
            throw KeychainError.unhandled(errSecInternalError)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errorOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            if process.terminationStatus == itemNotFoundExitCode {
                throw KeychainError.itemNotFound
            }
            // Reported as an auth failure so the dropdown explains the denial
            // rather than showing a bare exit code.
            if errorText.contains("User interaction is not allowed")
                || errorText.contains("The user name or passphrase you entered is not correct") {
                throw KeychainError.unhandled(errSecAuthFailed)
            }
            throw KeychainError.unhandled(OSStatus(process.terminationStatus))
        }

        do {
            return try JSONDecoder().decode(ClaudeCredentials.self, from: data)
        } catch {
            throw KeychainError.malformedCredentials
        }
    }
}
