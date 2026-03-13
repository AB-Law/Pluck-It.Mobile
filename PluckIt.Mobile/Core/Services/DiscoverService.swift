import Foundation

final class DiscoverService {
    private let client: APIClient
    private let basePath = "api/scraper"

    init(client: APIClient) {
        self.client = client
    }

    func fetchFeed(_ request: DiscoverFeedQuery) async throws -> DiscoverFeedResponse {
        var params: [String: String] = [
            "page": String(request.page),
            "pageSize": String(request.pageSize)
        ]
        if let sort = request.sort, !sort.isEmpty {
            params["sort"] = sort
        }
        if let query = request.query, !query.isEmpty {
            params["query"] = query
        }
        if let continuationToken = request.continuationToken, !continuationToken.isEmpty {
            params["continuationToken"] = continuationToken
        }

        do {
            return try await client.send(method: "GET", path: "\(basePath)/items", query: params)
        } catch {
            let items: [ScrapedItem] = try await client.send(method: "GET", path: "\(basePath)/items", query: params)
            return DiscoverFeedResponse(items: items, nextContinuationToken: nil)
        }
    }

    func fetchSources() async throws -> [ScraperSource] {
        let response: ScraperSourcesResponse = try await client.send(method: "GET", path: "\(basePath)/sources")
        return response.sources
    }
}
