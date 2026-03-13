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

struct ScraperSource: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let sourceType: String
    let isGlobal: Bool
    let isActive: Bool
    let config: [String: DynamicJSONValue]?
    let createdAt: String?
    let lastScrapedAt: String?
    let subscribed: Bool?
    let needsClientIngest: Bool?
    let lastSyncAt: String?
    let baseUrl: String?

    init(
        id: String = "",
        name: String = "",
        sourceType: String = "",
        isGlobal: Bool = false,
        isActive: Bool = false,
        config: [String: DynamicJSONValue]? = nil,
        createdAt: String? = nil,
        lastScrapedAt: String? = nil,
        subscribed: Bool? = nil,
        needsClientIngest: Bool? = nil,
        lastSyncAt: String? = nil,
        baseUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceType = sourceType
        self.isGlobal = isGlobal
        self.isActive = isActive
        self.config = config
        self.createdAt = createdAt
        self.lastScrapedAt = lastScrapedAt
        self.subscribed = subscribed
        self.needsClientIngest = needsClientIngest
        self.lastSyncAt = lastSyncAt
        self.baseUrl = baseUrl
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourceType
        case isGlobal
        case isActive
        case config
        case createdAt
        case lastScrapedAt
        case subscribed
        case needsClientIngest
        case lastSyncAt
        case baseUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType) ?? ""
        isGlobal = try container.decodeIfPresent(Bool.self, forKey: .isGlobal) ?? false
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        config = try container.decodeIfPresent([String: DynamicJSONValue].self, forKey: .config)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        lastScrapedAt = try container.decodeIfPresent(String.self, forKey: .lastScrapedAt)
        subscribed = try container.decodeIfPresent(Bool.self, forKey: .subscribed)
        needsClientIngest = try container.decodeIfPresent(Bool.self, forKey: .needsClientIngest)
        lastSyncAt = try container.decodeIfPresent(String.self, forKey: .lastSyncAt)
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encode(isGlobal, forKey: .isGlobal)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(config, forKey: .config)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastScrapedAt, forKey: .lastScrapedAt)
        try container.encodeIfPresent(subscribed, forKey: .subscribed)
        try container.encodeIfPresent(needsClientIngest, forKey: .needsClientIngest)
        try container.encodeIfPresent(lastSyncAt, forKey: .lastSyncAt)
        try container.encodeIfPresent(baseUrl, forKey: .baseUrl)
    }
}

enum DynamicJSONValue: Codable, Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case object([String: DynamicJSONValue])
    case array([DynamicJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
            return
        }
        if let value = try? container.decode(Int.self) {
            self = .integer(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([DynamicJSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: DynamicJSONValue].self) {
            self = .object(value)
            return
        }
        throw DecodingError.typeMismatch(DynamicJSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
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

    init(sources: [ScraperSource] = []) {
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = try container.decodeIfPresent([ScraperSource].self, forKey: .sources) ?? []
    }
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
