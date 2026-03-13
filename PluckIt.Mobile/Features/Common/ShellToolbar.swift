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
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline)
                .foregroundStyle(PluckTheme.primaryText)
                .frame(width: PluckTheme.Control.rowHeight, height: PluckTheme.Control.rowHeight)
                .background(PluckTheme.card)
                .clipShape(Circle())
        }
    }
}

extension View {
    func shellToolbar() -> some View {
        modifier(ShellToolbarModifier())
    }
}
