import Foundation

/// Snapshot of an apply (Clean tab) or uninstall (Uninstall tab),
/// surfaced via `PreviewBanner`. `kind` records what actually happened
/// so the banner wording matches: a dry-run preview, a real move to
/// Trash, or a real permanent delete. Auto-dismissed by the owning
/// view-model 5 seconds after being set.
struct PreviewSummary: Equatable {
    enum Kind: Equatable {
        case preview
        case trashed
        case deleted
    }

    let items: Int
    let bytes: Int64
    var kind: Kind = .preview
}
