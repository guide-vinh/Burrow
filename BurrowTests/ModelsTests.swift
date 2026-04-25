import XCTest
@testable import Burrow

final class ModelsTests: XCTestCase {

    // MARK: - CleanRule decoding

    func testDecodeDirectoryContentsRule() throws {
        let json = #"""
        {"kind":"directoryContents","path":"~/Library/Caches/Foo","olderThanDays":7}
        """#.data(using: .utf8)!

        let rule = try JSONDecoder().decode(CleanRule.self, from: json)
        guard case let .directoryContents(path, days, hidden, priv) = rule else {
            return XCTFail("expected .directoryContents, got \(rule)")
        }
        XCTAssertEqual(path, "~/Library/Caches/Foo")
        XCTAssertEqual(days, 7)
        XCTAssertNil(hidden)
        XCTAssertNil(priv)
    }

    func testDecodeGlobRule() throws {
        let json = #"""
        {"kind":"glob","path":"~/Developer/*/node_modules"}
        """#.data(using: .utf8)!

        let rule = try JSONDecoder().decode(CleanRule.self, from: json)
        guard case let .glob(path, _, _, _) = rule else {
            return XCTFail("expected .glob, got \(rule)")
        }
        XCTAssertEqual(path, "~/Developer/*/node_modules")
    }

    func testDecodeCommandRule() throws {
        let json = #"""
        {"kind":"command","exec":"/opt/homebrew/bin/brew","args":["cleanup","--prune=all"],"needsPrivilege":false}
        """#.data(using: .utf8)!

        let rule = try JSONDecoder().decode(CleanRule.self, from: json)
        guard case let .command(exec, args, priv) = rule else {
            return XCTFail("expected .command, got \(rule)")
        }
        XCTAssertEqual(exec, "/opt/homebrew/bin/brew")
        XCTAssertEqual(args, ["cleanup", "--prune=all"])
        XCTAssertEqual(priv, false)
    }

    func testDecodeUnknownRuleKindThrows() {
        let json = #"""
        {"kind":"sorcery","path":"/tmp"}
        """#.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(CleanRule.self, from: json)) { err in
            guard case DecodingError.dataCorrupted = err else {
                return XCTFail("expected DecodingError.dataCorrupted, got \(err)")
            }
        }
    }

    func testCleanRuleRoundTrip() throws {
        let original = CleanRule.directoryContents(
            path: "~/Library/Caches/Foo",
            olderThanDays: 14,
            includeHidden: true,
            needsPrivilege: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CleanRule.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Bundled catalog

    func testBundledCleanRulesDecodes() throws {
        let url = try XCTUnwrap(
            Bundle(for: type(of: self)).url(forResource: "CleanRules", withExtension: "json")
                ?? Bundle.main.url(forResource: "CleanRules", withExtension: "json"),
            "CleanRules.json must be in the app bundle"
        )
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(CleanCatalog.self, from: data)

        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertFalse(catalog.categories.isEmpty)

        // Spot-check the seeded chrome category.
        let chrome = try XCTUnwrap(
            catalog.categories.first { $0.id == "browser.chrome" },
            "expected seeded browser.chrome category"
        )
        XCTAssertEqual(chrome.group, .browser)
        XCTAssertEqual(chrome.risk, .low)
        XCTAssertEqual(chrome.requiresAppQuit, "com.google.Chrome")
    }
}
