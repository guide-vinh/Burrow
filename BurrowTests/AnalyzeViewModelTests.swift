import XCTest
@testable import Burrow

@MainActor
final class AnalyzeViewModelTests: XCTestCase {

    // MARK: - Fixture setup

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("burrow-analyze-vm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
        try super.tearDownWithError()
    }

    // MARK: - Helper: make a DiskEntry

    private func makeEntry(
        url: URL,
        size: Int64 = 100,
        isDirectory: Bool = false,
        modifiedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        lastAccessedAt: Date? = nil
    ) -> DiskEntry {
        DiskEntry(
            id: UUID(),
            url: url,
            parentURL: url.deletingLastPathComponent(),
            name: url.lastPathComponent,
            size: size,
            isDirectory: isDirectory,
            modifiedAt: modifiedAt,
            lastAccessedAt: lastAccessedAt,
            childCount: 0
        )
    }

    /// Build an AsyncThrowingStream that yields the given progresses then finishes.
    private func progressStream(_ items: [ScanProgress]) -> AsyncThrowingStream<ScanProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for p in items {
                    continuation.yield(p)
                }
                continuation.finish()
            }
        }
    }

    private func makeProgress(phase: ScanProgress.Phase) -> ScanProgress {
        ScanProgress(
            phase: phase,
            entriesScanned: 0,
            totalBytes: 0,
            currentPath: nil,
            elapsed: 0
        )
    }

    // MARK: - 1. Scan populates entries on finish

    func testScanPopulatesEntriesOnFinish() async throws {
        let home = fixture
        let entries = [
            makeEntry(url: home!.appendingPathComponent("a.txt"), size: 100),
            makeEntry(url: home!.appendingPathComponent("b.txt"), size: 200),
            makeEntry(url: home!.appendingPathComponent("c.txt"), size: 300),
        ]

        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([
                    self.makeProgress(phase: .starting),
                    self.makeProgress(phase: .enumerating),
                    self.makeProgress(phase: .finished),
                ])
            },
            loadChildren: { _ in entries },
            homeDirectory: home!
        )

        await vm.scan()

        XCTAssertEqual(vm.visibleEntries.count, 3)
        XCTAssertEqual(vm.currentRoot, home)
        XCTAssertEqual(vm.breadcrumb, [home!])
        XCTAssertFalse(vm.isScanning)
        XCTAssertNil(vm.scanError)
    }

    // MARK: - 2. Scan cancelled leaves state clean

    func testScanCancelledLeavesStateClean() async throws {
        let home = fixture!

        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([
                    self.makeProgress(phase: .starting),
                    self.makeProgress(phase: .cancelled),
                ])
            },
            loadChildren: { _ in [] },
            homeDirectory: home
        )

        await vm.scan()

        XCTAssertFalse(vm.isScanning)
        XCTAssertTrue(vm.visibleEntries.isEmpty)
        XCTAssertNil(vm.scanError, "Cancellation is not an error")
    }

    // MARK: - 3. Scan error sets scanError

    func testScanErrorSetsScanError() async throws {
        struct TestError: Error { }

        let vm = AnalyzeViewModel(
            startScan: { _ in
                AsyncThrowingStream { continuation in
                    Task {
                        continuation.yield(ScanProgress(
                            phase: .starting,
                            entriesScanned: 0,
                            totalBytes: 0,
                            currentPath: nil,
                            elapsed: 0
                        ))
                        continuation.finish(throwing: TestError())
                    }
                }
            },
            loadChildren: { _ in [] },
            homeDirectory: self.fixture!
        )

        await vm.scan()

        XCTAssertNotNil(vm.scanError)
        XCTAssertFalse(vm.isScanning)
    }

    // MARK: - 4. topLargest returns top 5 by size

    func testTopLargestReturnsTop5BySize() async throws {
        let home = fixture!
        let sizes: [Int64] = [1, 5, 3, 9, 2, 7, 4]
        let entries = sizes.enumerated().map { idx, size in
            makeEntry(url: home.appendingPathComponent("file\(idx).txt"), size: size)
        }

        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([self.makeProgress(phase: .finished)])
            },
            loadChildren: { _ in entries },
            homeDirectory: home
        )

        await vm.scan()

        XCTAssertEqual(vm.topLargest.count, 5)
        XCTAssertEqual(vm.topLargest.map(\.size), [9, 7, 5, 4, 3])
    }

    // MARK: - 5. oldestNeverOpened degrades gracefully when atime is missing

    func testOldestNeverOpenedDegradesGracefullyWhenAtimeMissing() async throws {
        let home = fixture!
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        // All entries have lastAccessedAt == modifiedAt (within 1 second)
        let entries = (0..<5).map { i in
            makeEntry(
                url: home.appendingPathComponent("file\(i).txt"),
                modifiedAt: baseDate,
                lastAccessedAt: baseDate  // exactly equal
            )
        }

        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([self.makeProgress(phase: .finished)])
            },
            loadChildren: { _ in entries },
            homeDirectory: home
        )

        await vm.scan()

        XCTAssertFalse(vm.atimeAvailable)
        XCTAssertTrue(vm.oldestNeverOpened.isEmpty)
    }

    // MARK: - 6. oldestNeverOpened returns top 5 by access ascending

    func testOldestNeverOpenedReturnsTop5ByAccessAscending() async throws {
        let home = fixture!
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let modDate = Date(timeIntervalSince1970: 1_000_000_000) // much older mtime

        // 7 entries with distinct lastAccessedAt that differ significantly from modifiedAt
        let accessOffsets: [TimeInterval] = [100, 500, 200, 800, 300, 700, 400]
        let entries = accessOffsets.enumerated().map { idx, offset in
            makeEntry(
                url: home.appendingPathComponent("file\(idx).txt"),
                modifiedAt: modDate,
                lastAccessedAt: baseDate.addingTimeInterval(offset)
            )
        }

        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([self.makeProgress(phase: .finished)])
            },
            loadChildren: { _ in entries },
            homeDirectory: home
        )

        await vm.scan()

        XCTAssertTrue(vm.atimeAvailable)
        XCTAssertEqual(vm.oldestNeverOpened.count, 5)

        // Should be sorted ascending by lastAccessedAt (oldest first)
        let accessDates = vm.oldestNeverOpened.compactMap(\.lastAccessedAt)
        XCTAssertEqual(accessDates.count, 5)
        for i in 0..<accessDates.count - 1 {
            XCTAssertLessThanOrEqual(accessDates[i], accessDates[i + 1],
                "oldestNeverOpened should be sorted ascending by lastAccessedAt")
        }
        // Smallest 5 offsets: 100, 200, 300, 400, 500
        XCTAssertEqual(accessDates.first, baseDate.addingTimeInterval(100))
    }

    // MARK: - 7. zoomInto directory appends breadcrumb

    func testZoomIntoDirectoryAppendsBreadcrumb() async throws {
        let home = fixture!
        let sub = home.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let dirEntry = makeEntry(url: sub, isDirectory: true)

        var loadedURL: URL?
        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([self.makeProgress(phase: .finished)])
            },
            loadChildren: { url in
                loadedURL = url
                return []
            },
            homeDirectory: home
        )

        // Seed state after scan
        await vm.scan()
        XCTAssertEqual(vm.breadcrumb, [home])
        XCTAssertEqual(vm.currentRoot, home)

        // Reset loadedURL after scan (scan also calls loadChildren)
        loadedURL = nil

        await vm.zoomInto(dirEntry)

        XCTAssertEqual(vm.breadcrumb, [home, sub])
        XCTAssertEqual(vm.currentRoot, sub)
        XCTAssertEqual(loadedURL, sub)
    }

    // MARK: - 8. zoomInto file is no-op

    func testZoomIntoFileIsNoOp() async throws {
        let home = fixture!
        let fileEntry = makeEntry(url: home.appendingPathComponent("file.txt"), isDirectory: false)

        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([self.makeProgress(phase: .finished)])
            },
            loadChildren: { _ in [] },
            homeDirectory: home
        )

        await vm.scan()

        let breadcrumbBefore = vm.breadcrumb
        let rootBefore = vm.currentRoot

        await vm.zoomInto(fileEntry)

        XCTAssertEqual(vm.breadcrumb, breadcrumbBefore)
        XCTAssertEqual(vm.currentRoot, rootBefore)
    }

    // MARK: - 9. zoomOut pops breadcrumb

    func testZoomOutPopsBreadcrumb() async throws {
        let home = fixture!
        let a = home.appendingPathComponent("a")
        let b = a.appendingPathComponent("b")

        // Create directories so loadChildren can be called
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)

        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([self.makeProgress(phase: .finished)])
            },
            loadChildren: { _ in [] },
            homeDirectory: home
        )

        await vm.scan()

        // Manually build up breadcrumb [home, a, b]
        let dirA = makeEntry(url: a, isDirectory: true)
        let dirB = makeEntry(url: b, isDirectory: true)
        await vm.zoomInto(dirA)
        await vm.zoomInto(dirB)

        XCTAssertEqual(vm.breadcrumb, [home, a, b])

        await vm.zoomOut()

        XCTAssertEqual(vm.breadcrumb, [home, a])
        XCTAssertEqual(vm.currentRoot, a)
    }

    // MARK: - 10. zoomOut at root is no-op

    func testZoomOutAtRootIsNoOp() async throws {
        let home = fixture!

        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([self.makeProgress(phase: .finished)])
            },
            loadChildren: { _ in [] },
            homeDirectory: home
        )

        await vm.scan()

        XCTAssertEqual(vm.breadcrumb, [home])

        await vm.zoomOut()

        XCTAssertEqual(vm.breadcrumb, [home])
        XCTAssertEqual(vm.currentRoot, home)
    }

    // MARK: - 11. navigate to middle segment truncates

    func testNavigateToMiddleSegmentTruncates() async throws {
        let home = fixture!
        let a = home.appendingPathComponent("a")
        let b = a.appendingPathComponent("b")
        let c = b.appendingPathComponent("c")

        // Create directories so loadChildren can descend
        try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)

        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([self.makeProgress(phase: .finished)])
            },
            loadChildren: { _ in [] },
            homeDirectory: home
        )

        await vm.scan()

        let dirA = makeEntry(url: a, isDirectory: true)
        let dirB = makeEntry(url: b, isDirectory: true)
        let dirC = makeEntry(url: c, isDirectory: true)
        await vm.zoomInto(dirA)
        await vm.zoomInto(dirB)
        await vm.zoomInto(dirC)

        XCTAssertEqual(vm.breadcrumb, [home, a, b, c])

        await vm.navigate(to: a)

        XCTAssertEqual(vm.breadcrumb, [home, a])
        XCTAssertEqual(vm.currentRoot, a)
    }

    // MARK: - 12. moveToTrash removes from visibleEntries

    func testMoveToTrashRemovesFromVisibleEntries() async throws {
        let home = fixture!
        let fileURL = home.appendingPathComponent("deleteme.txt")
        try Data(repeating: 0xAA, count: 100).write(to: fileURL)

        let entry = makeEntry(url: fileURL)

        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([self.makeProgress(phase: .finished)])
            },
            loadChildren: { _ in [entry] },
            homeDirectory: home
        )

        await vm.scan()
        XCTAssertEqual(vm.visibleEntries.count, 1)

        await vm.moveToTrash(entry)

        XCTAssertFalse(vm.visibleEntries.contains(where: { $0.url == fileURL }),
            "Entry should be removed from visibleEntries after trash")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
            "File should be gone from disk (in Trash)")
    }

    // MARK: - 13. moveToTrash sets error on protected path

    func testMoveToTrashSetsErrorOnProtectedPath() async throws {
        let home = fixture!

        // /System is in the SafeFileOps deny-list
        let protectedEntry = makeEntry(url: URL(fileURLWithPath: "/System"))

        let vm = AnalyzeViewModel(
            startScan: { _ in
                self.progressStream([self.makeProgress(phase: .finished)])
            },
            loadChildren: { _ in [protectedEntry] },
            homeDirectory: home
        )

        await vm.scan()
        XCTAssertEqual(vm.visibleEntries.count, 1)

        await vm.moveToTrash(protectedEntry)

        XCTAssertNotNil(vm.scanError, "scanError should be set for protected path")
        XCTAssertEqual(vm.visibleEntries.count, 1, "Entry must NOT be removed on failure")
    }

    // MARK: - 14. cancelScan cancels in-flight task

    func testCancelScanCancelsInFlightTask() async throws {
        let home = fixture!

        let expectation = expectation(description: "scan task completes after cancel")

        let vm = AnalyzeViewModel(
            startScan: { _ in
                AsyncThrowingStream { continuation in
                    // Keep a reference to the inner task so we can cancel it
                    // when the stream consumer (the VM) is cancelled.
                    let innerTask = Task {
                        continuation.yield(ScanProgress(
                            phase: .starting,
                            entriesScanned: 0,
                            totalBytes: 0,
                            currentPath: nil,
                            elapsed: 0
                        ))
                        // Simulate a long-running scan that sleeps forever
                        do {
                            try await Task.sleep(nanoseconds: 60_000_000_000)
                        } catch {
                            // CancellationError — finish the stream cooperatively
                            continuation.finish()
                        }
                    }
                    // When the consumer abandons the stream, cancel the inner task.
                    continuation.onTermination = { _ in
                        innerTask.cancel()
                        expectation.fulfill()
                    }
                }
            },
            loadChildren: { _ in [] },
            homeDirectory: home
        )

        // Spawn scan in background — don't await it here
        let scanTask = Task {
            await vm.scan()
        }

        // Give the scan task time to start and yield the first item
        try await Task.sleep(nanoseconds: 100_000_000)

        // Cancel via the VM — this should propagate cancellation to the stream
        vm.cancelScan()

        // Cancel the outer task too so the for-await loop terminates
        scanTask.cancel()

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertFalse(vm.isScanning, "isScanning should be false after cancel")
    }
}
