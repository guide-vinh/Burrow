import Foundation

/// One filesystem hit from `AppScanner.findLeftovers(for:)`. Pairs the
/// resolved URL with the catalog `LeftoverPattern` that produced it,
/// plus the engine's per-match flags.
struct LeftoverMatch: Hashable, Identifiable {
    /// Resolved on-disk URL (placeholder substitution + matchType
    /// expansion already applied).
    let url: URL

    /// Recursive byte size measured by `SafeFileOps.size(_:)`.
    let bytes: Int64

    /// The catalog rule that produced this match.
    let pattern: LeftoverPattern

    /// True when this match targets a vendor-shared root (e.g. the
    /// Adobe directory that all Adobe apps share). UI must surface
    /// the vendor `warning` and default-uncheck regardless of risk.
    let isShared: Bool

    var id: URL { url }
}
