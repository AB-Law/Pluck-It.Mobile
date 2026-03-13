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

    static let `default` = UserPreferences(
        currencyCode: "USD",
        preferredSizeSystem: "US",
        stylePreferences: [],
        favoriteBrands: [],
        preferredColours: []
    )
}
