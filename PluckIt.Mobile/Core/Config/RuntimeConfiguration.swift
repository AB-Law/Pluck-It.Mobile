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

    /// If true, auth headers are intentionally not added to requests.
    let skipAuthHeader: Bool

    /// Whether to log request/response payloads for API debugging.
    let networkDebugEnabled: Bool

    init() {
        let processInfo = ProcessInfo.processInfo
        let env = processInfo.environment

        func readEnv(_ name: String) -> String? {
            guard let rawValue = env[name] else { return nil }
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        func readPlist(_ key: String) -> String? {
            Bundle.main.object(forInfoDictionaryKey: key) as? String
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
            ?? readPlist("PluckItApiBaseURL")
            ?? "http://127.0.0.1:7072"

        let processorUrlValue = readEnv("PLUCKIT_PROCESSOR_BASE_URL")
            ?? readPlist("PluckItProcessorBaseURL")
            ?? "http://127.0.0.1:7071"

        self.apiBaseUrl = URL(string: apiUrlValue) ?? URL(string: "http://127.0.0.1:7072")!
        self.processorBaseUrl = URL(string: processorUrlValue) ?? URL(string: "http://127.0.0.1:7071")!
        self.mockUserId = readEnv("PLUCKIT_MOCK_USER_ID")
        self.mockUserEmail = readEnv("PLUCKIT_MOCK_USER_EMAIL")
        self.skipAuthHeader = readBool("PLUCKIT_SKIP_AUTH_HEADER", defaultValue: false)
        self.networkDebugEnabled = readBool("PLUCKIT_NETWORK_DEBUG", defaultValue: true)
    }
}
