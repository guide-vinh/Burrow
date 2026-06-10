import Foundation

/// One reclaimable class of Docker storage, as reported by
/// `docker system df`. Produced by `DockerCacheScanner`.
///
/// Unlike every other Clean entry these are **not** trashable —
/// `docker … prune` deletes immediately and irreversibly. The view
/// surfaces them in a self-contained section with its own Reclaim
/// button and confirmation dialog, never via the shared
/// Move-to-Trash footer.
struct DockerCacheEntry: Hashable, Identifiable {

    /// Kinds Burrow surfaces. Volumes are deliberately excluded — they
    /// hold data (named DB mounts, etc.), not cache, and pruning them
    /// is a footgun even for sophisticated users.
    enum Kind: String, CaseIterable, Hashable {
        case buildCache
        case images
        case containers

        /// Maps `docker system df`'s `Type` column to a kind. Returns
        /// nil for rows Burrow doesn't surface (e.g. "Local Volumes").
        init?(dfType: String) {
            switch dfType {
            case "Build Cache": self = .buildCache
            case "Images":      self = .images
            case "Containers":  self = .containers
            default:            return nil
            }
        }

        var title: String {
            switch self {
            case .buildCache: return "Build cache"
            case .images:     return "Unused images"
            case .containers: return "Stopped containers"
            }
        }

        var summary: String {
            switch self {
            case .buildCache:
                return "Layer cache from docker build; rebuilt on next build"
            case .images:
                return "Images not used by any container; re-pulled on next use"
            case .containers:
                return "Exited containers and their writable layers"
            }
        }

        var icon: String {
            switch self {
            case .buildCache: return "shippingbox"
            case .images:     return "square.stack.3d.up"
            case .containers: return "cube.box"
            }
        }

        /// Re-pulling images costs bandwidth, so they read as medium
        /// risk; build cache and stopped containers regenerate locally
        /// and are low risk.
        var risk: RiskLevel {
            switch self {
            case .buildCache: return .low
            case .images:     return .medium
            case .containers: return .low
            }
        }

        /// Pre-ticked on first scan. Images are off by default so we
        /// never silently force a re-pull on the user's next build.
        var defaultEnabled: Bool {
            switch self {
            case .buildCache, .containers: return true
            case .images:                  return false
            }
        }

        /// `docker` argv (no leading "docker") that reclaims this kind.
        /// `--force` skips Docker's own interactive prompt; Burrow gates
        /// with its own confirmation instead.
        var pruneArguments: [String] {
            switch self {
            case .buildCache: return ["builder",   "prune", "--all", "--force"]
            case .images:     return ["image",     "prune", "--all", "--force"]
            case .containers: return ["container", "prune", "--force"]
            }
        }
    }

    let kind: Kind
    /// Bytes `docker system df` reports as reclaimable for this kind.
    let reclaimableBytes: Int64
    /// Number of reclaimable items (total − active per df).
    let count: Int

    var id: String { kind.rawValue }
    var title: String { kind.title }
    var summary: String { kind.summary }
    var icon: String { kind.icon }
    var risk: RiskLevel { kind.risk }
}
