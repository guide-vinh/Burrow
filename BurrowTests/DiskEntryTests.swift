import XCTest
@testable import Burrow

final class DiskEntryTests: XCTestCase {

    // MARK: - Helpers

    private func makeEntry(
        id: UUID = UUID(),
        url: URL = URL(fileURLWithPath: "/tmp/fixture"),
        parentURL: URL? = nil,
        name: String = "fixture",
        size: Int64 = 1024,
        isDirectory: Bool = false,
        modifiedAt: Date = Date(),
        lastAccessedAt: Date? = nil,
        childCount: Int = 0
    ) -> DiskEntry {
        DiskEntry(
            id: id,
            url: url,
            parentURL: parentURL,
            name: name,
            size: size,
            isDirectory: isDirectory,
            modifiedAt: modifiedAt,
            lastAccessedAt: lastAccessedAt,
            childCount: childCount
        )
    }

    // MARK: - Hash / Equality

    /// Two DiskEntry constructed with all-equal fields (including same UUID) hash
    /// to the same bucket and are ==. Two with different UUIDs but otherwise
    /// identical are NOT equal.
    func testHashEqualityIsValueBased() {
        let sharedID = UUID()
        let sharedDate = Date(timeIntervalSince1970: 0)
        let sharedURL = URL(fileURLWithPath: "/tmp/test-path")

        let a = makeEntry(
            id: sharedID,
            url: sharedURL,
            name: "file",
            size: 512,
            modifiedAt: sharedDate
        )
        let b = makeEntry(
            id: sharedID,
            url: sharedURL,
            name: "file",
            size: 512,
            modifiedAt: sharedDate
        )

        XCTAssertEqual(a, b, "Entries with identical fields must be equal")
        XCTAssertEqual(a.hashValue, b.hashValue, "Equal entries must share the same hash")

        let differentID = UUID()
        let c = makeEntry(
            id: differentID,
            url: sharedURL,
            name: "file",
            size: 512,
            modifiedAt: sharedDate
        )

        XCTAssertNotEqual(a, c, "Entries with different UUIDs must not be equal")
    }

    // MARK: - Identifiable

    /// The Identifiable id is the stored UUID.
    func testIdentifiableUsesUUID() {
        let uuid = UUID()
        let entry = makeEntry(id: uuid)
        XCTAssertEqual(entry.id, uuid)
    }

    // MARK: - colorComponents

    /// Same url.path → identical (h, s, b) tuple.
    func testColorComponentsDeterministic() {
        let url = URL(fileURLWithPath: "/Users/vinh/Library/Caches/Foo")
        let entry1 = makeEntry(url: url)
        let entry2 = makeEntry(url: url)

        let c1 = entry1.colorComponents
        let c2 = entry2.colorComponents

        XCTAssertEqual(c1.hue,        c2.hue,        accuracy: 0.0001)
        XCTAssertEqual(c1.saturation, c2.saturation, accuracy: 0.0001)
        XCTAssertEqual(c1.brightness, c2.brightness, accuracy: 0.0001)
    }

    /// For an arbitrary fixture path, components stay within spec ranges.
    func testColorComponentsBoundedRanges() {
        let url = URL(fileURLWithPath: "/Users/vinh/Documents/Project/README.md")
        let entry = makeEntry(url: url)
        let c = entry.colorComponents

        XCTAssertGreaterThanOrEqual(c.hue,        0.0)
        XCTAssertLessThanOrEqual(c.hue,           1.0)
        XCTAssertGreaterThanOrEqual(c.saturation,  0.45)
        XCTAssertLessThanOrEqual(c.saturation,     0.70)
        XCTAssertGreaterThanOrEqual(c.brightness,  0.62)
        XCTAssertLessThanOrEqual(c.brightness,     0.80)
    }

    /// Smoke test: colorSeed wrapper (Color from components) is callable
    /// without crashing. We don't assert Color value equality because
    /// SwiftUI.Color has no reliable Equatable on macOS 12.
    func testColorSeedIsCallable() {
        let entry = makeEntry(url: URL(fileURLWithPath: "/tmp/colorSeed-fixture"))
        _ = entry.colorSeed
    }

    /// ~/Foo and ~/Bar produce different tuples (at least one component differs).
    func testColorComponentsDifferForDifferentPaths() {
        let urlFoo = URL(fileURLWithPath: "/Users/vinh/Foo")
        let urlBar = URL(fileURLWithPath: "/Users/vinh/Bar")

        let entryFoo = makeEntry(url: urlFoo)
        let entryBar = makeEntry(url: urlBar)

        let cFoo = entryFoo.colorComponents
        let cBar = entryBar.colorComponents

        let anyComponentDiffers =
            abs(cFoo.hue        - cBar.hue)        > 0.0001 ||
            abs(cFoo.saturation - cBar.saturation) > 0.0001 ||
            abs(cFoo.brightness - cBar.brightness) > 0.0001

        XCTAssertTrue(anyComponentDiffers, "Different paths must produce different color components")
    }

    // MARK: - humanSize

    /// humanSize returns non-empty localized strings.
    /// For size > 0, the result contains digits.
    /// For size == 0, ByteCountFormatter may return a word like "Zero KB"
    /// (locale-dependent) — just assert non-empty.
    func testHumanSizeFormatsBytes() {
        let zeroEntry = makeEntry(size: 0)
        XCTAssertFalse(zeroEntry.humanSize.isEmpty, "humanSize must not be empty for size 0")

        let nonZeroSizes: [Int64] = [1_024, 1_048_576, 5_368_709_120]
        for size in nonZeroSizes {
            let entry = makeEntry(size: size)
            let formatted = entry.humanSize
            XCTAssertFalse(formatted.isEmpty, "humanSize must not be empty for size \(size)")
            let hasDigit = formatted.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
            XCTAssertTrue(hasDigit, "humanSize '\(formatted)' must contain at least one digit for size \(size)")
        }
    }

    /// Result for 1024 bytes contains "1" or "K", proving the formatter ran.
    func testHumanSizeIsLocaleAware() {
        let entry = makeEntry(size: 1_024)
        let formatted = entry.humanSize
        let containsOneOrK = formatted.contains("1") || formatted.contains("K") || formatted.contains("k")
        XCTAssertTrue(containsOneOrK, "humanSize '\(formatted)' for 1024 bytes should contain '1' or 'K'")
    }
}
