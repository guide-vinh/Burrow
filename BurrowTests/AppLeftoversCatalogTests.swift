import XCTest
@testable import Burrow

final class AppLeftoversCatalogTests: XCTestCase {

    private func loadBundledCatalog() throws -> AppLeftoversCatalog {
        let url = try XCTUnwrap(
            Bundle(for: type(of: self)).url(forResource: "AppLeftovers", withExtension: "json")
                ?? Bundle.main.url(forResource: "AppLeftovers", withExtension: "json"),
            "AppLeftovers.json must be in the app bundle"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppLeftoversCatalog.self, from: data)
    }

    // MARK: - Top-level shape

    func testBundledCatalogDecodes() throws {
        let catalog = try loadBundledCatalog()
        XCTAssertEqual(catalog.schemaVersion, 2)
        XCTAssertEqual(catalog.userPaths.count, 38)
        XCTAssertEqual(catalog.systemPaths.count, 19)
    }

    // MARK: - vendorOverrides _doc filtering

    func testVendorOverridesFiltersUnderscoreKeys() throws {
        let catalog = try loadBundledCatalog()
        XCTAssertEqual(
            catalog.vendorOverrides.count, 7,
            "expected 7 real vendors after _doc filter (Adobe, Microsoft, JetBrains, Chrome, Firefox, Spotify, Docker)"
        )
        XCTAssertNil(catalog.vendorOverrides["_doc"], "_doc must not appear")
        XCTAssertNil(catalog.vendorOverrides["_documentation"], "_documentation must not appear")
    }

    func testVendorOverridesContainExpectedVendors() throws {
        let catalog = try loadBundledCatalog()
        for key in ["com.adobe.", "com.microsoft.", "com.jetbrains.",
                    "com.google.Chrome", "org.mozilla.firefox",
                    "com.spotify.client", "com.docker."] {
            XCTAssertNotNil(catalog.vendorOverrides[key], "missing vendor key \(key)")
        }
    }

    func testAdobeVendorEntryShape() throws {
        let catalog = try loadBundledCatalog()
        let adobe = try XCTUnwrap(catalog.vendorOverrides["com.adobe."])
        XCTAssertEqual(adobe.displayName, "Adobe")
        XCTAssertGreaterThanOrEqual(adobe.paths.count, 4)
        XCTAssertNotNil(adobe.warning, "Adobe entry has the shared-resource warning")
    }

    // MARK: - Pattern enums

    func testAllMatchTypesAppearInCatalog() throws {
        let catalog = try loadBundledCatalog()
        let allPatterns = catalog.userPaths + catalog.systemPaths +
            catalog.vendorOverrides.values.flatMap(\.paths)
        let matchTypes = Set(allPatterns.map(\.matchType))
        XCTAssertEqual(matchTypes,
                       [.exact, .prefix, .containsBundleId, .glob, .nestedName],
                       "every matchType from the schema docs should appear in v2")
    }

    func testAllRiskValuesAppearInCatalog() throws {
        let catalog = try loadBundledCatalog()
        let allPatterns = catalog.userPaths + catalog.systemPaths +
            catalog.vendorOverrides.values.flatMap(\.paths)
        let risks = Set(allPatterns.map(\.risk))
        XCTAssertEqual(risks, [.safe, .caution, .highValue])
    }

    // MARK: - Config blocks

    func testIgnoreAppsAndDetectionBlocksLoad() throws {
        let catalog = try loadBundledCatalog()
        XCTAssertFalse(catalog.ignoreApps.patterns.isEmpty)
        XCTAssertTrue(catalog.ignoreApps.patterns.contains("com.apple.*"))
        XCTAssertFalse(catalog.homebrewDetection.caskroomPrefixes.isEmpty)
        XCTAssertEqual(catalog.macAppStoreDetection.receiptPath, "Contents/_MASReceipt/receipt")
    }

    // MARK: - Round-trip resilience

    func testEncodeDecodeRoundTripPreservesData() throws {
        let original = try loadBundledCatalog()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppLeftoversCatalog.self, from: encoded)
        XCTAssertEqual(decoded.schemaVersion, original.schemaVersion)
        XCTAssertEqual(decoded.userPaths.count, original.userPaths.count)
        XCTAssertEqual(decoded.systemPaths.count, original.systemPaths.count)
        XCTAssertEqual(Set(decoded.vendorOverrides.keys), Set(original.vendorOverrides.keys))
    }
}
