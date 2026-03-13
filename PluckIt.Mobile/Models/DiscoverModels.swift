import Foundation

struct BuyLink: Codable, Equatable {
    let platform: String?
    let url: String
    let label: String?

    init(platform: String? = nil, url: String = "", label: String? = nil) {
        self.platform = platform
        self.url = url
        self.label = label
    }
}

struct ScraperSource: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let isActive: Bool
    let baseUrl: String?

    init(id: String = "", name: String = "", isActive: Bool = false, baseUrl: String? = nil) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.baseUrl = baseUrl
    }
}

struct ScrapedItem: Codable, Equatable, Identifiable {
    let id: String
    let title: String?
    let brand: String?
    let imageUrl: String?
    let source: ScraperSource?
    let detailUrl: String?
    let priceText: String?
    let displaySourceName: String?
    let displayDetailUrl: String?
    let displayPriceText: String?
    let buyLinks: [BuyLink]?
    let tags: [String]?

    init(
        id: String = "",
        title: String? = nil,
        brand: String? = nil,
        imageUrl: String? = nil,
        source: ScraperSource? = nil,
        detailUrl: String? = nil,
        priceText: String? = nil,
        displaySourceName: String? = nil,
        displayDetailUrl: String? = nil,
        displayPriceText: String? = nil,
        buyLinks: [BuyLink]? = nil,
        tags: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.brand = brand
        self.imageUrl = imageUrl
        self.source = source
        self.detailUrl = detailUrl
        self.priceText = priceText
        self.displaySourceName = displaySourceName
        self.displayDetailUrl = displayDetailUrl
        self.displayPriceText = displayPriceText
        self.buyLinks = buyLinks
        self.tags = tags
    }
}

struct ScraperSourcesResponse: Codable {
    let sources: [ScraperSource]
}

struct DiscoverFeedResponse: Codable {
    let items: [ScrapedItem]
    let nextContinuationToken: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextContinuationToken
    }

    init(items: [ScrapedItem], nextContinuationToken: String? = nil) {
        self.items = items
        self.nextContinuationToken = nextContinuationToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decodeIfPresent([ScrapedItem].self, forKey: .items) ?? []
        self.nextContinuationToken = try container.decodeIfPresent(String.self, forKey: .nextContinuationToken)
    }
}

struct DiscoverFeedQuery {
    var page: Int = 1
    var pageSize: Int = 20
    var query: String?
    var sort: String?
    var continuationToken: String?
}
