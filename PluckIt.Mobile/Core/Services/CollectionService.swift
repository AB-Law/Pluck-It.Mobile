import Foundation

final class CollectionService {
    private let client: APIClient
    private let basePath = "api/collections"

    init(client: APIClient) {
        self.client = client
    }

    func fetchCollections(page: Int = 1, pageSize: Int = 50, query: String? = nil) async throws -> [Collection] {
        var params: [String: String] = [
            "page": String(page),
            "pageSize": String(pageSize)
        ]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            params["query"] = query
        }
        let response: CollectionPageResponse = try await client.send(method: "GET", path: basePath, query: params)
        return response.items
    }

    func createCollection(_ request: CreateCollectionRequest) async throws -> Collection {
        let body = try JSONEncoder().encode(request)
        return try await client.send(method: "POST", path: basePath, body: body)
    }

    func deleteCollection(_ id: String) async throws {
        try await client.send(method: "DELETE", path: "\(basePath)/\(id)")
    }
}
