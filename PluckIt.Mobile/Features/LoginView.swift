import SwiftUI
import UIKit

/// Entry screen rendered when no authenticated identity is available.
struct LoginView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var isSigningIn = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.12, blue: 0.16),
                    PluckTheme.background,
                    Color(red: 0.06, green: 0.06, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: PluckTheme.Spacing.xl) {
                    VStack(spacing: PluckTheme.Spacing.md) {
                        Image(systemName: "leaf.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 86, height: 86)
                            .background(PluckTheme.card)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(PluckTheme.accent, lineWidth: 1.2)
                            )

                        VStack(spacing: 6) {
                            Text("Welcome to PluckIt")
                                .font(.title2.bold())
                                .foregroundStyle(PluckTheme.primaryText)
                                .multilineTextAlignment(.center)
                            Text("Sign in to connect your wardrobe and unlock your weekly AI recommendations.")
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(PluckTheme.secondaryText)
                                .padding(.horizontal, PluckTheme.Spacing.md)
                        }
                    }
                .pluckReveal(delay: 0.04)
                    .padding(.top, 44)

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(PluckTheme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, PluckTheme.Spacing.md)
                    }

                    VStack(spacing: PluckTheme.Spacing.sm) {
                        Button {
                            pluckImpactFeedback()
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
                        .pluckReveal(delay: 0.14)
                        .disabled(isSigningIn)
                        .buttonStyle(.plain)

                        Text("We keep your data synced securely and only use it for wardrobe intelligence.")
                            .font(.caption2)
                            .foregroundStyle(PluckTheme.mutedText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, PluckTheme.Spacing.xl)
                    }
                    .pluckReveal(delay: 0.18)
                    .padding(.horizontal, PluckTheme.Spacing.md)

                    Spacer(minLength: PluckTheme.Spacing.xxl)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, PluckTheme.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PluckTheme.background)
        .preferredColorScheme(.dark)
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
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
