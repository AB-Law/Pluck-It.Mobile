import SwiftUI

/// SwiftUI shell matching the web app's tab and overlay patterns.
struct MobileShellView: View {
    @EnvironmentObject private var appServices: AppServices
    @EnvironmentObject private var navState: MobileNavState

    var body: some View {
        TabView(selection: $navState.selectedTab) {
            WardrobeView()
                .tabItem {
                    Label("Wardrobe", systemImage: "tshirt")
                }
                .tag(PluckTab.wardrobe)

            VaultView()
                .tabItem {
                    Label("Vault", systemImage: "square.grid.2x2")
                }
                .tag(PluckTab.vault)

            CollectionsView()
                .tabItem {
                    Label("Collections", systemImage: "rectangle.stack")
                }
                .tag(PluckTab.collections)

            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "sparkles")
                }
                .tag(PluckTab.discover)

            StylistView()
                .tabItem {
                    Label("Stylist", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(PluckTab.stylist)
        }
        .tint(PluckTheme.accent)
        .toolbarBackground(PluckTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .accentColor(PluckTheme.accent)
        .toolbarBackground(PluckTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .background(PluckTheme.background)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }
}
