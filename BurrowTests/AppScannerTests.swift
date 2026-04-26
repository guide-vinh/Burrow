import XCTest
@testable import Burrow

// NOT covered:
// - `.prefix` matchType: operationally identical to `.exact` per the implementation;
//   one test for `.exact` covers the existence check.
// - `needsPrivilege: true` filter behavior: that's the view-model's call, not
//   AppScanner's. AppScanner returns these matches; coverage belongs to
//   UninstallViewModel tests in Task 3.
// - `homebrewCask` / `macAppStore` install-source detection: requires fixture .app
//   bundles, which the actor's discovery walks /Applications not tmpdir. Defer to
//   integration tests in Phase 5.

final class AppScannerTests: XCTestCase {

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("burrow-scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
        try super.tearDownWithError()
    }

    // MARK: - Fixture helpers

    /// Write a minimal AppLeftoversCatalog v2 JSON to tmpdir, return its URL.
    private func writeFixtureCatalog(
        userPaths: [[String: Any]] = [],
        systemPaths: [[String: Any]] = [],
        vendorOverrides: [String: Any] = [:],
        ignoreApps: [String]? = nil
    ) throws -> URL {
        let catalog: [String: Any] = [
            "schemaVersion": 2,
            "userPaths": userPaths,
            "systemPaths": systemPaths,
            "vendorOverrides": vendorOverrides,
            "ignoreApps": ["patterns": ignoreApps ?? []],
            "homebrewDetection": [
                "caskroomPrefixes": ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"],
                "uninstallCommand": "brew uninstall --cask {caskName}",
                "afterCommand": "brew autoremove",
                "warningMessage": "..."
            ],
            "macAppStoreDetection": [
                "receiptPath": "Contents/_MASReceipt/receipt",
                "uiHint": "..."
            ]
        ]
        let url = fixture.appendingPathComponent("AppLeftovers.json")
        let data = try JSONSerialization.data(withJSONObject: catalog, options: [])
        try data.write(to: url)
        return url
    }

    /// Convenience for building one userPath dictionary.
    private func userPathEntry(
        path: String,
        matchType: String = "exact",
        risk: String = "safe",
        category: String = "test",
        description: String = "test"
    ) -> [String: Any] {
        ["path": path, "matchType": matchType, "risk": risk,
         "category": category, "description": description]
    }

    /// Convenience for building an InstalledApp.
    private func makeApp(
        bundleId: String,
        name: String? = nil,
        bundleURL: URL? = nil
    ) -> InstalledApp {
        let n = name ?? "Test"
        return InstalledApp(
            bundleId: bundleId,
            name: n,
            displayName: nil,
            bundleURL: bundleURL ?? URL(fileURLWithPath: "/Applications/\(n).app"),
            version: "1.0",
            build: "1",
            bundleSize: nil,
            lastOpenedDate: nil,
            installSource: .manual
        )
    }

    // MARK: - 1. Discovery: non-empty result with valid bundleIds

    func testDiscoverFindsAppInDirectory() async throws {
        let appsURL = URL(fileURLWithPath: "/Applications")
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: appsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        try XCTSkipIf(contents.isEmpty, "Skipping: /Applications is empty (CI sandbox)")

        let catalogURL = try writeFixtureCatalog()
        let scanner = AppScanner(catalogURL: catalogURL)
        let apps = await scanner.discoverInstalledApps()

        XCTAssertFalse(apps.isEmpty, "Expected at least one app from /Applications")
        XCTAssertTrue(
            apps.allSatisfy { !$0.bundleId.isEmpty },
            "Every discovered app must have a non-empty bundleId"
        )
    }

    // MARK: - 2. Discovery: no duplicate bundleIds

    func testDiscoverDedupesByBundleId() async throws {
        let appsURL = URL(fileURLWithPath: "/Applications")
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: appsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        try XCTSkipIf(contents.isEmpty, "Skipping: /Applications is empty (CI sandbox)")

        let catalogURL = try writeFixtureCatalog()
        let scanner = AppScanner(catalogURL: catalogURL)
        let apps = await scanner.discoverInstalledApps()

        let uniqueIds = Set(apps.map(\.bundleId))
        XCTAssertEqual(
            uniqueIds.count, apps.count,
            "Discovered apps must have unique bundleIds (no duplicates)"
        )
    }

    // MARK: - 3. Discovery: sorted by localizedStandardCompare

    func testDiscoverSortsByLocalizedName() async throws {
        let appsURL = URL(fileURLWithPath: "/Applications")
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: appsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        try XCTSkipIf(contents.isEmpty, "Skipping: /Applications is empty (CI sandbox)")

        let catalogURL = try writeFixtureCatalog()
        let scanner = AppScanner(catalogURL: catalogURL)
        let apps = await scanner.discoverInstalledApps()

        guard apps.count > 1 else { return }
        for i in 0..<(apps.count - 1) {
            let result = apps[i].name.localizedStandardCompare(apps[i + 1].name)
            XCTAssertNotEqual(
                result, .orderedDescending,
                "Apps must be sorted ascending: '\(apps[i].name)' should not come after '\(apps[i + 1].name)'"
            )
        }
    }

    // MARK: - 4. findLeftovers: ignoreApps glob pattern

    func testFindLeftoversIgnoresAppViaIgnoreList() async throws {
        let catalogURL = try writeFixtureCatalog(
            userPaths: [userPathEntry(path: fixture.path + "/some-path")],
            ignoreApps: ["com.apple.*"]
        )
        let scanner = AppScanner(catalogURL: catalogURL)
        let app = makeApp(bundleId: "com.apple.Safari", name: "Safari")
        let matches = await scanner.findLeftovers(for: app)
        XCTAssertEqual(matches.count, 0, "com.apple.Safari should be ignored by 'com.apple.*' glob")
    }

    // MARK: - 5. findLeftovers: ignoreApps literal pattern doesn't prefix-match

    func testFindLeftoversIgnoresAppViaLiteralPattern() async throws {
        // Create a real path so the non-ignored app can potentially match
        let sharedPath = fixture.appendingPathComponent("some-data")
        try FileManager.default.createDirectory(at: sharedPath, withIntermediateDirectories: true)

        let catalogURL = try writeFixtureCatalog(
            userPaths: [userPathEntry(path: sharedPath.path)],
            ignoreApps: ["com.crowdstrike.falcon.Agent"]
        )
        let scanner = AppScanner(catalogURL: catalogURL)

        // Exact match — should be ignored
        let ignoredApp = makeApp(bundleId: "com.crowdstrike.falcon.Agent", name: "Falcon")
        let ignoredMatches = await scanner.findLeftovers(for: ignoredApp)
        XCTAssertEqual(ignoredMatches.count, 0, "Exact literal bundleId should be ignored")

        // Longer bundleId — literal pattern must NOT prefix-match
        let notIgnoredApp = makeApp(bundleId: "com.crowdstrike.falcon.AgentFOO", name: "FalconFOO")
        let notIgnoredMatches = await scanner.findLeftovers(for: notIgnoredApp)
        // The literal pattern "com.crowdstrike.falcon.Agent" should not catch
        // "com.crowdstrike.falcon.AgentFOO" — it has a matching userPath entry
        // so it should return 1 match (the sharedPath exists on disk)
        XCTAssertFalse(
            ignoredMatches.count == notIgnoredMatches.count && ignoredMatches.isEmpty,
            "Literal pattern must not prefix-match a longer bundleId"
        )
        // More direct: the non-ignored app must NOT be silenced by the ignore list
        // (the path exists, so it should produce a match)
        XCTAssertFalse(
            notIgnoredMatches.isEmpty && !ignoredMatches.isEmpty,
            "Non-ignored app should find leftovers; ignored app should not"
        )
        XCTAssertGreaterThan(
            notIgnoredMatches.count, ignoredMatches.count,
            "Non-ignored app should have more matches than the ignored one"
        )
    }

    // MARK: - 6. findLeftovers: {bundleId} placeholder expansion

    func testFindLeftoversExpandsBundleIdPlaceholder() async throws {
        // Create: <fixture>/cache/com.example.app/data.bin
        let cacheDir = fixture.appendingPathComponent("cache")
            .appendingPathComponent("com.example.app")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let dataFile = cacheDir.appendingPathComponent("data.bin")
        try Data("test".utf8).write(to: dataFile)

        let catalogURL = try writeFixtureCatalog(
            userPaths: [userPathEntry(path: fixture.path + "/cache/{bundleId}")]
        )
        let scanner = AppScanner(catalogURL: catalogURL)
        let app = makeApp(bundleId: "com.example.app", name: "ExampleApp")
        let matches = await scanner.findLeftovers(for: app)

        XCTAssertEqual(matches.count, 1, "Expected exactly 1 match for {bundleId} expansion")
        let matchPath = matches[0].url.standardizedFileURL.path
        let expectedPath = cacheDir.standardizedFileURL.path
        XCTAssertEqual(matchPath, expectedPath, "Resolved URL should match the bundleId-substituted path")
    }

    // MARK: - 7. findLeftovers: two-form {name} expansion

    func testFindLeftoversTwoFormNameExpansion() async throws {
        // Create both: <fixture>/Code/ and <fixture>/Visual Studio Code/
        let codeDir = fixture.appendingPathComponent("Code")
        let vsCodeDir = fixture.appendingPathComponent("Visual Studio Code")
        try FileManager.default.createDirectory(at: codeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vsCodeDir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: codeDir.appendingPathComponent("data.bin"))
        try Data("x".utf8).write(to: vsCodeDir.appendingPathComponent("data.bin"))

        let catalogURL = try writeFixtureCatalog(
            userPaths: [userPathEntry(path: fixture.path + "/{name}")]
        )
        let scanner = AppScanner(catalogURL: catalogURL)

        // CFBundleName = "Code", .app filename = "Visual Studio Code.app"
        let app = makeApp(
            bundleId: "com.microsoft.VSCode",
            name: "Code",
            bundleURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        )
        let matches = await scanner.findLeftovers(for: app)

        // Both forms should expand since name != filename
        XCTAssertEqual(matches.count, 2, "Two-form expansion should yield 2 matches when name != filename")
        let paths = Set(matches.map { $0.url.standardizedFileURL.path })
        XCTAssertTrue(paths.contains(codeDir.standardizedFileURL.path), "Should match 'Code' directory")
        XCTAssertTrue(paths.contains(vsCodeDir.standardizedFileURL.path), "Should match 'Visual Studio Code' directory")

        // Dedup: when name == filename (e.g. Slack), only one match
        let slackDir = fixture.appendingPathComponent("Slack")
        try FileManager.default.createDirectory(at: slackDir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: slackDir.appendingPathComponent("data.bin"))

        let slackCatalogURL = try {
            let url = fixture.appendingPathComponent("AppLeftoversCatalog-Slack.json")
            let catalog: [String: Any] = [
                "schemaVersion": 2,
                "userPaths": [userPathEntry(path: fixture.path + "/{name}")],
                "systemPaths": [],
                "vendorOverrides": [:],
                "ignoreApps": ["patterns": []],
                "homebrewDetection": [
                    "caskroomPrefixes": ["/opt/homebrew/Caskroom"],
                    "uninstallCommand": "brew uninstall --cask {caskName}",
                    "afterCommand": "brew autoremove",
                    "warningMessage": "..."
                ],
                "macAppStoreDetection": [
                    "receiptPath": "Contents/_MASReceipt/receipt",
                    "uiHint": "..."
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: catalog, options: [])
            try data.write(to: url)
            return url
        }()

        let slackScanner = AppScanner(catalogURL: slackCatalogURL)
        let slackApp = makeApp(
            bundleId: "com.tinyspeck.slackmacgap",
            name: "Slack",
            bundleURL: URL(fileURLWithPath: "/Applications/Slack.app")
        )
        let slackMatches = await slackScanner.findLeftovers(for: slackApp)
        XCTAssertEqual(slackMatches.count, 1, "When name == filename, only one match (no dedup needed)")
    }

    // MARK: - 8. findLeftovers: containsBundleId depth-1 only

    func testFindLeftoversContainsBundleIdDepthOne() async throws {
        let groupsDir = fixture.appendingPathComponent("groups")
        try FileManager.default.createDirectory(at: groupsDir, withIntermediateDirectories: true)

        // depth-1: these should match (contain "com.microsoft")
        let match1 = groupsDir.appendingPathComponent("UBF8T346G9.com.microsoft.teams")
        let match2 = groupsDir.appendingPathComponent("com.microsoft.something")
        try FileManager.default.createDirectory(at: match1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: match2, withIntermediateDirectories: true)

        // depth-2 nested: should NOT match (not at depth-1 of groupsDir).
        // The parent "subdir" intentionally does NOT contain "com.microsoft" so
        // it won't be a false positive at depth-1. The deep entry that does
        // contain the bundleId lives at depth-2+ and must be excluded.
        let nested = groupsDir
            .appendingPathComponent("subdir")
            .appendingPathComponent("UBF8T346G9.com.microsoft.shouldnotmatch")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let catalogURL = try writeFixtureCatalog(
            userPaths: [userPathEntry(path: groupsDir.path, matchType: "containsBundleId")]
        )
        let scanner = AppScanner(catalogURL: catalogURL)
        let app = makeApp(bundleId: "com.microsoft", name: "Microsoft")
        let matches = await scanner.findLeftovers(for: app)

        let matchPaths = Set(matches.map { $0.url.standardizedFileURL.path })
        XCTAssertTrue(matchPaths.contains(match1.standardizedFileURL.path), "UBF8T346G9.com.microsoft.teams should match")
        XCTAssertTrue(matchPaths.contains(match2.standardizedFileURL.path), "com.microsoft.something should match")
        // depth-2 entry: its last path component is "UBF8T346G9.com.microsoft.shouldnotmatch"
        // but it's not a direct child of groupsDir, so it won't be listed by depth-1 walk
        XCTAssertFalse(
            matchPaths.contains(nested.standardizedFileURL.path),
            "Depth-2 nested entry must not be matched"
        )
        XCTAssertEqual(matches.count, 2, "Only 2 depth-1 entries should match")
    }

    // MARK: - 9. findLeftovers: glob matchType

    func testFindLeftoversGlobUsesPathResolver() async throws {
        // Create: <fixture>/UBF8T346G9.com.microsoft.teams/
        //         <fixture>/UBF8T346G9.com.microsoft.oneauth/
        //         <fixture>/SOMETHING.else/
        let teams = fixture.appendingPathComponent("UBF8T346G9.com.microsoft.teams")
        let oneauth = fixture.appendingPathComponent("UBF8T346G9.com.microsoft.oneauth")
        let other = fixture.appendingPathComponent("SOMETHING.else")
        try FileManager.default.createDirectory(at: teams, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oneauth, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        let globPattern = fixture.path + "/UBF8T346G9.com.microsoft*"
        let catalogURL = try writeFixtureCatalog(
            userPaths: [userPathEntry(path: globPattern, matchType: "glob")]
        )
        let scanner = AppScanner(catalogURL: catalogURL)
        let app = makeApp(bundleId: "com.microsoft.Teams", name: "Teams")
        let matches = await scanner.findLeftovers(for: app)

        XCTAssertEqual(matches.count, 2, "Glob should match exactly 2 entries (teams + oneauth)")
        let matchNames = Set(matches.map { $0.url.lastPathComponent })
        XCTAssertTrue(matchNames.contains("UBF8T346G9.com.microsoft.teams"))
        XCTAssertTrue(matchNames.contains("UBF8T346G9.com.microsoft.oneauth"))
        XCTAssertFalse(matchNames.contains("SOMETHING.else"), "SOMETHING.else must not match")
    }

    // MARK: - 10. findLeftovers: vendor prefix key matches

    func testFindLeftoversVendorPrefixKeyMatches() async throws {
        let adobeShared = fixture.appendingPathComponent("adobe-shared")
        try FileManager.default.createDirectory(at: adobeShared, withIntermediateDirectories: true)

        let vendorEntry: [String: Any] = [
            "displayName": "Adobe",
            "paths": [userPathEntry(path: adobeShared.path)],
            "warning": "Shared Adobe resources"
        ]
        let catalogURL = try writeFixtureCatalog(
            vendorOverrides: ["com.adobe.": vendorEntry]
        )
        let scanner = AppScanner(catalogURL: catalogURL)
        let app = makeApp(bundleId: "com.adobe.Photoshop", name: "Photoshop")
        let matches = await scanner.findLeftovers(for: app)

        XCTAssertEqual(matches.count, 1, "Vendor prefix key 'com.adobe.' should match 'com.adobe.Photoshop'")
        XCTAssertEqual(matches[0].url.standardizedFileURL.path, adobeShared.standardizedFileURL.path)
    }

    // MARK: - 11. findLeftovers: vendor literal key exact match only

    func testFindLeftoversVendorLiteralKeyMatchesExact() async throws {
        let chromeData = fixture.appendingPathComponent("chrome-data")
        try FileManager.default.createDirectory(at: chromeData, withIntermediateDirectories: true)

        let vendorEntry: [String: Any] = [
            "displayName": "Chrome",
            "paths": [userPathEntry(path: chromeData.path)],
        ]
        let catalogURL = try writeFixtureCatalog(
            vendorOverrides: ["com.google.Chrome": vendorEntry]
        )
        let scanner = AppScanner(catalogURL: catalogURL)

        // Exact match: should return 1 match
        let chromeApp = makeApp(bundleId: "com.google.Chrome", name: "Chrome")
        let chromeMatches = await scanner.findLeftovers(for: chromeApp)
        XCTAssertEqual(chromeMatches.count, 1, "Literal key 'com.google.Chrome' must match exact bundleId")

        // Longer bundleId: literal key must NOT prefix-match
        let canaryApp = makeApp(bundleId: "com.google.Chrome.canary", name: "Chrome Canary")
        let canaryMatches = await scanner.findLeftovers(for: canaryApp)
        XCTAssertEqual(canaryMatches.count, 0, "Literal key 'com.google.Chrome' must NOT prefix-match 'com.google.Chrome.canary'")
    }

    // MARK: - 12. findLeftovers: isShared=true for vendor root not containing bundleId/name

    func testFindLeftoversIsSharedFlagForVendorRoot() async throws {
        let adobeShared = fixture.appendingPathComponent("adobe-shared")
        try FileManager.default.createDirectory(at: adobeShared, withIntermediateDirectories: true)

        let vendorEntry: [String: Any] = [
            "displayName": "Adobe",
            "paths": [userPathEntry(path: adobeShared.path)],
            "warning": "Shared Adobe resources"
        ]
        let catalogURL = try writeFixtureCatalog(
            vendorOverrides: ["com.adobe.": vendorEntry]
        )
        let scanner = AppScanner(catalogURL: catalogURL)
        let app = makeApp(bundleId: "com.adobe.Photoshop", name: "Adobe Photoshop")
        let matches = await scanner.findLeftovers(for: app)

        XCTAssertEqual(matches.count, 1)
        // "adobe-shared" does NOT contain "com.adobe.Photoshop" or "Adobe Photoshop"
        XCTAssertTrue(matches[0].isShared, "Vendor path not containing bundleId or name should be isShared=true")
    }

    // MARK: - 13. findLeftovers: isShared=false for app-specific path

    func testFindLeftoversIsSharedFalseForAppSpecific() async throws {
        let appSpecificPath = fixture.appendingPathComponent("com.example.app")
        try FileManager.default.createDirectory(at: appSpecificPath, withIntermediateDirectories: true)

        let vendorEntry: [String: Any] = [
            "displayName": "Example Vendor",
            "paths": [userPathEntry(path: appSpecificPath.path)],
        ]
        let catalogURL = try writeFixtureCatalog(
            vendorOverrides: ["com.example.": vendorEntry]
        )
        let scanner = AppScanner(catalogURL: catalogURL)
        let app = makeApp(bundleId: "com.example.app", name: "Example")
        let matches = await scanner.findLeftovers(for: app)

        XCTAssertEqual(matches.count, 1)
        // "com.example.app" DOES contain "com.example.app" (the bundleId)
        XCTAssertFalse(matches[0].isShared, "Path containing bundleId should be isShared=false")
    }

    // MARK: - 14. findLeftovers: dedupes by URL

    func testFindLeftoversDedupesByURL() async throws {
        let sharedPath = fixture.appendingPathComponent("shared-resource")
        try FileManager.default.createDirectory(at: sharedPath, withIntermediateDirectories: true)

        // Both userPaths and a vendorOverride target the same path
        let vendorEntry: [String: Any] = [
            "displayName": "Example Vendor",
            "paths": [userPathEntry(path: sharedPath.path)],
        ]
        let catalogURL = try writeFixtureCatalog(
            userPaths: [userPathEntry(path: sharedPath.path)],
            vendorOverrides: ["com.example.": vendorEntry]
        )
        let scanner = AppScanner(catalogURL: catalogURL)
        let app = makeApp(bundleId: "com.example.MyApp", name: "MyApp")
        let matches = await scanner.findLeftovers(for: app)

        XCTAssertEqual(matches.count, 1, "Duplicate URL from userPaths and vendorOverride must be deduped to 1 match")
    }

    // MARK: - 15. findLeftovers: bundled catalog loads without error

    func testFindLeftoversReturnsBundledCatalog() async throws {
        let appsURL = URL(fileURLWithPath: "/Applications")
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: appsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        try XCTSkipIf(contents.isEmpty, "Skipping: /Applications is empty (CI sandbox)")

        // Uses init(catalogURL: nil) — loads Bundle.main's AppLeftovers.json
        let scanner = AppScanner(catalogURL: nil)
        let app = makeApp(bundleId: "com.example.never.installed", name: "NeverInstalled")
        // The call must succeed (not crash). For a non-existent app with a novel
        // bundleId, we expect 0 matches because no paths exist on disk, but the
        // bundled catalog must load without error.
        let matches = await scanner.findLeftovers(for: app)
        // If the catalog failed to load, the actor returns [] via the catch branch.
        // We can't distinguish from a legit 0. So just call discoverInstalledApps
        // as a stronger signal that the catalog loads correctly.
        let apps = await scanner.discoverInstalledApps()
        XCTAssertFalse(apps.isEmpty, "Bundled catalog must load: discoverInstalledApps should find at least one app")
        // matches may be [] since the app is fake — that's fine
        _ = matches
    }
}
