import Foundation

/// One row in the disk cache. Mirrors `disk_cache` table in
/// PHASE3B_DECISIONS.md §3. Sendable so it crosses actor boundaries.
struct CachedEntry: Sendable, Equatable {
    let path: String              // standardized URL path; PRIMARY KEY
    let parentPath: String?       // nil for cache root entries
    let inode: UInt64
    let mtime: Date
    let size: Int64               // recursive bytes
    let childCount: Int
    let isDirectory: Bool
    let lastScanned: Date
}
