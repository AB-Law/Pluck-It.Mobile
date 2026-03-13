import Foundation

protocol StringSearchableItem {
    func searchableText() -> String
}

struct ClothingPrice: Codable, Equatable {
    let amount: Double?
    let originalCurrency: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case originalCurrency
        case currency
    }

    init(amount: Double? = nil, originalCurrency: String? = nil) {
        self.amount = amount
        self.originalCurrency = originalCurrency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decodeIfPresent(Double.self, forKey: .amount)
        originalCurrency = try container.decodeIfPresent(String.self, forKey: .originalCurrency)
            ?? container.decodeIfPresent(String.self, forKey: .currency)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(originalCurrency, forKey: .originalCurrency)
    }
}

struct ClothingColour: Codable, Equatable {
    let name: String?
    let hex: String?

    enum CodingKeys: String, CodingKey {
        case name
        case hex
        case color
        case family
    }

    init(name: String? = nil, hex: String? = nil) {
        self.name = name
        self.hex = hex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .color)
            ?? container.decodeIfPresent(String.self, forKey: .family)
        hex = try container.decodeIfPresent(String.self, forKey: .hex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(hex, forKey: .hex)
    }
}

struct WearEvent: Codable, Equatable {
    let occurredAt: String?

    enum CodingKeys: String, CodingKey {
        case occurredAt
        case wornAt
    }

    init(occurredAt: String? = nil) {
        self.occurredAt = occurredAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        occurredAt = try container.decodeIfPresent(String.self, forKey: .occurredAt)
            ?? container.decodeIfPresent(String.self, forKey: .wornAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(occurredAt, forKey: .occurredAt)
    }
}

typealias DraftStatus = String
typealias ItemCondition = String
struct ClothingSize: Codable, Equatable {
    let letter: String?
    let waist: Double?
    let inseam: Double?
    let shoeSize: Double?
    let system: String?

    init(letter: String? = nil, waist: Double? = nil, inseam: Double? = nil, shoeSize: Double? = nil, system: String? = nil) {
        self.letter = letter
        self.waist = waist
        self.inseam = inseam
        self.shoeSize = shoeSize
        self.system = system
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.init()
            return
        }

        if let legacyString = try? container.decode(String.self) {
            self.init(letter: legacyString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : legacyString)
            return
        }

        struct SizePayload: Codable {
            let letter: String?
            let waist: Double?
            let inseam: Double?
            let shoeSize: Double?
            let system: String?
        }

        let payload = try container.decode(SizePayload.self)
        let trimmedLetter = payload.letter?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            letter: trimmedLetter?.isEmpty == true ? nil : trimmedLetter,
            waist: payload.waist,
            inseam: payload.inseam,
            shoeSize: payload.shoeSize,
            system: payload.system
        )
    }
}

struct ClothingItem: Codable, Equatable, StringSearchableItem, Identifiable {
    let id: String
    let imageUrl: String?
    let rawImageBlobUrl: String?
    let tags: [String]?
    let colours: [ClothingColour]?
    let brand: String?
    let category: String?
    let price: ClothingPrice?
    let notes: String?
    let dateAdded: String?
    let wearCount: Int?
    let purchaseDate: String?
    let careInfo: [String]?
    let condition: ItemCondition?
    let size: ClothingSize?
    let aestheticTags: [String]?
    let draftStatus: DraftStatus?
    let draftError: String?
    let userId: String?
    let estimatedMarketValue: Double?
    let lastWornAt: String?
    let wearEvents: [WearEvent]?
    let draftCreatedAt: String?
    let draftUpdatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case imageUrl
        case rawImageBlobUrl
        case tags
        case colours
        case brand
        case category
        case price
        case notes
        case dateAdded
        case wearCount
        case purchaseDate
        case careInfo
        case condition
        case size
        case aestheticTags
        case draftStatus
        case draftError
        case userId
        case estimatedMarketValue
        case lastWornAt
        case wearEvents
        case draftCreatedAt
        case draftUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        rawImageBlobUrl = try container.decodeIfPresent(String.self, forKey: .rawImageBlobUrl)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        colours = try container.decodeIfPresent([ClothingColour].self, forKey: .colours)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        price = try container.decodeIfPresent(ClothingPrice.self, forKey: .price)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        dateAdded = try container.decodeIfPresent(String.self, forKey: .dateAdded)
        wearCount = try container.decodeIfPresent(Int.self, forKey: .wearCount)
        purchaseDate = try container.decodeIfPresent(String.self, forKey: .purchaseDate)
        careInfo = try container.decodeIfPresent([String].self, forKey: .careInfo)
        condition = try container.decodeIfPresent(ItemCondition.self, forKey: .condition)
        size = try container.decodeIfPresent(ClothingSize.self, forKey: .size)
        aestheticTags = try container.decodeIfPresent([String].self, forKey: .aestheticTags)
        draftStatus = try container.decodeIfPresent(DraftStatus.self, forKey: .draftStatus)
        draftError = try container.decodeIfPresent(String.self, forKey: .draftError)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        estimatedMarketValue = try container.decodeIfPresent(Double.self, forKey: .estimatedMarketValue)
        lastWornAt = try container.decodeIfPresent(String.self, forKey: .lastWornAt)
        wearEvents = try container.decodeIfPresent([WearEvent].self, forKey: .wearEvents) ?? []
        draftCreatedAt = try container.decodeIfPresent(String.self, forKey: .draftCreatedAt)
        draftUpdatedAt = try container.decodeIfPresent(String.self, forKey: .draftUpdatedAt)
    }

    init(
        id: String,
        imageUrl: String? = nil,
        rawImageBlobUrl: String? = nil,
        tags: [String]? = nil,
        colours: [ClothingColour]? = nil,
        brand: String? = nil,
        category: String? = nil,
        price: ClothingPrice? = nil,
        notes: String? = nil,
        dateAdded: String? = nil,
        wearCount: Int? = nil,
        purchaseDate: String? = nil,
        careInfo: [String]? = nil,
        condition: ItemCondition? = nil,
        size: ClothingSize? = nil,
        aestheticTags: [String]? = nil,
        draftStatus: DraftStatus? = nil,
        draftError: String? = nil,
        userId: String? = nil,
        estimatedMarketValue: Double? = nil,
        lastWornAt: String? = nil,
        wearEvents: [WearEvent]? = nil,
        draftCreatedAt: String? = nil,
        draftUpdatedAt: String? = nil
    ) {
        self.id = id
        self.imageUrl = imageUrl
        self.rawImageBlobUrl = rawImageBlobUrl
        self.tags = tags
        self.colours = colours
        self.brand = brand
        self.category = category
        self.price = price
        self.notes = notes
        self.dateAdded = dateAdded
        self.wearCount = wearCount
        self.purchaseDate = purchaseDate
        self.careInfo = careInfo
        self.condition = condition
        self.size = size
        self.aestheticTags = aestheticTags
        self.draftStatus = draftStatus
        self.draftError = draftError
        self.userId = userId
        self.estimatedMarketValue = estimatedMarketValue
        self.lastWornAt = lastWornAt
        self.wearEvents = wearEvents ?? []
        self.draftCreatedAt = draftCreatedAt
        self.draftUpdatedAt = draftUpdatedAt
    }

    func searchableText() -> String {
        [brand, category, notes]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
    }
}

struct WardrobeQuery: Codable {
    let page: Int
    let pageSize: Int
    let continuationToken: String?
    let search: String?

    init(page: Int = 1, pageSize: Int = 20, continuationToken: String? = nil, search: String? = nil) {
        self.page = page
        self.pageSize = pageSize
        self.continuationToken = continuationToken
        self.search = search
    }
}

struct WardrobePagedResponse: Codable {
    let items: [ClothingItem]
    let nextContinuationToken: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextContinuationToken
    }

    init(items: [ClothingItem], nextContinuationToken: String? = nil) {
        self.items = items
        self.nextContinuationToken = nextContinuationToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decodeIfPresent([ClothingItem].self, forKey: .items) ?? []
        self.nextContinuationToken = try container.decodeIfPresent(String.self, forKey: .nextContinuationToken)
    }
}

struct WardrobeUploadDraft: Codable, Identifiable, Equatable {
    let id: String
    let status: String
    let createdAt: String?
    let updatedAt: String?
    let item: ClothingItem?
}

struct DraftActionRequest: Codable {
    let payload: String?
}

struct WardrobeWearLogRequest: Codable {
    let delta: Int
}
