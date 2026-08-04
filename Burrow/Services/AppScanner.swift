import Foundation
import os

private let logger = Logger(subsystem: "fun.burrow", category: "AppScanner")

/// Enumerates installed applications and finds their leftover files using
/// patterns from `AppLeftovers.json`. Read-only — never mutates the file
/// system. All destructive operations are deferred to `SafeFileOps`.
actor AppScanner {

    // MARK: - Singleton

    /// Production singleton — uses Bundle.main for the catalog.
    static let shared = AppScanner()

    // MARK: - Properties

    private let catalogURL: URL?
    private var cachedCatalog: AppLeftoversCatalog?

    // MARK: - Init

    /// Inject a custom catalog URL for tests.
    init(catalogURL: URL? = nil) {
        self.catalogURL = catalogURL
    }

    // MARK: - Public API

    /// Maximum folder depth below an Applications root at which a .app
    /// can sit — covers vendor nesting like
    /// `/Applications/Adobe Creative Cloud/Adobe Photoshop/Photoshop.app`
    /// without crawling arbitrarily deep trees.
    private static let maxDiscoveryDepth = 4

    /// Walks /Applications and ~/Applications recursively (up to
    /// `maxDiscoveryDepth` levels, so vendor subfolders like
    /// `/Applications/Setapp/Foo.app` are found too; never descends
    /// into a .app bundle). Parses each .app's Info.plist for
    /// bundleId/name/version/build. Detects installSource per the
    /// catalog's homebrewDetection + macAppStoreDetection blocks.
    /// Dedupes by bundleId. Returns alphabetically sorted by
    /// `name.localizedStandardCompare`.
    func discoverInstalledApps() async -> [InstalledApp] {
        let catalog: AppLeftoversCatalog
        do {
            catalog = try loadCatalog()
        } catch {
            logger.warning("Catalog load failed: \(error.localizedDescription, privacy: .public)")
            return []
        }

        let home = NSHomeDirectory()
        let roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: home).appendingPathComponent("Applications"),
        ]

        var seenBundleIds = Set<String>()
        var apps: [InstalledApp] = []
        let fm = FileManager.default

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else {
                    if enumerator.level >= Self.maxDiscoveryDepth {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                // Never descend into a bundle — embedded helper apps
                // are not uninstall candidates.
                enumerator.skipDescendants()

                guard let bundle = Bundle(url: url),
                      let bundleId = bundle.bundleIdentifier else {
                    logger.warning("Skipping app with no bundleId at \(url.path, privacy: .private)")
                    continue
                }

                // Dedupe by bundleId — keep first occurrence in walk order
                guard seenBundleIds.insert(bundleId).inserted else {
                    continue
                }

                let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

                let installSource = detectInstallSource(
                    appURL: url,
                    catalog: catalog
                )

                let app = InstalledApp(
                    bundleId: bundleId,
                    name: name,
                    displayName: displayName,
                    bundleURL: url,
                    version: version,
                    build: build,
                    bundleSize: nil,
                    lastOpenedDate: nil,
                    installSource: installSource
                )
                apps.append(app)
            }
        }

        logger.info("Discovered \(apps.count, privacy: .public) apps")

        return apps.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// For a given app, expands every applicable LeftoverPattern in
    /// the catalog (userPaths + systemPaths + matching vendorOverrides)
    /// and returns one LeftoverMatch per resolved URL. Dedupes by URL.
    /// Returns [] if the bundleId matches catalog.ignoreApps.
    func findLeftovers(for app: InstalledApp) async -> [LeftoverMatch] {
        let catalog: AppLeftoversCatalog
        do {
            catalog = try loadCatalog()
        } catch {
            logger.warning("Catalog load failed: \(error.localizedDescription, privacy: .public)")
            return []
        }

        // Check ignore list
        if isIgnored(app.bundleId, by: catalog.ignoreApps) {
            logger.info("Skipping ignored app \(app.bundleId, privacy: .public)")
            return []
        }

        // Collect candidate patterns: userPaths + systemPaths
        var patternEntries: [(pattern: LeftoverPattern, fromVendor: Bool)] = []
        for pattern in catalog.userPaths {
            patternEntries.append((pattern: pattern, fromVendor: false))
        }
        for pattern in catalog.systemPaths {
            patternEntries.append((pattern: pattern, fromVendor: false))
        }

        // Matching vendorOverrides
        for (key, vendor) in catalog.vendorOverrides {
            if vendorKeyMatches(key: key, bundleId: app.bundleId) {
                for pattern in vendor.paths {
                    patternEntries.append((pattern: pattern, fromVendor: true))
                }
            }
        }

        // Per-run directory cache: parent URL → children
        var directoryCache: [URL: [URL]] = [:]
        defer { directoryCache.removeAll() }

        var seenPaths = Set<String>()
        var matches: [LeftoverMatch] = []

        for entry in patternEntries {
            let resolved = expandPattern(
                entry.pattern,
                for: app,
                directoryCache: &directoryCache
            )
            for url in resolved {
                let standardPath = url.standardizedFileURL.path
                guard seenPaths.insert(standardPath).inserted else { continue }

                let bytes = SafeFileOps.size(url)
                let shared = entry.fromVendor && isSharedPath(url, app: app)

                let match = LeftoverMatch(
                    url: url,
                    bytes: bytes,
                    pattern: entry.pattern,
                    isShared: shared
                )
                matches.append(match)
            }
        }

        logger.info(
            "Found \(matches.count, privacy: .public) leftovers for \(app.bundleId, privacy: .public)"
        )

        return matches
    }

    // MARK: - Catalog loading

    private func loadCatalog() throws -> AppLeftoversCatalog {
        if let cached = cachedCatalog { return cached }
        let url = catalogURL ?? Bundle.main.url(forResource: "AppLeftovers", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(AppLeftoversCatalog.self, from: data)
        cachedCatalog = catalog
        return catalog
    }

    // MARK: - Install source detection

    private func detectInstallSource(
        appURL: URL,
        catalog: AppLeftoversCatalog
    ) -> InstallSource {
        // Check for MAS receipt
        let receiptPath = catalog.macAppStoreDetection.receiptPath
        let receiptURL = appURL.appendingPathComponent(receiptPath)
        if FileManager.default.fileExists(atPath: receiptURL.path) {
            return .macAppStore
        }

        // Check if the app's resolved symlink path starts with a Caskroom prefix
        let resolvedPath = appURL.resolvingSymlinksInPath().path
        for prefix in catalog.homebrewDetection.caskroomPrefixes {
            let expandedPrefix = PathResolver.expand(prefix)
            if resolvedPath.hasPrefix(expandedPrefix) {
                return .homebrewCask
            }
        }

        return .manual
    }

    // MARK: - Pattern expansion

    /// Expands a single `LeftoverPattern` for an app, returning only
    /// URLs that exist on disk. Uses the per-run directory cache for
    /// `.containsBundleId` parent directory listings.
    private func expandPattern(
        _ pattern: LeftoverPattern,
        for app: InstalledApp,
        directoryCache: inout [URL: [URL]]
    ) -> [URL] {
        switch pattern.matchType {
        case .exact:
            return expandExact(pattern.path, for: app)

        case .prefix:
            return expandPrefix(pattern.path, for: app)

        case .containsBundleId:
            return expandContainsBundleId(pattern.path, for: app, cache: &directoryCache)

        case .glob:
            return expandGlob(pattern.path, for: app)
        }
    }

    /// `.exact` — returns `[url]` if the resolved path exists, regardless
    /// of file-vs-directory.
    private func expandExact(_ path: String, for app: InstalledApp) -> [URL] {
        var results: [URL] = []
        for substituted in substituteAll(path: path, app: app) {
            let expanded = PathResolver.expand(substituted)
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.standardizedFileURL.path) {
                results.append(url)
            }
        }
        return results
    }

    /// `.prefix` — returns `[url]` if the substituted path exists. The
    /// URL-ancestor semantics are enforced at match time in the dedup loop.
    private func expandPrefix(_ path: String, for app: InstalledApp) -> [URL] {
        var results: [URL] = []
        for substituted in substituteAll(path: path, app: app) {
            let expanded = PathResolver.expand(substituted)
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.standardizedFileURL.path) {
                results.append(url)
            }
        }
        return results
    }

    /// `.containsBundleId` — depth-1 walk of the parent directory;
    /// returns entries whose last path component contains the bundle ID.
    private func expandContainsBundleId(
        _ path: String,
        for app: InstalledApp,
        cache: inout [URL: [URL]]
    ) -> [URL] {
        let parent = URL(fileURLWithPath: PathResolver.expand(path))

        if cache[parent] == nil {
            let kids = (try? FileManager.default.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            cache[parent] = kids
        }

        return (cache[parent] ?? []).filter {
            $0.lastPathComponent.contains(app.bundleId)
        }
    }

    /// `.glob` — delegates to `PathResolver.resolve(_:)` after
    /// substituting placeholders.
    private func expandGlob(_ path: String, for app: InstalledApp) -> [URL] {
        var results: [URL] = []
        for substituted in substituteAll(path: path, app: app) {
            let resolved = PathResolver.resolve(substituted)
            results.append(contentsOf: resolved)
        }
        return results
    }

    // MARK: - Placeholder substitution

    /// Returns one or two substituted paths for a pattern, handling both
    /// `{bundleId}` (single expansion) and `{name}` (two-form expansion:
    /// CFBundleName and .app filename without extension). If both name
    /// forms are equal, only one result is returned.
    private func substituteAll(path: String, app: InstalledApp) -> [String] {
        let hasBundleId = path.contains("{bundleId}")
        let hasName = path.contains("{name}")

        if hasBundleId {
            return [path.replacingOccurrences(of: "{bundleId}", with: app.bundleId)]
        }

        if hasName {
            let cfBundleName = app.name
            let filename = app.bundleURL.deletingPathExtension().lastPathComponent

            let form1 = path.replacingOccurrences(of: "{name}", with: cfBundleName)
            if cfBundleName == filename {
                return [form1]
            }
            let form2 = path.replacingOccurrences(of: "{name}", with: filename)
            return [form1, form2]
        }

        // No placeholder — return as-is
        return [path]
    }

    // MARK: - Vendor key matching

    private func vendorKeyMatches(key: String, bundleId: String) -> Bool {
        if key.hasSuffix(".") {
            return bundleId.hasPrefix(key)
        } else {
            return bundleId == key
        }
    }

    // MARK: - isShared flag

    /// Returns true IFF the resolved URL's last path component does NOT
    /// contain the app's bundleId AND does NOT contain the app's name.
    private func isSharedPath(_ url: URL, app: InstalledApp) -> Bool {
        let lastComponent = url.lastPathComponent
        return !lastComponent.contains(app.bundleId) && !lastComponent.contains(app.name)
    }

    // MARK: - ignoreApps matching

    private func isIgnored(_ bundleId: String, by ignoreApps: AppLeftoversCatalog.IgnoreApps) -> Bool {
        for pattern in ignoreApps.patterns {
            if pattern.contains("*") {
                // Glob: convert * → .*, anchor, regex match
                let escaped = NSRegularExpression.escapedPattern(for: pattern)
                    .replacingOccurrences(of: "\\*", with: ".*")
                let regex = "^" + escaped + "$"
                if bundleId.range(of: regex, options: .regularExpression) != nil { return true }
            } else {
                if bundleId == pattern { return true }
            }
        }
        return false
    }
}
