import AppKit               // NSWorkspace.activateFileViewerSelecting
import Foundation
import SwiftUI // ObservableObject + @Published only — no Color/Font/Image
import os

/// Drives the Clean tab. Loads the catalog from the bundle, runs scans
/// against `RuleEngine`, tracks selection state, and forwards apply
/// actions. Pure data; views map data → visuals.
@MainActor
final class CleanViewModel: ObservableObject {

    // MARK: - Logger

    private let logger = Logger(subsystem: "fun.burrow", category: "CleanViewModel")

    // MARK: - Published state

    @Published private(set) var categories: [CleanCategory] = []
    @Published private(set) var scanResults: [String: ScanResult] = [:]
    @Published var selectedCategoryIds: Set<String> = []
    @Published var dryRun: Bool = false
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var isApplying: Bool = false
    @Published private(set) var lastError: String? = nil
    @Published private(set) var previewBanner: PreviewSummary? = nil

    // node_modules section
    @Published private(set) var nodeModulesEntries: [NodeModulesEntry] = []
    @Published var nodeModulesSelection: Set<URL> = []
    @Published private(set) var isScanningNodeModules: Bool = false
    @Published var nodeModulesSort: NodeModulesSort = .parentMtime

    // MARK: - Dependencies

    private var engine: RuleEngine?
    private let log: OperationLog
    private var bannerDismissTask: Task<Void, Never>?

    // MARK: - Init

    /// Production initializer. Catalog is loaded asynchronously by
    /// `loadCatalog()` (typically from `View.task { await vm.loadCatalog() }`).
    init(log: OperationLog = .shared) {
        self.log = log
    }

    /// Test convenience: pre-built catalog, no Bundle.main lookup. Defaults
    /// the selection to every category whose `defaultEnabled == true`.
    init(catalog: CleanCatalog, log: OperationLog = .shared) {
        self.log = log
        self.categories = catalog.categories
        self.engine = RuleEngine(catalog: catalog, log: log)
        self.selectedCategoryIds = Set(catalog.categories.filter { $0.defaultEnabled }.map(\.id))
    }

    // MARK: - Catalog

    /// Loads `CleanRules.json` from `Bundle.main`, builds the engine,
    /// and pre-selects categories where `defaultEnabled == true`. Sets
    /// `lastError` (and leaves state empty) on failure.
    /// Idempotent — once a catalog is loaded, repeated calls are no-ops
    /// so re-mounting the view via tab-switch preserves selection + scan.
    func loadCatalog() async {
        guard categories.isEmpty else { return }

        guard let url = Bundle.main.url(forResource: "CleanRules", withExtension: "json") else {
            lastError = "Catalog not found in app bundle"
            logger.error("CleanRules.json not found in Bundle.main")
            return
        }

        let catalog: CleanCatalog
        do {
            catalog = try RuleEngine.loadCatalog(from: url)
        } catch {
            lastError = "Failed to load catalog: \(error.localizedDescription)"
            logger.error("Failed to decode CleanRules.json: \(error.localizedDescription, privacy: .public)")
            return
        }

        let installed = Self.filterInstalled(catalog.categories)
        let installedCatalog = CleanCatalog(
            schemaVersion: catalog.schemaVersion,
            categories: installed
        )

        self.categories = installed
        self.engine = RuleEngine(catalog: installedCatalog, log: log)
        self.selectedCategoryIds = Set(installed.filter { $0.defaultEnabled }.map(\.id))
        self.lastError = nil

        logger.info(
            "Catalog loaded: \(installed.count, privacy: .public) of \(catalog.categories.count, privacy: .public) categories present on disk"
        )
    }

    /// Drops categories whose every rule resolves to nothing on disk.
    /// Keeps categories with at least one existing path. Command-only
    /// rules are always kept (we can't probe whether the executable
    /// will succeed without running it).
    static func filterInstalled(_ categories: [CleanCategory]) -> [CleanCategory] {
        categories.filter { category in
            category.rules.contains { rule in
                switch rule {
                case let .directoryContents(path, _, _, _),
                     let .glob(path, _, _, _):
                    return !PathResolver.resolve(path).isEmpty
                case .command:
                    return true
                }
            }
        }
    }

    // MARK: - Scan

    /// Scans every loaded category and stores results in `scanResults`
    /// keyed by category id. Toggles `isScanning` for the duration.
    func scan() async {
        guard let engine else {
            lastError = "Catalog not loaded"
            logger.warning("scan() called before catalog was loaded")
            return
        }

        isScanning = true
        defer { isScanning = false }

        let results = await engine.scanAll(categories)

        var dict: [String: ScanResult] = [:]
        dict.reserveCapacity(results.count)
        for result in results {
            dict[result.categoryId] = result
        }
        self.scanResults = dict
        self.lastError = nil
        dismissPreviewBanner()  // a fresh scan invalidates any prior preview

        let totalBytes = dict.values.reduce(0) { $0 + $1.totalBytes }
        logger.info(
            "Scan complete: \(dict.count, privacy: .public) categories, \(totalBytes, privacy: .public) bytes total"
        )
    }

    // MARK: - Apply

    /// Trashes (or dry-runs) every ScanResult belonging to a selected
    /// category. Per-category errors are recorded in `lastError` and
    /// the loop continues — one bad category never aborts the batch.
    /// On a successful real (non-dry) apply, `scanResults` is cleared
    /// because the on-disk state is now stale.
    func apply() async {
        guard let engine else {
            lastError = "Catalog not loaded"
            logger.warning("apply() called before catalog was loaded")
            return
        }

        isApplying = true
        defer { isApplying = false }

        var encounteredError = false
        var totalBytes: Int64 = 0
        var totalItems = 0

        for id in selectedCategoryIds {
            guard let result = scanResults[id] else { continue }

            do {
                let bytes = try await engine.apply(result, dryRun: dryRun)
                totalBytes += bytes
                totalItems += result.items.count
                logger.info(
                    "Apply succeeded for \(id, privacy: .public) (dryRun=\(self.dryRun, privacy: .public))"
                )
            } catch {
                let message = "Apply failed for \(id): \(error.localizedDescription)"
                lastError = message
                encounteredError = true
                logger.error("\(message, privacy: .public)")
                // continue — one bad category must not abort the batch
            }
        }

        if !dryRun && !encounteredError {
            scanResults = [:]
            selectedCategoryIds = []
            dismissPreviewBanner()
            logger.info("Real apply completed cleanly; scan results and selection cleared")
        } else if dryRun && !encounteredError {
            previewBanner = PreviewSummary(items: totalItems, bytes: totalBytes)
            scheduleBannerDismiss()
        }
    }

    // MARK: - Banner

    /// User taps the × on the banner.
    func dismissPreviewBanner() {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        previewBanner = nil
    }

    /// URL of the operations log file, exposed so the view can hand it
    /// to `Environment(\.openURL)` or `NSWorkspace.open(_:)`.
    var operationsLogURL: URL {
        log.logURL
    }

    /// Auto-dismiss the banner after a short delay so it doesn't sit
    /// indefinitely. Cancellable — repeated previews reset the timer.
    private func scheduleBannerDismiss() {
        bannerDismissTask?.cancel()
        bannerDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.previewBanner = nil }
        }
    }

    // MARK: - Computed

    /// Total bytes across all scanned items belonging to selected
    /// categories. Drives the footer total.
    var selectedTotalBytes: Int64 {
        selectedCategoryIds
            .compactMap { scanResults[$0]?.totalBytes }
            .reduce(0, +)
    }

    /// Total bytes across the entire scan. Drives the header subtitle
    /// "Found N GB reclaimable".
    var totalReclaimable: Int64 {
        scanResults.values.reduce(0) { $0 + $1.totalBytes }
    }

    /// True iff either category scan or node_modules scan is in flight.
    var isScanningAny: Bool { isScanning || isScanningNodeModules }

    /// Categories + node_modules combined item count for the footer label.
    var combinedSelectedItemCount: Int {
        selectedItemCount + nodeModulesSelection.count
    }

    /// Categories + node_modules combined byte total for the footer label.
    var combinedSelectedBytes: Int64 {
        selectedTotalBytes + nodeModulesSelectedBytes
    }

    /// Combined reclaimable across both lists — drives the header subtitle.
    var combinedReclaimable: Int64 {
        totalReclaimable + nodeModulesEntries.reduce(0) { $0 + $1.totalBytes }
    }

    /// True iff there's at least one selected category OR node_modules entry.
    var hasAnySelection: Bool {
        selectedItemCount > 0 || !nodeModulesSelection.isEmpty
    }

    /// Number of selected categories — i.e. how many checkboxes the
    /// user ticked. Drives the footer's "N categories" label.
    var selectedCategoryCount: Int {
        selectedCategoryIds.count
    }

    /// Number of underlying ScanItems (filesystem paths) across all
    /// selected categories. Drives the footer's "M paths" label.
    var selectedItemCount: Int {
        selectedCategoryIds
            .compactMap { scanResults[$0]?.items.count }
            .reduce(0, +)
    }

    /// Reveal the first existing path of `category` in Finder.
    /// Walks rules in declaration order, resolves each via PathResolver,
    /// and opens whichever URL exists first. No-op if nothing resolves
    /// (which shouldn't happen post-`filterInstalled`, but harmless).
    func revealInFinder(_ category: CleanCategory) {
        for rule in category.rules {
            let path: String
            switch rule {
            case let .directoryContents(p, _, _, _),
                 let .glob(p, _, _, _):
                path = p
            case .command:
                continue
            }
            if let url = PathResolver.resolve(path).first {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }
        }
        logger.warning("revealInFinder: no resolvable path for \(category.id, privacy: .public)")
    }

    /// True iff every loaded category is selected. Drives the
    /// "Select all" header checkbox.
    var allCategoriesSelected: Bool {
        !categories.isEmpty && selectedCategoryIds.count == categories.count
    }

    /// Toggle every category on (any → all) or off (all → none).
    func toggleSelectAll() {
        if allCategoriesSelected {
            selectedCategoryIds = []
        } else {
            selectedCategoryIds = Set(categories.map(\.id))
        }
    }

    /// Categories grouped by `CategoryGroup`, sorted alphabetically by
    /// the group's raw value for stable UI ordering.
    var categoriesByGroup: [(group: CategoryGroup, categories: [CleanCategory])] {
        let grouped = Dictionary(grouping: categories, by: \.group)
        return grouped
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { (group: $0.key, categories: $0.value) }
    }

    // MARK: - node_modules

    /// Sort key for the node_modules list.
    enum NodeModulesSort: String, CaseIterable, Identifiable {
        case parentMtime  // last project edit (excluding node_modules)
        case nodeModulesMtime  // last `npm install` / build
        case size  // descending size

        var id: String { rawValue }
        var label: String {
            switch self {
            case .parentMtime:      return "Project last edited"
            case .nodeModulesMtime: return "node_modules last touched"
            case .size:             return "Size"
            }
        }
    }

    /// Entries sorted per `nodeModulesSort`. View binds to this so the list
    /// re-orders without re-scanning.
    var sortedNodeModules: [NodeModulesEntry] {
        switch nodeModulesSort {
        case .parentMtime:
            return nodeModulesEntries.sorted { $0.parentMtime < $1.parentMtime }
        case .nodeModulesMtime:
            return nodeModulesEntries.sorted { $0.nodeModulesMtime < $1.nodeModulesMtime }
        case .size:
            return nodeModulesEntries.sorted { $0.totalBytes > $1.totalBytes }
        }
    }

    /// Total bytes of currently-selected entries — drives the footer label.
    var nodeModulesSelectedBytes: Int64 {
        nodeModulesEntries
            .filter { nodeModulesSelection.contains($0.url) }
            .reduce(0) { $0 + $1.totalBytes }
    }

    /// Run both scans concurrently — categories + node_modules. Used by
    /// the unified Scan button so the user gets one progress affordance.
    func scanAll() async {
        async let a: () = scan()
        async let b: () = scanNodeModules()
        _ = await (a, b)
    }

    /// Apply both selections — categories + node_modules. Computes the
    /// combined preview banner totals up-front so we can override the
    /// per-method banners with one summary at the end.
    func applyAll() async {
        let hasCategories = selectedItemCount > 0
        let hasNodeModules = !nodeModulesSelection.isEmpty
        guard hasCategories || hasNodeModules else { return }

        let totalItems = combinedSelectedItemCount
        let totalBytes = combinedSelectedBytes

        if hasCategories { await apply() }
        if hasNodeModules { await trashSelectedNodeModules() }

        previewBanner = PreviewSummary(items: totalItems, bytes: totalBytes)
        if dryRun { scheduleBannerDismiss() }
    }

    /// Walk `~/` looking for node_modules directories. Long-running on
    /// large home dirs; toggles `isScanningNodeModules` for the duration.
    func scanNodeModules() async {
        isScanningNodeModules = true
        defer { isScanningNodeModules = false }

        let scanner = NodeModulesScanner()
        let entries = await scanner.scanHomeDirectory()
        nodeModulesEntries = entries
        // Drop any prior selections that no longer exist on disk.
        nodeModulesSelection.formIntersection(Set(entries.map(\.url)))

        logger.info("node_modules scan: \(entries.count, privacy: .public) dirs")
    }

    /// Trash every selected node_modules dir. Honors `dryRun`. Removes
    /// successfully-trashed entries from the list.
    func trashSelectedNodeModules() async {
        guard !nodeModulesSelection.isEmpty else { return }

        let targets = nodeModulesEntries.filter { nodeModulesSelection.contains($0.url) }
        var removed: Set<URL> = []
        var bytesReclaimed: Int64 = 0

        for entry in targets {
            do {
                let bytes = try await SafeFileOps.trash(entry.url, dryRun: dryRun)
                bytesReclaimed += bytes
                removed.insert(entry.url)
                try? await log.append(OperationLogEntry(
                    timestamp: Date(),
                    action: .trash,
                    target: entry.url.path,
                    bytes: bytes,
                    dryRun: dryRun
                ))
            } catch {
                logger.error(
                    "trash failed for \(entry.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        if !dryRun {
            nodeModulesEntries.removeAll { removed.contains($0.url) }
            nodeModulesSelection.subtract(removed)
        }
        previewBanner = PreviewSummary(items: removed.count, bytes: bytesReclaimed)
    }
}
