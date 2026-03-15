import Foundation

final class VaultInsightsService {
    private let client: APIClient
    private let basePath = "api/insights/vault"

    init(client: APIClient) {
        self.client = client
    }

    func fetchInsights(windowDays: Int = 90, targetCpw: Int = 100) async throws -> VaultInsightsResponse {
        let query: [String: String] = [
            "windowDays": String(windowDays),
            "targetCpw": String(targetCpw)
        ]
        return try await client.send(method: "GET", path: basePath, query: query)
    }
}
