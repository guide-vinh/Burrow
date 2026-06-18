import XCTest
@testable import Burrow

/// End-to-end integration sweep across DiskScanner → AnalyzeViewModel →
/// TreemapLayout. Verifies the three modules cooperate on a known fixture:
/// a tmpdir with 5 subdirectories and 20 files of varying sizes.
final class AnalyzePipelineTests: XCTestCase {

    // MARK: - Fixture

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("burrow-analyze-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: fixture,
            withIntermediateDirectories: true
        )
        try buildFixtureTree()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
        try super.tearDownWithError()
    }

    /// Layout: 5 subdirs, 20 files total, 4 files per subdir.
    /// Sizes increase with directory index so dirA < dirB < dirC < dirD < dirE.
    /// Each subdir's 4 files have sizes (1, 2, 4, 8) × dirMultiplier KiB.
    private func buildFixtureTree() throws {
        let multipliers: [String: Int] = [
            "dirA": 1, "dirB": 4, "dirC": 16, "dirD": 64, "dirE": 256,
        ]
        let perFile: [Int] = [1, 2, 4, 8]
        for (name, mult) in multipliers {
            for (i, k) in perFile.enumerated() {
                let bytes = k * mult * 1024
                let url = fixture
                    .appendingPathComponent(name)
                    .appendingPathComponent("file\(i).bin")
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data(repeating: 0xCC, count: bytes).write(to: url)
            }
        }
    }

    // MARK: - Pipeline

    func testFullPipelineProducesNonOverlappingTreemap() async throws {
        // 1. Scan the fixture via DiskScanner.
        let scanner = DiskScanner()
        var lastFinished: ScanProgress?
        for try await progress in await scanner.scan(fixture) {
            if progress.phase == .finished {
                lastFinished = progress
            }
        }
        XCTAssertNotNil(lastFinished, "Scan must yield a .finished progress event")
        XCTAssertEqual(lastFinished?.entriesScanned, 25,
                       "Expected 5 dirs + 20 files = 25 entries scanned")

        // 2. Resolve immediate children of the fixture root.
        let children = try await scanner.childrenOf(fixture)
        XCTAssertEqual(children.count, 5, "Fixture has 5 immediate subdirectories")
        XCTAssertTrue(children.allSatisfy { $0.isDirectory },
                      "All immediate children should be directories")

        // 3. Lay them out as a treemap in a 1000×600 bounds.
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let items = children.map { entry in
            TreemapLayout.Item(id: AnyHashable(entry.id), weight: Double(max(entry.size, 1)))
        }
        let rects = TreemapLayout.layout(items: items, in: bounds)
        XCTAssertEqual(rects.count, 5, "Each child should produce exactly one rect")

        // 4. All rects within bounds.
        for rect in rects {
            XCTAssertGreaterThanOrEqual(rect.x, 0)
            XCTAssertGreaterThanOrEqual(rect.y, 0)
            XCTAssertLessThanOrEqual(rect.x + rect.width, bounds.width + 0.001)
            XCTAssertLessThanOrEqual(rect.y + rect.height, bounds.height + 0.001)
        }

        // 5. No overlap (pairwise intersection area must be ~0).
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                let a = CGRect(x: rects[i].x, y: rects[i].y,
                               width: rects[i].width, height: rects[i].height)
                let b = CGRect(x: rects[j].x, y: rects[j].y,
                               width: rects[j].width, height: rects[j].height)
                let intersection = a.intersection(b)
                let area = intersection.width * intersection.height
                XCTAssertLessThan(area, 0.01,
                                  "Rects \(i) and \(j) overlap with area \(area)")
            }
        }
    }

    // MARK: - Largest folders (real `du` end-to-end)

    func testLargestFoldersViaDu() async throws {
        // Run the real du-backed AnalyzeViewModel over the fixture as "home".
        let vm = await AnalyzeViewModel(homeDirectory: fixture)
        await vm.scan()

        let folders = await vm.largestFolders
        XCTAssertGreaterThan(folders.count, 0,
                             "largestFolders should be populated after a successful scan")
        XCTAssertTrue(folders.allSatisfy(\.isDirectory), "only folders")

        // dirE has the highest size multiplier (256 × (1+2+4+8)), so it's the
        // largest top-level folder; dirD is next.
        XCTAssertEqual(folders.first?.name, "dirE",
                       "Largest folder must be dirE (largest fixture multiplier)")
        if folders.count >= 2 {
            XCTAssertEqual(folders[1].name, "dirD", "Second-largest must be dirD")
        }

        // largestFolders must be sorted descending by size.
        for i in 0..<(folders.count - 1) {
            XCTAssertGreaterThanOrEqual(
                folders[i].size, folders[i + 1].size,
                "largestFolders must be sorted descending by size"
            )
        }
    }
}
