import Foundation

/// One app discovered by `AppScanner`. Pure data — no AppKit / SwiftUI
/// types; the view loads `NSWorkspace.icon(forFile:)` at render time.
/// Identity is the bundle ID; two installs with the same bundle ID
/// (e.g. /Applications + ~/Applications) are treated as one app.
struct InstalledApp: Hashable, Identifiable, Sendable {
    /// `CFBundleIdentifier` — primary key, drives leftover scan.
    let bundleId: String

    /// `CFBundleName` or, if absent, the .app filename without extension.
    let name: String

    /// `CFBundleDisplayName`; may differ from `name` (e.g. localized).
    let displayName: String?

    /// On-disk path to the .app bundle.
    let bundleURL: URL

    /// `CFBundleShortVersionString` (e.g. "14.2").
    let version: String?

    /// `CFBundleVersion` (the build number, e.g. "1402.7").
    let build: String?

    /// Recursive size of the .app bundle in bytes. Computed lazily —
    /// nil until the scanner has measured it.
    let bundleSize: Int64?

    /// Last time the user opened this app, per Spotlight metadata
    /// (`kMDItemLastUsedDate`). Requires Full Disk Access; nil if
    /// unavailable.
    let lastOpenedDate: Date?

    /// How the app was installed. Set by `AppScanner` based on
    /// `_MASReceipt` presence and Caskroom symlink target.
    let installSource: InstallSource

    var id: String { bundleId }
}
