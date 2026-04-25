import XCTest
@testable import Burrow

final class SafeFileOpsTests: XCTestCase {

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("burrow-safefileops-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
        try super.tearDownWithError()
    }

    // MARK: - validate deny-list

    func testValidateRejectsSystemRoot() {
        let url = URL(fileURLWithPath: "/System")
        XCTAssertThrowsError(try SafeFileOps.validate(url)) { err in
            guard case SafeFileError.protectedPath = err else {
                return XCTFail("expected protectedPath, got \(err)")
            }
        }
    }

    func testValidateRejectsSystemDescendant() {
        let url = URL(fileURLWithPath: "/System/Library")
        XCTAssertThrowsError(try SafeFileOps.validate(url)) { err in
            guard case SafeFileError.protectedPath = err else {
                return XCTFail("expected protectedPath, got \(err)")
            }
        }
    }

    func testValidateRejectsHomeDocumentsRoot() {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Documents")
        XCTAssertThrowsError(try SafeFileOps.validate(url)) { err in
            guard case SafeFileError.protectedPath = err else {
                return XCTFail("expected protectedPath, got \(err)")
            }
        }
    }

    func testValidateAllowsChildOfHomeDocuments() throws {
        // Per SPEC section 6, only the *root* of ~/Documents is protected;
        // children are fine. Use a fixture inside the tmpdir so we can verify
        // the "exists + not-deny-listed" path without touching real Documents.
        let child = fixture.appendingPathComponent("totally-fine.tmp")
        try Data("ok".utf8).write(to: child)
        XCTAssertNoThrow(try SafeFileOps.validate(child))
    }

    func testValidateRejectsNonexistent() {
        let url = fixture.appendingPathComponent("never-existed")
        XCTAssertThrowsError(try SafeFileOps.validate(url)) { err in
            guard case SafeFileError.doesNotExist = err else {
                return XCTFail("expected doesNotExist, got \(err)")
            }
        }
    }

    // MARK: - size

    func testSizeOfFileMatchesByteCount() throws {
        let url = fixture.appendingPathComponent("blob.bin")
        let payload = Data(repeating: 0x42, count: 4096)
        try payload.write(to: url)
        XCTAssertGreaterThanOrEqual(SafeFileOps.size(url), 4096)
    }

    // MARK: - trash (real, lands in user's ~/.Trash)

    func testTrashMovesFileOffOriginalLocation() async throws {
        let url = fixture.appendingPathComponent("trash-me-\(UUID().uuidString).tmp")
        try Data("bye".utf8).write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let bytes = try await SafeFileOps.trash(url)
        XCTAssertGreaterThanOrEqual(bytes, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "fixture should have been recycled out of tmpdir")
    }

    func testTrashDryRunLeavesFileInPlace() async throws {
        let url = fixture.appendingPathComponent("dryrun-keep.tmp")
        try Data("stay".utf8).write(to: url)

        let bytes = try await SafeFileOps.trash(url, dryRun: true)
        XCTAssertGreaterThanOrEqual(bytes, 4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "dryRun must not touch the file system")
    }
}
