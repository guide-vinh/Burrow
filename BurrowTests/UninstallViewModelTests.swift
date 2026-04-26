import XCTest
@testable import Burrow

@MainActor
final class UninstallViewModelTests: XCTestCase {

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("burrow-uninstall-vm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeApp(
        bundleId: String = "com.example.test",
        name: String = "Test",
        bundleURL: URL? = nil
    ) -> InstalledApp {
        InstalledApp(
            bundleId: bundleId, name: name, displayName: nil,
            bundleURL: bundleURL ?? URL(fileURLWithPath: "/Applications/\(name).app"),
            version: "1.0", build: "1",
            bundleSize: nil, lastOpenedDate: nil, installSource: .manual
        )
    }

    private func makePattern(
        risk: LeftoverPattern.Risk = .safe,
        needsPrivilege: Bool? = nil
    ) -> LeftoverPattern {
        // Build via JSON decode since LeftoverPattern has no memberwise init.
        var json: [String: Any] = [
            "path": "/dummy",
            "matchType": "exact",
            "risk": risk.rawValue,
            "category": "test",
            "description": "test"
        ]
        if let np = needsPrivilege {
            json["needsPrivilege"] = np
        }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(LeftoverPattern.self, from: data)
    }

    private func makeMatch(
        url: URL,
        bytes: Int64 = 100,
        risk: LeftoverPattern.Risk = .safe,
        needsPrivilege: Bool? = nil,
        isShared: Bool = false
    ) -> LeftoverMatch {
        LeftoverMatch(
            url: url, bytes: bytes,
            pattern: makePattern(risk: risk, needsPrivilege: needsPrivilege),
            isShared: isShared
        )
    }

    private func freshLog() -> OperationLog {
        OperationLog(logURL: fixture.appendingPathComponent("log.jsonl"))
    }

    private func writeFile(_ relative: String, bytes: Int = 100) throws -> URL {
        let url = fixture.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xAA, count: bytes).write(to: url)
        return url
    }

    // MARK: - 1. Discovery: loadApps calls discoverApps closure

    func testLoadAppsCallsDiscoverClosure() async throws {
        let apps = [
            makeApp(bundleId: "com.a", name: "Alpha"),
            makeApp(bundleId: "com.b", name: "Beta"),
            makeApp(bundleId: "com.c", name: "Gamma"),
        ]
        let vm = UninstallViewModel(
            discoverApps: { apps },
            findLeftovers: { _ in [] },
            log: freshLog()
        )
        await vm.loadApps()
        XCTAssertEqual(vm.apps.count, 3)
        let names = vm.apps.map(\.name)
        XCTAssertTrue(names.contains("Alpha"))
        XCTAssertTrue(names.contains("Beta"))
        XCTAssertTrue(names.contains("Gamma"))
    }

    // MARK: - 2. Selection: select calls findLeftovers and populates state

    func testSelectAppCallsFindLeftoversAndPopulates() async throws {
        let app = makeApp(bundleId: "com.example", name: "Example")
        let leftoverURLs = (0..<4).map { fixture.appendingPathComponent("leftover\($0).dat") }
        let matches = leftoverURLs.map { makeMatch(url: $0) }

        let vm = UninstallViewModel(
            discoverApps: { [app] },
            findLeftovers: { _ in matches },
            log: freshLog()
        )
        await vm.loadApps()
        await vm.select(vm.apps.first)
        XCTAssertEqual(vm.leftovers.count, 4)
        XCTAssertNotNil(vm.selectedApp)
    }

    // MARK: - 3. Default checked URLs respect risk and shared flags

    func testDefaultCheckedRespectsRiskAndShared() async throws {
        let safeURL = fixture.appendingPathComponent("safe.dat")
        let cautionURL = fixture.appendingPathComponent("caution.dat")
        let highValueURL = fixture.appendingPathComponent("highvalue.dat")
        let sharedURL = fixture.appendingPathComponent("shared.dat")
        let privilegedURL = fixture.appendingPathComponent("privileged.dat")
        let appBundleURL = fixture.appendingPathComponent("TestApp.app")

        // Create the .app bundle directory so bundleURL is real
        try FileManager.default.createDirectory(at: appBundleURL, withIntermediateDirectories: true)

        let matches: [LeftoverMatch] = [
            makeMatch(url: safeURL, risk: .safe),
            makeMatch(url: cautionURL, risk: .caution),
            makeMatch(url: highValueURL, risk: .highValue),
            makeMatch(url: sharedURL, risk: .safe, isShared: true),
            makeMatch(url: privilegedURL, risk: .safe, needsPrivilege: true),
        ]

        let app = makeApp(bundleId: "com.test.app", name: "TestApp", bundleURL: appBundleURL)
        let vm = UninstallViewModel(
            discoverApps: { [app] },
            findLeftovers: { _ in matches },
            log: freshLog()
        )
        await vm.loadApps()
        await vm.select(vm.apps.first)

        // Expected checked: .app bundle + safe + caution = 3
        XCTAssertEqual(vm.checkedURLs.count, 3)
        XCTAssertTrue(vm.checkedURLs.contains(appBundleURL), ".app bundle must be checked")
        XCTAssertTrue(vm.checkedURLs.contains(safeURL), "safe risk must be checked")
        XCTAssertTrue(vm.checkedURLs.contains(cautionURL), "caution risk must be checked")
        XCTAssertFalse(vm.checkedURLs.contains(highValueURL), "highValue risk must NOT be checked")
        XCTAssertFalse(vm.checkedURLs.contains(sharedURL), "shared must NOT be checked")
        XCTAssertFalse(vm.checkedURLs.contains(privilegedURL), "needsPrivilege must NOT be checked")
    }

    // MARK: - 4. Search: filtered apps are case-insensitive

    func testFilteredAppsCaseInsensitive() async throws {
        let apps = [
            makeApp(bundleId: "com.slack", name: "Slack"),
            makeApp(bundleId: "com.notion", name: "Notion"),
            makeApp(bundleId: "com.discord", name: "Discord"),
        ]
        let vm = UninstallViewModel(
            discoverApps: { apps },
            findLeftovers: { _ in [] },
            log: freshLog()
        )
        await vm.loadApps()
        vm.searchQuery = "NOT"
        XCTAssertEqual(vm.filteredApps.count, 1)
        XCTAssertEqual(vm.filteredApps.first?.name, "Notion")
    }

    // MARK: - 5. Search: empty query returns all apps

    func testFilteredAppsEmptyQueryReturnsAll() async throws {
        let apps = [
            makeApp(bundleId: "com.slack", name: "Slack"),
            makeApp(bundleId: "com.notion", name: "Notion"),
            makeApp(bundleId: "com.discord", name: "Discord"),
        ]
        let vm = UninstallViewModel(
            discoverApps: { apps },
            findLeftovers: { _ in [] },
            log: freshLog()
        )
        await vm.loadApps()
        vm.searchQuery = ""
        XCTAssertEqual(vm.filteredApps.count, 3)
        vm.searchQuery = "   "
        XCTAssertEqual(vm.filteredApps.count, 3)
    }

    // MARK: - 6. Uninstall dry run preserves files and shows banner

    func testUninstallDryRunPreservesFilesAndShowsBanner() async throws {
        let file1 = try writeFile("leftover1.dat", bytes: 200)
        let file2 = try writeFile("leftover2.dat", bytes: 300)
        let appBundle = try writeFile("TestApp.app/Contents/Info.plist", bytes: 50)
        let appBundleURL = fixture.appendingPathComponent("TestApp.app")

        let matches = [
            makeMatch(url: file1, bytes: 200),
            makeMatch(url: file2, bytes: 300),
        ]
        let app = makeApp(bundleId: "com.test.app", name: "TestApp", bundleURL: appBundleURL)
        let vm = UninstallViewModel(
            discoverApps: { [app] },
            findLeftovers: { _ in matches },
            log: freshLog()
        )
        await vm.loadApps()
        await vm.select(vm.apps.first)
        // Ensure all 3 are checked: appBundle + 2 leftovers
        vm.checkedURLs = [file1, file2, appBundleURL]
        vm.dryRun = true
        await vm.uninstall()

        // Files still exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path), "file1 must not be removed in dry run")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2.path), "file2 must not be removed in dry run")
        XCTAssertTrue(FileManager.default.fileExists(atPath: appBundleURL.path), "app bundle must not be removed in dry run")

        // Banner appears
        let banner = try XCTUnwrap(vm.previewBanner, "previewBanner should be set after dry run")
        XCTAssertEqual(banner.items, 3)
        XCTAssertGreaterThanOrEqual(banner.bytes, 500, "bytes should be at least 500 (200+300)")

        // State preserved
        XCTAssertEqual(vm.leftovers.count, 2)
        XCTAssertEqual(vm.checkedURLs.count, 3)

        // Suppress unused variable warning
        _ = appBundle
    }

    // MARK: - 7. Uninstall real trashes files and clears state

    func testUninstallRealTrashesFilesAndClearsState() async throws {
        let file1 = try writeFile("leftover1.dat", bytes: 200)
        let file2 = try writeFile("leftover2.dat", bytes: 300)
        let appBundleURL = fixture.appendingPathComponent("TestApp.app")
        try FileManager.default.createDirectory(at: appBundleURL, withIntermediateDirectories: true)

        let matches = [
            makeMatch(url: file1, bytes: 200),
            makeMatch(url: file2, bytes: 300),
        ]
        let app = makeApp(bundleId: "com.test.app", name: "TestApp", bundleURL: appBundleURL)
        let vm = UninstallViewModel(
            discoverApps: { [app] },
            findLeftovers: { _ in matches },
            log: freshLog()
        )
        await vm.loadApps()
        await vm.select(vm.apps.first)
        vm.checkedURLs = [file1, file2, appBundleURL]
        vm.dryRun = false
        await vm.uninstall()

        // Files trashed — no longer on disk
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path), "file1 should be trashed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2.path), "file2 should be trashed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: appBundleURL.path), "app bundle should be trashed")

        // State cleared
        XCTAssertTrue(vm.leftovers.isEmpty)
        XCTAssertTrue(vm.checkedURLs.isEmpty)
        XCTAssertNil(vm.previewBanner)
    }

    // MARK: - 8. Uninstall real re-discovers apps

    func testUninstallRealReDiscovers() async throws {
        let appBundleURL = fixture.appendingPathComponent("ReDiscover.app")
        try FileManager.default.createDirectory(at: appBundleURL, withIntermediateDirectories: true)

        // Simple counter class that closures can mutate
        final class Counter { var value = 0 }
        let counter = Counter()

        let app = makeApp(bundleId: "com.rediscover", name: "ReDiscover", bundleURL: appBundleURL)
        let vm = UninstallViewModel(
            discoverApps: {
                counter.value += 1
                return [app]
            },
            findLeftovers: { _ in [] },
            log: freshLog()
        )

        await vm.loadApps()
        XCTAssertEqual(counter.value, 1, "discoverApps called once on initial loadApps")

        // Set up a checked URL so uninstall has work to do
        vm.checkedURLs = [appBundleURL]
        vm.dryRun = false
        await vm.uninstall()

        XCTAssertEqual(counter.value, 2, "discoverApps should be called again after real uninstall")
    }

    // MARK: - 9. Uninstall protected path sets lastError

    func testUninstallProtectedPathSetsLastError() async throws {
        let validFile = try writeFile("valid.dat", bytes: 100)
        let protectedURL = URL(fileURLWithPath: "/System")

        let app = makeApp(bundleId: "com.test.protected", name: "Protected")
        let vm = UninstallViewModel(
            discoverApps: { [app] },
            findLeftovers: { _ in [] },
            log: freshLog()
        )

        // Manually set up checked URLs with a protected path and a valid file
        await vm.loadApps()
        vm.checkedURLs = [protectedURL, validFile]
        vm.dryRun = false
        await vm.uninstall()

        XCTAssertNotNil(vm.lastError, "lastError should be set when a protected path fails")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: validFile.path),
            "valid file should still be trashed even when another item fails"
        )
    }

    // MARK: - 10. Dismiss preview banner clears immediately

    func testDismissPreviewBannerClearsImmediately() async throws {
        let file1 = try writeFile("dismiss1.dat", bytes: 100)
        let appBundleURL = fixture.appendingPathComponent("DismissApp.app")
        try FileManager.default.createDirectory(at: appBundleURL, withIntermediateDirectories: true)

        let app = makeApp(bundleId: "com.dismiss", name: "DismissApp", bundleURL: appBundleURL)
        let match = makeMatch(url: file1, bytes: 100)
        let vm = UninstallViewModel(
            discoverApps: { [app] },
            findLeftovers: { _ in [match] },
            log: freshLog()
        )
        await vm.loadApps()
        await vm.select(vm.apps.first)
        vm.checkedURLs = [file1, appBundleURL]
        vm.dryRun = true
        await vm.uninstall()

        XCTAssertNotNil(vm.previewBanner, "banner should appear after dry run")
        vm.dismissPreviewBanner()
        XCTAssertNil(vm.previewBanner, "banner should be nil after dismissPreviewBanner()")
    }

    // MARK: - 11. Selecting different app clears banner

    func testSelectingDifferentAppClearsBanner() async throws {
        let file1 = try writeFile("app1-leftover.dat", bytes: 100)
        let appBundle1 = fixture.appendingPathComponent("App1.app")
        let appBundle2 = fixture.appendingPathComponent("App2.app")
        try FileManager.default.createDirectory(at: appBundle1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appBundle2, withIntermediateDirectories: true)

        let app1 = makeApp(bundleId: "com.app1", name: "App1", bundleURL: appBundle1)
        let app2 = makeApp(bundleId: "com.app2", name: "App2", bundleURL: appBundle2)
        let match = makeMatch(url: file1, bytes: 100)

        let vm = UninstallViewModel(
            discoverApps: { [app1, app2] },
            findLeftovers: { app in
                app.bundleId == "com.app1" ? [match] : []
            },
            log: freshLog()
        )
        await vm.loadApps()
        await vm.select(app1)
        vm.checkedURLs = [file1, appBundle1]
        vm.dryRun = true
        await vm.uninstall()

        XCTAssertNotNil(vm.previewBanner, "banner should appear after dry run on app1")

        // Select a different app — banner should be dismissed
        await vm.select(app2)
        XCTAssertNil(vm.previewBanner, "banner should be nil after selecting a different app")
    }

    // MARK: - 12. Operations log URL matches injected log

    func testOperationsLogURLMatchesInjectedLog() throws {
        let logURL = fixture.appendingPathComponent("myLog.jsonl")
        let log = OperationLog(logURL: logURL)
        let vm = UninstallViewModel(
            discoverApps: { [] },
            findLeftovers: { _ in [] },
            log: log
        )
        XCTAssertEqual(vm.operationsLogURL, logURL)
    }
}
