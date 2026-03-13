import SwiftUI

/// Root shell of the PluckIt application including tab navigation and overlays.
struct AppRootView: View {
    @EnvironmentObject private var appServices: AppServices
    @EnvironmentObject private var navState: MobileNavState

    var body: some View {
        ZStack(alignment: .top) {
            MobileShellView()
                .environmentObject(appServices)
                .environmentObject(navState)
                .transition(.opacity)
                .pluckReveal()

            if !appServices.networkMonitor.isOnline {
                VStack {
                    HStack {
                        Label("Offline", systemImage: "wifi.slash")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, PluckTheme.Spacing.md)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.75))
                            .foregroundStyle(PluckTheme.primaryText)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(PluckTheme.border, lineWidth: 1)
                            )
                        Spacer()
                    }
                    .padding(.horizontal, PluckTheme.Spacing.md)
                    .padding(.top, PluckTheme.Spacing.md)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: appServices.networkMonitor.isOnline)
        .sheet(isPresented: $navState.isProfileOpen) {
            ProfileOverlay()
                .environmentObject(appServices)
        }
        .fullScreenCover(isPresented: $navState.isDigestOpen) {
            DigestPanelView()
                .environmentObject(appServices)
        }
        .preferredColorScheme(.dark)
    }
}
