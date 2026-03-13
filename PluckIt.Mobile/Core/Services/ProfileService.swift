import Foundation

final class ProfileService {
    private let client: APIClient
    private let basePath = "api/user"

    init(client: APIClient) {
        self.client = client
    }

    func fetchProfile() async throws -> UserProfile {
        try await client.send(method: "GET", path: "\(basePath)/me")
    }
}
