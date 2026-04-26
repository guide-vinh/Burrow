import XCTest
@testable import Burrow

final class RuleEngineTests: XCTestCase {

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("burrow-engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeThreeFiles() throws -> [URL] {
        let urls = [
            fixture.appendingPathComponent("a.bin"),
            fixture.appendingPathComponent("b.bin"),
            fixture.appendingPathComponent("c.bin"),
        ]
        try Data(repeating: 0x01, count: 100).write(to: urls[0])
        try Data(repeating: 0x02, count: 500).write(to: urls[1])
        try Data(repeating: 0x03, count: 2000).write(to: urls[2])
        return urls
    }

    private func directoryContentsCategory(
        path: String,
        exclude: [String]? = nil
    ) -> CleanCategory {
        CleanCategory(
            id: "test.fixture",
            title: "Test Fixture",
            summary: "Tmpdir scan fixture",
            group: .system,
            icon: "trash",
            risk: .low,
            defaultEnabled: true,
            requiresAppQuit: nil,
            exclude: exclude,
            rules: [
                .directoryContents(path: path, olderThanDays: nil, includeHidden: nil, needsPrivilege: nil)
            ]
        )
    }

    private func freshLog() -> OperationLog {
        OperationLog(logURL: fixture.appendingPathComponent("log.jsonl"))
    }

    // MARK: - A. loadCatalog

    func testLoadCatalogParsesBundledCleanRules() throws {
        let url = try XCTUnwrap(
            Bundle(for: type(of: self)).url(forResource: "CleanRules", withExtension: "json")
                ?? Bundle.main.url(forResource: "CleanRules", withExtension: "json"),
            "CleanRules.json must be in the app bundle"
        )
        let catalog = try RuleEngine.loadCatalog(from: url)
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertNotNil(
            catalog.categories.first { $0.id == "browser.chrome" },
            "expected seeded browser.chrome category"
        )
    }

    func testLoadCatalogThrowsOnMissingFile() {
        let missingURL = fixture.appendingPathComponent("does-not-exist.json")
        XCTAssertThrowsError(try RuleEngine.loadCatalog(from: missingURL))
    }

    // MARK: - B. scan

    func testScanReports2600BytesAcross3Items() async throws {
        _ = try makeThreeFiles()
        let category = directoryContentsCategory(path: fixture.path)
        let log = freshLog()
        let catalog = CleanCatalog(schemaVersion: 1, categories: [category])
        let engine = RuleEngine(catalog: catalog, log: log)
        let result = await engine.scan(category)
        XCTAssertEqual(result.items.count, 3)
        XCTAssertGreaterThanOrEqual(result.totalBytes, 2600)
        XCTAssertLessThanOrEqual(result.totalBytes, 100_000)
    }

    func testScanHonorsExclude() async throws {
        _ = try makeThreeFiles()
        // List the directory to get the canonical paths that contentsOfDirectory
        // returns (e.g. /private/var/... on macOS, not the symlinked /var/...).
        let listedURLs = try FileManager.default.contentsOfDirectory(
            at: fixture,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        // a.bin=0, b.bin=1, c.bin=2 — exclude c.bin (the 2000-byte file).
        let excludedURL = listedURLs.first { $0.lastPathComponent == "c.bin" }!
        let category = directoryContentsCategory(
            path: fixture.path,
            exclude: [excludedURL.path]
        )
        let log = freshLog()
        let catalog = CleanCatalog(schemaVersion: 1, categories: [category])
        let engine = RuleEngine(catalog: catalog, log: log)
        let result = await engine.scan(category)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertFalse(
            result.items.contains { $0.url.lastPathComponent == "c.bin" },
            "excluded file should not appear in scan results"
        )
    }

    func testScanSkipsCommandRules() async throws {
        let category = CleanCategory(
            id: "test.command",
            title: "Command Category",
            summary: "Tests command rule skipping",
            group: .system,
            icon: "terminal",
            risk: .low,
            defaultEnabled: true,
            requiresAppQuit: nil,
            exclude: nil,
            rules: [
                .command(exec: "/bin/echo", args: ["hi"], needsPrivilege: nil)
            ]
        )
        let log = freshLog()
        let catalog = CleanCatalog(schemaVersion: 1, categories: [category])
        let engine = RuleEngine(catalog: catalog, log: log)
        let result = await engine.scan(category)
        XCTAssertTrue(result.items.isEmpty, "command rules should produce no scan items in Phase 1")
    }

    // MARK: - C. scanAll cancellation

    func testScanAllRespondsToCancellationWithoutCrashing() async throws {
        _ = try makeThreeFiles()
        // Build a catalog with 5 identical categories
        let categories = (0..<5).map { i -> CleanCategory in
            CleanCategory(
                id: "test.fixture.\(i)",
                title: "Test Fixture \(i)",
                summary: "Tmpdir scan fixture",
                group: .system,
                icon: "trash",
                risk: .low,
                defaultEnabled: true,
                requiresAppQuit: nil,
                exclude: nil,
                rules: [
                    .directoryContents(path: fixture.path, olderThanDays: nil, includeHidden: nil, needsPrivilege: nil)
                ]
            )
        }
        let log = freshLog()
        let catalog = CleanCatalog(schemaVersion: 1, categories: categories)
        let engine = RuleEngine(catalog: catalog, log: log)

        let task = Task {
            await engine.scanAll(categories)
        }
        task.cancel()
        let results = await task.value
        // Partial results are acceptable; just verify no crash and sane count
        XCTAssertLessThanOrEqual(results.count, 5)
    }

    // MARK: - D. apply dry-run + real

    func testApplyDryRunLeavesFilesAndLogsThreeEntries() async throws {
        let urls = try makeThreeFiles()
        let category = directoryContentsCategory(path: fixture.path)
        let log = freshLog()
        let catalog = CleanCatalog(schemaVersion: 1, categories: [category])
        let engine = RuleEngine(catalog: catalog, log: log)

        let result = await engine.scan(category)
        XCTAssertEqual(result.items.count, 3)

        try await engine.apply(result, dryRun: true)

        // (a) All files still on disk
        for url in urls {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "dryRun must not remove \(url.lastPathComponent)"
            )
        }

        // (b) Log has 3 entries
        let entries = try await log.readAll()
        XCTAssertEqual(entries.count, 3)

        // (c) Every entry has dryRun=true and action=.trash
        for entry in entries {
            XCTAssertTrue(entry.dryRun, "expected dryRun=true")
            XCTAssertEqual(entry.action, .trash)
        }
    }

    func testApplyTrashesFilesAndLogsSixTotalEntries() async throws {
        let urls = try makeThreeFiles()
        let category = directoryContentsCategory(path: fixture.path)
        let log = freshLog()
        let catalog = CleanCatalog(schemaVersion: 1, categories: [category])
        let engine = RuleEngine(catalog: catalog, log: log)

        let result = await engine.scan(category)
        XCTAssertEqual(result.items.count, 3)

        // First pass: dry-run
        try await engine.apply(result, dryRun: true)

        // Second pass: real trash
        try await engine.apply(result, dryRun: false)

        // All 3 files should be gone from the fixture directory
        for url in urls {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: url.path),
                "\(url.lastPathComponent) should have been trashed"
            )
        }

        // Log should have 6 total entries
        let entries = try await log.readAll()
        XCTAssertEqual(entries.count, 6)

        // First 3 entries: dryRun=true
        for entry in entries.prefix(3) {
            XCTAssertTrue(entry.dryRun, "first 3 entries should have dryRun=true")
        }

        // Last 3 entries: dryRun=false
        for entry in entries.suffix(3) {
            XCTAssertFalse(entry.dryRun, "last 3 entries should have dryRun=false")
        }
    }

    // MARK: - E. glob and olderThanDays branches

    func testScanResolvesGlobRule() async throws {
        // cache1/data.bin and cache2/data.bin should match; nope/data.bin
        // should not — only the cache* prefix wins.
        let cache1 = fixture.appendingPathComponent("cache1")
        let cache2 = fixture.appendingPathComponent("cache2")
        let nope   = fixture.appendingPathComponent("nope")
        for dir in [cache1, cache2, nope] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0xAA, count: 256).write(to: dir.appendingPathComponent("data.bin"))
        }

        let category = CleanCategory(
            id: "test.glob",
            title: "Glob Fixture",
            summary: "Tests .glob branch",
            group: .system,
            icon: "trash",
            risk: .low,
            defaultEnabled: true,
            requiresAppQuit: nil,
            exclude: nil,
            rules: [
                .glob(
                    path: fixture.path + "/cache*/data.bin",
                    olderThanDays: nil,
                    includeHidden: nil,
                    needsPrivilege: nil
                ),
            ]
        )
        let log = freshLog()
        let catalog = CleanCatalog(schemaVersion: 1, categories: [category])
        let engine = RuleEngine(catalog: catalog, log: log)

        let result = await engine.scan(category)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.allSatisfy { $0.url.lastPathComponent == "data.bin" })
        let parents = Set(result.items.map { $0.url.deletingLastPathComponent().lastPathComponent })
        XCTAssertEqual(parents, ["cache1", "cache2"])
    }

    func testScanFiltersOutFreshFilesByOlderThanDays() async throws {
        _ = try makeThreeFiles()  // mtimes are "now"
        let category = CleanCategory(
            id: "test.older",
            title: "Older fixture",
            summary: "Tests olderThanDays filter",
            group: .system,
            icon: "trash",
            risk: .low,
            defaultEnabled: true,
            requiresAppQuit: nil,
            exclude: nil,
            rules: [
                .directoryContents(
                    path: fixture.path,
                    olderThanDays: 1,
                    includeHidden: nil,
                    needsPrivilege: nil
                ),
            ]
        )
        let log = freshLog()
        let catalog = CleanCatalog(schemaVersion: 1, categories: [category])
        let engine = RuleEngine(catalog: catalog, log: log)

        let result = await engine.scan(category)
        XCTAssertTrue(
            result.items.isEmpty,
            "fresh files should be filtered out when olderThanDays=1"
        )
    }

    func testScanSkipsProtectedPathsViaIsAllowed() async throws {
        // /System exists but is in SafeFileOps' deny-list. The .glob rule
        // resolves to it; RuleEngine.isAllowed's protectedPath catch
        // branch should silently drop it from the result. This test
        // exercises the validate-failure branch without scanning system
        // contents (PathResolver.resolve only returns the literal /System
        // URL — we never enumerate its children).
        let category = CleanCategory(
            id: "test.protected",
            title: "Protected path rule",
            summary: "Tests isAllowed deny-list catch branch",
            group: .system,
            icon: "trash",
            risk: .low,
            defaultEnabled: true,
            requiresAppQuit: nil,
            exclude: nil,
            rules: [
                .glob(
                    path: "/System",
                    olderThanDays: nil,
                    includeHidden: nil,
                    needsPrivilege: nil
                ),
            ]
        )
        let log = freshLog()
        let catalog = CleanCatalog(schemaVersion: 1, categories: [category])
        let engine = RuleEngine(catalog: catalog, log: log)

        let result = await engine.scan(category)
        XCTAssertTrue(
            result.items.isEmpty,
            "/System is in the SafeFileOps deny-list and must be dropped"
        )
    }

    func testScanIncludesAgedFilesByOlderThanDays() async throws {
        let url = fixture.appendingPathComponent("aged.bin")
        try Data(repeating: 0xBB, count: 128).write(to: url)
        // Backdate mtime by 2 days so it qualifies as "older than 1 day".
        let twoDaysAgo = Date().addingTimeInterval(-2 * 86400)
        try FileManager.default.setAttributes(
            [.modificationDate: twoDaysAgo],
            ofItemAtPath: url.path
        )

        let category = CleanCategory(
            id: "test.aged",
            title: "Aged fixture",
            summary: "Tests olderThanDays include branch",
            group: .system,
            icon: "trash",
            risk: .low,
            defaultEnabled: true,
            requiresAppQuit: nil,
            exclude: nil,
            rules: [
                .directoryContents(
                    path: fixture.path,
                    olderThanDays: 1,
                    includeHidden: nil,
                    needsPrivilege: nil
                ),
            ]
        )
        let log = freshLog()
        let catalog = CleanCatalog(schemaVersion: 1, categories: [category])
        let engine = RuleEngine(catalog: catalog, log: log)

        let result = await engine.scan(category)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.url.lastPathComponent, "aged.bin")
    }
}
