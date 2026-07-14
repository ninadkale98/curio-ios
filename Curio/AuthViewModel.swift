import Foundation
import Security
import Observation

// MARK: - AuthViewModel
// Holds the current session, persists it to Keychain (not UserDefaults —
// these are real bearer tokens), and refreshes it on launch.
@MainActor
@Observable
final class AuthViewModel {
    private(set) var session: AuthSession?
    private(set) var isSigningIn = false
    private(set) var errorMessage: String?

    private let service = AuthService()
    private let keychainKey = "com.curio.newsreel.authSession"

    var isSignedIn: Bool { session != nil }

    init() {
        session = Self.loadFromKeychain(key: keychainKey)
    }

    /// Call once at launch — silently refreshes a stored session, or signs
    /// the user out locally if the refresh token is no longer valid.
    func restoreSession() async {
        guard let session else { return }
        do {
            let refreshed = try await service.refresh(session.refreshToken)
            self.session = refreshed
            Self.saveToKeychain(refreshed, key: keychainKey)
        } catch {
            self.session = nil
            Self.deleteFromKeychain(key: keychainKey)
        }
    }

    func signInWithApple() async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let session = try await service.signInWithApple()
            self.session = session
            Self.saveToKeychain(session, key: keychainKey)
        } catch AuthError.cancelled {
            // No error banner for a plain user-cancelled sheet.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        if let session { await service.signOut(accessToken: session.accessToken) }
        session = nil
        Self.deleteFromKeychain(key: keychainKey)
    }

    // MARK: Keychain
    private static func saveToKeychain(_ session: AuthSession, key: String) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func loadFromKeychain(key: String) -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    private static func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
