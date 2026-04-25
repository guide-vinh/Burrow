import SwiftUI

// MARK: - Color

extension Color {

    // Surface
    static let surfacePrimary     = Color(hex: 0xFFFEFC)
    static let surfaceSecondary   = Color(hex: 0xFAF7F4)
    static let surfaceTertiary    = Color(hex: 0xF2EDE8)
    static let surfaceInverse     = Color(hex: 0xFF7A59)
    static let surfaceInverseSoft = Color(hex: 0xFFE4DC)

    // Foreground
    static let fgPrimary   = Color(hex: 0x2A2522)
    static let fgSecondary = Color(hex: 0x6B6360)
    static let fgMuted     = Color(hex: 0x9C928C)
    static let fgInverse   = Color.white

    // Accent (warm coral)
    static let accentPrimary      = Color(hex: 0xFF7A59)
    static let accentPrimaryHover = Color(hex: 0xE85D3C)
    static let accentSoft         = Color(hex: 0xFFF1ED)

    // Destructive
    static let destructive      = Color(hex: 0xDC2626)
    static let destructiveHover = Color(hex: 0xB91C1C)

    // Borders
    static let borderSubtle = Color(hex: 0xEDE6DF)

    // Risk level pairs (background, foreground)
    enum Risk {
        static let lowBG  = Color(hex: 0xE8F5E9)
        static let lowFG  = Color(hex: 0x2E7D32)
        static let medBG  = Color(hex: 0xFFF4E5)
        static let medFG  = Color(hex: 0xB45309)
        static let highBG = Color(hex: 0xFEE2E2)
        static let highFG = Color(hex: 0xB91C1C)
    }
}

// MARK: - Spacing — 4pt grid

enum Spacing {
    static let xs: CGFloat  = 4
    static let sm: CGFloat  = 8
    static let md: CGFloat  = 12
    static let lg: CGFloat  = 16
    static let xl: CGFloat  = 24
    static let xxl: CGFloat = 32
}

// MARK: - Radii

enum Radius {
    static let sm: CGFloat   = 6
    static let md: CGFloat   = 8
    static let lg: CGFloat   = 12
    static let xl: CGFloat   = 16
    static let pill: CGFloat = 9999
}
