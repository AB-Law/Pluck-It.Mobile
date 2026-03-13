import Foundation

struct VaultInsightsResponse: Codable {
    let generatedAt: String?
    let currency: String?
    let insufficientData: Bool?
    let behavioralInsights: VaultBehavioralInsights?
    let cpwIntel: [CpwIntelItem]?
}

struct VaultBehavioralInsights: Codable {
    let topColorWearShare: TopColorWearShare?
    let unworn90dPct: Double?
    let mostExpensiveUnworn: ExpensiveUnwornItem?
    let sparseHistory: Bool?
}

struct TopColorWearShare: Codable {
    let color: String
    let pct: Double
}

struct ExpensiveUnwornItem: Codable {
    let itemId: String
    let amount: Double
    let currency: String
}

struct CpwIntelItem: Codable {
    let itemId: String?
    let cpw: Double?
    let badge: String?
    let breakEvenReached: Bool?
    let breakEvenTargetCpw: Double?
}

struct WearLogResponse: Codable {
    let id: String
    let message: String?
}
