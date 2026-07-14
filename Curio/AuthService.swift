import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

// MARK: - AuthSession
struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var userID: String
    var email: String?
}

enum AuthError: LocalizedError {
    case missingIdentityToken
    case cancelled
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken: return "Apple didn't return an identity token."
        case .cancelled: return "Sign-in was cancelled."
        case .server(let message): return message
        }
    }
}

// MARK: - AuthService
// Hand-rolled REST against Supabase's GoTrue auth API — same style as
// NewsService.swift's SupabaseNewsService, no SDK dependency. The anon key is
// safe to embed (same key already shipped for reading stories); GoTrue itself
// is what verifies the Apple identity token, not this key.
struct AuthService {
    private let baseURL = URL(string: "https://mixkzotcnwvkdvlxhobe.supabase.co/auth/v1")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1peGt6b3Rjbnd2a2R2bHhob2JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4NzI0ODYsImV4cCI6MjA5ODQ0ODQ4Nn0.3ALwtoucsBj976IN02l4bvkHz2Vaog6fVQaPvxHDVOE"

    // MARK: Apple sign-in
    @MainActor
    func signInWithApple() async throws -> AuthSession {
        let rawNonce = Self.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)

        let coordinator = AppleSignInCoordinator()
        let credential = try await coordinator.perform(request)
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.missingIdentityToken
        }
        return try await exchangeIDToken(idToken, nonce: rawNonce)
    }

    private func exchangeIDToken(_ idToken: String, nonce: String) async throws -> AuthSession {
        let url = baseURL.appendingPathComponent("token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "id_token")])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "provider": "apple", "id_token": idToken, "nonce": nonce,
        ])
        return try await send(request)
    }

    // MARK: Refresh (call on launch to restore a session from the stored refresh token)
    func refresh(_ refreshToken: String) async throws -> AuthSession {
        let url = baseURL.appendingPathComponent("token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])
        return try await send(request)
    }

    // MARK: Sign out
    func signOut(accessToken: String) async {
        var request = URLRequest(url: baseURL.appendingPathComponent("logout"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private func send(_ request: URLRequest) async throws -> AuthSession {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error_description"]
                ?? "Sign-in failed."
            throw AuthError.server(message)
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AuthSession(accessToken: token.accessToken, refreshToken: token.refreshToken,
                            userID: token.user.id, email: token.user.email)
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let user: SupabaseUser
        struct SupabaseUser: Decodable { let id: String; let email: String? }
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token", user
        }
    }

    // MARK: Nonce (Apple requires the sha256 in the request; Supabase verifies
    // against the raw value to prevent replay)
    private static func randomNonce(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            precondition(status == errSecSuccess)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - AppleSignInCoordinator
// Bridges ASAuthorizationController's delegate callbacks to async/await.
@MainActor
private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
                                             ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    func perform(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                  didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation?.resume(returning: credential)
        } else {
            continuation?.resume(throwing: AuthError.missingIdentityToken)
        }
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: AuthError.cancelled)
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
