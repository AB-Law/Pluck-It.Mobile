import Foundation

final class ProfileService {
    private let client: APIClient
    private let identityPath = "api/user"
    private let preferencesPath = "api/profile"

    init(client: APIClient) {
        self.client = client
    }

    func fetchProfile() async throws -> UserProfile {
        try await client.send(method: "GET", path: "\(identityPath)/me")
    }

    func fetchPreferences() async throws -> UserPreferences {
        try await client.send(method: "GET", path: preferencesPath)
    }

    func updatePreferences(_ prefs: UserPreferences) async throws {
        let body = try JSONEncoder().encode(prefs)
        try await client.send(method: "PUT", path: preferencesPath, body: body)
    }
}
