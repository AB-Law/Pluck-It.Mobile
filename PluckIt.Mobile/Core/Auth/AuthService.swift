import Foundation
import Combine
import GoogleSignIn
import UIKit

/// Represents the current authenticated identity in local app sessions.
struct AppIdentity: Codable, Equatable {
    let userId: String
    let email: String?
    let token: String?
    let isLocalMock: Bool
}

/// Authentication facade used by API clients and services.
///
/// For the local-first roadmap, this implementation supports:
/// - token-relay integration when remote auth is available
/// - mock local identity for backend parity checks when auth headers are disabled
/// - Google Sign-In token exchange for production-ready session tokens
@MainActor
final class AuthService: ObservableObject {
    enum AuthError: LocalizedError {
        case missingGoogleClientId
        case missingGoogleIdToken
        case missingExchangeToken
        case exchangeFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingGoogleClientId:
                return "Google OAuth is not configured. Set PLUCKIT_GOOGLE_CLIENT_ID or include GoogleService-Info.plist."
            case .missingGoogleIdToken:
                return "Google Sign-In did not return an ID token."
            case .missingExchangeToken:
                return "Auth relay response did not include an app token."
            case .exchangeFailed(let message):
                return "Failed to exchange Google token: \(message)"
            }
        }
    }

    @Published private(set) var identity: AppIdentity?
    @Published private(set) var isSignedIn = false
    @Published private(set) var lastAuthError: String?

    private let runtimeConfiguration: RuntimeConfiguration
    private let tokenExchangeClient: APIClient

    /// Creates the auth service.
    ///
    /// - Parameters:
    ///   - runtimeConfiguration: Resolved runtime configuration from env/plist.
    ///   - tokenExchangeClient: Client for unauthenticated Google token exchange.
    init(runtimeConfiguration: RuntimeConfiguration, tokenExchangeClient: APIClient) {
        self.runtimeConfiguration = runtimeConfiguration
        self.tokenExchangeClient = tokenExchangeClient
    }

    /// Initializes auth state from persisted local storage.
    func bootstrap() {
        if let value = UserDefaults.standard.string(forKey: "pluckIt.local.identity") {
            identity = try? JSONDecoder().decode(AppIdentity.self, from: Data(base64Encoded: value) ?? Data())
            isSignedIn = identity != nil

            if isSignedIn,
               !runtimeConfiguration.useMockAuthFallback,
               (identity?.isLocalMock == true) {
                identity = nil
                isSignedIn = false
                UserDefaults.standard.removeObject(forKey: "pluckIt.local.identity")
            }
        }

        if !isSignedIn, runtimeConfiguration.useMockAuthFallback {
            isSignedIn = true
            let fallback = AppIdentity(
                userId: runtimeConfiguration.mockUserId ?? "local-dev-user",
                email: runtimeConfiguration.mockUserEmail ?? "local@pluckit.test",
                token: runtimeConfiguration.localMockToken,
                isLocalMock: true
            )
            identity = fallback
            persist(identity: fallback)
        }
    }

    /// Clears in-memory and persisted auth state.
    func signOut() {
        identity = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: "pluckIt.local.identity")
        GIDSignIn.sharedInstance.signOut()
    }

    /// Provides a bearer token for API requests.
    ///
    /// If local-only mode is enabled, this returns `nil` so clients can skip Authorization.
    func currentToken() async -> String? {
        guard isSignedIn else { return nil }
        if runtimeConfiguration.skipAuthHeader { return nil }
        if let token = identity?.token, !token.isEmpty { return token }
        return runtimeConfiguration.useMockAuthFallback ? identity?.userId : nil
    }

    /// Updates current local identity and persists it.
    /// - Parameters:
    ///   - userId: Local user identifier.
    ///   - email: Optional local email.
    ///   - token: Optional local token.
    func signInMock(userId: String, email: String?, token: String? = nil) {
        let nextIdentity = AppIdentity(
            userId: userId,
            email: email,
            token: token,
            isLocalMock: true
        )
        identity = nextIdentity
        isSignedIn = true
        persist(identity: nextIdentity)
        lastAuthError = nil
    }

    /// Signs in with Google and exchanges the Google ID token for an app token.
    ///
    /// - Parameter presentingViewController: Controller used for presenting Google sign-in UI.
    func signInWithGoogle(presentingViewController: UIViewController) async throws {
        guard let googleClientId = runtimeConfiguration.googleClientId else {
            throw AuthError.missingGoogleClientId
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientId)

        let signInResult: GIDSignInResult
        do {
            signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        } catch {
            self.lastAuthError = error.localizedDescription
            throw error
        }

        guard let idToken = signInResult.user.idToken?.tokenString else {
            let error = AuthError.missingGoogleIdToken
            lastAuthError = error.localizedDescription
            throw error
        }

        do {
            let body = try tokenExchangeClient.jsonEncoder.encode(MobileAuthRequest(idToken: idToken))
            let response: MobileAuthResponse = try await tokenExchangeClient.send(
                method: "POST",
                path: runtimeConfiguration.googleTokenExchangePath,
                body: body
            )

            guard let appToken = resolveToken(from: response) else {
                let error = AuthError.missingExchangeToken
                self.lastAuthError = error.localizedDescription
                throw error
            }

            let nextIdentity = AppIdentity(
                userId: resolveUserId(from: response, fallback: signInResult.user.userID),
                email: resolveEmail(from: response, fallback: signInResult.user.profile?.email),
                token: appToken,
                isLocalMock: false
            )
            identity = nextIdentity
            isSignedIn = true
            persist(identity: nextIdentity)
            lastAuthError = nil
        } catch {
            let exchangeError = AuthError.exchangeFailed(String(describing: error))
            lastAuthError = exchangeError.localizedDescription
            throw exchangeError
        }
    }

    /// Stores identity state to local storage.
    ///
    /// - Parameter identity: The identity object to persist.
    func persist(identity: AppIdentity) {
        if let data = try? JSONEncoder().encode(identity) {
            UserDefaults.standard.setValue(data.base64EncodedString(), forKey: "pluckIt.local.identity")
        }
    }

    /// Resolves a usable token from Google auth response payloads.
    private func resolveToken(from response: MobileAuthResponse) -> String? {
        response.accessToken
            ?? response.token
            ?? response.sessionToken
            ?? response.appToken
            ?? response.idToken
            ?? resolveToken(from: response.data)
    }

    private func resolveToken(from response: MobileAuthResponsePayload?) -> String? {
        guard let response else { return nil }
        return response.accessToken
            ?? response.token
            ?? response.sessionToken
            ?? response.appToken
            ?? response.idToken
    }

    private func resolveUserId(from response: MobileAuthResponse, fallback: String?) -> String {
        response.userId
            ?? response.user?.userId
            ?? response.user?.id
            ?? response.user?.sub
            ?? resolveUserId(from: response.data, fallback: nil)
            ?? fallback
            ?? "local-dev-user"
    }

    private func resolveUserId(from response: MobileAuthResponsePayload?, fallback: String?) -> String? {
        guard let response else { return fallback }
        return response.userId
            ?? response.user?.userId
            ?? response.user?.id
            ?? response.user?.sub
            ?? fallback
    }

    private func resolveEmail(from response: MobileAuthResponse, fallback: String?) -> String? {
        response.email
            ?? response.user?.email
            ?? resolveEmail(from: response.data, fallback: nil)
            ?? fallback
    }

    private func resolveEmail(from response: MobileAuthResponsePayload?, fallback: String?) -> String? {
        guard let response else { return fallback }
        return response.email
            ?? response.user?.email
            ?? fallback
    }
}

private struct MobileAuthRequest: Encodable {
    let idToken: String
}

private struct MobileAuthResponse: Decodable {
    let accessToken: String?
    let token: String?
    let sessionToken: String?
    let appToken: String?
    let idToken: String?
    let userId: String?
    let email: String?
    let user: MobileAuthUser?
    let data: MobileAuthResponsePayload?
}

private struct MobileAuthUser: Decodable {
    let id: String?
    let userId: String?
    let email: String?
    let sub: String?
}

private struct MobileAuthResponsePayload: Decodable {
    let accessToken: String?
    let token: String?
    let sessionToken: String?
    let appToken: String?
    let idToken: String?
    let userId: String?
    let email: String?
    let user: MobileAuthUser?
}
