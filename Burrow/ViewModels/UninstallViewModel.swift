import Foundation
import SwiftUI // ObservableObject + @Published only — no Color/Font/Image
import os

/// Drives the Uninstall tab. Discovers installed apps, finds their
/// leftovers via `AppScanner`, lets the user pick what to remove, and
/// trashes everything ticked through `SafeFileOps`. Pure data; views
/// map data → visuals.
@MainActor
final class UninstallViewModel: ObservableObject {

    // MARK: - Logger

    private let logger = Logger(subsystem: "fun.burrow", category: "UninstallViewModel")

    // MARK: - Published state

    @Published private(set) var apps: [InstalledApp] = []
    @Published var selectedApp: InstalledApp?
    @Published private(set) var leftovers: [LeftoverMatch] = []
    @Published var checkedURLs: Set<URL> = []
    @Published var searchQuery: String = ""
    @Published var dryRun: Bool = false
    @Published private(set) var isLoadingApps: Bool = false
    @Published private(set) var isLoadingLeftovers: Bool = false
    @Published private(set) var isApplying: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var previewBanner: PreviewSummary?

    // MARK: - Dependencies

    private let discoverApps: () async -> [InstalledApp]
    private let findLeftovers: (InstalledApp) async -> [LeftoverMatch]
    private let log: OperationLog
    private var bannerDismissTask: Task<Void, Never>?

    // MARK: - Init

    /// Closure-injected so tests don't need to refactor `AppScanner`.
    /// Production callers use the defaults, which route through the
    /// `AppScanner.shared` actor.
    init(
        discoverApps: @escaping () async -> [InstalledApp]
            = { await AppScanner.shared.discoverInstalledApps() },
        findLeftovers: @escaping (InstalledApp) async -> [LeftoverMatch]
            = { await AppScanner.shared.findLeftovers(for: $0) },
        log: OperationLog = .shared
    ) {
        self.discoverApps = discoverApps
        self.findLeftovers = findLeftovers
        self.log = log
    }

    // MARK: - Discovery

    /// Walks /Applications etc. via `AppScanner` and stores the result
    /// in `apps`. Toggles `isLoadingApps` for the duration.
    func loadApps() async {
        isLoadingApps = true
        defer { isLoadingApps = false }

        let discovered = await discoverApps()
        self.apps = discovered
        // NOTE: don't clear `lastError` here — loadApps is a refresh
        // (called on init AND post-uninstall) so an in-flight uninstall
        // error must survive the re-discover. `select()` resets state
        // when the user picks a fresh app.
        logger.info("Loaded \(discovered.count, privacy: .public) installed apps")
    }

    // MARK: - Selection

    /// Switch the selected app and re-scan its leftovers. Pre-checks
    /// the safe + caution non-shared non-privileged matches, plus the
    /// .app bundle URL. Cancels any prior preview banner.
    func select(_ app: InstalledApp?) async {
        dismissPreviewBanner()
        selectedApp = app

        guard let app else {
            leftovers = []
            checkedURLs = []
            return
        }

        isLoadingLeftovers = true
        defer { isLoadingLeftovers = false }

        let found = await findLeftovers(app)
        self.leftovers = found
        self.checkedURLs = defaultCheckedURLs(for: app, leftovers: found)
        self.lastError = nil
        logger.info(
            "Selected \(app.bundleId, privacy: .public): \(found.count, privacy: .public) leftovers, \(self.checkedURLs.count, privacy: .public) pre-checked"
        )
    }

    /// Pre-check rules per Phase 2 locked decisions:
    /// - needsPrivilege: true  → unchecked (no privileged helper in v0.1)
    /// - isShared: true        → unchecked (vendor-shared root)
    /// - risk: .highValue      → unchecked (user data)
    /// - else (safe/caution)   → checked
    /// - The .app bundle URL itself is always pre-checked.
    private func defaultCheckedURLs(
        for app: InstalledApp,
        leftovers: [LeftoverMatch]
    ) -> Set<URL> {
        var checked: Set<URL> = [app.bundleURL]
        for match in leftovers {
            if match.pattern.needsPrivilege == true { continue }
            if match.isShared { continue }
            if match.pattern.risk == .highValue { continue }
            checked.insert(match.url)
        }
        return checked
    }

    // MARK: - Apply

    /// Trashes (or dry-runs) every URL in `checkedURLs`. Per-URL
    /// failures are recorded in `lastError` and the loop continues.
    /// On a real (non-dry) successful apply, clears state and re-
    /// discovers apps so the trashed .app drops out of the list.
    /// `permanently` bypasses the Trash (callers must confirm with the
    /// user first).
    func uninstall(permanently: Bool = false) async {
        guard !checkedURLs.isEmpty else { return }

        isApplying = true
        defer { isApplying = false }

        var encounteredError = false
        var totalBytes: Int64 = 0
        var totalItems = 0

        // Deepest paths first, so a checked install folder (which
        // contains the .app) is trashed after its own contents and
        // never triggers doesNotExist failures on the rest.
        let targets = checkedURLs.sorted {
            $0.standardizedFileURL.pathComponents.count
                > $1.standardizedFileURL.pathComponents.count
        }

        for url in targets {
            do {
                let bytes = permanently
                    ? try await SafeFileOps.permanentlyDelete(url, dryRun: dryRun)
                    : try await SafeFileOps.trash(url, dryRun: dryRun)
                totalBytes += bytes
                totalItems += 1

                let entry = OperationLogEntry(
                    timestamp: Date(),
                    action: permanently ? .permanentDelete : .trash,
                    target: url.path,
                    bytes: bytes,
                    dryRun: dryRun
                )
                do {
                    try await log.append(entry)
                } catch {
                    logger.error(
                        "Audit log failed for \(url.path, privacy: .private): \(error.localizedDescription, privacy: .public)"
                    )
                }
            } catch {
                let message = "Failed to trash \(url.lastPathComponent): \(error.localizedDescription)"
                lastError = message
                encounteredError = true
                logger.error("\(message, privacy: .public)")
            }
        }

        if !dryRun && totalItems > 0 {
            leftovers = []
            checkedURLs = []
            if let app = selectedApp,
               !FileManager.default.fileExists(atPath: app.bundleURL.path) {
                selectedApp = nil
            }
            await loadApps()
            dismissPreviewBanner()
            logger.info(
                "Real uninstall completed; refreshed app list (\(self.apps.count, privacy: .public) apps remain, encounteredError=\(encounteredError, privacy: .public))"
            )
        } else if dryRun && totalItems > 0 {
            previewBanner = PreviewSummary(items: totalItems, bytes: totalBytes)
            scheduleBannerDismiss()
        }
    }

    // MARK: - Banner

    /// Clears the last error so its banner dismisses. Called from the UI's
    /// close button on the error banner.
    func dismissError() {
        lastError = nil
    }

    func dismissPreviewBanner() {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        previewBanner = nil
    }

    private func scheduleBannerDismiss() {
        bannerDismissTask?.cancel()
        bannerDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.previewBanner = nil }
        }
    }

    // MARK: - View accessors

    var operationsLogURL: URL { log.logURL }

    /// Apps filtered by `searchQuery` (case-insensitive `contains`).
    var filteredApps: [InstalledApp] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return apps }
        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(trimmed)
                || app.bundleId.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Number of items the user has ticked (.app bundle counts as 1).
    var selectedItemCount: Int { checkedURLs.count }

    /// Sum of bytes across all ticked items (pulls from the
    /// `LeftoverMatch.bytes` field; the .app bundle's size is taken
    /// from `selectedApp.bundleSize` if known, else 0).
    var selectedTotalBytes: Int64 {
        var total: Int64 = 0
        for match in leftovers where checkedURLs.contains(match.url) {
            total += match.bytes
        }
        if let app = selectedApp, checkedURLs.contains(app.bundleURL) {
            total += app.bundleSize ?? 0
        }
        return total
    }
}
