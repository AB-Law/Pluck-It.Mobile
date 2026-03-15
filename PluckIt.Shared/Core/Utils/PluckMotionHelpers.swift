import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Subtle reveal animation used for page sections and card-like content.
struct PluckRevealModifier: ViewModifier {
    let delay: Double
    let distance: CGFloat
    let scale: CGFloat

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : distance)
            .scaleEffect(isVisible ? 1 : scale)
            .animation(
                .spring(response: 0.42, dampingFraction: 0.86).delay(delay),
                value: isVisible
            )
            .onAppear {
                isVisible = true
            }
    }
}

extension View {
    /// Adds an entrance fade/offset/scale animation to the view.
    func pluckReveal(delay: Double = 0.0, distance: CGFloat = 12, scale: CGFloat = 0.985) -> some View {
        modifier(PluckRevealModifier(delay: delay, distance: distance, scale: scale))
    }
}

/// Triggers a subtle haptic cue for press and action confirmation.
enum PluckHapticStyle {
    case light
    case medium
    case heavy
}

#if canImport(UIKit)
func pluckImpactFeedback(_ style: PluckHapticStyle = .light) {
    let generatorStyle: UIImpactFeedbackGenerator.FeedbackStyle = {
        switch style {
        case .light: return .light
        case .medium: return .medium
        case .heavy: return .heavy
        }
    }()
    let generator = UIImpactFeedbackGenerator(style: generatorStyle)
    generator.prepare()
    generator.impactOccurred()
}
#else
func pluckImpactFeedback(_ style: PluckHapticStyle = .light) {
    _ = style
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
}
#endif
