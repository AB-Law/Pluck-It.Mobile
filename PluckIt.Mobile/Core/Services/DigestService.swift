import Foundation

final class DigestService {
    private let client: APIClient
    private let basePath = "api/digest"

    init(client: APIClient) {
        self.client = client
    }

    func fetchLatest() async throws -> WardrobeDigest? {
        let wrapper: DigestLatestResponse = try await client.send(method: "GET", path: "\(basePath)/latest")
        return wrapper.digest
    }

    func fetchFeedback(digestId: String) async throws -> [DigestFeedbackItem] {
        let wrapper: DigestFeedbackListResponse = try await client.send(
            method: "GET",
            path: "\(basePath)/feedback",
            query: ["digestId": digestId]
        )
        return wrapper.feedback
    }

    func sendFeedback(_ body: DigestFeedbackRequest) async throws {
        let data = try JSONEncoder().encode(body)
        try await client.sendVoid(method: "POST", path: "\(basePath)/feedback", body: data)
    }
}
