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
    @Published private(set) var lastPreview: PreviewSummary? = nil

    /// Snapshot of the most recent dry-run apply, surfaced in the
    /// footer so users can see "what would have happened" was actually
    /// computed. Cleared on next scan or on a real apply.
    struct PreviewSummary: Equatable {
        let items: Int
        let bytes: Int64
    }

    // MARK: - Dependencies

    private var engine: RuleEngine?
    private let log: OperationLog

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
    func loadCatalog() async {
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

        self.categories = catalog.categories
        self.engine = RuleEngine(catalog: catalog, log: log)
        self.selectedCategoryIds = Set(catalog.categories.filter { $0.defaultEnabled }.map(\.id))
        self.lastError = nil

        logger.info("Catalog loaded: \(catalog.categories.count, privacy: .public) categories")
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
        self.lastPreview = nil  // a fresh scan invalidates any prior preview

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
            lastPreview = nil
            logger.info("Real apply completed cleanly; scan results and selection cleared")
        } else if dryRun && !encounteredError {
            lastPreview = PreviewSummary(items: totalItems, bytes: totalBytes)
        }
    }

    // MARK: - Computed

    /// Total bytes across all scanned items belonging to selected
    /// categories. Drives the footer "X items selected · N GB" text.
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

    /// Number of ScanItems across all selected categories. Drives the
    /// footer "X items selected" count.
    var selectedItemCount: Int {
        selectedCategoryIds
            .compactMap { scanResults[$0]?.items.count }
            .reduce(0, +)
    }

    /// Categories grouped by `CategoryGroup`, sorted alphabetically by
    /// the group's raw value for stable UI ordering.
    var categoriesByGroup: [(group: CategoryGroup, categories: [CleanCategory])] {
        let grouped = Dictionary(grouping: categories, by: \.group)
        return grouped
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { (group: $0.key, categories: $0.value) }
    }
}
