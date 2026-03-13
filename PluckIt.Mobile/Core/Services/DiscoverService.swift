import Foundation

final class DiscoverService {
    private let client: APIClient
    private let basePath = "api/scraper"

    init(client: APIClient) {
        self.client = client
    }

    func fetchFeed(_ request: DiscoverFeedQuery) async throws -> DiscoverFeedResponse {
        var params: [String: String] = [
            "pageSize": String(request.pageSize)
        ]
        if let sortBy = request.sortBy, !sortBy.isEmpty {
            params["sortBy"] = sortBy
        }
        if let sourceIds = request.sourceIds, !sourceIds.isEmpty {
            params["sourceIds"] = sourceIds.joined(separator: ",")
        }
        if let timeRange = request.timeRange, !timeRange.isEmpty {
            params["timeRange"] = timeRange
        }
        if let continuationToken = request.continuationToken, !continuationToken.isEmpty {
            params["continuationToken"] = continuationToken
        }
        return try await client.send(method: "GET", path: "\(basePath)/items", query: params)
    }

    func fetchSources() async throws -> [ScraperSource] {
        let response: ScraperSourcesResponse = try await client.send(method: "GET", path: "\(basePath)/sources")
        return response.sources
    }
}
