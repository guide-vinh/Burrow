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

    // MARK: - Failures

    /// Two categories in temp dirs: "good" (one file) and "bad" (two files).
    /// After a scan, deleting a "bad" file makes `SafeFileOps.validate`
    /// reject it (doesNotExist) before anything is mutated.
    private func catalogForFailures() throws -> (CleanCatalog, goodFile: URL, badKept: URL, badGone: URL) {
        let goodDir = fixture.appendingPathComponent("good")
        let badDir = fixture.appendingPathComponent("bad")
        for dir in [goodDir, badDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let goodFile = goodDir.appendingPathComponent("cache.bin")
        let badKept = badDir.appendingPathComponent("a.bin")
        let badGone = badDir.appendingPathComponent("b.bin")
        try Data(repeating: 0x01, count: 100).write(to: goodFile)
        try Data(repeating: 0x02, count: 200).write(to: badKept)
        try Data(repeating: 0x03, count: 400).write(to: badGone)

        func category(_ id: String, dir: URL) -> CleanCategory {
            CleanCategory(
                id: id, title: id, summary: "", group: .system, icon: "trash", risk: .low,
                defaultEnabled: true, requiresAppQuit: nil, exclude: nil,
                rules: [.directoryContents(path: dir.path, olderThanDays: nil, includeHidden: nil, needsPrivilege: nil)]
            )
        }
        let catalog = CleanCatalog(schemaVersion: 1, categories: [
            category("test.good", dir: goodDir),
            category("test.bad", dir: badDir),
        ])
        return (catalog, goodFile, badKept, badGone)
    }

    /// Replaces `url` (after the scan) with a symlink into the running app
    /// bundle. `SafeFileOps.validate` resolves symlinks for the bundle check
    /// and throws `protectedPath` BEFORE anything is mutated, so a real apply
    /// fails for that item without touching it or the bundle. The guard below
    /// proves that before any apply can run.
    private func makeUnremovable(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: Bundle.main.bundleURL)
        XCTAssertThrowsError(try SafeFileOps.validate(url), "precondition: validate must reject the link", file: file, line: line) { error in
            guard case SafeFileError.protectedPath = error else {
                return XCTFail("expected protectedPath, got \(error)", file: file, line: line)
            }
        }
    }

    func testVanishedItemIsNotAFailure() async throws {
        let (catalog, goodFile, badKept, badGone) = try catalogForFailures()
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        let goodBytes = try XCTUnwrap(vm.scanResults["test.good"]).totalBytes
        let keptBytes = try XCTUnwrap(vm.scanResults["test.bad"]?.items.first { $0.url.lastPathComponent == "a.bin" }).bytes
        try FileManager.default.removeItem(at: badGone)

        await vm.applyAll()

        XCTAssertNil(vm.lastError, "a file that is already gone is the outcome the user wanted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: goodFile.path))
        let banner = try XCTUnwrap(vm.previewBanner)
        XCTAssertEqual(banner.items, 2, "the vanished item is not counted")
        XCTAssertEqual(banner.bytes, goodBytes + keptBytes)
        XCTAssertTrue(vm.scanResults.isEmpty, "category with a vanished leftover clears normally")
        XCTAssertTrue(vm.selectedCategoryIds.isEmpty)
    }

    func testEverythingVanishedClearsWithoutErrorOrBanner() async throws {
        let (catalog, goodFile, badKept, badGone) = try catalogForFailures()
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        for url in [goodFile, badKept, badGone] { try FileManager.default.removeItem(at: url) }

        await vm.applyAll()

        XCTAssertNil(vm.lastError)
        XCTAssertNil(vm.previewBanner, "nothing was done, so no success banner")
        XCTAssertTrue(vm.scanResults.isEmpty)
        XCTAssertTrue(vm.selectedCategoryIds.isEmpty)
    }

    func testApplyAllPartialFailureCountsOnlySuccessesAndKeepsFailedCategory() async throws {
        let (catalog, goodFile, badKept, badGone) = try catalogForFailures()
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        let goodBytes = try XCTUnwrap(vm.scanResults["test.good"]).totalBytes
        let badItems = try XCTUnwrap(vm.scanResults["test.bad"]).items
        let keptBytes = try XCTUnwrap(badItems.first { $0.url.lastPathComponent == "a.bin" }).bytes
        let goneBytes = try XCTUnwrap(badItems.first { $0.url.lastPathComponent == "b.bin" }).bytes
        try makeUnremovable(badGone)

        await vm.applyAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: goodFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: badKept.path), "the item that could be trashed still is")
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: badGone.path), "the refused link was left alone")
        let banner = try XCTUnwrap(vm.previewBanner)
        XCTAssertEqual(banner.items, 2, "good file + the surviving file; the failed one is not counted")
        XCTAssertEqual(banner.bytes, goodBytes + keptBytes)
        let error = try XCTUnwrap(vm.lastError)
        XCTAssertTrue(error.hasPrefix("Couldn't clean 1 item."), error)
        XCTAssertTrue(error.contains("b.bin is protected"), "first reason names the file: \(error)")
        XCTAssertFalse(error.contains("test.bad"), "no raw category ids")

        XCTAssertNil(vm.scanResults["test.good"], "clean category is cleared despite the other failing")
        XCTAssertFalse(vm.selectedCategoryIds.contains("test.good"))
        let remaining = try XCTUnwrap(vm.scanResults["test.bad"], "failed category stays listed")
        XCTAssertEqual(remaining.items.map(\.url.lastPathComponent), ["b.bin"], "shrunk to the failed item")
        XCTAssertEqual(remaining.totalBytes, goneBytes, "sizes shown are for what is left")
        XCTAssertTrue(vm.selectedCategoryIds.contains("test.bad"), "failed category stays selected")
    }

    func testApplyAllWhereEverythingFailsShowsErrorAndNoSuccessBanner() async throws {
        let (catalog, goodFile, badKept, badGone) = try catalogForFailures()
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        for url in [goodFile, badKept, badGone] { try makeUnremovable(url) }

        await vm.applyAll()

        XCTAssertNil(vm.previewBanner, "no success banner when nothing succeeded")
        let error = try XCTUnwrap(vm.lastError)
        XCTAssertTrue(error.hasPrefix("Couldn't clean 3 items."), error)
        XCTAssertEqual(Set(vm.scanResults.keys), ["test.good", "test.bad"], "nothing was cleaned, nothing cleared")
        XCTAssertEqual(vm.selectedCategoryIds, ["test.good", "test.bad"])
    }

    func testApplyAloneSurfacesFailures() async throws {
        let (catalog, _, _, badGone) = try catalogForFailures()
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        try makeUnremovable(badGone)

        await vm.apply()

        XCTAssertTrue(try XCTUnwrap(vm.lastError).hasPrefix("Couldn't clean 1 item."))
        XCTAssertNotNil(vm.scanResults["test.bad"])
        XCTAssertNil(vm.scanResults["test.good"])
    }

    func testDismissErrorClearsIt() async throws {
        let (catalog, _, _, badGone) = try catalogForFailures()
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        try makeUnremovable(badGone)
        await vm.applyAll()
        XCTAssertNotNil(vm.lastError)

        vm.dismissError()

        XCTAssertNil(vm.lastError)
    }

    func testFailedCategoryCleansOnRetryAndNewRunClearsOldError() async throws {
        let (catalog, _, badKept, badGone) = try catalogForFailures()
        let vm = CleanViewModel(catalog: catalog, log: freshLog())
        await vm.scan()
        try makeUnremovable(badGone)
        await vm.applyAll()
        XCTAssertNotNil(vm.lastError)
        XCTAssertNotNil(vm.scanResults["test.bad"])

        // The obstacle goes away (a real file is back), so the retry works.
        try FileManager.default.removeItem(at: badGone)
        try Data(repeating: 0x03, count: 400).write(to: badGone)
        await vm.applyAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: badGone.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: badKept.path))
        XCTAssertNil(vm.lastError, "a new run clears the previous run's error")
        XCTAssertNil(vm.scanResults["test.bad"], "category fails in one run, succeeds in the next")
        XCTAssertTrue(vm.selectedCategoryIds.isEmpty)
        XCTAssertEqual(vm.previewBanner?.items, 1)
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
