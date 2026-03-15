import SwiftUI

/// Shell container for authenticated Mac flow and high-level feature navigation.
struct MacShellView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var selection: MacSidebarItem? = .wardrobe
    @State private var lastHeartbeat = "SYSTEM READY"

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                MacWindowChrome(
                    title: "PluckIt Terminal | ARCHIVE_NODE_14",
                    detail: lastHeartbeat
                ) {
                    Button {
                        appServices.authService.signOut()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .font(.caption)
                        .foregroundStyle(PluckTheme.terminalMuter)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 999)
                            .fill(PluckTheme.background.opacity(0.2))
                    )
                }

                List(MacSidebarItem.allCases, selection: $selection) { item in
                    MacShellRow(title: item.title, icon: item.symbol, isSelected: item == selection)
                        .tag(item)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(PluckTheme.terminalPanel)
            }
            .background(PluckTheme.background)
        } detail: {
            ZStack {
                PluckTheme.background
                    .ignoresSafeArea()

                // All views are kept alive in the hierarchy to preserve their
                // loaded state (items, images) across tab switches. Opacity
                // hides inactive tabs without destroying them.
                let active = selection ?? .wardrobe
                MacWardrobeView()
                    .opacity(active == .wardrobe ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MacVaultView()
                    .opacity(active == .vault ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MacCollectionsView()
                    .opacity(active == .collections ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MacDiscoverView()
                    .opacity(active == .discover ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MacStylistView()
                    .opacity(active == .stylist ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MacProfileView()
                    .opacity(active == .profile ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(PluckTheme.background)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            updateStatusPulse()
        }
    }

    private func updateStatusPulse() {
        let format = DateFormatter()
        format.timeStyle = .short
        lastHeartbeat = "SYSTEM READY • \(format.string(from: Date()))"
    }
}

private enum MacSidebarItem: String, CaseIterable, Identifiable {
    case wardrobe
    case vault
    case collections
    case discover
    case stylist
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wardrobe:
            return "Wardrobe"
        case .vault:
            return "Vault"
        case .collections:
            return "Collections"
        case .discover:
            return "Discover"
        case .stylist:
            return "Stylist"
        case .profile:
            return "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .wardrobe:
            return "tshirt"
        case .vault:
            return "chart.bar.xaxis"
        case .collections:
            return "square.grid.2x2"
        case .discover:
            return "sparkles"
        case .stylist:
            return "bubble.left.and.bubble.right"
        case .profile:
            return "person.crop.circle"
        }
    }
}
