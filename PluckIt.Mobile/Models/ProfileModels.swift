import Foundation

struct UserProfile: Codable {
    let userId: String?
    let email: String?
    let displayName: String?
    let knownBrands: [String]?
    let knownColors: [String]?
    let knownCategories: [String]?
}
