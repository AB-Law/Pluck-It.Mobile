import SwiftUI

/// Adds the shared profile and digest toolbar buttons to any tab view's NavigationStack.
struct ShellToolbarModifier: ViewModifier {
    @EnvironmentObject private var navState: MobileNavState

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                shellBarButton(systemName: "chart.bar") {
                    navState.isDigestOpen = true
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                shellBarButton(systemName: "person.circle") {
                    navState.isProfileOpen = true
                }
            }
        }
    }

    private func shellBarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            pluckImpactFeedback(.light)
            action()
        } label: {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PluckTheme.primaryText)
                .frame(width: PluckTheme.Control.rowHeight, height: PluckTheme.Control.rowHeight)
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(PluckTheme.border, lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

extension View {
    func shellToolbar() -> some View {
        modifier(ShellToolbarModifier())
    }
}
