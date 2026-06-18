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

    // Flutter section
    @Published private(set) var flutterProjects: [FlutterProjectEntry] = []
    @Published var flutterSelection: Set<URL> = []  // keyed by projectURL
    @Published private(set) var isScanningFlutterProjects: Bool = false
    @Published var flutterSort: FlutterSort = .pubspecMtime

    // Docker section (IRREVERSIBLE — runs `docker … prune`, never trash)
    @Published private(set) var dockerCacheEntries: [DockerCacheEntry] = []
    @Published var dockerSelection: Set<DockerCacheEntry.Kind> = []
    @Published private(set) var isScanningDockerCache: Bool = false
    @Published private(set) var isPruningDocker: Bool = false

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
    /// On a successful real (non-dry) apply, removes ONLY the
    /// categories that were actually applied from `scanResults` and
    /// `selectedCategoryIds`. (Previously this wiped the entire
    /// scan dict, which made the header "Found N reclaimable" total
    /// jump to zero after a partial cleanup — users had to re-scan
    /// just to see what was still on disk.)
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
        var appliedIds: Set<String> = []

        for id in selectedCategoryIds {
            guard let result = scanResults[id] else { continue }

            do {
                let bytes = try await engine.apply(result, dryRun: dryRun)
                totalBytes += bytes
                totalItems += result.items.count
                appliedIds.insert(id)
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
            // Drop only the categories we actually emptied; leave the
            // rest of the scan visible so the header still shows the
            // remaining reclaimable total.
            for id in appliedIds {
                scanResults.removeValue(forKey: id)
            }
            selectedCategoryIds.subtract(appliedIds)
            dismissPreviewBanner()
            logger.info("Real apply completed cleanly; \(appliedIds.count, privacy: .public) categories cleared")
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

    /// True iff any scan (categories + node_modules + Flutter + Docker)
    /// is in flight. Drives the unified header Scan button's spinner.
    var isScanningAny: Bool {
        isScanning
            || isScanningNodeModules
            || isScanningFlutterProjects
            || isScanningDockerCache
    }

    /// Combined item count for the footer label — categories + project caches.
    var combinedSelectedItemCount: Int {
        selectedItemCount + nodeModulesSelection.count + flutterSelection.count
    }

    /// Combined byte total for the footer label.
    var combinedSelectedBytes: Int64 {
        selectedTotalBytes + nodeModulesSelectedBytes + flutterSelectedBytes
    }

    /// Combined reclaimable across all lists — drives the header
    /// subtitle. Includes Docker's reclaimable purely as an informational
    /// total; Docker is NOT part of the trash footer (see
    /// `pruneSelectedDocker`).
    var combinedReclaimable: Int64 {
        totalReclaimable
            + nodeModulesEntries.reduce(0) { $0 + $1.totalBytes }
            + flutterProjects.reduce(0) { $0 + $1.totalBytes }
            + dockerCacheEntries.reduce(0) { $0 + $1.reclaimableBytes }
    }

    /// True iff there's at least one selection across categories, node_modules,
    /// or Flutter projects.
    var hasAnySelection: Bool {
        selectedItemCount > 0
            || !nodeModulesSelection.isEmpty
            || !flutterSelection.isEmpty
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

    /// True iff every non-empty list (categories + node_modules + Flutter)
    /// is fully selected. Drives the global "Select all" header checkbox.
    var allItemsSelected: Bool {
        var hasAny = false
        if !categories.isEmpty {
            hasAny = true
            if selectedCategoryIds.count != categories.count { return false }
        }
        if !nodeModulesEntries.isEmpty {
            hasAny = true
            if nodeModulesSelection.count != nodeModulesEntries.count { return false }
        }
        if !flutterProjects.isEmpty {
            hasAny = true
            if flutterSelection.count != flutterProjects.count { return false }
        }
        return hasAny
    }

    /// Toggle every item across all three lists on (any → all) or off
    /// (all → none). Empty lists are no-ops.
    func toggleSelectAll() {
        if allItemsSelected {
            selectedCategoryIds = []
            nodeModulesSelection = []
            flutterSelection = []
        } else {
            selectedCategoryIds = Set(categories.map(\.id))
            nodeModulesSelection = Set(nodeModulesEntries.map(\.url))
            flutterSelection = Set(flutterProjects.map(\.projectURL))
        }
    }

    /// Categories grouped by `CategoryGroup`, sorted alphabetically by
    /// the group's raw value for stable UI ordering. Categories that were
    /// scanned and found empty (0 bytes) are hidden — only meaningful
    /// results stay in the list. Un-scanned categories are always shown.
    var categoriesByGroup: [(group: CategoryGroup, categories: [CleanCategory])] {
        let visible = categories.filter { category in
            guard let result = scanResults[category.id] else { return true }
            return result.totalBytes > 0
        }
        let grouped = Dictionary(grouping: visible, by: \.group)
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

    /// Run every scan concurrently — categories + node_modules +
    /// Flutter + Docker. Used by the unified Scan button so the user
    /// gets one progress affordance instead of four.
    func scanAll() async {
        async let a: () = scan()
        async let b: () = scanNodeModules()
        async let c: () = scanFlutterProjects()
        async let d: () = scanDockerCache()
        _ = await (a, b, c, d)
    }

    /// Apply every selection — categories + node_modules + Flutter caches.
    /// Computes combined banner totals up-front so we can override the
    /// per-method banners with one summary at the end.
    func applyAll() async {
        let hasCategories = selectedItemCount > 0
        let hasNodeModules = !nodeModulesSelection.isEmpty
        let hasFlutter = !flutterSelection.isEmpty
        guard hasCategories || hasNodeModules || hasFlutter else { return }

        let totalItems = combinedSelectedItemCount
        let totalBytes = combinedSelectedBytes

        if hasCategories { await apply() }
        if hasNodeModules { await trashSelectedNodeModules() }
        if hasFlutter { await trashSelectedFlutterProjects() }

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

    // MARK: - Flutter projects

    /// Sort key for the Flutter projects list.
    enum FlutterSort: String, CaseIterable, Identifiable {
        case pubspecMtime  // last project edit (pubspec.yaml mtime)
        case cacheMtime  // newer of .dart_tool / build mtimes
        case size  // descending size

        var id: String { rawValue }
        var label: String {
            switch self {
            case .pubspecMtime: return "Project last edited"
            case .cacheMtime:   return "Caches last touched"
            case .size:         return "Size"
            }
        }
    }

    /// Entries sorted per `flutterSort`. View binds to this so the list
    /// re-orders without re-scanning.
    var sortedFlutterProjects: [FlutterProjectEntry] {
        switch flutterSort {
        case .pubspecMtime:
            return flutterProjects.sorted { $0.pubspecMtime < $1.pubspecMtime }
        case .cacheMtime:
            return flutterProjects.sorted { $0.lastTouchedMtime < $1.lastTouchedMtime }
        case .size:
            return flutterProjects.sorted { $0.totalBytes > $1.totalBytes }
        }
    }

    /// Total bytes across currently-selected Flutter projects.
    var flutterSelectedBytes: Int64 {
        flutterProjects
            .filter { flutterSelection.contains($0.projectURL) }
            .reduce(0) { $0 + $1.totalBytes }
    }

    /// Walk `~/` looking for pubspec.yaml files. Long-running on large
    /// home dirs; toggles `isScanningFlutterProjects` for the duration.
    func scanFlutterProjects() async {
        isScanningFlutterProjects = true
        defer { isScanningFlutterProjects = false }

        let scanner = FlutterProjectScanner()
        let entries = await scanner.scanHomeDirectory()
        flutterProjects = entries
        // Drop any prior selections that no longer exist on disk.
        flutterSelection.formIntersection(Set(entries.map(\.projectURL)))

        logger.info("Flutter scan: \(entries.count, privacy: .public) projects")
    }

    /// Trash `.dart_tool` and `build` for every selected Flutter project.
    /// Honors `dryRun`. A project is removed from the list only if every
    /// cache it owns trashed successfully.
    func trashSelectedFlutterProjects() async {
        guard !flutterSelection.isEmpty else { return }

        let targets = flutterProjects.filter { flutterSelection.contains($0.projectURL) }
        var removed: Set<URL> = []
        var bytesReclaimed: Int64 = 0

        for entry in targets {
            let caches = [entry.dartToolURL, entry.buildURL].compactMap { $0 }
            var allOK = true
            for cacheURL in caches {
                do {
                    let bytes = try await SafeFileOps.trash(cacheURL, dryRun: dryRun)
                    bytesReclaimed += bytes
                    try? await log.append(OperationLogEntry(
                        timestamp: Date(),
                        action: .trash,
                        target: cacheURL.path,
                        bytes: bytes,
                        dryRun: dryRun
                    ))
                } catch {
                    allOK = false
                    logger.error(
                        "trash failed for \(cacheURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            if allOK { removed.insert(entry.projectURL) }
        }

        if !dryRun {
            flutterProjects.removeAll { removed.contains($0.projectURL) }
            flutterSelection.subtract(removed)
        }
        previewBanner = PreviewSummary(items: removed.count, bytes: bytesReclaimed)
    }

    // MARK: - Docker cache (IRREVERSIBLE — separate from the trash flow)
    //
    // `docker … prune` deletes immediately and cannot be restored from
    // the Trash, so Docker selections are *deliberately* excluded from
    // `applyAll`, `hasAnySelection`, `toggleSelectAll`, and the footer
    // totals. The DockerCacheSection card hosts its own Reclaim button
    // and confirmation dialog. Only `combinedReclaimable` (informational
    // header total) and `isScanningAny` (unified Scan spinner) include it.

    /// Sum of reclaimable bytes across currently-selected Docker kinds.
    /// Drives the in-card "Reclaim N MB" button label.
    var dockerSelectedBytes: Int64 {
        dockerCacheEntries
            .filter { dockerSelection.contains($0.kind) }
            .reduce(0) { $0 + $1.reclaimableBytes }
    }

    /// Asks the Docker daemon what's reclaimable via the CLI scanner.
    /// On the FIRST populated scan, pre-ticks the safe defaults
    /// (`Kind.defaultEnabled`); on subsequent scans, preserves the
    /// user's selection and only drops kinds that vanished. Safe no-op
    /// if Docker isn't installed or the daemon is down — the scanner
    /// returns `[]`.
    func scanDockerCache() async {
        let isFirstPopulatedScan = dockerCacheEntries.isEmpty

        isScanningDockerCache = true
        defer { isScanningDockerCache = false }

        let scanner = DockerCacheScanner()
        let entries = await scanner.scan()
        dockerCacheEntries = entries

        let present = Set(entries.map(\.kind))
        if isFirstPopulatedScan {
            dockerSelection = Set(
                entries.filter { $0.kind.defaultEnabled }.map(\.kind)
            )
        } else {
            dockerSelection.formIntersection(present)
        }

        logger.info("Docker scan: \(entries.count, privacy: .public) reclaimable classes")
    }

    /// Run `docker … prune` for every selected kind. IRREVERSIBLE —
    /// callers (i.e. `DockerCacheSection`) must confirm with the user
    /// first when `dryRun == false`. In dry-run mode nothing runs, but
    /// a preview banner still reports the would-reclaim total and audit
    /// entries are appended with `dryRun: true`.
    func pruneSelectedDocker() async {
        guard !dockerSelection.isEmpty else { return }

        let targets = dockerCacheEntries.filter { dockerSelection.contains($0.kind) }

        isPruningDocker = true
        defer { isPruningDocker = false }

        let succeeded: Set<DockerCacheEntry.Kind>
        if dryRun {
            // Pretend every selection succeeded — used only for the
            // preview banner and audit log; nothing is pruned.
            succeeded = Set(targets.map(\.kind))
        } else {
            let scanner = DockerCacheScanner()
            succeeded = await scanner.prune(targets.map(\.kind))
        }

        var bytesReclaimed: Int64 = 0
        for entry in targets where succeeded.contains(entry.kind) {
            bytesReclaimed += entry.reclaimableBytes
            let argv = entry.kind.pruneArguments.joined(separator: " ")
            try? await log.append(OperationLogEntry(
                timestamp: Date(),
                action: .exec,
                target: "docker \(argv)",
                bytes: entry.reclaimableBytes,
                dryRun: dryRun
            ))
        }

        if !dryRun {
            dockerCacheEntries.removeAll { succeeded.contains($0.kind) }
            dockerSelection.subtract(succeeded)
        }

        previewBanner = PreviewSummary(items: succeeded.count, bytes: bytesReclaimed)
        if dryRun { scheduleBannerDismiss() }
    }
}
