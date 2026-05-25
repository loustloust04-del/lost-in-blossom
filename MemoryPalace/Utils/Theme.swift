import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Theme {
    private static var currentTokens: ThemeTokenSet {
        ThemeManager.shared.currentTokenSet
    }

    static var mainBg: Color { currentTokens.mainBg.color }
    static var sidebarBg: Color { currentTokens.sidebarBg.color }
    static var userBubble: Color { currentTokens.userBubble.color }
    static var assistantBubble: Color { currentTokens.assistantBubble.color }
    static var accent: Color { currentTokens.accent.color }
    static var textPrimary: Color { currentTokens.textPrimary.color }
    static var textSecondary: Color { currentTokens.textSecondary.color }
    static var textMuted: Color { currentTokens.textMuted.color }
    static var favorite: Color { currentTokens.favorite.color }
    static var danger: Color { currentTokens.danger.color }
    static var branchIndicator: Color { currentTokens.branchIndicator.color }
    static var activeScheme: ColorScheme { ThemeManager.shared.activeScheme }

    #if os(macOS)
    static var platformMainBackgroundColor: NSColor { currentTokens.mainBg.platformColor }
    #else
    static var platformMainBackgroundColor: UIColor { currentTokens.mainBg.platformColor }
    #endif

    static let bubbleCornerRadius: CGFloat = 16
    static let bubblePadding: CGFloat = 14
    static let bubbleSpacing: CGFloat = 6
    static let bubbleMaxWidthRatio: CGFloat = 0.75
    static let cardShadow = Color.black.opacity(0.04)
    static let cardShadowRadius: CGFloat = 3

    enum SettingsFont {
        #if os(iOS)
        static let sectionHeader: CGFloat = 16
        static let label: CGFloat = 15
        static let body: CGFloat = 14
        static let secondary: CGFloat = 13
        static let caption: CGFloat = 11
        static let badge: CGFloat = 11
        static let mono: CGFloat = 13
        #else
        static let sectionHeader: CGFloat = 13
        static let label: CGFloat = 12
        static let body: CGFloat = 11
        static let secondary: CGFloat = 10
        static let caption: CGFloat = 9
        static let badge: CGFloat = 8
        static let mono: CGFloat = 11
        #endif
    }

    // 全局别名，方便非设置页使用
    typealias F = SettingsFont

    #if os(iOS)
    static let optionRowVerticalPadding: CGFloat = 12
    static let optionRowSpacing: CGFloat = 2
    #else
    static let optionRowVerticalPadding: CGFloat = 6
    static let optionRowSpacing: CGFloat = 4
    #endif

    static var cream: Color { mainBg }
    static var paleBlue: Color { accent }
    static var softBlue: Color { branchIndicator }
    static var userCard: Color { userBubble }
    static var assistantCard: Color { assistantBubble }
    static let cardCornerRadius = bubbleCornerRadius
    static let cardPadding = bubblePadding
    static let cardSpacing = bubbleSpacing
}

// MARK: - Hex Color Extension
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
