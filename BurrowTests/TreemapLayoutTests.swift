import CoreGraphics
import XCTest

@testable import Burrow

final class TreemapLayoutTests: XCTestCase {

    // MARK: - 1. Empty input

    func testEmptyItemsReturnsEmpty() {
        let result = TreemapLayout.layout(items: [], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(result.isEmpty, "Empty item list should produce empty layout")
    }

    // MARK: - 2. Zero-area bounds

    func testZeroBoundsReturnsEmpty() {
        let item = TreemapLayout.Item(id: "a", weight: 10)
        XCTAssertTrue(
            TreemapLayout.layout(items: [item], in: .zero).isEmpty,
            "CGRect.zero bounds should produce empty layout"
        )
        XCTAssertTrue(
            TreemapLayout.layout(items: [item], in: CGRect(x: 0, y: 0, width: 0, height: 100)).isEmpty,
            "Zero-width bounds should produce empty layout"
        )
        XCTAssertTrue(
            TreemapLayout.layout(items: [item], in: CGRect(x: 0, y: 0, width: 100, height: 0)).isEmpty,
            "Zero-height bounds should produce empty layout"
        )
    }

    // MARK: - 3. Non-positive weights are filtered out

    func testNonPositiveWeightsAreFilteredOut() {
        let items = [
            TreemapLayout.Item(id: "zero", weight: 0),
            TreemapLayout.Item(id: "negative", weight: -5),
            TreemapLayout.Item(id: "positive", weight: 10),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = TreemapLayout.layout(items: items, in: bounds)
        XCTAssertEqual(result.count, 1, "Only the positive-weight item should appear")
        XCTAssertEqual(result[0].id, AnyHashable("positive"))
    }

    func testAllNonPositiveWeightsReturnsEmpty() {
        let items = [
            TreemapLayout.Item(id: "a", weight: 0),
            TreemapLayout.Item(id: "b", weight: -1),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(TreemapLayout.layout(items: items, in: bounds).isEmpty)
    }

    // MARK: - 4. Single item fills bounds

    func testSingleItemFillsBounds() {
        let bounds = CGRect(x: 5, y: 10, width: 200, height: 150)
        let item = TreemapLayout.Item(id: "solo", weight: 42)
        let result = TreemapLayout.layout(items: [item], in: bounds)
        XCTAssertEqual(result.count, 1)
        let rect = result[0]
        XCTAssertEqual(rect.id, AnyHashable("solo"))
        XCTAssertEqual(rect.x, Double(bounds.origin.x), accuracy: 0.001)
        XCTAssertEqual(rect.y, Double(bounds.origin.y), accuracy: 0.001)
        XCTAssertEqual(rect.width, Double(bounds.width), accuracy: 0.001)
        XCTAssertEqual(rect.height, Double(bounds.height), accuracy: 0.001)
    }

    // MARK: - 5. Total area ≈ bounds area (within 0.1%)

    func testTotalAreaApproximatelyEqualsBounds() {
        // 10 items with varied weights (not random — deterministic for reproducibility).
        let weights: [Double] = [500, 300, 200, 150, 100, 80, 60, 40, 20, 10]
        let items = weights.enumerated().map { TreemapLayout.Item(id: $0.offset, weight: $0.element) }
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let result = TreemapLayout.layout(items: items, in: bounds)

        let expectedArea = Double(bounds.width) * Double(bounds.height)
        let actualArea = result.reduce(0.0) { $0 + $1.width * $1.height }
        let tolerance = expectedArea * 0.001  // 0.1%
        XCTAssertEqual(actualArea, expectedArea, accuracy: tolerance,
            "Total rect area should match bounds area within 0.1%")
        XCTAssertEqual(result.count, items.count)
    }

    // MARK: - 6. No overlap (50 items)

    func testNoOverlap() {
        let weights: [Double] = (1...50).map { Double($0 * 7 + 13) }  // deterministic, varied
        let items = weights.enumerated().map { TreemapLayout.Item(id: $0.offset, weight: $0.element) }
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 400)
        let result = TreemapLayout.layout(items: items, in: bounds)

        for i in 0..<result.count {
            for j in (i + 1)..<result.count {
                let a = result[i]
                let b = result[j]
                let overlapW = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
                let overlapH = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
                let overlapArea = overlapW * overlapH
                XCTAssertEqual(overlapArea, 0, accuracy: 0.001,
                    "Rects \(i) and \(j) overlap with area \(overlapArea)")
            }
        }
    }

    // MARK: - 7. All rects within bounds

    func testAllRectsWithinBounds() {
        let weights: [Double] = (1...30).map { Double($0 * 11 + 5) }
        let items = weights.enumerated().map { TreemapLayout.Item(id: $0.offset, weight: $0.element) }
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 250)
        let result = TreemapLayout.layout(items: items, in: bounds)

        let bx = Double(bounds.origin.x)
        let by = Double(bounds.origin.y)
        let bRight = bx + Double(bounds.width)
        let bBottom = by + Double(bounds.height)
        let epsilon = 0.001

        for rect in result {
            XCTAssertGreaterThanOrEqual(rect.x, bx - epsilon,
                "Rect x=\(rect.x) is left of bounds origin \(bx)")
            XCTAssertGreaterThanOrEqual(rect.y, by - epsilon,
                "Rect y=\(rect.y) is above bounds origin \(by)")
            XCTAssertLessThanOrEqual(rect.x + rect.width, bRight + epsilon,
                "Rect right=\(rect.x + rect.width) exceeds bounds right \(bRight)")
            XCTAssertLessThanOrEqual(rect.y + rect.height, bBottom + epsilon,
                "Rect bottom=\(rect.y + rect.height) exceeds bounds bottom \(bBottom)")
        }
    }

    // MARK: - 8. Deterministic output

    func testDeterministic() {
        let items = [
            TreemapLayout.Item(id: "a", weight: 100),
            TreemapLayout.Item(id: "b", weight: 200),
            TreemapLayout.Item(id: "c", weight: 50),
            TreemapLayout.Item(id: "d", weight: 75),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let first  = TreemapLayout.layout(items: items, in: bounds)
        let second = TreemapLayout.layout(items: items, in: bounds)
        XCTAssertEqual(first, second, "Same input must produce identical output")
    }

    // MARK: - 9. Sorted by weight descending (largest weight → largest area)

    func testSortedByWeightDescending() {
        let items = [
            TreemapLayout.Item(id: 1, weight: 1),
            TreemapLayout.Item(id: 2, weight: 2),
            TreemapLayout.Item(id: 3, weight: 3),
            TreemapLayout.Item(id: 4, weight: 4),
            TreemapLayout.Item(id: 5, weight: 5),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let result = TreemapLayout.layout(items: items, in: bounds)

        // Build a map from id → area.
        var areaById: [AnyHashable: Double] = [:]
        for rect in result {
            areaById[rect.id] = rect.width * rect.height
        }

        // The item with weight 5 must have the largest area.
        let area5 = areaById[AnyHashable(5)] ?? 0
        let area1 = areaById[AnyHashable(1)] ?? 0
        XCTAssertGreaterThan(area5, area1,
            "Item with weight 5 should have larger area than item with weight 1")

        // Confirm monotonicity: area should be non-decreasing with weight.
        for w in 1...4 {
            let areaW   = areaById[AnyHashable(w)]   ?? 0
            let areaWp1 = areaById[AnyHashable(w + 1)] ?? 0
            XCTAssertLessThanOrEqual(areaW, areaWp1 + 0.001,
                "Item weight \(w) area (\(areaW)) should be ≤ weight \(w+1) area (\(areaWp1))")
        }
    }

    // MARK: - 10. Extreme weight ratio (1000:1:1)

    func testExtremeWeightRatio() {
        let items = [
            TreemapLayout.Item(id: "big",    weight: 1000),
            TreemapLayout.Item(id: "small1", weight: 1),
            TreemapLayout.Item(id: "small2", weight: 1),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let result = TreemapLayout.layout(items: items, in: bounds)

        let totalArea = 1_000_000.0
        var areaById: [AnyHashable: Double] = [:]
        for rect in result {
            areaById[rect.id] = rect.width * rect.height
        }

        // The big item must hold ≥ 99% of total area.
        let bigArea = areaById[AnyHashable("big")] ?? 0
        XCTAssertGreaterThanOrEqual(bigArea / totalArea, 0.99,
            "1000-weight item should occupy ≥ 99% of area, got \(bigArea / totalArea * 100)%")

        // Small items must each have positive area OR be absent.
        // (Per spec, they may be dropped if sub-pixel in BOTH axes.)
        for key in ["small1", "small2"] as [String] {
            if let a = areaById[AnyHashable(key)] {
                XCTAssertGreaterThan(a, 0, "Small item '\(key)' present but has zero area")
            }
            // Absence is also acceptable per spec.
        }
    }

    // MARK: - 11. Large item count (performance)

    func testLargeItemCount() {
        // 500 deterministic weights
        let items = (0..<500).map { i in
            TreemapLayout.Item(id: i, weight: Double((i % 97) + 1) * Double((i % 13) + 1))
        }
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        let start = Date()
        let result = TreemapLayout.layout(items: items, in: bounds)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.1, "layout(500 items) must complete under 100 ms, took \(elapsed * 1000) ms")
        // All 500 items must have positive weights → all 500 should appear.
        XCTAssertEqual(result.count, 500, "Expected 500 rects for 500 positive-weight items")
    }

    // MARK: - Additional edge case: two equal-weight items

    func testTwoEqualWeightItems() {
        let items = [
            TreemapLayout.Item(id: "a", weight: 50),
            TreemapLayout.Item(id: "b", weight: 50),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let result = TreemapLayout.layout(items: items, in: bounds)
        XCTAssertEqual(result.count, 2)

        let areaA = result.first(where: { $0.id == AnyHashable("a") }).map { $0.width * $0.height } ?? 0
        let areaB = result.first(where: { $0.id == AnyHashable("b") }).map { $0.width * $0.height } ?? 0
        XCTAssertEqual(areaA, areaB, accuracy: 0.01,
            "Equal-weight items should have equal areas")
    }
}
