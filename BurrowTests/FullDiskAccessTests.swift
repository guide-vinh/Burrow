import XCTest
@testable import Burrow

// NOTE: openSystemSettings() is intentionally not tested here because it
// opens a real System Settings window, which would be invasive (and
// disruptive to CI) on every test run.

final class FullDiskAccessTests: XCTestCase {

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("burrow-fda-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions on the fixture dir before removal so that
        // FileManager.removeItem can descend into it even if test 3
        // chmod'd a child to 0o000.
        _ = chmod(fixture.path, 0o755)
        try? FileManager.default.removeItem(at: fixture)
        try super.tearDownWithError()
    }

    // MARK: - probe

    func testProbeReturnsTrueForReadableFile() throws {
        let url = fixture.appendingPathComponent("readable.bin")
        try Data([0xAB, 0xCD]).write(to: url)
        XCTAssertTrue(FullDiskAccess.probe(at: url))
    }

    func testProbeReturnsFalseForMissingFile() {
        let url = fixture.appendingPathComponent("never-created.bin")
        XCTAssertFalse(FullDiskAccess.probe(at: url))
    }

    func testProbeReturnsFalseForUnreadableFile() throws {
        try XCTSkipIf(getuid() == 0, "owner-bypass — root can read regardless of perms")

        let url = fixture.appendingPathComponent("unreadable.bin")
        try Data([0x01]).write(to: url)
        chmod(url.path, 0o000)
        XCTAssertFalse(FullDiskAccess.probe(at: url))
    }

    // MARK: - defaultProbe

    func testDefaultProbeIsSafariCloudTabs() {
        XCTAssertTrue(
            FullDiskAccess.defaultProbe.path.hasSuffix("Library/Safari/CloudTabs.db"),
            "defaultProbe.path should end in Library/Safari/CloudTabs.db, got \(FullDiskAccess.defaultProbe.path)"
        )
    }
}
