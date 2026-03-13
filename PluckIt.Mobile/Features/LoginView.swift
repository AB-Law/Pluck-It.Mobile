import SwiftUI
import UIKit

/// Entry screen rendered when no authenticated identity is available.
struct LoginView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var isSigningIn = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: PluckTheme.Spacing.lg) {
            Spacer()

            VStack(spacing: PluckTheme.Spacing.sm) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 56))
                    .foregroundStyle(PluckTheme.accent)
                Text("Welcome to PluckIt")
                    .font(.title2.bold())
                    .foregroundStyle(PluckTheme.primaryText)
                Text("Sign in with Google to connect your wardrobe and unlock synced recommendations.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PluckTheme.secondaryText)
                    .padding(.horizontal, PluckTheme.Spacing.md)
            }

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(PluckTheme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PluckTheme.Spacing.md)
            }

            Button {
                Task {
                    await signInWithGoogle()
                }
            } label: {
                HStack(spacing: PluckTheme.Spacing.sm) {
                    if isSigningIn {
                        ProgressView()
                            .tint(PluckTheme.background)
                    }
                    Text(isSigningIn ? "Signing in..." : "Continue with Google")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, PluckTheme.Spacing.md)
                .background(PluckTheme.accent)
                .foregroundStyle(PluckTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.medium))
            }
            .disabled(isSigningIn)
            .padding(.horizontal, PluckTheme.Spacing.md)

            Spacer()
        }
        .padding(.vertical, PluckTheme.Spacing.xl)
        .frame(maxHeight: .infinity)
        .background(PluckTheme.background)
    }

    private func signInWithGoogle() async {
        guard !isSigningIn else { return }
        guard let presenter = activeViewController() else {
            errorText = "Could not find the app window. Open the app again and retry."
            return
        }

        isSigningIn = true
        errorText = nil

        do {
            try await appServices.authService.signInWithGoogle(presentingViewController: presenter)
        } catch {
            errorText = String(describing: error)
        }

        isSigningIn = false
    }

    private func activeViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return nil
        }

        if let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            return deepestPresentedController(from: root)
        }

        return scene.windows
            .compactMap(\.rootViewController)
            .compactMap(deepestPresentedController(from:))
            .first
    }

    private func deepestPresentedController(from controller: UIViewController?) -> UIViewController? {
        guard var current = controller else { return nil }
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
}
