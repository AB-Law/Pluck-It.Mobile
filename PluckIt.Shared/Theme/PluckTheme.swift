import SwiftUI

enum PluckTheme {
    static let background = Color(red: 0.08, green: 0.08, blue: 0.12)
    static let card = Color(red: 0.16, green: 0.16, blue: 0.22)
    static let muted = Color(red: 0.74, green: 0.72, blue: 0.86)
    static let accent = Color(red: 0.74, green: 0.47, blue: 0.26)
    static let title = Color.white
    static let terminalBackground = Color(red: 0.03, green: 0.03, blue: 0.06)
    static let terminalPanel = Color(red: 0.14, green: 0.14, blue: 0.22)
    static let terminalPanelSubtle = Color(red: 0.08, green: 0.08, blue: 0.12)
    static let terminalBorder = Color(red: 0.42, green: 0.53, blue: 0.64).opacity(0.22)
    static let terminalGrid = Color.white.opacity(0.03)
    static let terminalScanline = Color(red: 0.39, green: 1.0, blue: 0.84).opacity(0.45)
    static let terminalSuccess = Color(red: 0.35, green: 0.95, blue: 0.52)
    static let terminalWarning = Color(red: 1.0, green: 0.83, blue: 0.40)
    static let terminalInfo = Color(red: 0.24, green: 0.72, blue: 1.0)
    static let terminalMuter = Color(red: 0.57, green: 0.67, blue: 0.76).opacity(0.4)

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

    enum Motion {
        static let fast = 0.18
        static let medium = 0.3
        static let slow = 0.45
    }

    enum Typography {
        static let sectionHeader = Font.system(.subheadline, design: .rounded).weight(.semibold)
        static let valueStrong = Font.system(.title2, design: .rounded).weight(.bold)
        static let terminalHeadline = Font.system(.title, design: .rounded).weight(.bold)
        static let terminalLabel = Font.system(.caption, design: .monospaced).weight(.semibold)
        static let terminalBody = Font.system(.body, design: .monospaced)
    }
}
