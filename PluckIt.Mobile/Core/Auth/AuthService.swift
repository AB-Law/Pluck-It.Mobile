import Foundation
import Combine

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
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var identity: AppIdentity?
    @Published private(set) var isSignedIn = false
    @Published private(set) var lastAuthError: String?

    private let runtimeConfiguration: RuntimeConfiguration

    init(runtimeConfiguration: RuntimeConfiguration) {
        self.runtimeConfiguration = runtimeConfiguration
    }

    /// Initializes auth state from persisted local storage.
    func bootstrap() {
        if let value = UserDefaults.standard.string(forKey: "pluckIt.local.identity") {
            identity = try? JSONDecoder().decode(AppIdentity.self, from: Data(base64Encoded: value) ?? Data())
            isSignedIn = identity != nil
        }

        if !isSignedIn, runtimeConfiguration.skipAuthHeader || runtimeConfiguration.mockUserId != nil || runtimeConfiguration.mockUserEmail != nil {
            // Conservative fallback for local development without persisted identity.
            // Keeps local user identity available even when auth headers are intentionally skipped.
            isSignedIn = true
            let fallback = AppIdentity(
                userId: runtimeConfiguration.mockUserId ?? "local-dev-user",
                email: runtimeConfiguration.mockUserEmail ?? "local@pluckit.test",
                token: nil,
                isLocalMock: true
            )
            identity = fallback
            persist(identity: fallback)
        } else if !isSignedIn, !runtimeConfiguration.skipAuthHeader {
            isSignedIn = true
            let fallback = AppIdentity(
                userId: runtimeConfiguration.mockUserId ?? "local-dev-user",
                email: runtimeConfiguration.mockUserEmail ?? "local@pluckit.test",
                token: nil,
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
    }

    /// Provides a bearer token for API requests.
    ///
    /// If local-only mode is enabled, this returns `nil` so clients can skip Authorization.
    func currentToken() async -> String? {
        guard isSignedIn else { return nil }
        if let token = identity?.token, !token.isEmpty { return token }
        if runtimeConfiguration.skipAuthHeader { return nil }
        return identity?.userId
    }

    /// Updates current local identity and persists it.
    func signInMock(userId: String, email: String?) {
        let nextIdentity = AppIdentity(
            userId: userId,
            email: email,
            token: nil,
            isLocalMock: true
        )
        identity = nextIdentity
        isSignedIn = true
        persist(identity: nextIdentity)
        lastAuthError = nil
    }

    /// Persists identity into user defaults.
    private func persist(identity: AppIdentity) {
        if let data = try? JSONEncoder().encode(identity) {
            UserDefaults.standard.setValue(data.base64EncodedString(), forKey: "pluckIt.local.identity")
        }
    }
}
