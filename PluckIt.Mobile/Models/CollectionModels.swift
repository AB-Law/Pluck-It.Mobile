import Foundation

struct Collection: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let imageUrl: String?
    let clothingItemIds: [String]?
    let itemIds: [String]?
    let memberUserIds: [String]?
    let isPublic: Bool
    let createdAt: String?
    let updatedAt: String?

    init(id: String, name: String = "", description: String? = nil, imageUrl: String? = nil, clothingItemIds: [String]? = nil, itemIds: [String]? = nil, memberUserIds: [String]? = nil, isPublic: Bool = false, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.imageUrl = imageUrl
        self.clothingItemIds = clothingItemIds
        self.itemIds = itemIds
        self.memberUserIds = memberUserIds
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct CollectionPageResponse: Codable {
    let items: [Collection]
    let totalCount: Int?
    let page: Int?
    let pageSize: Int?

    init(items: [Collection], totalCount: Int? = nil, page: Int? = nil, pageSize: Int? = nil) {
        self.items = items
        self.totalCount = totalCount
        self.page = page
        self.pageSize = pageSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decodeIfPresent([Collection].self, forKey: .items) ?? []
        self.totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount)
        self.page = try container.decodeIfPresent(Int.self, forKey: .page)
        self.pageSize = try container.decodeIfPresent(Int.self, forKey: .pageSize)
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case totalCount
        case page
        case pageSize
    }
}

enum CollectionListResponse: Decodable {
    case items([Collection])
    case page(CollectionPageResponse)

    var collections: [Collection] {
        switch self {
        case let .items(list):
            return list
        case let .page(page):
            return page.items
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let collections = try? container.decode([Collection].self) {
            self = .items(collections)
            return
        }

        if let pageResponse = try? container.decode(CollectionPageResponse.self) {
            self = .page(pageResponse)
            return
        }

        throw DecodingError.typeMismatch(
            CollectionListResponse.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected collection list response as array or paged object."
            )
        )
    }
}

struct CreateCollectionRequest: Codable {
    let name: String
    let isPublic: Bool
    let description: String?
    let clothingItemIds: [String]

    init(name: String, isPublic: Bool = false, description: String? = nil, clothingItemIds: [String] = []) {
        self.name = name
        self.isPublic = isPublic
        self.description = description
        self.clothingItemIds = clothingItemIds
    }
}
