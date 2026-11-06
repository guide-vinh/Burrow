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

    // MARK: - validate self-protection

    private func assertProtected(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try SafeFileOps.validate(url), file: file, line: line) { err in
            guard case SafeFileError.protectedPath = err else {
                return XCTFail("expected protectedPath, got \(err)", file: file, line: line)
            }
        }
    }

    func testValidateRejectsRunningApp() {
        assertProtected(Bundle.main.bundleURL)
    }

    func testValidateRejectsInsideRunningApp() {
        assertProtected(Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist"))
    }

    func testValidateRejectsFolderHoldingRunningApp() {
        assertProtected(Bundle.main.bundleURL.deletingLastPathComponent())
    }

    func testValidateRejectsFilesystemRootAndHome() {
        assertProtected(URL(fileURLWithPath: "/"))
        assertProtected(URL(fileURLWithPath: NSHomeDirectory()))
    }

    func testValidateRejectsSymlinkToRunningApp() throws {
        let link = fixture.appendingPathComponent("Burrow-link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: Bundle.main.bundleURL)
        assertProtected(link)
    }

    func testValidateAllowsSiblingOfRunningApp() throws {
        // Same name prefix, but not the bundle — must not match by string prefix.
        let sibling = URL(fileURLWithPath: Bundle.main.bundleURL.path + ".burrow-test-\(UUID().uuidString)")
        try Data("ok".utf8).write(to: sibling)
        defer { try? FileManager.default.removeItem(at: sibling) }
        XCTAssertNoThrow(try SafeFileOps.validate(sibling))
    }

    func testValidateAllowsCopyOfBurrowThatIsNotRunning() throws {
        // e.g. an old copy already in the Trash — Empty Trash must still reach it.
        let copy = fixture.appendingPathComponent("Burrow.app")
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        XCTAssertNoThrow(try SafeFileOps.validate(copy))
    }

    func testTrashAndDeleteRefuseRunningAppEvenInDryRun() async {
        for operation in [
            { try await SafeFileOps.trash(Bundle.main.bundleURL, dryRun: true) },
            { try await SafeFileOps.permanentlyDelete(Bundle.main.bundleURL, dryRun: true) },
        ] as [() async throws -> Int64] {
            do {
                _ = try await operation()
                XCTFail("expected protectedPath")
            } catch SafeFileError.protectedPath {
                // expected
            } catch {
                XCTFail("expected protectedPath, got \(error)")
            }
        }
    }

    func testProtectedPathErrorNamesTheItem() {
        let error = SafeFileError.protectedPath(URL(fileURLWithPath: "/Applications/Burrow.app"))
        XCTAssertTrue(error.localizedDescription.contains("Burrow.app"))
    }

    // MARK: - validate iCloud Drive folders

    /// Builds `<fixture>/Library/Mobile Documents/<relative>` and returns it.
    private func makeICloudItem(_ relative: String, isFile: Bool = false) throws -> URL {
        let url = fixture.appendingPathComponent("Library/Mobile Documents/\(relative)")
        let fm = FileManager.default
        if isFile {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("ok".utf8).write(to: url)
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    func testICloudProtectsStructuralFolders() throws {
        let home = fixture.path
        let container = try makeICloudItem("com~apple~CloudDocs")
        let documents = try makeICloudItem("iCloud~md~obsidian/Documents")
        for url in [container, documents, container.deletingLastPathComponent(), fixture.appendingPathComponent("Library")] {
            XCTAssertTrue(SafeFileOps.isICloudStructural(url, home: home), url.path)
        }
    }

    func testICloudMatchesCaseInsensitively() throws {
        let documents = try makeICloudItem("iCloud~md~obsidian/Documents")
        let respelled = documents.deletingLastPathComponent().appendingPathComponent("DOCUMENTS")
        XCTAssertTrue(SafeFileOps.isICloudStructural(respelled, home: fixture.path))
    }

    func testICloudProtectsSymlinkToContainer() throws {
        let container = try makeICloudItem("com~apple~CloudDocs")
        let link = fixture.appendingPathComponent("cloud-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: container)
        XCTAssertTrue(SafeFileOps.isICloudStructural(link, home: fixture.path))
    }

    func testICloudAllowsContentInsideStores() throws {
        let home = fixture.path
        let allowed = [
            try makeICloudItem("com~apple~CloudDocs/Projects"),
            try makeICloudItem("com~apple~CloudDocs/Projects/notes.txt", isFile: true),
            try makeICloudItem("iCloud~md~obsidian/Documents/Vault"),
            try makeICloudItem("stray-file.txt", isFile: true),
        ]
        for url in allowed {
            XCTAssertFalse(SafeFileOps.isICloudStructural(url, home: home), url.path)
        }
    }

    func testICloudIgnoresUnrelatedPaths() throws {
        let other = fixture.appendingPathComponent("Library/Caches/Mobile Documents")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        XCTAssertFalse(SafeFileOps.isICloudStructural(other, home: fixture.path))
    }

    func testValidateRejectsLibraryRoot() {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library")
        XCTAssertThrowsError(try SafeFileOps.validate(url)) { err in
            guard case SafeFileError.protectedPath = err else {
                return XCTFail("expected protectedPath, got \(err)")
            }
        }
    }

    func testValidateRejectsNonexistent() {
        let url = fixture.appendingPathComponent("never-existed")
        XCTAssertThrowsError(try SafeFileOps.validate(url)) { err in
            guard case SafeFileError.doesNotExist = err else {
                return XCTFail("expected doesNotExist, got \(err)")
            }
        }
    }

    // MARK: - .app carve-out (Phase 2 Uninstall)

    func testValidateAllowsDirectAppChildOfApplications() throws {
        // Safari.app ships with macOS — the carve-out must allow it
        // even though /Applications is in the deny-list.
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: url.path),
            "Safari not installed at /Applications/Safari.app"
        )
        XCTAssertNoThrow(try SafeFileOps.validate(url))
    }

    func testValidateRejectsContentsInsideAppBundle() throws {
        // The carve-out is only for the .app boundary — anything DEEPER
        // is still protected so we never accidentally reach inside.
        let url = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: url.path),
            "Safari Info.plist not found"
        )
        XCTAssertThrowsError(try SafeFileOps.validate(url)) { err in
            guard case SafeFileError.protectedPath = err else {
                return XCTFail("expected protectedPath, got \(err)")
            }
        }
    }

    func testValidateRejectsApplicationsRootItself() {
        let url = URL(fileURLWithPath: "/Applications")
        XCTAssertThrowsError(try SafeFileOps.validate(url)) { err in
            guard case SafeFileError.protectedPath = err else {
                return XCTFail("expected protectedPath, got \(err)")
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
