import Foundation
import Combine

enum PluckTab: Int, CaseIterable {
    case wardrobe = 0
    case vault = 1
    case wishlist = 2
    case collections = 3
    case discover = 4
    case stylist = 5
    case profile = 6
}

@MainActor
final class MobileNavState: ObservableObject {
    @Published var selectedTab: PluckTab = .wardrobe
    @Published var isProfileOpen: Bool = false
    @Published var isDigestOpen: Bool = false
}
