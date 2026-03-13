import SwiftUI

/// Root shell of the PluckIt application including tab navigation and overlays.
struct AppRootView: View {
    @EnvironmentObject private var appServices: AppServices
    @EnvironmentObject private var navState: MobileNavState

    var body: some View {
        ZStack {
            MobileShellView()
                .environmentObject(appServices)
                .environmentObject(navState)

            if !appServices.networkMonitor.isOnline {
                VStack {
                    Text("Offline")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $navState.isProfileOpen) {
            ProfileOverlay()
                .environmentObject(appServices)
        }
        .fullScreenCover(isPresented: $navState.isDigestOpen) {
            DigestOverlay()
                .environmentObject(appServices)
        }
    }
}

private struct DigestOverlay: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Digest")
                    .font(.largeTitle)
                    .fontWeight(.black)
                    .foregroundStyle(.white)
                Text("Digest insights from your wardrobe are coming in Phase 2.")
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PluckTheme.background)
            .navigationTitle("Digest")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Close")
                    }
                }
            }
        }
    }
}
