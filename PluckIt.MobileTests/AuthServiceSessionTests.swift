import Foundation
import Testing
@testable import PluckIt_Mobile

private let identityStorageKey = "pluckIt.local.identity"
private let accessTokenRefreshPath = "/api/auth/refresh"
private let revokePath = "/api/auth/revoke"

private func makeISO8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private func setEnvironmentValue(_ key: String, _ value: String) {
    setenv(key, value, 1)
}

private func configureAuthRuntimeEnvironment() {
    setEnvironmentValue("PLUCKIT_API_BASE_URL", "https://example.test/api")
    setEnvironmentValue("PLUCKIT_TOKEN_REFRESH_PATH", accessTokenRefreshPath)
    setEnvironmentValue("PLUCKIT_TOKEN_REVOKE_PATH", revokePath)
    setEnvironmentValue("PLUCKIT_TOKEN_RELAY_PATH", "/api/auth/mobile-token")
    setEnvironmentValue("PLUCKIT_SKIP_AUTH_HEADER", "false")
    setEnvironmentValue("PLUCKIT_USE_MOCK_AUTH_FALLBACK", "false")
    setEnvironmentValue("PLUCKIT_MOCK_USER_ID", "")
    setEnvironmentValue("PLUCKIT_MOCK_USER_EMAIL", "")
    setEnvironmentValue("PLUCKIT_MOCK_TOKEN", "")
    setEnvironmentValue("PLUCKIT_LOCAL_AUTH_TOKEN", "")
    setEnvironmentValue("PLUCKIT_LOCAL_USER_ID", "")
    setEnvironmentValue("PLUCKIT_LOCAL_USER_EMAIL", "")
}

private func clearAuthRuntimeEnvironment() {
    setEnvironmentValue("PLUCKIT_API_BASE_URL", "")
    setEnvironmentValue("PLUCKIT_TOKEN_REFRESH_PATH", "")
    setEnvironmentValue("PLUCKIT_TOKEN_REVOKE_PATH", "")
    setEnvironmentValue("PLUCKIT_TOKEN_RELAY_PATH", "")
    setEnvironmentValue("PLUCKIT_SKIP_AUTH_HEADER", "")
    setEnvironmentValue("PLUCKIT_USE_MOCK_AUTH_FALLBACK", "")
    setEnvironmentValue("PLUCKIT_MOCK_USER_ID", "")
    setEnvironmentValue("PLUCKIT_MOCK_USER_EMAIL", "")
    setEnvironmentValue("PLUCKIT_MOCK_TOKEN", "")
    setEnvironmentValue("PLUCKIT_LOCAL_AUTH_TOKEN", "")
    setEnvironmentValue("PLUCKIT_LOCAL_USER_ID", "")
    setEnvironmentValue("PLUCKIT_LOCAL_USER_EMAIL", "")
}

private func clearStoredIdentity() {
    UserDefaults.standard.removeObject(forKey: identityStorageKey)
}

private func encodedIdentity(_ identity: AppIdentity) throws -> String {
    let data = try JSONEncoder().encode(identity)
    return data.base64EncodedString()
}

private func decodeJSONBody(_ request: URLRequest) -> [String: String]? {
    let body = request.httpBody ?? {
        guard let stream = request.httpBodyStream else { return nil }
        let bufferSize = 4_096
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        stream.open()
        defer { stream.close() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }

        return data.isEmpty ? nil : data
    }()

    guard let body, let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        return nil
    }
    return payload.compactMapValues { $0 as? String }
}

/// URL protocol stub used by APIClient tests.
final class MockURLProtocol: URLProtocol {
    struct ObservedRequest {
        let request: URLRequest
    }

    static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?
    static var observedRequests: [ObservedRequest] = []

    static func reset() {
        requestHandler = nil
        observedRequests.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var request = self.request
        request = Self.ensureBodyAvailable(on: request)
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.observedRequests.append(.init(request: request))
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func ensureBodyAvailable(on request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else {
            return request
        }

        let bufferedStream = stream
        bufferedStream.open()
        defer { bufferedStream.close() }

        let bufferLength = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferLength)
        defer { buffer.deallocate() }

        var collected = Data()
        while bufferedStream.hasBytesAvailable {
            let bytesRead = bufferedStream.read(buffer, maxLength: bufferLength)
            if bytesRead <= 0 { break }
            collected.append(buffer, count: bytesRead)
        }

        var mutableRequest = request
        if !collected.isEmpty {
            mutableRequest.httpBody = collected
        }
        return mutableRequest
    }

    override func stopLoading() {
    }
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

@Suite(.serialized)
@MainActor
struct AuthServiceSessionTests {
    @Test func refreshSessionUpdatesIdentityFromBackendContract() async throws {
        clearStoredIdentity()
        MockURLProtocol.reset()
        configureAuthRuntimeEnvironment()
        defer {
            clearStoredIdentity()
            clearAuthRuntimeEnvironment()
            MockURLProtocol.reset()
        }

        let currentIdentity = AppIdentity(
            userId: "user-123",
            email: "user@example.test",
            token: "at-old",
            refreshToken: "rt-old",
            accessTokenExpiresAt: Date().addingTimeInterval(-90),
            refreshTokenExpiresAt: Date().addingTimeInterval(90_000),
            isLocalMock: false
        )
        UserDefaults.standard.setValue(try encodedIdentity(currentIdentity), forKey: identityStorageKey)

        var observedRefreshToken: String?
        MockURLProtocol.requestHandler = { request in
            observedRefreshToken = decodeJSONBody(request)?["refresh_token"]
            let payload: [String: Any] = [
                "access_token": "at-new",
                "refresh_token": "rt-new",
                "access_token_expires_at": makeISO8601String(Date().addingTimeInterval(900)),
                "refresh_token_expires_at": makeISO8601String(Date().addingTimeInterval(90_000)),
                "user_id": "user-123",
                "token_type": "Bearer",
                "expires_in": 1800,
                "refresh_token_expires_in": 2_592_000,
                "refresh_token_rotation": "single-use",
                "refresh_token_revoke_on_logout": true,
            ]
            let data = try! JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        let runtimeConfiguration = RuntimeConfiguration()
        let apiClient = APIClient(
            baseUrl: runtimeConfiguration.apiBaseUrl,
            session: makeMockSession(),
            tokenProvider: nil,
            debugLoggingEnabled: false
        )
        let service = AuthService(runtimeConfiguration: runtimeConfiguration, tokenExchangeClient: apiClient)
        service.bootstrap()

        let result = await service.refreshSession()

        #expect(result == true)
        #expect(service.identity?.token == "at-new")
        #expect(service.identity?.refreshToken == "rt-new")
        #expect((observedRefreshToken ?? MockURLProtocol.observedRequests.first.flatMap { decodeJSONBody($0.request)?["refreshToken"] }) == "rt-old")
        #expect(MockURLProtocol.observedRequests.count == 1)
        #expect(MockURLProtocol.observedRequests[0].request.url?.path == accessTokenRefreshPath)
    }

    @Test func refreshSessionClearsIdentityWhenRefreshTokenExpired() async {
        clearStoredIdentity()
        MockURLProtocol.reset()
        configureAuthRuntimeEnvironment()
        defer {
            clearStoredIdentity()
            clearAuthRuntimeEnvironment()
            MockURLProtocol.reset()
        }

        let currentIdentity = AppIdentity(
            userId: "user-123",
            email: "user@example.test",
            token: "at-old",
            refreshToken: "rt-old",
            accessTokenExpiresAt: Date().addingTimeInterval(-3600),
            refreshTokenExpiresAt: Date().addingTimeInterval(-60),
            isLocalMock: false
        )
        UserDefaults.standard.setValue(try? encodedIdentity(currentIdentity), forKey: identityStorageKey)

        let runtimeConfiguration = RuntimeConfiguration()
        let service = AuthService(runtimeConfiguration: runtimeConfiguration, tokenExchangeClient: APIClient(
            baseUrl: runtimeConfiguration.apiBaseUrl,
            session: makeMockSession(),
            tokenProvider: nil,
            debugLoggingEnabled: false
        ))
        service.bootstrap()

        let result = await service.refreshSession()

        #expect(result == false)
        #expect(service.identity == nil)
        #expect(service.isSignedIn == false)
        #expect(MockURLProtocol.observedRequests.isEmpty)
    }

    @Test func signOutClearsIdentityAndPostsRevokeRequest() async throws {
        clearStoredIdentity()
        MockURLProtocol.reset()
        configureAuthRuntimeEnvironment()
        defer {
            clearStoredIdentity()
            clearAuthRuntimeEnvironment()
            MockURLProtocol.reset()
        }

        var observedBody: [String: String]?
        MockURLProtocol.requestHandler = { request in
            observedBody = decodeJSONBody(request)
            let data = try! JSONSerialization.data(
                withJSONObject: ["revoked": true]
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        let currentIdentity = AppIdentity(
            userId: "user-signout",
            email: "user@example.test",
            token: "at-current",
            refreshToken: "rt-signout",
            accessTokenExpiresAt: Date().addingTimeInterval(600),
            refreshTokenExpiresAt: Date().addingTimeInterval(90_000),
            isLocalMock: false
        )
        UserDefaults.standard.setValue(try encodedIdentity(currentIdentity), forKey: identityStorageKey)

        let runtimeConfiguration = RuntimeConfiguration()
        let service = AuthService(runtimeConfiguration: runtimeConfiguration, tokenExchangeClient: APIClient(
            baseUrl: runtimeConfiguration.apiBaseUrl,
            session: makeMockSession(),
            tokenProvider: nil,
            debugLoggingEnabled: false
        ))
        service.bootstrap()

        service.signOut()
        for _ in 0..<80 {
            if !MockURLProtocol.observedRequests.isEmpty { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(service.identity == nil)
        #expect(service.isSignedIn == false)
        #expect(MockURLProtocol.observedRequests.count == 1)
        #expect(MockURLProtocol.observedRequests[0].request.url?.path == revokePath)
        #expect((observedBody?["refresh_token"] ?? observedBody?["refreshToken"]) == "rt-signout")
        #expect((observedBody?["user_id"] ?? observedBody?["userId"]) == "user-signout")
    }
}

