import Foundation
import Combine

enum PluckTab: Int, CaseIterable {
    case wardrobe = 0
    case vault = 1
    case collections = 2
    case discover = 3
    case stylist = 4
    case profile = 5
}

@MainActor
final class MobileNavState: ObservableObject {
    @Published var selectedTab: PluckTab = .wardrobe
    @Published var isProfileOpen: Bool = false
    @Published var isDigestOpen: Bool = false
}
