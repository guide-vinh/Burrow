import AppKit               // NSWorkspace.activateFileViewerSelecting
import Foundation
import SwiftUI               // ObservableObject + @Published only — no Color/Font/Image
import os

private let logger = Logger(subsystem: "fun.burrow", category: "AnalyzeViewModel")

/// Drives the Analyze tab. Sizes the home folder with the system `du` tool,
/// one top-level folder at a time in parallel, and streams results in live:
/// a whole-volume storage breakdown (donut + legend) and a list of the
/// largest folders. Folders drill down on demand. All deletions route
/// through `SafeFileOps`. Pure data; views map data → visuals.
@MainActor
final class AnalyzeViewModel: ObservableObject {

    // MARK: - Sort

    enum FolderSort: String, CaseIterable, Identifiable {
        case bySize
        case byName

        var id: String { rawValue }
        var label: String {
            switch self {
            case .bySize: return "By size"
            case .byName: return "By name"
            }
        }
    }

    // MARK: - Scan state

    @Published private(set) var isScanning: Bool = false
    @Published private(set) var scanError: String?
    @Published private(set) var foldersScanned: Int = 0
    @Published private(set) var totalTopLevel: Int = 0

    // MARK: - Results

    @Published private(set) var storage: StorageBreakdown?
    @Published private(set) var largestFolders: [DiskEntry] = []
    @Published var sortOrder: FolderSort = .bySize

    /// Largest subfolders per folder URL (top-level pre-filled during the scan,
    /// deeper levels loaded lazily on expand).
    @Published private(set) var childrenCache: [URL: [DiskEntry]] = [:]
    @Published private(set) var loadingChildren: Set<URL> = []

    /// True once a breakdown exists — the view's "scanned" state.
    var hasResults: Bool { storage != nil }

    var displayedFolders: [DiskEntry] {
        switch sortOrder {
        case .bySize:
            return largestFolders
        case .byName:
            return largestFolders.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    var maxFolderSize: Int64 { largestFolders.map(\.size).max() ?? 1 }

    // MARK: - Tuning

    private let maxLargestFolders = 8
    private let maxChildren = 8

    // MARK: - Dependencies

    private let capacity: @Sendable (URL) -> (total: Int64, free: Int64, name: String)?
    private let topLevel: @Sendable (URL) -> (dirs: [URL], looseBytes: Int64)
    private let scanFolder: @Sendable (URL) async -> DiskUsageScanner.FolderScan
    private let applicationsSize: @Sendable () async -> Int64
    private let homeDirectory: URL

    private var scanTask: Task<Void, Never>?

    // MARK: - Init

    /// Closure-injected for tests. Production callers use the defaults.
    init(
        capacity: @escaping @Sendable (URL) -> (total: Int64, free: Int64, name: String)?
            = { VolumeInfo.capacity(of: $0) },
        topLevel: @escaping @Sendable (URL) -> (dirs: [URL], looseBytes: Int64)
            = { DiskUsageScanner.topLevel(of: $0) },
        scanFolder: @escaping @Sendable (URL) async -> DiskUsageScanner.FolderScan
            = { await DiskUsageScanner.scan($0) },
        applicationsSize: @escaping @Sendable () async -> Int64
            = {
                let fm = FileManager.default
                var total = await DiskUsageScanner.scan(URL(fileURLWithPath: "/Applications")).total
                let userApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
                if fm.fileExists(atPath: userApps.path) {
                    total += await DiskUsageScanner.scan(userApps).total
                }
                return total
            },
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.capacity = capacity
        self.topLevel = topLevel
        self.scanFolder = scanFolder
        self.applicationsSize = applicationsSize
        self.homeDirectory = homeDirectory
    }

    // MARK: - Scan

    /// Size every top-level folder in parallel with `du`, streaming the donut
    /// and largest-folders list as each finishes.
    func scan() async {
        cancelScan()

        isScanning = true
        scanError = nil
        largestFolders = []
        childrenCache = [:]
        loadingChildren = []
        foldersScanned = 0

        let home = homeDirectory
        let scanFolder = self.scanFolder
        let applicationsSize = self.applicationsSize

        scanTask = Task { [weak self] in
            guard let self else { return }

            let cap = self.capacity(home)
            let (dirs, looseBytes) = self.topLevel(home)
            self.totalTopLevel = dirs.count

            // Show the dashboard immediately (capacity known; folders fill in).
            self.update(cap: cap, totals: [:], looseBytes: looseBytes, appsBytes: 0)

            // /Applications sizing runs alongside the folder fan-out.
            async let appsBytesTask = applicationsSize()

            var totals: [URL: Int64] = [:]
            let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)

            await withTaskGroup(of: (URL, DiskUsageScanner.FolderScan).self) { group in
                var queue = dirs
                for _ in 0..<min(maxConcurrent, queue.count) {
                    let dir = queue.removeLast()
                    group.addTask { (dir, await scanFolder(dir)) }
                }

                while let (dir, result) = await group.next() {
                    if Task.isCancelled { group.cancelAll(); break }

                    totals[dir] = result.total
                    self.childrenCache[dir] = self.prepare(result.children)
                    self.foldersScanned += 1
                    self.largestFolders = self.topFolders(from: totals)
                    self.update(cap: cap, totals: totals, looseBytes: looseBytes, appsBytes: 0)

                    if let next = queue.popLast() {
                        group.addTask { (next, await scanFolder(next)) }
                    }
                }
            }

            let appsBytes = await appsBytesTask
            if !Task.isCancelled {
                self.update(cap: cap, totals: totals, looseBytes: looseBytes, appsBytes: appsBytes)
                self.isScanning = false
                logger.info("Scan finished: \(self.foldersScanned, privacy: .public) top-level folders")
            }
        }

        await scanTask?.value
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: - Drill-down

    func children(of entry: DiskEntry) -> [DiskEntry] {
        childrenCache[entry.url] ?? []
    }

    func isLoadingChildren(_ entry: DiskEntry) -> Bool {
        loadingChildren.contains(entry.url)
    }

    /// Lazily `du` `entry`'s subfolders. No-op if already loaded or in flight.
    /// Top-level folders are pre-loaded during the scan, so this only runs for
    /// deeper levels.
    func loadChildrenIfNeeded(_ entry: DiskEntry) async {
        guard childrenCache[entry.url] == nil, !loadingChildren.contains(entry.url) else { return }
        loadingChildren.insert(entry.url)
        defer { loadingChildren.remove(entry.url) }
        let result = await scanFolder(entry.url)
        childrenCache[entry.url] = prepare(result.children)
    }

    // MARK: - Actions

    func revealInFinder(_ entry: DiskEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    func openInFinder(_ entry: DiskEntry) {
        NSWorkspace.shared.open(entry.url)
    }

    func moveToTrash(_ entry: DiskEntry) async {
        await remove(entry, permanently: false)
    }

    /// Permanent deletion, bypassing the Trash. Callers must confirm
    /// with the user first — this cannot be undone.
    func deletePermanently(_ entry: DiskEntry) async {
        await remove(entry, permanently: true)
    }

    private func remove(_ entry: DiskEntry, permanently: Bool) async {
        do {
            let bytes = permanently
                ? try await SafeFileOps.permanentlyDelete(entry.url, dryRun: false)
                : try await SafeFileOps.trash(entry.url, dryRun: false)
            try? await OperationLog.shared.append(OperationLogEntry(
                timestamp: Date(),
                action: permanently ? .permanentDelete : .trash,
                target: entry.url.path,
                bytes: bytes,
                dryRun: false
            ))
            largestFolders.removeAll { $0.url == entry.url }
            childrenCache[entry.url] = nil
            logger.info(
                "\(permanently ? "Deleted" : "Trashed", privacy: .public) \(bytes, privacy: .public) bytes at \(entry.url.path, privacy: .private)"
            )
        } catch {
            scanError = permanently
                ? "Couldn't delete: \(error.localizedDescription)"
                : "Couldn't move to Trash: \(error.localizedDescription)"
            logger.error(
                "\(permanently ? "Delete" : "Trash", privacy: .public) failed: \(error.localizedDescription, privacy: .public) for \(entry.url.path, privacy: .private)"
            )
        }
    }

    // MARK: - Helpers

    /// Recompute the storage breakdown from the totals gathered so far.
    private func update(
        cap: (total: Int64, free: Int64, name: String)?,
        totals: [URL: Int64],
        looseBytes: Int64,
        appsBytes: Int64
    ) {
        let homeTotal = looseBytes + totals.values.reduce(0, +)
        storage = Self.makeBreakdown(
            totalBytes: cap?.total ?? 0,
            freeBytes: cap?.free ?? 0,
            volumeName: cap?.name ?? "Macintosh HD",
            homeTotalBytes: homeTotal,
            applicationsBytes: appsBytes,
            documentsBytes: totals[homeDirectory.appendingPathComponent("Documents").standardizedFileURL] ?? 0,
            photosBytes: totals[homeDirectory.appendingPathComponent("Pictures").standardizedFileURL] ?? 0
        )
    }

    /// Top-level folders sorted largest first, capped for display.
    private func topFolders(from totals: [URL: Int64]) -> [DiskEntry] {
        totals
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(maxLargestFolders)
            .map { url, size in
                DiskEntry(
                    id: UUID(), url: url, parentURL: homeDirectory,
                    name: url.lastPathComponent, size: size, isDirectory: true,
                    modifiedAt: Date(), lastAccessedAt: nil, childCount: 0
                )
            }
    }

    /// Directory children only, largest first, capped.
    private func prepare(_ children: [DiskEntry]) -> [DiskEntry] {
        children
            .filter { $0.isDirectory && $0.size > 0 }
            .sorted { $0.size > $1.size }
            .prefix(maxChildren)
            .map { $0 }
    }

    /// Build the six-category breakdown. "System" is the remainder of used
    /// space outside `/Applications` and the home folder. Every derived value
    /// is clamped to ≥ 0:  apps + system + documents + photos + other + free.
    static func makeBreakdown(
        totalBytes: Int64,
        freeBytes: Int64,
        volumeName: String = "Macintosh HD",
        homeTotalBytes: Int64,
        applicationsBytes: Int64,
        documentsBytes: Int64,
        photosBytes: Int64
    ) -> StorageBreakdown {
        let total = max(0, totalBytes)
        let free = min(max(0, freeBytes), total)
        let used = max(0, total - free)

        let apps = max(0, applicationsBytes)
        let homeTotal = max(0, homeTotalBytes)
        let documents = max(0, documentsBytes)
        let photos = max(0, photosBytes)
        let otherHome = max(0, homeTotal - documents - photos)
        let system = max(0, used - apps - homeTotal)

        let categories: [StorageCategory] = [
            StorageCategory(kind: .applications, bytes: apps),
            StorageCategory(kind: .system, bytes: system),
            StorageCategory(kind: .documents, bytes: documents),
            StorageCategory(kind: .photos, bytes: photos),
            StorageCategory(kind: .other, bytes: otherHome),
            StorageCategory(kind: .free, bytes: free),
        ]
        return StorageBreakdown(
            totalBytes: total,
            usedBytes: used,
            freeBytes: free,
            volumeName: volumeName,
            categories: categories
        )
    }
}
