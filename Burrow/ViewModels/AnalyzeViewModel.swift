import AppKit               // NSWorkspace.activateFileViewerSelecting
import Foundation
import SwiftUI               // ObservableObject + @Published only — no Color/Font/Image
import os

private let logger = Logger(subsystem: "fun.burrow", category: "AnalyzeViewModel")

/// Drives the Analyze tab. Runs a recursive disk scan, exposes a
/// navigable treemap view, surfaces insights (largest + oldest), and
/// routes all deletions through `SafeFileOps`. Pure data; views map
/// data → visuals.
@MainActor
final class AnalyzeViewModel: ObservableObject {

    // MARK: - Scan state

    @Published private(set) var isScanning: Bool = false
    @Published private(set) var scanProgress: ScanProgress?
    @Published private(set) var scanError: String?

    // MARK: - Current view state

    @Published private(set) var currentRoot: URL?
    @Published private(set) var breadcrumb: [URL] = []
    @Published private(set) var visibleEntries: [DiskEntry] = []

    // MARK: - Insights

    @Published private(set) var topLargest: [DiskEntry] = []
    @Published private(set) var oldestNeverOpened: [DiskEntry] = []
    @Published private(set) var atimeAvailable: Bool = true

    // MARK: - Dependencies

    private let startScan: (URL) -> AsyncThrowingStream<ScanProgress, Error>
    private let loadChildren: (URL) async throws -> [DiskEntry]
    private let homeDirectory: URL

    // MARK: - Private state

    private var scanTask: Task<Void, Never>?

    // MARK: - Init

    /// Closure-injected for tests (mirrors UninstallViewModel pattern).
    /// Production callers use the defaults.
    init(
        startScan: @escaping (URL) -> AsyncThrowingStream<ScanProgress, Error>
            = { url in
                // Bridge the actor-isolated DiskScanner.scan into a plain
                // synchronous-returning AsyncThrowingStream by forwarding
                // each yielded value through a wrapper stream.
                AsyncThrowingStream { continuation in
                    Task {
                        do {
                            for try await progress in DiskScanner.shared.scan(url) {
                                continuation.yield(progress)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            },
        loadChildren: @escaping (URL) async throws -> [DiskEntry]
            = { url in try await DiskScanner.shared.childrenOf(url) },
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.startScan = startScan
        self.loadChildren = loadChildren
        self.homeDirectory = homeDirectory
    }

    // MARK: - Actions

    /// Start a full recursive scan from `homeDirectory`.
    func scan() async {
        cancelScan()

        isScanning = true
        scanError = nil

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = self.startScan(self.homeDirectory)
                for try await progress in stream {
                    guard !Task.isCancelled else { break }
                    self.scanProgress = progress

                    if progress.phase == .finished {
                        await self.loadAndDisplay(
                            url: self.homeDirectory,
                            appendBreadcrumb: false
                        )
                        self.isScanning = false
                        logger.info(
                            "Scan finished: \(progress.entriesScanned, privacy: .public) entries, \(progress.totalBytes, privacy: .public) bytes"
                        )
                        return
                    }

                    if progress.phase == .cancelled {
                        self.isScanning = false
                        logger.info("Scan cancelled")
                        return
                    }
                }
                // Stream exhausted without .finished / .cancelled — treat as done
                self.isScanning = false
            } catch is CancellationError {
                self.isScanning = false
                logger.info("Scan task cancelled via CancellationError")
            } catch {
                self.scanError = error.localizedDescription
                self.isScanning = false
                logger.error("Scan error: \(error.localizedDescription, privacy: .public)")
            }
        }

        await scanTask?.value
    }

    /// Cancel an in-flight scan. Safe to call even when not scanning.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
    }

    /// Navigate into a directory entry (zoom in one level).
    func zoomInto(_ entry: DiskEntry) async {
        guard entry.isDirectory else {
            logger.debug("zoomInto called on non-directory \(entry.url.path, privacy: .private) — no-op")
            return
        }
        await loadAndDisplay(url: entry.url, appendBreadcrumb: true)
    }

    /// Navigate up one breadcrumb level.
    func zoomOut() async {
        guard breadcrumb.count > 1 else { return }
        let parent = breadcrumb[breadcrumb.count - 2]
        // Drop last from breadcrumb before navigating so loadAndDisplay
        // doesn't double-append.
        breadcrumb.removeLast()
        await loadAndDisplay(url: parent, appendBreadcrumb: false)
    }

    /// Jump to a specific breadcrumb segment, dropping everything after it.
    func navigate(to url: URL) async {
        guard let idx = breadcrumb.firstIndex(of: url) else { return }
        breadcrumb = Array(breadcrumb.prefix(idx + 1))
        await loadAndDisplay(url: url, appendBreadcrumb: false)
    }

    /// Open Finder with the entry selected.
    func revealInFinder(_ entry: DiskEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    /// Move a single entry to Trash through the SafeFileOps gate.
    func moveToTrash(_ entry: DiskEntry) async {
        do {
            let bytes = try await SafeFileOps.trash(entry.url, dryRun: false)
            try? await OperationLog.shared.append(OperationLogEntry(
                timestamp: Date(),
                action: .trash,
                target: entry.url.path,
                bytes: bytes,
                dryRun: false
            ))
            visibleEntries.removeAll { $0.url == entry.url }
            recomputeInsights()
            logger.info(
                "Trashed \(bytes, privacy: .public) bytes at \(entry.url.path, privacy: .private)"
            )
        } catch {
            scanError = "Couldn't move to Trash: \(error.localizedDescription)"
            logger.error(
                "Trash failed: \(error.localizedDescription, privacy: .public) for \(entry.url.path, privacy: .private)"
            )
        }
    }

    // MARK: - Private helpers

    /// Load children of `url`, update state. If `appendBreadcrumb` is true,
    /// push `url` onto `breadcrumb`; otherwise trust the caller already
    /// adjusted `breadcrumb` (used by zoomOut / navigate).
    private func loadAndDisplay(url: URL, appendBreadcrumb: Bool) async {
        do {
            let children = try await loadChildren(url)
            currentRoot = url
            if appendBreadcrumb {
                breadcrumb.append(url)
            } else if breadcrumb.last != url {
                // After zoomOut / navigate sets breadcrumb, just sync currentRoot.
                // If breadcrumb is completely empty (first scan), seed it.
                if breadcrumb.isEmpty {
                    breadcrumb = [url]
                }
            }
            visibleEntries = truncateForDisplay(children)
            recomputeInsights()
            logger.info(
                "Loaded \(children.count, privacy: .public) children for \(url.path, privacy: .private)"
            )
        } catch {
            scanError = "Couldn't load directory: \(error.localizedDescription)"
            logger.error(
                "loadChildren failed for \(url.path, privacy: .private): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Top-100 truncation per DECISIONS §4.
    private func truncateForDisplay(_ entries: [DiskEntry]) -> [DiskEntry] {
        let sorted = entries.sorted { $0.size > $1.size }
        if sorted.count <= 100 { return sorted }
        // Return top 100 as-is. Synthetic "Other" entry deferred to Phase 3a.1.
        return Array(sorted.prefix(100))
    }

    /// Refresh `topLargest` and `oldestNeverOpened` from `visibleEntries`.
    private func recomputeInsights() {
        topLargest = Array(visibleEntries.sorted { $0.size > $1.size }.prefix(5))
        computeAtimeInsights(visibleEntries)
    }

    /// Populate `oldestNeverOpened` with graceful degradation when atime is
    /// unavailable (DECISIONS §6).
    private func computeAtimeInsights(_ entries: [DiskEntry]) {
        let withAtime = entries.compactMap { e -> (DiskEntry, Date)? in
            guard let a = e.lastAccessedAt else { return nil }
            return (e, a)
        }

        // If for ALL entries lastAccessedAt is nil OR equal-to-modifiedAt
        // (within 1 second), conclude atime is disabled.
        let atimeMatchesMtime = entries.allSatisfy { e in
            guard let a = e.lastAccessedAt else { return true }
            return abs(a.timeIntervalSince(e.modifiedAt)) <= 1.0
        }

        if entries.isEmpty == false && atimeMatchesMtime {
            atimeAvailable = false
            oldestNeverOpened = []
            return
        }

        atimeAvailable = true
        oldestNeverOpened = Array(
            withAtime.sorted { $0.1 < $1.1 }.prefix(5).map(\.0)
        )
    }
}
