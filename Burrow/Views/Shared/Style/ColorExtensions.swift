import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex & 0xFF0000) >> 16) / 255
        let g = Double((hex & 0x00FF00) >> 8)  / 255
        let b = Double(hex & 0x0000FF)         / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
