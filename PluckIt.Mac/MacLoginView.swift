import SwiftUI
import AppKit

/// Terminal-inspired login screen for macOS with Google auth entrypoint.
struct MacLoginView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var isSigningIn = false
    @State private var errorText: String?

    private let bootLines: [(String, String, String?)] = [
        ("BOOT", "Initializing Pluck-It OS core modules...", "DONE"),
        ("VISION", "Loading AI Vision v4.0.12 ...", "READY"),
        ("AUTH", "Awaiting user credential handshake...", nil)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    PluckTheme.terminalBackground,
                    PluckTheme.background,
                    Color(red: 0.04, green: 0.05, blue: 0.09)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    HStack {
                        MacBackgroundGlyph("checkroom", size: 130)
                            .rotationEffect(.degrees(-9))
                            .offset(x: geometry.size.width * -0.28, y: geometry.size.height * -0.12)
                        Spacer()
                    }
                    HStack {
                        Spacer()
                        MacBackgroundGlyph("apparel", size: 132)
                            .rotationEffect(.degrees(15))
                            .offset(x: geometry.size.width * 0.17, y: geometry.size.height * -0.08)
                        Spacer()
                    }
                    HStack {
                        Spacer()
                        MacBackgroundGlyph("lasso.badge.sparkles", size: 90)
                            .rotationEffect(.degrees(32))
                            .offset(x: geometry.size.width * -0.14, y: geometry.size.height * 0.12)
                        Spacer()
                    }
                    MacScanlineOverlay()
                        .allowsHitTesting(false)
                        .opacity(0.8)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: PluckTheme.Spacing.xl) {
                MacWindowChrome(
                    title: "PLUCK_IT_SECURE_AUTH_ENVIRONMENT_v4.2",
                    detail: "ID: ARCHIVE_ALPHA_09"
                )
                .frame(maxWidth: 980)
                .background(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.large)
                        .fill(PluckTheme.terminalPanel.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: PluckTheme.Radius.large)
                                .stroke(PluckTheme.terminalBorder, lineWidth: 1)
                        )
                )

                MacGlassPanel(
                    title: "Authenticate to Access Your Archive",
                    subtitle: "PluckIt for Mac • secure identity layer"
                ) {
                    VStack(spacing: PluckTheme.Spacing.lg) {
                        VStack(alignment: .center, spacing: PluckTheme.Spacing.sm) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkroom")
                                    .font(.system(size: 44, weight: .semibold))
                                    .foregroundStyle(PluckTheme.terminalInfo)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(PluckTheme.accent)
                            }
                            Text("Pluck-It")
                                .font(.system(size: 42, design: .rounded).weight(.black))
                                .foregroundStyle(PluckTheme.primaryText)
                            Text("Authenticate to Access Your Archive")
                                .font(.caption)
                                .tracking(3)
                                .foregroundStyle(PluckTheme.secondaryText)
                        }
                        .padding(.top, PluckTheme.Spacing.sm)

                        VStack(spacing: PluckTheme.Spacing.sm) {
                            ForEach(Array(bootLines.enumerated()), id: \.offset) { index, line in
                                TerminalBootLine(
                                    leftTag: line.0,
                                    message: line.1,
                                    rightTag: line.2,
                                    delay: 0.35 + Double(index) * 0.45
                                )
                            }
                        }

                        Button {
                            Task { await signIn() }
                        } label: {
                            HStack(spacing: PluckTheme.Spacing.sm) {
                                if isSigningIn {
                                    ProgressView()
                                        .tint(PluckTheme.background)
                                        .controlSize(.regular)
                                }
                                Text(isSigningIn ? "Signing in..." : "Continue with Google")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.vertical, PluckTheme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                                    .fill(PluckTheme.accent)
                            )
                            .foregroundStyle(PluckTheme.background)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSigningIn)

                        if let errorText {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(PluckTheme.danger)
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: PluckTheme.Spacing.md) {
                            Text("Protocol: AES-256-GCM Hardware-Accelerated")
                                .font(.caption)
                                .foregroundStyle(PluckTheme.terminalMuter)
                                .tracking(1.3)
                                .textCase(.uppercase)
                            Spacer()
                            Text("LATENCY: 14ms | UPLINK: STABLE")
                                .font(.caption)
                                .foregroundStyle(PluckTheme.secondaryText)
                                .tracking(1.1)
                        }
                    }
                    .padding(.horizontal, PluckTheme.Spacing.lg)
                    .padding(.bottom, PluckTheme.Spacing.md)
                }
                .frame(maxWidth: 980)

                HStack(spacing: PluckTheme.Spacing.md) {
                    Link(
                        "Terms of Service",
                        destination: URL(string: "https://pluckit.app/tos") ?? URL(string: "https://example.com")!
                    )
                    Link(
                        "Privacy",
                        destination: URL(string: "https://pluckit.app/privacy") ?? URL(string: "https://example.com")!
                    )
                }
                .font(.caption2)
                .foregroundStyle(PluckTheme.secondaryText)
                .pluckReveal(delay: 0.05)
            }
            .frame(maxWidth: 1024, maxHeight: .infinity)
            .padding(.horizontal, PluckTheme.Spacing.lg)
            .padding(.top, PluckTheme.Spacing.md)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private func signIn() async {
        guard !isSigningIn else { return }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
            errorText = "Could not find the active app window."
            return
        }

        isSigningIn = true
        errorText = nil
        do {
            try await appServices.authService.signInWithGoogle(presentingWindow: window)
        } catch {
            let nsError = error as NSError
            print("[MacLogin] Google sign-in failed")
            print("[MacLogin] description: \(error.localizedDescription)")
            print("[MacLogin] domain: \(nsError.domain)")
            print("[MacLogin] code: \(nsError.code)")
            print("[MacLogin] userInfo: \(nsError.userInfo)")
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSigningIn = false
    }
}

private struct TerminalBootLine: View {
    let leftTag: String
    let message: String
    let rightTag: String?
    let delay: Double

    @State private var reveal = false
    @State private var cursorPulse = false

    var body: some View {
        HStack(alignment: .top, spacing: PluckTheme.Spacing.md) {
            Text("[\(leftTag)]")
                .font(PluckTheme.Typography.terminalBody)
                .foregroundStyle(PluckTheme.terminalInfo)
                .frame(width: 74, alignment: .leading)
                .opacity(reveal ? 1 : 0)

            Text(message)
                .font(PluckTheme.Typography.terminalBody)
                .foregroundStyle(PluckTheme.terminalMuter)
                .opacity(reveal ? 1 : 0)

            Spacer()

            if let rightTag {
                Text(rightTag)
                    .font(PluckTheme.Typography.terminalBody)
                    .foregroundStyle(PluckTheme.terminalSuccess)
                    .opacity(reveal ? 1 : 0)
            } else if reveal {
                Rectangle()
                    .fill(PluckTheme.accent)
                    .frame(width: 9, height: 4)
                    .opacity(cursorPulse ? 0.95 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: cursorPulse)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: PluckTheme.Motion.medium)) {
                    reveal = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5) {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    cursorPulse = true
                }
            }
        }
    }
}
#if false
import SwiftUI
import AppKit

struct MacLoginView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var isSigningIn = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.10, green: 0.10, blue: 0.16),
                    Color(red: 0.06, green: 0.06, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: PluckTheme.Spacing.lg) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(PluckTheme.accent)

                VStack(spacing: PluckTheme.Spacing.sm) {
                    Text("PluckIt for Mac")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(PluckTheme.primaryText)
                    Text("Browse your wardrobe, manage collections, chat with the stylist, and upload new items from Finder.")
                        .font(.body)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(PluckTheme.danger)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                Button {
                    Task { await signIn() }
                } label: {
                    HStack(spacing: 10) {
                        if isSigningIn {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSigningIn ? "Signing in..." : "Continue with Google")
                            .font(.headline)
                    }
                    .frame(minWidth: 220)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(PluckTheme.accent)
                .disabled(isSigningIn)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(PluckTheme.card.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(PluckTheme.border, lineWidth: 1)
                    )
            )
            .padding(32)
        }
    }

    private func signIn() async {
        guard !isSigningIn else { return }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
            errorText = "Could not find the active app window."
            return
        }

        isSigningIn = true
        errorText = nil
        do {
            try await appServices.authService.signInWithGoogle(presentingWindow: window)
        } catch {
            let nsError = error as NSError
            print("[MacLogin] Google sign-in failed")
            print("[MacLogin] description: \(error.localizedDescription)")
            print("[MacLogin] domain: \(nsError.domain)")
            print("[MacLogin] code: \(nsError.code)")
            print("[MacLogin] userInfo: \(nsError.userInfo)")
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSigningIn = false
    }
}
#endif
