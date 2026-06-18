import XCTest
@testable import Burrow

@MainActor
final class AnalyzeViewModelTests: XCTestCase {

    // MARK: - Fixture

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

    // MARK: - Helpers

    private func makeEntry(url: URL, size: Int64 = 100, isDirectory: Bool = true) -> DiskEntry {
        DiskEntry(
            id: UUID(), url: url.standardizedFileURL, parentURL: url.deletingLastPathComponent(),
            name: url.lastPathComponent, size: size, isDirectory: isDirectory,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000), lastAccessedAt: nil, childCount: 0
        )
    }

    /// VM wired with deterministic injected `du` results (no real subprocess).
    private func makeVM(
        home: URL,
        dirs: [URL],
        looseBytes: Int64 = 0,
        folderScans: [URL: DiskUsageScanner.FolderScan] = [:],
        capacity: (total: Int64, free: Int64, name: String)? = (512, 200, "Test HD"),
        applications: Int64 = 0
    ) -> AnalyzeViewModel {
        AnalyzeViewModel(
            capacity: { _ in capacity },
            topLevel: { _ in (dirs.map(\.standardizedFileURL), looseBytes) },
            scanFolder: { url in
                folderScans[url.standardizedFileURL] ?? DiskUsageScanner.FolderScan(total: 0, children: [])
            },
            applicationsSize: { applications },
            homeDirectory: home
        )
    }

    // MARK: - Scan

    func testScanStreamsResultsAndBreakdown() async throws {
        let home = fixture!
        let docs = home.appendingPathComponent("Documents")
        let movies = home.appendingPathComponent("Movies")
        let vm = makeVM(
            home: home,
            dirs: [docs, movies],
            looseBytes: 12,
            folderScans: [
                docs.standardizedFileURL: .init(total: 200, children: [makeEntry(url: docs.appendingPathComponent("Big"), size: 150)]),
                movies.standardizedFileURL: .init(total: 100, children: []),
            ]
        )

        await vm.scan()

        XCTAssertFalse(vm.isScanning)
        XCTAssertTrue(vm.hasResults)
        XCTAssertEqual(vm.storage?.totalBytes, 512)
        XCTAssertEqual(vm.storage?.usedBytes, 312)
        XCTAssertEqual(vm.storage?.volumeName, "Test HD")
        XCTAssertEqual(vm.largestFolders.map(\.name), ["Documents", "Movies"])

        let docsBytes = vm.storage?.categories.first { $0.kind == .documents }?.bytes
        XCTAssertEqual(docsBytes, 200)

        // Top-level folder children are pre-loaded during the scan.
        let docsEntry = makeEntry(url: docs, size: 200)
        XCTAssertEqual(vm.children(of: docsEntry).map(\.name), ["Big"])
    }

    func testCancelStopsScanning() async throws {
        let vm = makeVM(home: fixture!, dirs: [])
        await vm.scan()
        XCTAssertFalse(vm.isScanning)
    }

    // MARK: - makeBreakdown

    func testMakeBreakdownComputesCategoriesAndSumsToTotal() {
        let b = AnalyzeViewModel.makeBreakdown(
            totalBytes: 512, freeBytes: 200, homeTotalBytes: 220,
            applicationsBytes: 86, documentsBytes: 48, photosBytes: 72
        )
        func bytes(_ k: StorageCategoryKind) -> Int64 { b.categories.first { $0.kind == k }?.bytes ?? -1 }
        XCTAssertEqual(b.usedBytes, 312)
        XCTAssertEqual(bytes(.applications), 86)
        XCTAssertEqual(bytes(.documents), 48)
        XCTAssertEqual(bytes(.photos), 72)
        XCTAssertEqual(bytes(.other), 100)   // 220 - 48 - 72
        XCTAssertEqual(bytes(.system), 6)    // 312 - 86 - 220
        XCTAssertEqual(bytes(.free), 200)
        XCTAssertEqual(b.categories.reduce(Int64(0)) { $0 + $1.bytes }, 512)
    }

    func testMakeBreakdownClampsNegativesToZero() {
        let b = AnalyzeViewModel.makeBreakdown(
            totalBytes: 100, freeBytes: 200, homeTotalBytes: 500,
            applicationsBytes: 400, documentsBytes: 0, photosBytes: 0
        )
        XCTAssertEqual(b.freeBytes, 100)
        XCTAssertEqual(b.usedBytes, 0)
        for category in b.categories {
            XCTAssertGreaterThanOrEqual(category.bytes, 0, "\(category.kind) must not be negative")
        }
    }

    // MARK: - Drill-down

    func testLoadChildrenLazilyForDeepFolder() async throws {
        let home = fixture!
        let docs = home.appendingPathComponent("Documents")
        let big = docs.appendingPathComponent("Big")
        let vm = makeVM(
            home: home,
            dirs: [docs],
            folderScans: [
                docs.standardizedFileURL: .init(total: 200, children: [makeEntry(url: big, size: 150)]),
                big.standardizedFileURL: .init(total: 150, children: [
                    makeEntry(url: big.appendingPathComponent("Sub"), size: 120),
                    makeEntry(url: big.appendingPathComponent("note.txt"), size: 30, isDirectory: false),
                ]),
            ]
        )
        await vm.scan()

        let bigEntry = makeEntry(url: big, size: 150)
        XCTAssertTrue(vm.children(of: bigEntry).isEmpty, "deep folder not loaded until expanded")
        await vm.loadChildrenIfNeeded(bigEntry)
        XCTAssertEqual(vm.children(of: bigEntry).map(\.name), ["Sub"], "dirs only, sorted")
    }

    // MARK: - Sort

    func testSortOrderReordersDisplayedFolders() async throws {
        let home = fixture!
        let zebra = home.appendingPathComponent("Zebra")
        let apple = home.appendingPathComponent("Apple")
        let vm = makeVM(
            home: home, dirs: [zebra, apple],
            folderScans: [
                zebra.standardizedFileURL: .init(total: 300, children: []),
                apple.standardizedFileURL: .init(total: 100, children: []),
            ]
        )
        await vm.scan()

        XCTAssertEqual(vm.displayedFolders.map(\.name), ["Zebra", "Apple"], "default by size")
        vm.sortOrder = .byName
        XCTAssertEqual(vm.displayedFolders.map(\.name), ["Apple", "Zebra"])
    }

    // MARK: - moveToTrash

    func testMoveToTrashRemovesFolderFromList() async throws {
        let home = fixture!
        let target = home.appendingPathComponent("BigFolder")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(count: 2048).write(to: target.appendingPathComponent("payload.bin"))

        let vm = makeVM(
            home: home, dirs: [target],
            folderScans: [target.standardizedFileURL: .init(total: 2048, children: [])]
        )
        await vm.scan()
        XCTAssertEqual(vm.largestFolders.map(\.name), ["BigFolder"])

        await vm.moveToTrash(makeEntry(url: target, size: 2048))

        XCTAssertNil(vm.scanError)
        XCTAssertTrue(vm.largestFolders.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
}
