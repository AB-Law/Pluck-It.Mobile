import Foundation

final class WardrobeService {
    private let client: APIClient
    private let basePath = "api/wardrobe"

    init(client: APIClient) {
        self.client = client
    }

    func fetchItems(page: Int = 1, pageSize: Int = 20, continuationToken: String? = nil, search: String? = nil) async throws -> WardrobePagedResponse {
        var query: [String: String] = [
            "page": String(page),
            "pageSize": String(pageSize)
        ]
        if let continuationToken, !continuationToken.isEmpty {
            query["continuationToken"] = continuationToken
        }
        if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query["search"] = search
        }

        return try await client.send(method: "GET", path: basePath, query: query)
    }

    func fetchItem(by id: String) async throws -> ClothingItem {
        return try await client.send(method: "GET", path: "\(basePath)/\(id)")
    }

    func createDraft(from item: ClothingItem) async throws -> ClothingItem {
        let body = try JSONEncoder().encode(item)
        return try await client.send(method: "POST", path: "\(basePath)/drafts", body: body)
    }

    func fetchDrafts() async throws -> [WardrobeUploadDraft] {
        do {
            let response: [ClothingItem] = try await client.send(method: "GET", path: "\(basePath)/drafts")
            return response.compactMap { item in
                let status = (item.draftStatus ?? "queued")
                return WardrobeUploadDraft(
                    id: item.id,
                    status: status,
                    createdAt: item.draftCreatedAt,
                    updatedAt: item.draftUpdatedAt,
                    item: item
                )
            }
        } catch {
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
        }
    }

    func acceptDraft(_ draftId: String) async throws {
        try await client.send(method: "POST", path: "\(basePath)/drafts/\(draftId)/accept")
    }

    func rejectDraft(_ draftId: String) async throws {
        try await client.send(method: "POST", path: "\(basePath)/drafts/\(draftId)/reject")
    }

    func logWear(_ itemId: String) async throws {
        let payload = try JSONEncoder().encode(WardrobeWearLogRequest(delta: 1))
        try await client.send(method: "PATCH", path: "\(basePath)/\(itemId)/wear", body: payload)
    }
}
