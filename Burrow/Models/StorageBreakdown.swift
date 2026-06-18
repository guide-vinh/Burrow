import Foundation
import SwiftUI

/// One slice of the volume's storage, used by the Analyze donut + legend.
/// Categories are derived (see `AnalyzeViewModel.makeBreakdown`) from the
/// volume capacity plus the `~/` scan — "System" is the remainder of used
/// space outside `/Applications` and the home folder.
enum StorageCategoryKind: String, CaseIterable, Sendable {
    case applications
    case system
    case documents
    case photos
    case other
    case free

    var title: String {
        switch self {
        case .applications: return "Applications"
        case .system:       return "System"
        case .documents:    return "Documents"
        case .photos:       return "Photos"
        case .other:        return "Other"
        case .free:         return "Free space"
        }
    }

    /// Segment / legend-dot color. Pulls from the shared accent where it
    /// matches the mockup, with category-specific hues for the rest.
    var color: Color {
        switch self {
        case .applications: return .accentPrimary          // warm coral
        case .system:       return Color(hex: 0x7A746E)    // warm grey
        case .documents:    return Color(hex: 0xE0A458)    // amber
        case .photos:       return Color(hex: 0xB5705A)    // terracotta
        case .other:        return Color(hex: 0xC4BDB4)    // taupe
        case .free:         return Color(hex: 0xECE7E1)    // pale sand
        }
    }

    /// The pale "Free space" dot needs an outline to read against white.
    var dotStroke: Color? {
        self == .free ? Color(hex: 0xD9D3CB) : nil
    }
}

/// One category's byte count. `Identifiable` for `ForEach` in the legend.
struct StorageCategory: Identifiable, Sendable {
    let kind: StorageCategoryKind
    let bytes: Int64

    var id: StorageCategoryKind { kind }
    var title: String { kind.title }
    var color: Color { kind.color }

    var humanSize: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

/// Whole-volume storage breakdown shown in the Analyze tab's left column.
/// `categories` is ordered for both the donut (clockwise) and the legend,
/// and includes the trailing `.free` slice.
struct StorageBreakdown: Sendable {
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64
    let volumeName: String
    let categories: [StorageCategory]

    /// Fraction of the volume that is used (0...1).
    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    /// Fraction of the volume that is free (0...1).
    var freeFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(freeBytes) / Double(totalBytes)
    }

    /// Used percent, rounded for display (e.g. 61).
    var usedPercent: Int { Int((usedFraction * 100).rounded()) }

    /// Free percent, rounded for display (e.g. 39).
    var freePercent: Int { Int((freeFraction * 100).rounded()) }

    var humanUsed: String { Self.human(usedBytes) }
    var humanTotal: String { Self.human(totalBytes) }
    var humanFree: String { Self.human(freeBytes) }

    private static func human(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
