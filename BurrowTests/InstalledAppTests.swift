import XCTest
@testable import Burrow

final class InstalledAppTests: XCTestCase {

    private func makeApp(bundleId: String = "com.example.app") -> InstalledApp {
        InstalledApp(
            bundleId: bundleId,
            name: "Example",
            displayName: "Example App",
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app"),
            version: "1.0",
            build: "100",
            bundleSize: 12_345,
            lastOpenedDate: Date(timeIntervalSince1970: 1_730_000_000),
            installSource: .manual
        )
    }

    func testIdentifiableUsesBundleId() {
        let app = makeApp(bundleId: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(app.id, "com.tinyspeck.slackmacgap")
    }

    func testEqualityByValue() {
        let a = makeApp()
        let b = makeApp()
        XCTAssertEqual(a, b)
    }

    func testTwoAppsWithSameBundleIdHashEqual() {
        let a = makeApp(bundleId: "com.same.app")
        let b = makeApp(bundleId: "com.same.app")
        var set = Set<InstalledApp>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1, "same-value apps should collapse in a Set")
    }

    func testInstallSourceRoundTrip() throws {
        for source in [InstallSource.manual, .macAppStore, .homebrewCask] {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(InstallSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
    }
}
