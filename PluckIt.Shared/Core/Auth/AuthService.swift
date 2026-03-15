import Foundation
import Combine
import GoogleSignIn
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Represents the current authenticated identity in local app sessions.
struct AppIdentity: Codable, Equatable {
    let userId: String
    let email: String?
    let token: String?
    let refreshToken: String?
    let accessTokenExpiresAt: Date?
    let refreshTokenExpiresAt: Date?
    let isLocalMock: Bool

    init(
        userId: String,
        email: String?,
        token: String?,
        refreshToken: String?,
        accessTokenExpiresAt: Date?,
        refreshTokenExpiresAt: Date?,
        isLocalMock: Bool
    ) {
        self.userId = userId
        self.email = email
        self.token = token
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.isLocalMock = isLocalMock
    }

    enum CodingKeys: String, CodingKey {
        case userId
        case email
        case token
        case refreshToken
        case accessTokenExpiresAt
        case refreshTokenExpiresAt
        case isLocalMock
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.token = try container.decodeIfPresent(String.self, forKey: .token)
        self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        self.accessTokenExpiresAt = try container.decodeIfPresent(Date.self, forKey: .accessTokenExpiresAt)
        self.refreshTokenExpiresAt = try container.decodeIfPresent(Date.self, forKey: .refreshTokenExpiresAt)
        self.isLocalMock = try container.decode(Bool.self, forKey: .isLocalMock)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(token, forKey: .token)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encodeIfPresent(accessTokenExpiresAt, forKey: .accessTokenExpiresAt)
        try container.encodeIfPresent(refreshTokenExpiresAt, forKey: .refreshTokenExpiresAt)
        try container.encode(isLocalMock, forKey: .isLocalMock)
    }
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
        case missingRefreshToken
        case tokenAudienceMismatch(expectedClientId: String, actualClientId: String?)
        case exchangeFailed(String)
        case refreshFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingGoogleClientId:
                return "Google OAuth is not configured. Set PLUCKIT_GOOGLE_CLIENT_ID or include GoogleService-Info.plist."
            case .missingGoogleIdToken:
                return "Google Sign-In did not return an ID token."
            case .missingRefreshToken:
                return "No refresh token available to refresh the session."
            case .tokenAudienceMismatch(let expectedClientId, let actualClientId):
                let actual = actualClientId ?? "unknown"
                return "Google token audience mismatch. Expected client ID \(expectedClientId), got \(actual)."
            case .missingExchangeToken:
                return "Auth relay response did not include an app token."
            case .refreshFailed(let message):
                return "Failed to refresh session token: \(message)"
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
    private static let identityStorageKey = "pluckIt.local.identity"
    private static let accessTokenRefreshGracePeriodSeconds: TimeInterval = 60

    /// In-flight refresh task. Concurrent callers await this instead of starting
    /// a new refresh, preventing rotating-token invalidation races.
    private var refreshTask: Task<Bool, Never>?

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
        if let value = UserDefaults.standard.string(forKey: Self.identityStorageKey) {
            identity = try? JSONDecoder().decode(AppIdentity.self, from: Data(base64Encoded: value) ?? Data())
            isSignedIn = identity != nil

            if isSignedIn,
               !runtimeConfiguration.useMockAuthFallback,
               (identity?.isLocalMock == true) {
                identity = nil
                isSignedIn = false
                UserDefaults.standard.removeObject(forKey: Self.identityStorageKey)
            }
            if isSignedIn,
               !runtimeConfiguration.useMockAuthFallback,
               let token = identity?.token,
               let expectedClientId = runtimeConfiguration.googleClientId,
               let tokenAudience = extractJWTAudience(from: token),
               tokenAudience != expectedClientId {
                #if DEBUG
                print("[Auth] Persisted session token audience mismatch. Stored token is for \(tokenAudience), expected \(expectedClientId). Clearing local session.")
                #endif
                identity = nil
                isSignedIn = false
                UserDefaults.standard.removeObject(forKey: Self.identityStorageKey)
            }
            Task {
                await self.bootstrapRefreshIfNeeded()
            }
        }

        if !isSignedIn, runtimeConfiguration.useMockAuthFallback {
            isSignedIn = true
            let fallback = AppIdentity(
                userId: runtimeConfiguration.mockUserId ?? "local-dev-user",
                email: runtimeConfiguration.mockUserEmail ?? "local@pluckit.test",
                token: runtimeConfiguration.localMockToken,
                refreshToken: nil,
                accessTokenExpiresAt: nil,
                refreshTokenExpiresAt: nil,
                isLocalMock: true
            )
            identity = fallback
            persist(identity: fallback)
        }
    }

    /// Clears in-memory and persisted auth state.
    func signOut() {
        let identityToRevoke = identity
        clearStoredIdentity()
        GIDSignIn.sharedInstance.signOut()
        Task { [weak self] in
            await self?.revokeSession(identityToRevoke)
        }
    }

    /// Clears stored state without calling Google sign out, used for session refresh invalidation.
    private func clearStoredIdentity() {
        identity = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: Self.identityStorageKey)
    }

    private func revokeSession(_ currentIdentity: AppIdentity?) async {
        guard let currentIdentity,
              !currentIdentity.isLocalMock,
              !runtimeConfiguration.skipAuthHeader else { return }

        guard currentIdentity.refreshToken?.isEmpty == false || !currentIdentity.userId.isEmpty else {
            return
        }

        do {
            let request = MobileAuthRevokeRequest(
                refreshToken: currentIdentity.refreshToken,
                userId: currentIdentity.userId
            )
            let body = try tokenExchangeClient.jsonEncoder.encode(request)
            _ = try await tokenExchangeClient.sendVoid(
                method: "POST",
                path: runtimeConfiguration.googleTokenRevokePath,
                body: body
            )
        } catch {
            #if DEBUG
            print("[Auth] Failed to revoke session: \(error)")
            #endif
        }
    }

    /// Provides a bearer token for API requests.
    ///
    /// If local-only mode is enabled, this returns `nil` so clients can skip Authorization.
    func currentToken() async -> String? {
        guard isSignedIn else { return nil }
        if runtimeConfiguration.skipAuthHeader { return nil }

        if runtimeConfiguration.useMockAuthFallback {
            if let token = identity?.token, !token.isEmpty {
                return token
            }
            return identity?.userId
        }

        guard let currentIdentity = identity else { return nil }
        if currentIdentity.isLocalMock {
            if let token = currentIdentity.token, !token.isEmpty {
                return token
            }
            return currentIdentity.userId
        }

        guard let token = currentIdentity.token, !token.isEmpty else {
            if await refreshSession() {
                return identity?.token
            }
            return nil
        }

        if isJwtToken(token), let expiration = extractJWTExpiration(token), expiration <= Date() {
            #if DEBUG
            print("[Auth] Persisted JWT expired, clearing local session for user \(currentIdentity.userId).")
            #endif
            clearStoredIdentity()
            return nil
        }

        if !isJwtToken(token) {
            #if DEBUG
            let audience = extractJWTAudience(from: token) ?? "non-JWT"
            print("[Auth] currentToken session token aud: \(audience)")
            print("[Auth] currentToken session token preview: \(String(token.prefix(20)))...")
            #endif
            if runtimeConfiguration.useMockAuthFallback {
                return token
            }
            guard currentIdentity.refreshToken?.isEmpty == false else {
                #if DEBUG
                print("[Auth] currentToken found non-JWT access token without refresh token. Clearing identity for \(currentIdentity.userId).")
                #endif
                clearStoredIdentity()
                return nil
            }
            if await refreshSession() {
                return identity?.token
            }
            clearStoredIdentity()
            return nil
        }

        if await refreshSession() {
            return identity?.token
        }

        if !tokenNeedsRefresh(currentIdentity) {
            return token
        }
        return nil
    }

    private func isJwtToken(_ token: String) -> Bool {
        let segments = token.split(separator: ".")
        return segments.count == 3
    }

    private func extractJWTExpiration(_ token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else {
            return nil
        }
        var payload = String(segments[1])
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if payload.count % 4 != 0 {
            payload += String(repeating: "=", count: 4 - payload.count % 4)
        }
        guard
            let payloadData = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
            let payloadJson = try? JSONSerialization.jsonObject(with: payloadData, options: []),
            let payloadMap = payloadJson as? [String: Any],
            let exp = payloadMap["exp"] else {
            return nil
        }

        if let expInt = exp as? TimeInterval {
            return Date(timeIntervalSince1970: expInt)
        }
        if let expInt = exp as? Int {
            return Date(timeIntervalSince1970: TimeInterval(expInt))
        }
        if let expString = exp as? String, let expInt = TimeInterval(expString) {
            return Date(timeIntervalSince1970: expInt)
        }
        return nil
    }

    /// Refreshes the current access token from the stored refresh token.
    ///
    /// Concurrent callers share a single in-flight refresh task to avoid
    /// racing on a rotating refresh token (which would invalidate each other).
    func refreshSession() async -> Bool {
        if let existing = refreshTask {
            return await existing.value
        }

        let task = Task<Bool, Never> {
            await self._performRefresh()
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func _performRefresh() async -> Bool {
        guard isSignedIn else { return false }
        guard let currentIdentity = identity else { return false }
        if !currentIdentity.isLocalMock {
            if let refreshToken = currentIdentity.refreshToken, !refreshToken.isEmpty {
                if isRefreshTokenExpired(refreshExpiresAt: currentIdentity.refreshTokenExpiresAt) {
                    clearStoredIdentity()
                    return false
                }
            } else {
                let error = AuthError.missingRefreshToken
                lastAuthError = error.localizedDescription
                return false
            }
        }

        guard let refreshToken = currentIdentity.refreshToken, !refreshToken.isEmpty else {
            return false
        }

        do {
            let body = try tokenExchangeClient.jsonEncoder.encode(
                MobileAuthRefreshRequest(refreshToken: refreshToken)
            )
            let response: MobileAuthResponse = try await tokenExchangeClient.send(
                method: "POST",
                path: runtimeConfiguration.googleTokenRefreshPath,
                body: body
            )

            guard let nextIdentity = buildIdentity(
                from: response,
                fallbackUserId: currentIdentity.userId,
                fallbackEmail: currentIdentity.email,
                fallbackRefreshToken: refreshToken
            ) else {
                let error = AuthError.missingExchangeToken
                lastAuthError = error.localizedDescription
                return false
            }

            identity = nextIdentity
            isSignedIn = true
            persist(identity: nextIdentity)
            lastAuthError = nil
            return true
        } catch {
            let refreshError = AuthError.refreshFailed(String(describing: error))
            lastAuthError = refreshError.localizedDescription
            #if DEBUG
            print("[Auth] refreshSession failed: \(refreshError.localizedDescription)")
            #endif
            return false
        }
    }

    private func bootstrapRefreshIfNeeded() async {
        if runtimeConfiguration.useMockAuthFallback || runtimeConfiguration.skipAuthHeader { return }
        guard let currentIdentity = identity, !currentIdentity.isLocalMock else { return }
        if tokenNeedsRefresh(currentIdentity) {
            let refreshed = await refreshSession()
            if !refreshed {
                #if DEBUG
                print("[Auth] bootstrap refresh attempt failed for user: \(currentIdentity.userId)")
                #endif
            }
        }
    }

    private func tokenNeedsRefresh(_ identity: AppIdentity) -> Bool {
        if identity.isLocalMock {
            return false
        }
        if identity.token == nil {
            return !(identity.refreshToken ?? "").isEmpty
        }
        guard let expiresAt = identity.accessTokenExpiresAt else {
            return false
        }
        return expiresAt <= Date().addingTimeInterval(Self.accessTokenRefreshGracePeriodSeconds)
    }

    private func isRefreshTokenExpired(refreshExpiresAt: Date?) -> Bool {
        guard let refreshExpiresAt else { return false }
        return refreshExpiresAt <= Date()
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
            refreshToken: nil,
            accessTokenExpiresAt: nil,
            refreshTokenExpiresAt: nil,
            isLocalMock: true
        )
        identity = nextIdentity
        isSignedIn = true
        persist(identity: nextIdentity)
        lastAuthError = nil
    }

    /// Signs in with Google on iOS and exchanges the Google ID token for an app token.
    ///
    /// - Parameter presentingViewController: Controller used for presenting Google sign-in UI.
    #if canImport(UIKit)
    func signInWithGoogle(presentingViewController: UIViewController) async throws {
        guard let googleClientId = runtimeConfiguration.googleClientId else {
            throw AuthError.missingGoogleClientId
        }
        #if DEBUG
        print("[Auth] Google client in use: \(googleClientId)")
        #endif

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
        guard let tokenAudience = extractJWTAudience(from: idToken) else {
            #if DEBUG
            print("[Auth] Google ID token could not be decoded; unable to validate audience")
            #endif
            let error = AuthError.tokenAudienceMismatch(expectedClientId: googleClientId, actualClientId: nil)
            lastAuthError = error.localizedDescription
            throw error
        }
        #if DEBUG
        print("[Auth] Google ID token aud: \(tokenAudience)")
        #endif
        guard tokenAudience == googleClientId else {
            let error = AuthError.tokenAudienceMismatch(
                expectedClientId: googleClientId,
                actualClientId: tokenAudience
            )
            lastAuthError = error.localizedDescription
            throw error
        }

        do {
            try await exchangeGoogleToken(
                idToken: idToken,
                fallbackUserId: signInResult.user.userID,
                fallbackEmail: signInResult.user.profile?.email
            )
        } catch {
            let exchangeError = AuthError.exchangeFailed(String(describing: error))
            lastAuthError = exchangeError.localizedDescription
            throw exchangeError
        }
    }
    #endif

    /// Signs in with Google on macOS and exchanges the Google ID token for an app token.
    #if canImport(AppKit)
    func signInWithGoogle(presentingWindow: NSWindow) async throws {
        guard let googleClientId = runtimeConfiguration.googleClientId else {
            throw AuthError.missingGoogleClientId
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientId)

        let signInResult: GIDSignInResult
        do {
            signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingWindow)
        } catch {
            self.lastAuthError = error.localizedDescription
            throw error
        }

        guard let idToken = signInResult.user.idToken?.tokenString else {
            let error = AuthError.missingGoogleIdToken
            lastAuthError = error.localizedDescription
            throw error
        }
        guard let tokenAudience = extractJWTAudience(from: idToken), tokenAudience == googleClientId else {
            let error = AuthError.tokenAudienceMismatch(
                expectedClientId: googleClientId,
                actualClientId: extractJWTAudience(from: idToken)
            )
            lastAuthError = error.localizedDescription
            throw error
        }

        do {
            try await exchangeGoogleToken(
                idToken: idToken,
                fallbackUserId: signInResult.user.userID,
                fallbackEmail: signInResult.user.profile?.email
            )
        } catch {
            let exchangeError = AuthError.exchangeFailed(String(describing: error))
            lastAuthError = exchangeError.localizedDescription
            throw exchangeError
        }
    }
    #endif

    /// Stores identity state to local storage.
    ///
    /// - Parameter identity: The identity object to persist.
    func persist(identity: AppIdentity) {
        if let data = try? JSONEncoder().encode(identity) {
            UserDefaults.standard.setValue(data.base64EncodedString(), forKey: Self.identityStorageKey)
        }
    }

    private func buildIdentity(
        from response: MobileAuthResponse,
        fallbackUserId: String?,
        fallbackEmail: String?,
        fallbackRefreshToken: String? = nil
    ) -> AppIdentity? {
        let appToken = resolveToken(from: response)
        guard let appToken, !appToken.isEmpty else {
            return nil
        }

        return AppIdentity(
            userId: resolveUserId(from: response, fallback: fallbackUserId),
            email: resolveEmail(from: response, fallback: fallbackEmail),
            token: appToken,
            refreshToken: resolveRefreshToken(from: response) ?? fallbackRefreshToken,
            accessTokenExpiresAt: response.accessTokenExpiresAt,
            refreshTokenExpiresAt: response.refreshTokenExpiresAt ?? identity?.refreshTokenExpiresAt,
            isLocalMock: false
        )
    }

    private func exchangeGoogleToken(
        idToken: String,
        fallbackUserId: String?,
        fallbackEmail: String?
    ) async throws {
        let body = try tokenExchangeClient.jsonEncoder.encode(MobileAuthRequest(idToken: idToken))
        let response: MobileAuthResponse = try await tokenExchangeClient.send(
            method: "POST",
            path: runtimeConfiguration.googleTokenExchangePath,
            body: body
        )

        guard let nextIdentity = buildIdentity(
            from: response,
            fallbackUserId: fallbackUserId,
            fallbackEmail: fallbackEmail
        ) else {
            let error = AuthError.missingExchangeToken
            self.lastAuthError = error.localizedDescription
            throw error
        }
        identity = nextIdentity
        isSignedIn = true
        persist(identity: nextIdentity)
        lastAuthError = nil
    }

    /// Resolves a usable token from Google auth response payloads.
    private func resolveToken(from response: MobileAuthResponse) -> String? {
        resolveBestToken([
            response.appToken,
            response.sessionToken,
            response.accessToken,
            response.token,
            response.idToken,
            resolveToken(from: response.data)
        ])
    }

    private func resolveRefreshToken(from response: MobileAuthResponse) -> String? {
        response.refreshToken
            ?? response.data?.refreshToken
    }

    private func resolveToken(from response: MobileAuthResponsePayload?) -> String? {
        guard let response else { return nil }
        return resolveBestToken([
            response.appToken,
            response.sessionToken,
            response.accessToken,
            response.token,
            response.idToken
        ])
    }

    private func resolveBestToken(_ tokens: [String?]) -> String? {
        let candidates = tokens.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if let jwtToken = candidates.first(where: isJwtToken) {
            return jwtToken
        }
        return candidates.first
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

    private func extractJWTAudience(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if payload.count % 4 != 0 {
            payload += String(repeating: "=", count: 4 - payload.count % 4)
        }
        guard let payloadData = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
            return nil
        }
        guard let decodedPayload = try? JSONDecoder().decode(GoogleIDTokenPayload.self, from: payloadData) else {
            return nil
        }
        return decodedPayload.aud
    }
}

private struct MobileAuthRequest: Encodable {
    let idToken: String
}

private struct MobileAuthRefreshRequest: Encodable {
    let refreshToken: String
}

private struct MobileAuthRevokeRequest: Encodable {
    let refreshToken: String?
    let userId: String
}

private struct MobileAuthResponse: Decodable {
    let accessToken: String?
    let token: String?
    let sessionToken: String?
    let appToken: String?
    let idToken: String?
    let accessTokenExpiresAt: Date?
    let refreshTokenExpiresAt: Date?
    let refreshToken: String?
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
    let accessTokenExpiresAt: Date?
    let refreshTokenExpiresAt: Date?
    let refreshToken: String?
    let userId: String?
    let email: String?
    let user: MobileAuthUser?
}

private struct GoogleIDTokenPayload: Decodable {
    let aud: String?
}
