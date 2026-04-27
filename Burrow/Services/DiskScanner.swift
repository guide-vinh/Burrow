import Foundation
import os

// MARK: - DiskScanner

/// Scans the file system recursively, streaming progress via
/// AsyncThrowingStream. Results are cached in-memory for treemap
/// navigation. Read-only — no file mutations happen here.
actor DiskScanner {

    // MARK: - Singleton

    /// Production singleton.
    static let shared = DiskScanner()

    // MARK: - Init

    init() { }

    // MARK: - Private state

    /// Keyed by `url.standardizedFileURL` for consistent URL equality.
    private var cachedEntries: [URL: DiskEntry] = [:]
    private var lastRoot: URL?

    // MARK: - Logger

    private let logger = Logger(subsystem: "fun.burrow", category: "DiskScanner")

    // MARK: - Resource keys

    private static let resourceKeys: [URLResourceKey] = [
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .contentModificationDateKey,
        .contentAccessDateKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
    ]

    // MARK: - Public API

    /// Scan a directory recursively, streaming progress.
    /// Caller cancels by cancelling the parent Task.
    /// On successful completion, results are cached internally.
    func scan(_ root: URL, includeHidden: Bool = false) -> AsyncThrowingStream<ScanProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.runScan(
                    root: root.standardizedFileURL,
                    includeHidden: includeHidden,
                    continuation: continuation
                )
            }
        }
    }

    /// Resolve a single directory's IMMEDIATE children with sizes.
    /// Used for treemap zoom-in; does NOT update the cache.
    /// Each child's `size` is the total recursive size of that subtree.
    func childrenOf(_ url: URL) async throws -> [DiskEntry] {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsHiddenFiles]
        )
        let homeDir = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        var result: [DiskEntry] = []
        for childURL in urls {
            let stdChild = childURL.standardizedFileURL
            if Self.isExcludedPath(stdChild.path, home: homeDir) {
                continue
            }
            let values = try stdChild.resourceValues(forKeys: Set(Self.resourceKeys))
            if values.isSymbolicLink == true { continue }
            let isPackage = values.isPackage == true
            let isDir = (values.isDirectory == true) && !isPackage
            let size: Int64 = (isDir || isPackage)
                ? SafeFileOps.size(stdChild)
                : Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            result.append(DiskEntry(
                id: UUID(),
                url: stdChild,
                parentURL: url.standardizedFileURL,
                name: stdChild.lastPathComponent,
                size: size,
                isDirectory: isDir,
                modifiedAt: values.contentModificationDate ?? Date(),
                lastAccessedAt: values.contentAccessDate,
                childCount: 0
            ))
        }
        return result
    }

    /// URL of the root passed to the most recent successful `scan`.
    /// Nil if never scanned, or if the last scan was cancelled / failed.
    func lastScanRoot() -> URL? {
        lastRoot
    }

    /// Cached entries whose `parentURL == under` from the most recent scan.
    /// Empty array if no scan has completed or no children exist.
    func entries(under: URL) -> [DiskEntry] {
        let std = under.standardizedFileURL
        return cachedEntries.values.filter { $0.parentURL == std }
    }

    // MARK: - Private helpers

    /// Core scan loop. Runs inside a Task spawned by `scan(_:)`.
    /// All URLs here are already standardized before entry.
    private func runScan(
        root: URL,
        includeHidden: Bool,
        continuation: AsyncThrowingStream<ScanProgress, Error>.Continuation
    ) async {
        let scanStart = Date()
        var entriesScanned = 0
        var totalBytes: Int64 = 0
        var lastYield = Date()
        /// Keyed by standardized URL.
        var localEntries: [URL: DiskEntry] = [:]

        // 1. Starting phase
        continuation.yield(ScanProgress(
            phase: .starting,
            entriesScanned: 0,
            totalBytes: 0,
            currentPath: root,
            elapsed: 0
        ))

        logger.info("Scan started for \(root.path, privacy: .private)")

        // Insert the root entry itself
        let rootMod = (try? root.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let rootAcc = (try? root.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
        let rootEntry = DiskEntry(
            id: UUID(),
            url: root,
            parentURL: nil,
            name: root.lastPathComponent,
            size: 0,
            isDirectory: true,
            modifiedAt: rootMod,
            lastAccessedAt: rootAcc,
            childCount: 0
        )
        localEntries[root] = rootEntry

        do {
            let fm = FileManager.default
            let homeDir = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
            var enumeratorOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
            if !includeHidden {
                enumeratorOptions.insert(.skipsHiddenFiles)
            }

            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: Self.resourceKeys,
                options: enumeratorOptions
            ) else {
                continuation.yield(ScanProgress(
                    phase: .finished,
                    entriesScanned: 0,
                    totalBytes: 0,
                    currentPath: nil,
                    elapsed: Date().timeIntervalSince(scanStart)
                ))
                continuation.finish()
                return
            }

            // 2. Enumerating phase
            for case let rawURL as URL in enumerator {
                // Cancellation check at top of every iteration
                if Task.isCancelled {
                    continuation.yield(ScanProgress(
                        phase: .cancelled,
                        entriesScanned: entriesScanned,
                        totalBytes: totalBytes,
                        currentPath: nil,
                        elapsed: Date().timeIntervalSince(scanStart)
                    ))
                    continuation.finish()
                    return
                }

                // Standardize the URL so it matches keys/parentURLs stored in dict
                let url = rawURL.standardizedFileURL

                // Skip excluded paths
                if Self.isExcludedPath(url.path, home: homeDir) {
                    enumerator.skipDescendants()
                    continue
                }

                // Fetch resource values using the raw (non-standardized) URL
                // since standardizedFileURL can sometimes strip info needed for
                // resource value resolution. Fall back gracefully on error.
                let values: URLResourceValues
                do {
                    values = try rawURL.resourceValues(forKeys: Set(Self.resourceKeys))
                } catch {
                    logger.warning("Could not read resource values for \(url.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
                    continue
                }

                // Skip symlinks entirely
                if values.isSymbolicLink == true {
                    logger.warning("Skipped symlink at \(url.path, privacy: .private)")
                    enumerator.skipDescendants()
                    continue
                }

                let isPackage = values.isPackage == true
                let isDirectory = (values.isDirectory == true) && !isPackage

                // For packages, record as opaque and skip descendants
                if isPackage {
                    enumerator.skipDescendants()
                }

                // File size
                let ownSize: Int64 = isDirectory
                    ? 0
                    : Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)

                // parentURL: standardized form of the containing directory
                let parentURL: URL? = (url == root) ? nil : url.deletingLastPathComponent()

                let entry = DiskEntry(
                    id: UUID(),
                    url: url,
                    parentURL: parentURL,
                    name: url.lastPathComponent,
                    size: ownSize,
                    isDirectory: isDirectory,
                    modifiedAt: values.contentModificationDate ?? Date(),
                    lastAccessedAt: values.contentAccessDate,
                    childCount: 0
                )

                localEntries[url] = entry

                // Increment childCount on immediate parent
                if let pURL = parentURL, var parent = localEntries[pURL] {
                    parent = DiskEntry(
                        id: parent.id,
                        url: parent.url,
                        parentURL: parent.parentURL,
                        name: parent.name,
                        size: parent.size,
                        isDirectory: parent.isDirectory,
                        modifiedAt: parent.modifiedAt,
                        lastAccessedAt: parent.lastAccessedAt,
                        childCount: parent.childCount + 1
                    )
                    localEntries[pURL] = parent
                }

                // Bubble size up the parent chain
                if !isDirectory && ownSize > 0 {
                    var current: URL? = parentURL
                    while let cur = current {
                        if var parent = localEntries[cur] {
                            parent = DiskEntry(
                                id: parent.id,
                                url: parent.url,
                                parentURL: parent.parentURL,
                                name: parent.name,
                                size: parent.size + ownSize,
                                isDirectory: parent.isDirectory,
                                modifiedAt: parent.modifiedAt,
                                lastAccessedAt: parent.lastAccessedAt,
                                childCount: parent.childCount
                            )
                            localEntries[cur] = parent
                        }
                        if cur == root { break }
                        let parent = cur.deletingLastPathComponent()
                        if parent.path == "/" || parent.path.isEmpty { break }
                        current = parent
                    }
                }

                entriesScanned += 1
                totalBytes += ownSize

                // Yield progress per §7: every 1000 entries OR 0.5s
                if entriesScanned % 1000 == 0
                    || Date().timeIntervalSince(lastYield) >= 0.5 {
                    // Check cancellation before yielding
                    if Task.isCancelled {
                        continuation.yield(ScanProgress(
                            phase: .cancelled,
                            entriesScanned: entriesScanned,
                            totalBytes: totalBytes,
                            currentPath: nil,
                            elapsed: Date().timeIntervalSince(scanStart)
                        ))
                        continuation.finish()
                        return
                    }
                    continuation.yield(ScanProgress(
                        phase: .enumerating,
                        entriesScanned: entriesScanned,
                        totalBytes: totalBytes,
                        currentPath: url,
                        elapsed: Date().timeIntervalSince(scanStart)
                    ))
                    lastYield = Date()
                }
            }

            // 3. Finished phase — update cache only on success
            self.cachedEntries = localEntries
            self.lastRoot = root

            logger.info("Scan finished: \(entriesScanned, privacy: .public) entries, \(totalBytes, privacy: .public) bytes")

            continuation.yield(ScanProgress(
                phase: .finished,
                entriesScanned: entriesScanned,
                totalBytes: totalBytes,
                currentPath: nil,
                elapsed: Date().timeIntervalSince(scanStart)
            ))
            continuation.finish()

        } catch {
            // Top-level catch: yield error phase, finish with error
            logger.error("Scan failed: \(error.localizedDescription, privacy: .public)")
            continuation.yield(ScanProgress(
                phase: .cancelled,
                entriesScanned: entriesScanned,
                totalBytes: totalBytes,
                currentPath: nil,
                elapsed: Date().timeIntervalSince(scanStart)
            ))
            continuation.finish(throwing: error)
        }
    }

    // MARK: - Path exclusion

    /// Returns true if `path` should be skipped entirely.
    /// `home` is the current user's home directory path (injectable for tests).
    static func isExcludedPath(_ path: String, home: String) -> Bool {
        let excludedPrefixes: [String] = [
            home + "/Library/CloudStorage",
            home + "/Library/Mobile Documents",
            home + "/.Trash",
            "/System",
            "/private",
            "/Volumes",
        ]
        for prefix in excludedPrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") {
                return true
            }
        }
        return false
    }
}
