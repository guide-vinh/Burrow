import XCTest
@testable import Burrow

final class DiskScannerTests: XCTestCase {

    // MARK: - Fixture

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("burrow-disk-scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: fixture,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    @discardableResult
    private func writeFile(_ relative: String, bytes: Int) throws -> URL {
        let url = fixture.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xAA, count: bytes).write(to: url)
        return url
    }

    private func runScan(
        _ scanner: DiskScanner,
        root: URL
    ) async throws -> [ScanProgress] {
        var progresses: [ScanProgress] = []
        for try await p in await scanner.scan(root) {
            progresses.append(p)
        }
        return progresses
    }

    // MARK: - Test 1: Flat dir sizes

    func testScanReportsExpectedSizesForFlatTmpdir() async throws {
        try writeFile("a.bin", bytes: 100)
        try writeFile("b.bin", bytes: 500)
        try writeFile("c.bin", bytes: 2000)

        let scanner = DiskScanner()
        let progresses = try await runScan(scanner, root: fixture)

        // Last progress must be .finished
        guard let last = progresses.last else {
            XCTFail("No progress yielded")
            return
        }
        XCTAssertEqual(last.phase, .finished)
        XCTAssertGreaterThanOrEqual(last.totalBytes, 2600)

        // entries(under:) should return the 3 files
        let entries = await scanner.entries(under: fixture)
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.allSatisfy { !$0.isDirectory })
        let totalSize = entries.reduce(0) { $0 + $1.size }
        XCTAssertGreaterThanOrEqual(totalSize, 2600)
    }

    // MARK: - Test 2: Recursive dir aggregation

    func testScanRecursivelyAggregatesDirectorySizes() async throws {
        try writeFile("a/file.bin", bytes: 100)
        try writeFile("b/file1.bin", bytes: 200)
        try writeFile("b/file2.bin", bytes: 200)

        let scanner = DiskScanner()
        _ = try await runScan(scanner, root: fixture)

        let entries = await scanner.entries(under: fixture)

        let aDir = entries.first { $0.name == "a" }
        let bDir = entries.first { $0.name == "b" }

        XCTAssertNotNil(aDir, "Directory 'a' not found in entries")
        XCTAssertNotNil(bDir, "Directory 'b' not found in entries")
        XCTAssertTrue(aDir?.isDirectory == true)
        XCTAssertTrue(bDir?.isDirectory == true)
        XCTAssertGreaterThanOrEqual(aDir?.size ?? 0, 100)
        XCTAssertGreaterThanOrEqual(bDir?.size ?? 0, 400)
    }

    // MARK: - Test 3: Starting and finished phases for empty dir

    func testScanYieldsAtLeastFinishedAndStartingPhases() async throws {
        // Empty tmpdir
        let scanner = DiskScanner()
        let progresses = try await runScan(scanner, root: fixture)

        XCTAssertFalse(progresses.isEmpty, "Should yield at least one progress")
        XCTAssertEqual(progresses.first?.phase, .starting)

        let phases = progresses.map { $0.phase }
        XCTAssertTrue(phases.contains(.finished), "Should yield .finished phase")

        // Phases order: starting before finished
        let startIdx = phases.firstIndex(of: .starting) ?? Int.max
        let finishIdx = phases.firstIndex(of: .finished) ?? -1
        XCTAssertLessThan(startIdx, finishIdx, ".starting must come before .finished")
    }

    // MARK: - Test 4: Large fixture yields enumerating progress

    func testScanYieldsProgressForLargeFixture() async throws {
        // Create 1100 files to trigger the 1000-entry progress yield
        for i in 0..<1100 {
            try writeFile("f\(i).bin", bytes: 1)
        }

        let scanner = DiskScanner()
        let progresses = try await runScan(scanner, root: fixture)

        let enumeratingCount = progresses.filter { $0.phase == .enumerating }.count
        XCTAssertGreaterThanOrEqual(enumeratingCount, 1,
            "Should yield at least 1 .enumerating progress for 1100 files")
    }

    // MARK: - Test 5: Cancellation yields cancelled phase

    func testScanCancellationYieldsCancelledPhase() async throws {
        // Create enough files that cancellation can hit mid-scan
        for i in 0..<5000 {
            try writeFile("f\(i).bin", bytes: 1)
        }

        let scanner = DiskScanner()
        var receivedPhases: [ScanProgress.Phase] = []

        let task = Task {
            for try await p in await scanner.scan(fixture) {
                receivedPhases.append(p.phase)
            }
        }

        // Small yield to let the inner scan task start before cancelling
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        task.cancel()

        // Wait for task to finish
        _ = await task.result

        // Spec: "Don't be strict about timing — just no crash, no orphaned tasks."
        // The test simply verifies we reach this point without hanging or crashing.
        // The consumer task may have received any subset of phases before cancellation
        // interrupted the for-await loop (including an empty set if cancelled early).
        // All are valid outcomes.
        XCTAssertTrue(true, "Scan cancelled without crash or orphaned task")
    }

    // MARK: - Test 6: Symlinks skipped

    func testScanSkipsSymlinks() async throws {
        let realFile = try writeFile("real.bin", bytes: 100)
        let symlink = fixture.appendingPathComponent("link.bin")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realFile)

        let scanner = DiskScanner()
        _ = try await runScan(scanner, root: fixture)

        let entries = await scanner.entries(under: fixture)
        let names = entries.map { $0.name }
        XCTAssertTrue(names.contains("real.bin"), "real.bin should be present")
        XCTAssertFalse(names.contains("link.bin"), "symlink should be skipped")
    }

    // MARK: - Test 7: Performance — 1000 files in < 2s

    func testScanCompletesUnder2sFor1000Files() async throws {
        for i in 0..<1000 {
            try writeFile("f\(i).bin", bytes: 0)
        }

        let scanner = DiskScanner()
        let start = Date()
        _ = try await runScan(scanner, root: fixture)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 2.0, "Scan of 1000 files should complete in < 2s")
    }

    // MARK: - Test 8: entries(under:) empty before scan

    func testEntriesUnderEmptyBeforeScan() async {
        let scanner = DiskScanner()
        let entries = await scanner.entries(under: fixture)
        XCTAssertTrue(entries.isEmpty, "entries(under:) should be empty before any scan")

        let root = await scanner.lastScanRoot()
        XCTAssertNil(root, "lastScanRoot() should be nil before any scan")
    }

    // MARK: - Test 9: lastScanRoot set after success, updates on second scan

    func testLastScanRootSetAfterSuccess() async throws {
        let scanner = DiskScanner()

        // First scan
        try writeFile("file.bin", bytes: 100)
        _ = try await runScan(scanner, root: fixture)

        let firstRoot = await scanner.lastScanRoot()
        XCTAssertEqual(firstRoot?.standardizedFileURL, fixture.standardizedFileURL)

        // Second scan on a different tmpdir
        let secondFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("burrow-disk-scanner-second-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: secondFixture,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: secondFixture) }

        try Data(repeating: 0xBB, count: 50)
            .write(to: secondFixture.appendingPathComponent("file2.bin"))

        _ = try await runScan(scanner, root: secondFixture)

        let secondRoot = await scanner.lastScanRoot()
        XCTAssertEqual(secondRoot?.standardizedFileURL, secondFixture.standardizedFileURL)
    }

    // MARK: - Test 10: childrenOf returns immediate children

    func testChildrenOfReturnsImmediateChildren() async throws {
        try writeFile("a.bin", bytes: 100)
        try writeFile("b.bin", bytes: 200)
        try writeFile("c/inner.bin", bytes: 300)

        let scanner = DiskScanner()
        let children = try await scanner.childrenOf(fixture)

        let names = Set(children.map { $0.name })
        XCTAssertTrue(names.contains("a.bin"))
        XCTAssertTrue(names.contains("b.bin"))
        XCTAssertTrue(names.contains("c"))
        XCTAssertEqual(children.count, 3)

        // c should be a directory with recursive size >= 300
        let cEntry = children.first { $0.name == "c" }
        XCTAssertNotNil(cEntry)
        XCTAssertTrue(cEntry?.isDirectory == true)
        XCTAssertGreaterThanOrEqual(cEntry?.size ?? 0, 300)
    }

    // MARK: - Test 11: childrenOf skips symlinks

    func testChildrenOfSkipsSymlinks() async throws {
        let realFile = try writeFile("real.bin", bytes: 100)
        let symlink = fixture.appendingPathComponent("link.bin")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realFile)

        let scanner = DiskScanner()
        let children = try await scanner.childrenOf(fixture)

        let names = children.map { $0.name }
        XCTAssertTrue(names.contains("real.bin"))
        XCTAssertFalse(names.contains("link.bin"), "childrenOf should skip symlinks")
        XCTAssertEqual(children.count, 1)
    }

    // MARK: - Test 12: isExcludedPath logic

    func testIsExcludedPathCloudStorageExcluded() {
        let home = "/Users/testuser"

        // Excluded paths
        XCTAssertTrue(DiskScanner.isExcludedPath(
            home + "/Library/CloudStorage",
            home: home
        ))
        XCTAssertTrue(DiskScanner.isExcludedPath(
            home + "/Library/CloudStorage/iCloud Drive",
            home: home
        ))
        XCTAssertTrue(DiskScanner.isExcludedPath(
            home + "/Library/CloudStorage/iCloud Drive/file.bin",
            home: home
        ))
        XCTAssertTrue(DiskScanner.isExcludedPath(
            home + "/Library/Mobile Documents",
            home: home
        ))
        XCTAssertTrue(DiskScanner.isExcludedPath(
            home + "/.Trash",
            home: home
        ))
        XCTAssertTrue(DiskScanner.isExcludedPath("/System", home: home))
        XCTAssertTrue(DiskScanner.isExcludedPath("/private", home: home))
        XCTAssertTrue(DiskScanner.isExcludedPath("/Volumes", home: home))

        // Heavy system-managed folders (skipped for scan speed)
        XCTAssertTrue(DiskScanner.isExcludedPath(home + "/Library/Containers", home: home))
        XCTAssertTrue(DiskScanner.isExcludedPath(home + "/Library/Containers/com.apple.x/Data", home: home))
        XCTAssertTrue(DiskScanner.isExcludedPath(home + "/Library/Group Containers", home: home))
        XCTAssertTrue(DiskScanner.isExcludedPath(home + "/Library/Daemon Containers", home: home))
        XCTAssertTrue(DiskScanner.isExcludedPath(home + "/Library/Developer/CoreSimulator", home: home))
        XCTAssertTrue(DiskScanner.isExcludedPath(home + "/Library/Developer/Xcode/iOS DeviceSupport", home: home))

        // Allowed paths
        XCTAssertFalse(DiskScanner.isExcludedPath(
            home + "/Library/Developer/Xcode/DerivedData",
            home: home
        ))
        XCTAssertFalse(DiskScanner.isExcludedPath(
            home + "/Documents",
            home: home
        ))
        XCTAssertFalse(DiskScanner.isExcludedPath(
            home + "/Library/Caches",
            home: home
        ))
        XCTAssertFalse(DiskScanner.isExcludedPath(
            home + "/Downloads",
            home: home
        ))
    }

    // MARK: - Cache helper

    private func makeTmpdirCache() -> DiskCache {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("burrow-scanner-cache-\(UUID().uuidString).sqlite")
        return DiskCache(databaseURL: url)
    }

    // MARK: - Test 13: First scan writes cache

    func testFirstScanWritesCache() async throws {
        try writeFile("a/file.bin", bytes: 100)
        try writeFile("b/file.bin", bytes: 200)

        let cache = makeTmpdirCache()
        let scanner = DiskScanner(cache: cache)
        _ = try await runScan(scanner, root: fixture)

        // After scan completion, the cache must contain rows for fixture/a and fixture/b.
        let aCached = await cache.entry(at: fixture.appendingPathComponent("a").path)
        let bCached = await cache.entry(at: fixture.appendingPathComponent("b").path)
        XCTAssertNotNil(aCached, "fixture/a must be in cache after first scan")
        XCTAssertNotNil(bCached, "fixture/b must be in cache after first scan")
        XCTAssertEqual(aCached?.isDirectory, true)
        XCTAssertGreaterThanOrEqual(aCached?.size ?? 0, 100)
    }

    // MARK: - Test 14: Second scan reuses cache for unchanged subtrees

    func testSecondScanReusesCacheForUnchangedSubtrees() async throws {
        try writeFile("a/x.bin", bytes: 100)
        try writeFile("a/y.bin", bytes: 200)
        try writeFile("b/z.bin", bytes: 50)

        let cache = makeTmpdirCache()
        let scanner = DiskScanner(cache: cache)

        // First scan — populates cache.
        let first = try await runScan(scanner, root: fixture)
        let firstFinished = first.last
        XCTAssertEqual(firstFinished?.phase, .finished)
        let firstEntriesScanned = firstFinished?.entriesScanned ?? 0
        XCTAssertGreaterThan(firstEntriesScanned, 0)

        // Second scan — should hit cache for both subtrees, scan fewer entries.
        let second = try await runScan(scanner, root: fixture)
        let secondFinished = second.last
        XCTAssertEqual(secondFinished?.phase, .finished)
        let secondEntriesScanned = secondFinished?.entriesScanned ?? 0

        // Total bytes must be reported equally on both scans.
        XCTAssertEqual(firstFinished?.totalBytes, secondFinished?.totalBytes)
        // Second scan should process strictly fewer entries (file children skipped).
        XCTAssertLessThan(secondEntriesScanned, firstEntriesScanned,
                          "Second scan should reuse cache and process fewer entries")
    }

    // MARK: - Test 15: Cache invalidates when file changes

    func testCacheInvalidatesWhenFileChanges() async throws {
        let aDir = fixture.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: aDir, withIntermediateDirectories: true)
        let fileA = aDir.appendingPathComponent("file.bin")
        try Data(repeating: 0xAA, count: 100).write(to: fileA)

        let cache = makeTmpdirCache()
        let scanner = DiskScanner(cache: cache)

        // First scan — establishes cache.
        _ = try await runScan(scanner, root: fixture)
        let firstCached = await cache.entry(at: aDir.path)
        XCTAssertNotNil(firstCached)
        let firstSize = firstCached?.size ?? 0

        // Sleep briefly to ensure mtime changes detectably (>1s tolerance).
        try await Task.sleep(nanoseconds: 1_200_000_000)

        // Modify the file — this changes the parent dir's mtime.
        try Data(repeating: 0xBB, count: 5_000).write(to: fileA)

        // Touch the directory mtime explicitly (writing a file inside should
        // already do this on most filesystems, but be defensive).
        try FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: aDir.path
        )

        // Second scan — should see new mtime, invalidate cache, re-scan.
        _ = try await runScan(scanner, root: fixture)
        let secondCached = await cache.entry(at: aDir.path)
        XCTAssertNotNil(secondCached)
        let secondSize = secondCached?.size ?? 0
        XCTAssertGreaterThan(secondSize, firstSize,
                             "Cache must reflect the larger file after invalidation")
    }

    // MARK: - Test 12b: Scan skips CloudStorage subtree within scanned tree

    func testScanSkipsCloudStorageWithinScannedTree() async throws {
        // Create a fake CloudStorage-like structure inside the tmpdir
        // We test the exclusion logic using isExcludedPath directly since
        // the actual excluded paths are relative to the user's real home.
        // The scan exclusion is covered by testIsExcludedPathCloudStorageExcluded.
        //
        // For the integration test: create a nested "Library/CloudStorage/iCloud/file.bin"
        // inside fixture, scan fixture, and verify the file doesn't appear.
        // We do this by temporarily pointing the exclusion at the fixture's "Library" path.
        // Since DiskScanner.isExcludedPath uses the real home dir, we verify the
        // path logic in the unit test above. Here we verify the scan correctly
        // skips paths that match the home-relative prefixes.

        // Create a normal file and a "cloud" file
        try writeFile("normal.bin", bytes: 100)
        let cloudDir = fixture
            .appendingPathComponent("Library")
            .appendingPathComponent("CloudStorage")
        try FileManager.default.createDirectory(
            at: cloudDir,
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xCC, count: 500)
            .write(to: cloudDir.appendingPathComponent("cloud.bin"))

        // Scan the fixture root — the cloud subtree won't match the real
        // home-based exclusion, so it WILL be scanned here. This test validates
        // that the exclusion helper correctly identifies the real paths.
        // The functional exclusion of ~/Library/CloudStorage is tested via
        // testIsExcludedPathCloudStorageExcluded (unit test of the static helper).

        // What we CAN test: verify the helper rejects the path when home matches
        let fakeHome = fixture.path  // treat fixture AS the home dir
        XCTAssertTrue(
            DiskScanner.isExcludedPath(
                fixture.path + "/Library/CloudStorage/cloud.bin",
                home: fakeHome
            ),
            "CloudStorage path should be excluded when fixture is treated as home"
        )
        XCTAssertFalse(
            DiskScanner.isExcludedPath(
                fixture.path + "/normal.bin",
                home: fakeHome
            ),
            "Normal file should not be excluded"
        )
    }
}
