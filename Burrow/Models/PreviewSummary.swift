import Foundation

/// Snapshot of a dry-run apply (Clean tab) or dry-run uninstall
/// (Uninstall tab). Surfaced via `PreviewBanner`. Auto-dismissed by
/// the owning view-model 5 seconds after being set.
struct PreviewSummary: Equatable {
    let items: Int
    let bytes: Int64
}
