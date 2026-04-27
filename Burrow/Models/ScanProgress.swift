import Foundation

/// Streamed during scan. UI subscribes to AsyncStream<ScanProgress>.
struct ScanProgress: Sendable, Equatable {
    let phase: Phase
    let entriesScanned: Int
    let totalBytes: Int64
    let currentPath: URL?
    let elapsed: TimeInterval

    enum Phase: String, Sendable, Equatable {
        case starting
        case enumerating
        case computingSizes
        case finished
        case cancelled
    }
}
