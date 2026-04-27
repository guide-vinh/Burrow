import CryptoKit
import Foundation
import SwiftUI

/// One filesystem entry from a disk scan. Immutable, value-type.
/// Hashable so it can live in Sets and dictionaries.
struct DiskEntry: Hashable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    let parentURL: URL?
    let name: String
    let size: Int64           // bytes; recursive total for directories
    let isDirectory: Bool
    let modifiedAt: Date
    let lastAccessedAt: Date? // unreliable on macOS — see PHASE3_DECISIONS §6
    let childCount: Int       // immediate children, 0 for files
}

extension DiskEntry {

    /// Human-readable size, "1.4 GB" / "234 KB".
    /// Uses ByteCountFormatter, locale-aware.
    var humanSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// Deterministic (h, s, b) tuple derived from `url.path` via SHA-256.
    /// Bounded so the resulting color is readable with overlay text.
    /// Tests assert this tuple, not `Color`, since `Color` doesn't have
    /// reliable value-equality.
    /// Implementation per PHASE3_DECISIONS §5:
    ///   hash = SHA256(url.path)
    ///   hue = bytes[0] / 255
    ///   saturation = 0.45 + bytes[1] / 255 * 0.25   // → 0.45–0.70
    ///   brightness = 0.62 + bytes[2] / 255 * 0.18   // → 0.62–0.80
    var colorComponents: (hue: Double, saturation: Double, brightness: Double) {
        let data = url.path.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        let bytes = Array(hash.prefix(3))
        let hue = Double(bytes[0]) / 255.0
        let saturation = 0.45 + Double(bytes[1]) / 255.0 * 0.25
        let brightness = 0.62 + Double(bytes[2]) / 255.0 * 0.18
        return (hue: hue, saturation: saturation, brightness: brightness)
    }

    /// SwiftUI `Color` built from `colorComponents`. Exposed despite
    /// UI_ARCH §7 because PHASE3_PLAN.md Task 1 spec requires it
    /// (PHASE3_DECISIONS §13: PLAN > UI_ARCH in conflict).
    var colorSeed: Color {
        let c = colorComponents
        return Color(hue: c.hue, saturation: c.saturation, brightness: c.brightness)
    }
}
