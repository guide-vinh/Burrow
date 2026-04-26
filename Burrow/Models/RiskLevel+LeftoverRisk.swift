import Foundation

/// Bridges the catalog's three-level safety vocabulary
/// (`safe`/`caution`/`highValue`) onto the existing `RiskLevel` from
/// Phase 1 (`low`/`medium`/`high`) so the Uninstall view can reuse
/// `RiskPill` without translating at every call site.
extension LeftoverPattern.Risk {
    var asRiskLevel: RiskLevel {
        switch self {
        case .safe:      return .low
        case .caution:   return .medium
        case .highValue: return .high
        }
    }
}
