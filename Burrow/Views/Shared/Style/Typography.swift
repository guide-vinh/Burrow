import SwiftUI

extension Font {
    // Display & headlines
    static let displayXL = Font.system(size: 32, weight: .semibold, design: .rounded)
    static let titleL    = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let titleM    = Font.system(size: 16, weight: .semibold, design: .rounded)

    // Body
    static let bodyM    = Font.system(size: 14, weight: .regular, design: .rounded)
    static let bodyS    = Font.system(size: 13, weight: .regular, design: .rounded)
    static let bodySMed = Font.system(size: 13, weight: .medium,  design: .rounded)

    // Caption / labels
    static let captionM = Font.system(size: 12, weight: .regular,  design: .rounded)
    static let captionS = Font.system(size: 11, weight: .regular,  design: .rounded)
    static let pill     = Font.system(size: 10, weight: .semibold, design: .rounded)

    // Mono
    static let monoM = Font.system(size: 13, weight: .medium,  design: .monospaced)
    static let monoS = Font.system(size: 11, weight: .regular, design: .monospaced)
}
