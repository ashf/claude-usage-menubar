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
    static func claudeCredentials() throws -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialsService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unhandled(status)
        }

        guard let data = item as? Data else { throw KeychainError.malformedCredentials }

        do {
            return try JSONDecoder().decode(ClaudeCredentials.self, from: data)
        } catch {
            throw KeychainError.malformedCredentials
        }
    }
}
