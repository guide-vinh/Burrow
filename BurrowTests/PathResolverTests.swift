import XCTest
@testable import Burrow

final class PathResolverTests: XCTestCase {

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("burrow-pathresolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
        try super.tearDownWithError()
    }

    // MARK: - Tilde expansion

    func testExpandReplacesLeadingTildeWithHome() {
        let expanded = PathResolver.expand("~/Library/Caches")
        XCTAssertEqual(expanded, NSHomeDirectory() + "/Library/Caches")
    }

    func testExpandLeavesNonTildePathsAlone() {
        XCTAssertEqual(PathResolver.expand("/usr/local"), "/usr/local")
    }

    // MARK: - Single-segment glob

    func testResolveSingleStarMatchesSiblingDirectories() throws {
        try makeDir("alpha")
        try makeDir("beta")
        try makeDir("gamma")

        let resolved = PathResolver.resolve(fixture.path + "/*")
        let names = Set(resolved.map { $0.lastPathComponent })
        XCTAssertEqual(names, ["alpha", "beta", "gamma"])
    }

    func testResolveStarPrefixMatchesByName() throws {
        try makeDir("Cache")
        try makeDir("CacheStorage")
        try makeDir("Logs")

        let resolved = PathResolver.resolve(fixture.path + "/Cache*")
        let names = Set(resolved.map { $0.lastPathComponent })
        XCTAssertEqual(names, ["Cache", "CacheStorage"])
    }

    // MARK: - Mid-path glob

    func testResolveStarMidPathExpandsAcrossLevels() throws {
        try makeFile("alpha/leaf.txt")
        try makeFile("beta/leaf.txt")
        try makeFile("gamma/other.txt")

        let resolved = PathResolver.resolve(fixture.path + "/*/leaf.txt")
        let parents = Set(resolved.map { $0.deletingLastPathComponent().lastPathComponent })
        XCTAssertEqual(parents, ["alpha", "beta"])
    }

    // MARK: - No-match

    func testResolveNoGlobMatchReturnsEmpty() {
        let resolved = PathResolver.resolve(fixture.path + "/nope-*")
        XCTAssertEqual(resolved, [])
    }

    func testResolveNonexistentLiteralPathReturnsEmpty() {
        let resolved = PathResolver.resolve(fixture.path + "/never-was-here")
        XCTAssertEqual(resolved, [])
    }

    // MARK: - Helpers

    private func makeDir(_ relative: String) throws {
        try FileManager.default.createDirectory(
            at: fixture.appendingPathComponent(relative),
            withIntermediateDirectories: true
        )
    }

    private func makeFile(_ relative: String) throws {
        let url = fixture.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: url)
    }
}
