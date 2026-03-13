import Foundation

struct CpwIntelItem: Codable, Equatable {
    let key: String?
    let value: Double?
}

struct VaultInsightsResponse: Codable {
    let cpw: Double?
    let averageItemCount: Int?
    let totalItems: Int?
    let cpwItems: [CpwIntelItem]?
    let totalMarketValue: Double?
}

struct WearLogResponse: Codable {
    let id: String
    let message: String?
}
