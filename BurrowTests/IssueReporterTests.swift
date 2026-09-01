import XCTest
@testable import Burrow

// NOTE: IssueReporter.open() is intentionally not tested because it launches
// the user's browser. We test the URL builder and diagnostics instead.

final class IssueReporterTests: XCTestCase {

    func testBugURLPointsAtRepoNewIssue() throws {
        let url = try XCTUnwrap(IssueReporter.newIssueURL(.bug))
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/guide-vinh/Burrow/issues/new")
    }

    func testBugURLCarriesBugLabel() throws {
        let url = try XCTUnwrap(IssueReporter.newIssueURL(.bug))
        XCTAssertTrue(url.query?.contains("labels=bug") ?? false)
    }

    func testFeatureURLCarriesEnhancementLabel() throws {
        let url = try XCTUnwrap(IssueReporter.newIssueURL(.feature))
        XCTAssertTrue(url.query?.contains("labels=enhancement") ?? false)
    }

    func testBodyIsPercentEncoded() throws {
        // The template has spaces and newlines; a raw query would break the URL.
        // Restrictive encoding (alphanumerics) means no literal spaces survive.
        let url = try XCTUnwrap(IssueReporter.newIssueURL(.bug))
        let query = try XCTUnwrap(url.query)
        XCTAssertFalse(query.contains(" "))
        XCTAssertFalse(query.contains("\n"))
    }

    func testDiagnosticsIncludeVersionAndModel() {
        let diagnostics = IssueReporter.diagnostics()
        XCTAssertTrue(diagnostics.contains("Burrow:"))
        XCTAssertTrue(diagnostics.contains("macOS:"))
        XCTAssertTrue(diagnostics.contains("Model:"))
    }
}
