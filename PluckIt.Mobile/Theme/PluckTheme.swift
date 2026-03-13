import SwiftUI

enum PluckTheme {
    static let background = Color(red: 0.08, green: 0.08, blue: 0.12)
    static let card = Color(red: 0.16, green: 0.16, blue: 0.22)
    static let muted = Color(red: 0.74, green: 0.72, blue: 0.86)
    static let accent = Color(red: 0.74, green: 0.47, blue: 0.26)
    static let title = Color.white

    // Semantic palette for surfaces and text
    static let primaryText = Color.white
    static let secondaryText = Color(red: 0.82, green: 0.82, blue: 0.88)
    static let mutedText = muted
    static let border = Color(red: 0.24, green: 0.24, blue: 0.34).opacity(0.6)
    static let danger = Color(red: 1.0, green: 0.34, blue: 0.34)
    static let success = Color(red: 0.22, green: 0.78, blue: 0.42)
    static let info = Color(red: 0.42, green: 0.69, blue: 1.0)

    // Reusable message bubble colors
    static let assistantBubble = Color(red: 0.22, green: 0.22, blue: 0.29)
    static let userBubble = Color(red: 0.0, green: 0.47, blue: 1.0)

    enum Radius {
        static let xxSmall: CGFloat = 6
        static let xSmall: CGFloat = 10
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Control {
        static let rowHeight: CGFloat = 44
        static let cardPadding: CGFloat = 12
        static let sectionSpacing: CGFloat = 14
    }

    enum Typography {
        static let sectionHeader = Font.system(.subheadline, design: .rounded).weight(.semibold)
        static let valueStrong = Font.system(.title2, design: .rounded).weight(.bold)
    }
}
