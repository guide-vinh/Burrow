import XCTest
@testable import Burrow

@MainActor
final class CleanViewModelTests: XCTestCase {

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("burrow-vm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
        try super.tearDownWithError()
    }

    // MARK: - Per-group selection

    private func decodeCategories(ids: [String]) throws -> [CleanCategory] {
        let cats = ids.map { id in
            """
            { "id": "\(id)", "title": "\(id)", "summary": "", "group": "developer",
              "icon": "gear", "risk": "low", "defaultEnabled": false,
              "rules": [ { "kind": "directoryContents", "path": "~/x" } ] }
            """
        }.joined(separator: ",")
        return try JSONDecoder().decode([CleanCategory].self, from: Data("[\(cats)]".utf8))
    }

    func testToggleGroupSelectsThenClears() throws {
        let group = try decodeCategories(ids: ["A", "B"])
        let vm = CleanViewModel()
        XCTAssertFalse(vm.isGroupSelected(group))
        vm.toggleGroup(group)
        XCTAssertTrue(vm.isGroupSelected(group))
        XCTAssertEqual(vm.selectedCategoryIds, ["A", "B"])
        vm.toggleGroup(group)
        XCTAssertFalse(vm.isGroupSelected(group))
        XCTAssertTrue(vm.selectedCategoryIds.isEmpty)
    }

    func testToggleGroupFromPartialSelectsRest() throws {
        let group = try decodeCategories(ids: ["A", "B"])
        let vm = CleanViewModel()
        vm.selectedCategoryIds = ["A"]
        XCTAssertFalse(vm.isGroupSelected(group), "partial is not fully selected")
        vm.toggleGroup(group)
        XCTAssertTrue(vm.isGroupSelected(group))
        XCTAssertEqual(vm.selectedCategoryIds, ["A", "B"])
    }

    func testToggleGroupLeavesOtherSelectionsIntact() throws {
        let group = try decodeCategories(ids: ["A", "B"])
        let vm = CleanViewModel()
        vm.selectedCategoryIds = ["Z"]        // belongs to another group
        vm.toggleGroup(group)
        XCTAssertEqual(vm.selectedCategoryIds, ["A", "B", "Z"])
        vm.toggleGroup(group)
        XCTAssertEqual(vm.selectedCategoryIds, ["Z"], "clearing a group must not touch others")
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

    private func syntheticCatalog(defaultEnabled: Bool = true) -> CleanCatalog {
        let cat = CleanCategory(
            id: "test.fixture",
            title: "Test Fixture",
            summary: "Tmpdir scan fixture",
            group: .system,
            icon: "trash",
            risk: .low,
            defaultEnabled: defaultEnabled,
            requiresAppQuit: nil,
            exclude: nil,
            rules: [
                .directoryContents(path: fixture.path, olderThanDays: nil, includeHidden: nil, needsPrivilege: nil),
            ]
        )
        return CleanCatalog(schemaVersion: 1, categories: [cat])
    }

    private func freshLog() -> OperationLog {
        OperationLog(logURL: fixture.appendingPathComponent("log.jsonl"))
    }

    // MARK: - A. loadCatalog

    func testLoadCatalogPopulatesCategoriesFromBundle() async throws {
        let vm = CleanViewModel(log: freshLog())
        XCTAssertTrue(vm.categories.isEmpty, "categories should be empty before loadCatalog")
        await vm.loadCatalog()
        XCTAssertGreaterThan(vm.categories.count, 0, "categories should be populated after loadCatalog")
        XCTAssertNil(vm.lastError, "lastError should be nil after successful loadCatalog")
    }

    func testLoadCatalogPreSelectsDefaultEnabledCategories() async throws {
        let vm = CleanViewModel(log: freshLog())
        await vm.loadCatalog()
        XCTAssertFalse(
            vm.selectedCategoryIds.isEmpty,
            "selectedCategoryIds should be non-empty after loadCatalog (at least browser.chrome is defaultEnabled)"
        )
    }

    // MARK: - B. test convenience init

    func testTestInitPreSelectsDefaultEnabledCategory() throws {
        let catalog = syntheticCatalog(defaultEnabled: true)
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        XCTAssertEqual(vm.categories.count, 1)
        XCTAssertEqual(vm.selectedCategoryIds, ["test.fixture"])
    }

    func testTestInitDoesNotSelectDefaultDisabledCategory() throws {
        let catalog = syntheticCatalog(defaultEnabled: false)
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        XCTAssertTrue(
            vm.selectedCategoryIds.isEmpty,
            "selectedCategoryIds should be empty when defaultEnabled=false"
        )
    }

    // MARK: - C. scan

    func testScanPopulatesScanResults() async throws {
        _ = try makeThreeFiles()
        let catalog = syntheticCatalog(defaultEnabled: true)
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        XCTAssertEqual(vm.scanResults.count, 1)
        let result = try XCTUnwrap(vm.scanResults["test.fixture"])
        XCTAssertEqual(result.items.count, 3)
    }

    func testScanBeforeLoadCatalogSetsLastError() async throws {
        let vm = CleanViewModel(log: freshLog())
        await vm.scan()
        XCTAssertNotNil(vm.lastError, "lastError should be set when scan() called before catalog loaded")
        XCTAssertTrue(vm.scanResults.isEmpty)
    }

    // MARK: - D. apply

    func testApplyDryRunPreservesScanResultsAndSelection() async throws {
        let urls = try makeThreeFiles()
        let catalog = syntheticCatalog(defaultEnabled: true)
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        vm.dryRun = true
        await vm.apply()
        // All 3 files still on disk
        for url in urls {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "dryRun must not remove \(url.lastPathComponent)"
            )
        }
        // Scan results preserved
        XCTAssertEqual(vm.scanResults.count, 1)
        // Selection preserved
        XCTAssertFalse(vm.selectedCategoryIds.isEmpty)
        // Banner surfaces the preview total
        let banner = try XCTUnwrap(vm.previewBanner, "previewBanner should be set after dry run")
        XCTAssertEqual(banner.items, 3)
        XCTAssertGreaterThanOrEqual(banner.bytes, 2600)
    }

    // MARK: - requiresAppQuit

    /// One category that needs `com.example.open` quit, one that needs nothing.
    private func catalogWithAppCategory() throws -> (CleanCatalog, appFile: URL, plainFile: URL) {
        let appDir = fixture.appendingPathComponent("app")
        let plainDir = fixture.appendingPathComponent("plain")
        for dir in [appDir, plainDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let appFile = appDir.appendingPathComponent("cache.bin")
        let plainFile = plainDir.appendingPathComponent("cache.bin")
        try Data(repeating: 0x01, count: 100).write(to: appFile)
        try Data(repeating: 0x02, count: 100).write(to: plainFile)

        func category(_ id: String, _ title: String, quit: String?, dir: URL) -> CleanCategory {
            CleanCategory(
                id: id, title: title, summary: "", group: .system, icon: "trash", risk: .low,
                defaultEnabled: true, requiresAppQuit: quit, exclude: nil,
                rules: [.directoryContents(path: dir.path, olderThanDays: nil, includeHidden: nil, needsPrivilege: nil)]
            )
        }
        let catalog = CleanCatalog(schemaVersion: 1, categories: [
            category("test.app", "Open App", quit: "com.example.open", dir: appDir),
            category("test.plain", "Plain", quit: nil, dir: plainDir),
        ])
        return (catalog, appFile, plainFile)
    }

    func testApplySkipsCategoryWhileItsAppIsOpen() async throws {
        let (catalog, appFile, plainFile) = try catalogWithAppCategory()
        let vm = CleanViewModel(catalog: catalog, log: freshLog(), isAppRunning: { $0 == "com.example.open" })
        await vm.scan()

        await vm.applyAll()

        XCTAssertTrue(FileManager.default.fileExists(atPath: appFile.path), "open app's cache must stay")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plainFile.path))
        XCTAssertEqual(Set(vm.scanResults.keys), ["test.app"], "skipped category stays listed")
        XCTAssertEqual(vm.selectedCategoryIds, ["test.app"], "skipped category stays selected")
    }

    func testApplyAllBannerCountsOnlyWhatRanAndNamesSkippedApps() async throws {
        let (catalog, _, _) = try catalogWithAppCategory()
        let vm = CleanViewModel(catalog: catalog, log: freshLog(), isAppRunning: { $0 == "com.example.open" })
        await vm.scan()
        let plainBytes = try XCTUnwrap(vm.scanResults["test.plain"]).totalBytes

        await vm.applyAll()

        let banner = try XCTUnwrap(vm.previewBanner)
        XCTAssertEqual(banner.items, 1)
        XCTAssertEqual(banner.bytes, plainBytes)
        XCTAssertEqual(banner.skippedApps, ["Open App"])
    }

    func testDryRunAlsoSkipsAndReportsOpenApp() async throws {
        let (catalog, _, _) = try catalogWithAppCategory()
        let vm = CleanViewModel(catalog: catalog, log: freshLog(), isAppRunning: { _ in true })
        await vm.scan()
        vm.dryRun = true

        await vm.applyAll()

        let banner = try XCTUnwrap(vm.previewBanner)
        XCTAssertEqual(banner.items, 1)
        XCTAssertEqual(banner.skippedApps, ["Open App"])
    }

    func testApplyCleansCategoryOnceItsAppIsClosed() async throws {
        let (catalog, appFile, _) = try catalogWithAppCategory()
        let vm = CleanViewModel(catalog: catalog, log: freshLog(), isAppRunning: { _ in false })
        await vm.scan()

        await vm.applyAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: appFile.path))
        XCTAssertEqual(vm.previewBanner?.skippedApps, [])
    }

    func testIsRunningChecksRealApps() {
        XCTAssertTrue(CleanViewModel.isRunning("com.apple.finder"))
        XCTAssertFalse(CleanViewModel.isRunning("com.example.not-installed"))
    }

    func testScanClearsPreviewBanner() async throws {
        _ = try makeThreeFiles()
        let vm = CleanViewModel(catalog: syntheticCatalog(), log: freshLog())
        await vm.scan()
        vm.dryRun = true
        await vm.apply()
        XCTAssertNotNil(vm.previewBanner)

        await vm.scan()
        XCTAssertNil(vm.previewBanner, "fresh scan should drop the prior preview banner")
    }

    func testDismissPreviewBannerClearsIt() async throws {
        _ = try makeThreeFiles()
        let vm = CleanViewModel(catalog: syntheticCatalog(), log: freshLog())
        await vm.scan()
        vm.dryRun = true
        await vm.apply()
        XCTAssertNotNil(vm.previewBanner)

        vm.dismissPreviewBanner()
        XCTAssertNil(vm.previewBanner)
    }

    func testApplyRealClearsScanResultsAndSelection() async throws {
        let urls = try makeThreeFiles()
        let catalog = syntheticCatalog(defaultEnabled: true)
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        vm.dryRun = false
        await vm.apply()
        // All 3 files gone from fixture (trashed)
        for url in urls {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: url.path),
                "\(url.lastPathComponent) should have been trashed"
            )
        }
        // Scan results cleared after real apply
        XCTAssertTrue(vm.scanResults.isEmpty)
        // Selection cleared after real apply
        XCTAssertTrue(vm.selectedCategoryIds.isEmpty)
        // Real apply does not surface a preview banner
        XCTAssertNil(vm.previewBanner)
    }

    func testApplyBeforeLoadCatalogSetsLastError() async throws {
        let vm = CleanViewModel(log: freshLog())
        await vm.apply()
        XCTAssertNotNil(vm.lastError, "lastError should be set when apply() called before catalog loaded")
    }

    // MARK: - E. computed properties

    func testSelectedTotalBytesSumsScannedItems() async throws {
        _ = try makeThreeFiles()
        let catalog = syntheticCatalog(defaultEnabled: true)
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        XCTAssertGreaterThanOrEqual(
            vm.selectedTotalBytes,
            2600,
            "selectedTotalBytes should be at least 2600 (100+500+2000)"
        )
    }

    func testSelectedTotalBytesIsZeroWithoutSelection() async throws {
        _ = try makeThreeFiles()
        let catalog = syntheticCatalog(defaultEnabled: false)
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        XCTAssertEqual(
            vm.selectedTotalBytes,
            0,
            "selectedTotalBytes should be 0 when no categories are selected"
        )
        XCTAssertGreaterThanOrEqual(
            vm.totalReclaimable,
            2600,
            "totalReclaimable should reflect scanned bytes regardless of selection"
        )
    }

    func testSelectedItemCountReflectsSelection() async throws {
        _ = try makeThreeFiles()
        let catalog = syntheticCatalog(defaultEnabled: true)
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        XCTAssertEqual(vm.selectedItemCount, 3)
    }

    func testCategoriesByGroupSortsByGroupRawValue() throws {
        // Build 3 categories with ids that would sort differently from their group rawValues
        let catSystem = CleanCategory(
            id: "zzz.system",
            title: "System Category",
            summary: "In system group",
            group: .system,
            icon: "trash",
            risk: .low,
            defaultEnabled: false,
            requiresAppQuit: nil,
            exclude: nil,
            rules: []
        )
        let catBrowser = CleanCategory(
            id: "aaa.browser",
            title: "Browser Category",
            summary: "In browser group",
            group: .browser,
            icon: "globe",
            risk: .low,
            defaultEnabled: false,
            requiresAppQuit: nil,
            exclude: nil,
            rules: []
        )
        let catDeveloper = CleanCategory(
            id: "mmm.developer",
            title: "Developer Category",
            summary: "In developer group",
            group: .developer,
            icon: "hammer",
            risk: .low,
            defaultEnabled: false,
            requiresAppQuit: nil,
            exclude: nil,
            rules: []
        )
        let catalog = CleanCatalog(schemaVersion: 1, categories: [catSystem, catBrowser, catDeveloper])
        let vm = CleanViewModel(catalog: catalog, log: freshLog())

        let grouped = vm.categoriesByGroup
        XCTAssertEqual(grouped.count, 3, "should have 3 groups")

        // Alphabetical order by rawValue: "browser" < "developer" < "system"
        XCTAssertEqual(grouped[0].group, .browser)
        XCTAssertEqual(grouped[1].group, .developer)
        XCTAssertEqual(grouped[2].group, .system)
    }

    // MARK: - filterInstalled

    func testFilterInstalledKeepsCategoryWhenAtLeastOnePathExists() {
        let present = CleanCategory(
            id: "present", title: "Present", summary: "",
            group: .system, icon: "trash", risk: .low,
            defaultEnabled: true, requiresAppQuit: nil, exclude: nil,
            rules: [
                .directoryContents(path: fixture.path, olderThanDays: nil, includeHidden: nil, needsPrivilege: nil),
                .directoryContents(path: "/this/does/not/exist", olderThanDays: nil, includeHidden: nil, needsPrivilege: nil),
            ]
        )
        let absent = CleanCategory(
            id: "absent", title: "Absent", summary: "",
            group: .browser, icon: "globe", risk: .low,
            defaultEnabled: true, requiresAppQuit: nil, exclude: nil,
            rules: [
                .directoryContents(path: "/no/such/path/at/all", olderThanDays: nil, includeHidden: nil, needsPrivilege: nil),
            ]
        )

        let filtered = CleanViewModel.filterInstalled([present, absent])
        XCTAssertEqual(filtered.map(\.id), ["present"])
    }

    // MARK: - Select all

    func testAllCategoriesSelectedReflectsSelection() {
        let vm = CleanViewModel(catalog: syntheticCatalog(), log: freshLog())
        // Default: defaultEnabled=true so all are selected.
        XCTAssertTrue(vm.allItemsSelected)

        vm.selectedCategoryIds = []
        XCTAssertFalse(vm.allItemsSelected)
    }

    func testToggleSelectAllFlipsBetweenAllAndNone() {
        let vm = CleanViewModel(catalog: syntheticCatalog(), log: freshLog())
        XCTAssertTrue(vm.allItemsSelected, "starts with all selected")

        vm.toggleSelectAll()
        XCTAssertTrue(vm.selectedCategoryIds.isEmpty, "first toggle clears")

        vm.toggleSelectAll()
        XCTAssertTrue(vm.allItemsSelected, "second toggle re-selects all")
    }

    func testToggleSelectAllFromPartialSelectionSelectsAll() {
        // Build a 2-category catalog so partial selection is meaningful.
        let a = CleanCategory(id: "a", title: "A", summary: "", group: .system, icon: "a", risk: .low,
                              defaultEnabled: false, requiresAppQuit: nil, exclude: nil, rules: [])
        let b = CleanCategory(id: "b", title: "B", summary: "", group: .system, icon: "b", risk: .low,
                              defaultEnabled: false, requiresAppQuit: nil, exclude: nil, rules: [])
        let vm = CleanViewModel(catalog: CleanCatalog(schemaVersion: 1, categories: [a, b]), log: freshLog())

        vm.selectedCategoryIds = ["a"]   // partial
        XCTAssertFalse(vm.allItemsSelected)

        vm.toggleSelectAll()
        XCTAssertEqual(vm.selectedCategoryIds, ["a", "b"], "partial → all")
    }

    func testFilterInstalledKeepsCommandRulesUnconditionally() {
        let cmd = CleanCategory(
            id: "cmd", title: "Command", summary: "",
            group: .system, icon: "terminal", risk: .low,
            defaultEnabled: false, requiresAppQuit: nil, exclude: nil,
            rules: [
                .command(exec: "/usr/bin/true", args: nil, needsPrivilege: nil),
            ]
        )
        let filtered = CleanViewModel.filterInstalled([cmd])
        XCTAssertEqual(filtered.map(\.id), ["cmd"],
                       "command rules should never be hidden — we can't probe without running")
    }
}
