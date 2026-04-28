import XCTest
@testable import Burrow

final class BreadcrumbTests: XCTestCase {

    // MARK: - Fixtures

    private let root      = URL(fileURLWithPath: "/")
    private let users     = URL(fileURLWithPath: "/Users")
    private let vinh      = URL(fileURLWithPath: "/Users/vinh")
    private let library   = URL(fileURLWithPath: "/Users/vinh/Library")
    private let appSupport = URL(fileURLWithPath: "/Users/vinh/Library/Application Support")
    private let burrow    = URL(fileURLWithPath: "/Users/vinh/Library/Application Support/Burrow")
    private let logs      = URL(fileURLWithPath: "/Users/vinh/Library/Application Support/Burrow/Logs")
    private let year2026  = URL(fileURLWithPath: "/Users/vinh/Library/Application Support/Burrow/Logs/2026")

    // MARK: - Tests

    /// Empty input returns an empty array.
    func testEllipsizeEmptyPath() {
        let result = Breadcrumb.ellipsize(path: [], maxVisible: 4)
        XCTAssertTrue(result.isEmpty, "ellipsize with empty path must return empty array")
    }

    /// path.count == 3, maxVisible == 4 — no ellipsis needed; all 3 non-nil URLs returned in order.
    func testEllipsizeShortPathNotEllipsized() {
        let path = [root, users, vinh]
        let result = Breadcrumb.ellipsize(path: path, maxVisible: 4)

        XCTAssertEqual(result.count, 3, "Short path should not add extra slots")
        XCTAssertEqual(result[0], root)
        XCTAssertEqual(result[1], users)
        XCTAssertEqual(result[2], vinh)
        XCTAssertFalse(result.contains(where: { $0 == nil }), "No nil slots expected for short path")
    }

    /// path.count == 4, maxVisible == 4 — exactly at boundary, returns 4 non-nil URLs.
    func testEllipsizeAtBoundaryNotEllipsized() {
        let path = [root, users, vinh, library]
        let result = Breadcrumb.ellipsize(path: path, maxVisible: 4)

        XCTAssertEqual(result.count, 4, "At-boundary path should return 4 slots")
        XCTAssertEqual(result[0], root)
        XCTAssertEqual(result[1], users)
        XCTAssertEqual(result[2], vinh)
        XCTAssertEqual(result[3], library)
        XCTAssertFalse(result.contains(where: { $0 == nil }), "No nil slots expected at boundary")
    }

    /// path.count == 8, maxVisible == 4 — must have exactly one nil slot, keep first + last 2, 4 visual slots total.
    func testEllipsizeLongPathEllipsized() {
        let path = [root, users, vinh, library, appSupport, burrow, logs, year2026]
        let result = Breadcrumb.ellipsize(path: path, maxVisible: 4)

        XCTAssertEqual(result.count, 4, "Ellipsized result must have 4 visual slots")

        let nilCount = result.filter { $0 == nil }.count
        XCTAssertEqual(nilCount, 1, "Ellipsized result must contain exactly one nil (ellipsis) slot")

        XCTAssertEqual(result[0], root,     "First slot must be first segment")
        XCTAssertNil(result[1],             "Second slot must be the nil ellipsis")
        XCTAssertEqual(result[2], logs,     "Third slot must be second-to-last segment")
        XCTAssertEqual(result[3], year2026, "Fourth slot must be last segment")
    }

    /// For path.count == 6, maxVisible == 4 — the last two URLs must appear at the end of the output.
    func testEllipsizeKeepsLastTwoSegments() {
        let path = [root, users, vinh, library, appSupport, burrow]
        let result = Breadcrumb.ellipsize(path: path, maxVisible: 4)

        XCTAssertEqual(result.count, 4, "Ellipsized result must have 4 visual slots")
        // last two from input: appSupport, burrow
        XCTAssertEqual(result[result.count - 2], appSupport, "Second-to-last output must be second-to-last input")
        XCTAssertEqual(result[result.count - 1], burrow,     "Last output must be last input")
    }

    /// For any ellipsized result, result.first! equals path.first.
    func testEllipsizeKeepsFirstSegment() {
        let path = [root, users, vinh, library, appSupport]
        let result = Breadcrumb.ellipsize(path: path, maxVisible: 4)

        XCTAssertNotNil(result.first, "Result must not be empty")
        XCTAssertEqual(result.first!, root, "First slot of ellipsized result must equal first segment of input path")
    }

    /// path.count == maxVisible — returns all segments with no ellipsis.
    func testEllipsizeMaxVisibleEqualsPathCount() {
        let path = [root, users, vinh, library, appSupport]
        let result = Breadcrumb.ellipsize(path: path, maxVisible: path.count)

        XCTAssertEqual(result.count, path.count, "Result count must equal path count when maxVisible == path.count")
        XCTAssertFalse(result.contains(where: { $0 == nil }), "No nil slots when maxVisible equals path count")
        for (index, url) in path.enumerated() {
            XCTAssertEqual(result[index], url, "Segment at index \(index) must match input")
        }
    }
}
