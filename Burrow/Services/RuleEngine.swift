import Foundation
import os

private let logger = Logger(subsystem: "fun.burrow", category: "RuleEngine")

/// Loads the cleaning catalog and orchestrates scan + apply across
/// categories. Scans run in parallel via withTaskGroup. Every
/// destructive operation routes through SafeFileOps and is recorded
/// in OperationLog — including dry-run entries (with dryRun=true).
actor RuleEngine {

    // MARK: - Properties

    let catalog: CleanCatalog
    let log: OperationLog

    // MARK: - Init

    /// Inject both for testability. Production callers use
    /// `OperationLog.shared`.
    init(catalog: CleanCatalog, log: OperationLog = .shared) {
        self.catalog = catalog
        self.log = log
    }

    // MARK: - Catalog loading

    /// Loads and decodes a CleanCatalog from a JSON file. Used by the
    /// app to wire `Bundle.main.url(forResource: "CleanRules", ...)`.
    static func loadCatalog(from url: URL) throws -> CleanCatalog {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(CleanCatalog.self, from: data)
    }

    // MARK: - Scan

    /// Resolves all rules in `category` and measures sizes. Skips rules
    /// whose paths fail validation (per SafeFileOps deny-list) — logs a
    /// warning and continues. Honors `olderThanDays` filtering using
    /// the file's content modification date (mtime).
    func scan(_ category: CleanCategory) async -> ScanResult {
        var seenURLs = Set<URL>()
        var items: [ScanItem] = []

        let excludeSet: Set<String> = Set(category.exclude?.map {
            PathResolver.expand($0)
        } ?? [])

        for rule in category.rules {
            let ruleItems = await resolveRule(rule, excludeSet: excludeSet)
            for item in ruleItems {
                guard seenURLs.insert(item.url).inserted else { continue }
                items.append(item)
            }
        }

        let total = items.reduce(0) { $0 + $1.bytes }
        logger.info(
            "Scan finished for \(category.id, privacy: .public): \(items.count, privacy: .public) items totalling \(total, privacy: .public) bytes"
        )

        return ScanResult(categoryId: category.id, items: items)
    }

    /// Scans all `categories` in parallel using `withTaskGroup`. Adds a
    /// `Task.isCancelled` check inside the loop so a cancelled parent
    /// task aborts the engine cleanly with partial results.
    func scanAll(_ categories: [CleanCategory]) async -> [ScanResult] {
        await withTaskGroup(of: ScanResult.self) { group in
            for category in categories {
                if Task.isCancelled { break }
                group.addTask { [self] in
                    await scan(category)
                }
            }
            var out: [ScanResult] = []
            out.reserveCapacity(categories.count)
            for await r in group {
                out.append(r)
            }
            return out
        }
    }

    // MARK: - Apply

    /// For each ScanItem, calls SafeFileOps.trash(_:dryRun:) and writes
    /// an OperationLogEntry. Per-item failures are logged and skipped —
    /// a single bad item never aborts the batch (SPEC section 6).
    /// Returns the total bytes successfully acted on. In dry-run mode,
    /// nothing is touched on disk but log entries ARE written with
    /// dryRun=true (SPEC section 6 audit-trail requirement).
    @discardableResult
    func apply(_ result: ScanResult, dryRun: Bool) async throws -> Int64 {
        var total: Int64 = 0

        for item in result.items {
            try Task.checkCancellation()

            let bytes = item.bytes

            do {
                try await SafeFileOps.trash(item.url, dryRun: dryRun)
            } catch {
                logger.error(
                    "Trash failed for \(item.url.path, privacy: .private): \(error.localizedDescription, privacy: .public)"
                )
                continue
            }

            let entry = OperationLogEntry(
                timestamp: Date(),
                action: .trash,
                target: item.url.path,
                bytes: bytes,
                dryRun: dryRun
            )

            do {
                try await log.append(entry)
            } catch {
                logger.error(
                    "Audit log failed for \(item.url.path, privacy: .private): \(error.localizedDescription, privacy: .public)"
                )
            }

            total += bytes
        }

        logger.info(
            "Apply finished for \(result.categoryId, privacy: .public): \(total, privacy: .public) bytes acted on (dryRun=\(dryRun, privacy: .public))"
        )

        return total
    }

    // MARK: - Private helpers

    /// Resolves a single rule to a list of ScanItems, applying mtime
    /// filtering and pre-validation against the SafeFileOps deny-list.
    private func resolveRule(_ rule: CleanRule, excludeSet: Set<String>) async -> [ScanItem] {
        switch rule {
        case let .directoryContents(path, olderThanDays, includeHidden, _):
            return await resolveDirectoryContents(
                path: path,
                olderThanDays: olderThanDays,
                includeHidden: includeHidden ?? false,
                excludeSet: excludeSet
            )

        case let .glob(path, olderThanDays, _, _):
            return await resolveGlob(
                path: path,
                olderThanDays: olderThanDays,
                excludeSet: excludeSet
            )

        case .command:
            logger.warning("Skipping command rule (Phase 1 does not exec)")
            return []
        }
    }

    private func resolveDirectoryContents(
        path: String,
        olderThanDays: Int?,
        includeHidden: Bool,
        excludeSet: Set<String>
    ) async -> [ScanItem] {
        let directories = PathResolver.resolve(path)
        var items: [ScanItem] = []
        let fm = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .isDirectoryKey,
        ]
        let options: FileManager.DirectoryEnumerationOptions = includeHidden
            ? []
            : .skipsHiddenFiles

        for dir in directories {
            let children: [URL]
            do {
                children = try fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: options
                )
            } catch {
                logger.warning(
                    "Could not list directory \(dir.path, privacy: .private): \(error.localizedDescription, privacy: .public)"
                )
                continue
            }

            for child in children {
                if excludeSet.contains(PathResolver.expand(child.path)) { continue }

                if let days = olderThanDays {
                    guard let mtime = mtimeFor(child) else {
                        // Conservative: unknown age → skip
                        continue
                    }
                    guard mtime < Date().addingTimeInterval(-Double(days) * 86400) else {
                        continue
                    }
                }

                guard isAllowed(child) else { continue }

                let bytes = SafeFileOps.size(child)
                items.append(ScanItem(url: child, bytes: bytes))
            }
        }

        return items
    }

    private func resolveGlob(
        path: String,
        olderThanDays: Int?,
        excludeSet: Set<String>
    ) async -> [ScanItem] {
        let resolved = PathResolver.resolve(path)
        var items: [ScanItem] = []

        for url in resolved {
            if excludeSet.contains(PathResolver.expand(url.path)) { continue }

            if let days = olderThanDays {
                guard let mtime = mtimeFor(url) else {
                    // Conservative: unknown age → skip
                    continue
                }
                guard mtime < Date().addingTimeInterval(-Double(days) * 86400) else {
                    continue
                }
            }

            guard isAllowed(url) else { continue }

            let bytes = SafeFileOps.size(url)
            items.append(ScanItem(url: url, bytes: bytes))
        }

        return items
    }

    /// Returns true if `url` passes the SafeFileOps deny-list validation,
    /// logging a warning and returning false on rejection.
    private func isAllowed(_ url: URL) -> Bool {
        do {
            try SafeFileOps.validate(url)
            return true
        } catch SafeFileError.protectedPath {
            logger.warning(
                "Skipping rule with bad path \(url.path, privacy: .private)"
            )
            return false
        } catch SafeFileError.doesNotExist {
            // Race between resolve and validate — silently drop.
            return false
        } catch {
            logger.warning(
                "Skipping rule with bad path \(url.path, privacy: .private)"
            )
            return false
        }
    }

    /// Returns the content modification date (mtime) for `url` using
    /// cached resource values. Returns nil if the value is unavailable.
    private func mtimeFor(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}
