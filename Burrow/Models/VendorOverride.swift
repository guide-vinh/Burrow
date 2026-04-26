import Foundation

/// Per-vendor extra leftover patterns (Adobe, Microsoft, JetBrains, …).
/// Applied IN ADDITION TO the generic `userPaths` / `systemPaths`
/// patterns when an installed app's bundle ID matches the vendor key.
struct VendorOverride: Codable, Hashable {
    let displayName: String?
    let paths: [LeftoverPattern]
    /// Optional warning shown in the UI when this vendor's paths are
    /// about to be removed (e.g. "shared resources used by other apps").
    let warning: String?
}
