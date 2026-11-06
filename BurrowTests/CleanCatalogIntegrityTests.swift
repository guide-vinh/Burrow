import XCTest
@testable import Burrow

/// Guards the bundled `CleanRules.json`, which is hand-merged from Mole.
final class CleanCatalogIntegrityTests: XCTestCase {

    private var categories: [CleanCategory]!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let url = try XCTUnwrap(
            Bundle(for: type(of: self)).url(forResource: "CleanRules", withExtension: "json")
                ?? Bundle.main.url(forResource: "CleanRules", withExtension: "json")
        )
        categories = try RuleEngine.loadCatalog(from: url).categories
    }

    private var paths: [String] {
        categories.flatMap(\.rules).compactMap(\.path)
    }

    func testCategoryIdsAreUnique() {
        let ids = categories.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testEveryCategoryHasRules() {
        for category in categories {
            XCTAssertFalse(category.rules.isEmpty, category.id)
        }
    }

    func testRulesStayOutOfUserDataAndSystemStores() {
        let forbidden = [
            "/Mobile Documents", "/Library/Messages", "/Library/Keychains", "/Library/Mail/",
            "/Library/Accounts", "/Library/Calendars", "/Library/Preferences", "/AddressBook",
            "/Library/Suggestions", "/Saved Application State",
        ]
        for path in paths {
            for fragment in forbidden {
                XCTAssertFalse(path.contains(fragment), path)
            }
        }
    }

    func testRulesNeverTargetAWholeAppDataRoot() {
        let roots = ["~/Library/Caches", "~/Library/Application Support", "~/Library/Containers", "~/.cache", "~"]
        for path in paths {
            XCTAssertFalse(roots.contains(path), path)
            XCTAssertFalse(roots.contains { path == $0 + "/*" }, path)
        }
    }
}
