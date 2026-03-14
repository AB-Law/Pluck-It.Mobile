import Foundation

/// Identity/fingerprint data returned by GET api/user/me
struct UserProfile: Codable {
    let userId: String?
    let email: String?
    let displayName: String?
    let currencyCode: String?
    let knownBrands: [String]?
    let knownColors: [String]?
    let knownCategories: [String]?
}

/// Editable preferences stored at GET/PUT api/profile
struct UserPreferences: Codable {
    var currencyCode: String
    var preferredSizeSystem: String
    var heightCm: Double?
    var weightKg: Double?
    var chestCm: Double?
    var waistCm: Double?
    var hipsCm: Double?
    var inseamCm: Double?
    var stylePreferences: [String]
    var favoriteBrands: [String]
    var preferredColours: [String]
    var locationCity: String?
    var recommendationOptIn: Bool?

    init(
        currencyCode: String = "USD",
        preferredSizeSystem: String = "US",
        heightCm: Double? = nil,
        weightKg: Double? = nil,
        chestCm: Double? = nil,
        waistCm: Double? = nil,
        hipsCm: Double? = nil,
        inseamCm: Double? = nil,
        stylePreferences: [String] = [],
        favoriteBrands: [String] = [],
        preferredColours: [String] = [],
        locationCity: String? = nil,
        recommendationOptIn: Bool? = nil
    ) {
        self.currencyCode = currencyCode
        self.preferredSizeSystem = preferredSizeSystem
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.hipsCm = hipsCm
        self.inseamCm = inseamCm
        self.stylePreferences = stylePreferences
        self.favoriteBrands = favoriteBrands
        self.preferredColours = preferredColours
        self.locationCity = locationCity
        self.recommendationOptIn = recommendationOptIn
    }

    private enum CodingKeys: String, CodingKey {
        case currencyCode
        case preferredSizeSystem
        case heightCm
        case weightKg
        case chestCm
        case waistCm
        case hipsCm
        case inseamCm
        case stylePreferences
        case favoriteBrands
        case preferredColours
        case locationCity
        case recommendationOptIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? "USD"
        preferredSizeSystem = try container.decodeIfPresent(String.self, forKey: .preferredSizeSystem) ?? "US"
        heightCm = try container.decodeIfPresent(Double.self, forKey: .heightCm)
        weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        chestCm = try container.decodeIfPresent(Double.self, forKey: .chestCm)
        waistCm = try container.decodeIfPresent(Double.self, forKey: .waistCm)
        hipsCm = try container.decodeIfPresent(Double.self, forKey: .hipsCm)
        inseamCm = try container.decodeIfPresent(Double.self, forKey: .inseamCm)
        stylePreferences = try container.decodeIfPresent([String].self, forKey: .stylePreferences) ?? []
        favoriteBrands = try container.decodeIfPresent([String].self, forKey: .favoriteBrands) ?? []
        preferredColours = try container.decodeIfPresent([String].self, forKey: .preferredColours) ?? []
        locationCity = try container.decodeIfPresent(String.self, forKey: .locationCity)
        recommendationOptIn = try container.decodeIfPresent(Bool.self, forKey: .recommendationOptIn)
    }

    static let `default` = UserPreferences(
        currencyCode: "USD",
        preferredSizeSystem: "US",
        stylePreferences: [],
        favoriteBrands: [],
        preferredColours: []
    )
}
