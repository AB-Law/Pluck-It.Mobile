import Foundation

struct WardrobeDigest: Codable, Identifiable {
    let id: String
    let userId: String?
    let generatedAt: String?
    let wardrobeHash: String?
    let suggestions: [DigestSuggestion]
    let stylesConsidered: [String]?
    let totalItems: Int?
    let itemsWithWearHistory: Int?
    let climateZone: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        generatedAt = try c.decodeIfPresent(String.self, forKey: .generatedAt)
        wardrobeHash = try c.decodeIfPresent(String.self, forKey: .wardrobeHash)
        suggestions = try c.decodeIfPresent([DigestSuggestion].self, forKey: .suggestions) ?? []
        stylesConsidered = try c.decodeIfPresent([String].self, forKey: .stylesConsidered)
        totalItems = try c.decodeIfPresent(Int.self, forKey: .totalItems)
        itemsWithWearHistory = try c.decodeIfPresent(Int.self, forKey: .itemsWithWearHistory)
        climateZone = try c.decodeIfPresent(String.self, forKey: .climateZone)
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, generatedAt, wardrobeHash, suggestions, stylesConsidered,
             totalItems, itemsWithWearHistory, climateZone
    }
}

struct DigestSuggestion: Codable {
    let item: String
    let rationale: String?
}

struct DigestFeedbackRequest: Codable {
    let digestId: String
    let suggestionIndex: Int
    let suggestionDescription: String?
    let signal: String
}

struct DigestFeedbackItem: Codable {
    let suggestionIndex: Int
    let signal: String
}
