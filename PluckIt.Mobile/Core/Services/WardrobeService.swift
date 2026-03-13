import Foundation

final class WardrobeService {
    private let client: APIClient
    private let basePath = "api/wardrobe"

    init(client: APIClient) {
        self.client = client
    }

    func fetchItems(
        pageSize: Int = 30,
        continuationToken: String? = nil,
        sortField: String? = nil,
        sortDir: String? = nil,
        query: String? = nil,
        brand: String? = nil,
        condition: String? = nil,
        priceMin: Double? = nil,
        priceMax: Double? = nil,
        minWears: Int? = nil,
        category: String? = nil
    ) async throws -> WardrobePagedResponse {
        var params: [String: String] = ["pageSize": String(pageSize)]
        if let continuationToken, !continuationToken.isEmpty {
            params["continuationToken"] = continuationToken
        }
        if let sortField, !sortField.isEmpty { params["sortField"] = sortField }
        if let sortDir, !sortDir.isEmpty { params["sortDir"] = sortDir }
        if let query, !query.isEmpty { params["query"] = query }
        if let brand, !brand.isEmpty { params["brand"] = brand }
        if let condition, !condition.isEmpty { params["condition"] = condition }
        if let priceMin { params["priceMin"] = String(priceMin) }
        if let priceMax { params["priceMax"] = String(priceMax) }
        if let minWears { params["minWears"] = String(minWears) }
        if let category, !category.isEmpty { params["category"] = category }
        return try await client.send(method: "GET", path: basePath, query: params)
    }

    func fetchItem(by id: String) async throws -> ClothingItem {
        return try await client.send(method: "GET", path: "\(basePath)/\(id)")
    }

    func uploadForDraft(imageData: Data) async throws -> ClothingItem {
        return try await client.uploadMultipart(path: "\(basePath)/upload", imageData: imageData)
    }

    func retryDraft(_ draftId: String) async throws {
        try await client.sendVoid(method: "POST", path: "\(basePath)/drafts/\(draftId)/retry")
    }

    func dismissDraft(_ draftId: String) async throws {
        try await client.sendVoid(method: "DELETE", path: "\(basePath)/\(draftId)")
    }

    func createDraft(from item: ClothingItem) async throws -> ClothingItem {
        let body = try JSONEncoder().encode(item)
        return try await client.send(method: "POST", path: "\(basePath)/drafts", body: body)
    }

    func update(_ item: ClothingItem) async throws {
        let body = try JSONEncoder().encode(item)
        try await client.sendVoid(method: "PUT", path: "\(basePath)/\(item.id)", body: body)
    }

    func fetchDrafts() async throws -> [WardrobeUploadDraft] {
        do {
            let response: WardrobePagedResponse = try await client.send(method: "GET", path: "\(basePath)/drafts")
            return response.items.map { item in
                let status = item.draftStatus ?? "queued"
                return WardrobeUploadDraft(
                    id: item.id,
                    status: status,
                    createdAt: item.draftCreatedAt,
                    updatedAt: item.draftUpdatedAt,
                    item: item
                )
            }
        } catch {
            throw error
        }
    }

    func acceptDraft(_ draftId: String) async throws {
        try await client.send(method: "PATCH", path: "\(basePath)/drafts/\(draftId)/accept")
    }

    func rejectDraft(_ draftId: String) async throws {
        try await client.send(method: "POST", path: "\(basePath)/drafts/\(draftId)/reject")
    }

    func logWear(_ itemId: String) async throws {
        let payload = try JSONEncoder().encode(WardrobeWearLogRequest(delta: 1))
        try await client.send(method: "PATCH", path: "\(basePath)/\(itemId)/wear", body: payload)
    }
}
