import Foundation

/// Runtime configuration for API endpoints and local debug behavior.
///
/// Values are loaded from environment variables first, then Info.plist keys, and
/// finally hardcoded local defaults intended for simulator development.
struct RuntimeConfiguration {
    /// API gateway base URL used by main feature services.
    let apiBaseUrl: URL

    /// Processor/server-side augmentation base URL (for scraped/discover features).
    let processorBaseUrl: URL

    /// Optional mock local user ID for local development sessions.
    let mockUserId: String?

    /// Optional mock local user email for local dev display.
    let mockUserEmail: String?
    let localMockToken: String?

    /// Optional Google OAuth client identifiers for iOS sign in.
    let googleClientId: String?
    let googleReversedClientId: String?

    /// Relative backend path for exchanging Google ID token -> app session token.
    let googleTokenExchangePath: String
    let googleTokenRefreshPath: String
    let googleTokenRevokePath: String

    /// Enable mock/local identity even without a real auth token.
    let useMockAuthFallback: Bool

    /// If true, auth headers are intentionally not added to requests.
    let skipAuthHeader: Bool

    /// Whether to log request/response payloads for API debugging.
    let networkDebugEnabled: Bool

    init() {
        let processInfo = ProcessInfo.processInfo
        let env = processInfo.environment

        func readEnv(_ name: String) -> String? {
            guard let rawValue = env[name] else { return nil }
            return normalizeConfigValue(rawValue)
        }

        func normalizeConfigValue(_ rawValue: String?) -> String? {
            guard let rawValue else { return nil }
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let lowered = trimmed.lowercased()
            let isTemplateValue =
                (lowered == "__google_client_id__") ||
                (lowered == "__google_reversed_client_id__") ||
                (lowered.hasPrefix("${") && lowered.hasSuffix("}"))
            return isTemplateValue ? nil : trimmed
        }

        func readPlist(_ key: String) -> String? {
            normalizeConfigValue(Bundle.main.object(forInfoDictionaryKey: key) as? String)
        }

        func readGooglePlist(_ key: String) -> String? {
            func readGooglePlistFile(_ name: String) -> String? {
                guard let url = Bundle.main.url(forResource: name, withExtension: "plist"),
                  let data = try? Data(contentsOf: url),
                  let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dict = raw as? [String: Any] else {
                return nil
                }
                return normalizeConfigValue(dict[key] as? String)
            }
            return readGooglePlistFile("GoogleService-Info.local") ?? readGooglePlistFile("GoogleService-Info")
        }

        func normalizeUrl(_ raw: String?) -> String {
            guard let raw else { return "" }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }

            if let scheme = URLComponents(string: trimmed)?.scheme, !scheme.isEmpty {
                return trimmed
            }

            let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
            if normalized.hasPrefix("localhost:") || normalized.hasPrefix("127.0.0.1:") {
                return "http://\(normalized)"
            }

            return "https://\(normalized)"
        }

        func readBool(_ key: String, defaultValue: Bool) -> Bool {
            let value = readEnv(key) ?? readPlist(key)
            switch value?.lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return defaultValue
            }
        }

        let apiUrlValue = readEnv("PLUCKIT_API_BASE_URL")
            ?? readEnv("PLUCKIT_API_URL")
            ?? readPlist("PluckItApiBaseURL")
            ?? "https://pluckit-prod-api-func.azurewebsites.net"

        let processorUrlValue = readEnv("PLUCKIT_PROCESSOR_BASE_URL")
            ?? readEnv("PLUCKIT_CHAT_API_URL")
            ?? readPlist("PluckItProcessorBaseURL")
            ?? "https://pluckit-prod-processor-func.azurewebsites.net"

        self.apiBaseUrl = URL(string: normalizeUrl(apiUrlValue)) ?? URL(string: "https://pluckit-prod-api-func.azurewebsites.net")!
        self.processorBaseUrl = URL(string: normalizeUrl(processorUrlValue)) ?? URL(string: "https://pluckit-prod-processor-func.azurewebsites.net")!
        let mockUserId = readEnv("PLUCKIT_MOCK_USER_ID") ?? readEnv("PLUCKIT_LOCAL_USER_ID")
        let mockUserEmail = readEnv("PLUCKIT_MOCK_USER_EMAIL") ?? readEnv("PLUCKIT_LOCAL_USER_EMAIL")
        let mockToken = readEnv("PLUCKIT_MOCK_TOKEN") ?? readEnv("PLUCKIT_LOCAL_AUTH_TOKEN")
        self.mockUserId = mockUserId
        self.mockUserEmail = mockUserEmail
        self.localMockToken = mockToken
        self.skipAuthHeader = readBool("PLUCKIT_SKIP_AUTH_HEADER", defaultValue: false)
        self.useMockAuthFallback = readBool(
            "PLUCKIT_USE_MOCK_AUTH_FALLBACK",
            defaultValue: self.skipAuthHeader || mockUserId != nil || mockUserEmail != nil || mockToken != nil
        )
        self.googleClientId = readEnv("PLUCKIT_GOOGLE_CLIENT_ID")
            ?? readEnv("GOOGLE_CLIENT_ID")
            ?? readGooglePlist("CLIENT_ID")
        self.googleReversedClientId = readEnv("PLUCKIT_GOOGLE_REVERSED_CLIENT_ID")
            ?? readEnv("GOOGLE_REVERSED_CLIENT_ID")
            ?? readGooglePlist("REVERSED_CLIENT_ID")
        self.googleTokenExchangePath = readEnv("PLUCKIT_TOKEN_RELAY_PATH") ?? "/api/auth/mobile-token"
        self.googleTokenRefreshPath = readEnv("PLUCKIT_TOKEN_REFRESH_PATH") ?? "/api/auth/refresh"
        self.googleTokenRevokePath = readEnv("PLUCKIT_TOKEN_REVOKE_PATH") ?? "/api/auth/revoke"
        let networkDebugFromEnv = readBool("PLUCKIT_NETWORK_DEBUG", defaultValue: false)
#if DEBUG
        self.networkDebugEnabled = networkDebugFromEnv
#else
        self.networkDebugEnabled = false
#endif
    }
}
