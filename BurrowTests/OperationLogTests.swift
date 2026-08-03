import XCTest
@testable import Burrow

final class OperationLogTests: XCTestCase {

    private var fixture: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("burrow-oplog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func entry(
        target: String,
        action: OperationLogEntry.Action = .trash,
        dryRun: Bool = false
    ) -> OperationLogEntry {
        OperationLogEntry(
            timestamp: Date(timeIntervalSince1970: 1_730_000_000),
            action: action,
            target: target,
            bytes: 1024,
            dryRun: dryRun
        )
    }

    // MARK: - Tests

    func testReadAllReturnsEmptyForMissingLog() async throws {
        let logURL = fixture.appendingPathComponent("nonexistent.log")
        let log = OperationLog(logURL: logURL)
        let entries = try await log.readAll()
        XCTAssertEqual(entries, [])
    }

    func testAppendCreatesParentDirectoryAndFile() async throws {
        let logURL = fixture
            .appendingPathComponent("sub")
            .appendingPathComponent("dir")
            .appendingPathComponent("operations.log")
        let log = OperationLog(logURL: logURL)

        try await log.append(entry(target: "testfile.txt"))

        let parentDir = logURL.deletingLastPathComponent()
        var isDir: ObjCBool = false
        let dirExists = FileManager.default.fileExists(atPath: parentDir.path, isDirectory: &isDir)
        XCTAssertTrue(dirExists && isDir.boolValue, "parent directory should exist")

        let fileExists = FileManager.default.fileExists(atPath: logURL.path)
        XCTAssertTrue(fileExists, "log file should exist after append")

        let data = try Data(contentsOf: logURL)
        XCTAssertFalse(data.isEmpty, "log file should be non-empty after append")
    }

    func testAppendAndReadRoundTrip() async throws {
        let logURL = fixture.appendingPathComponent("operations.log")
        let log = OperationLog(logURL: logURL)

        let original = OperationLogEntry(
            timestamp: Date(timeIntervalSince1970: 1_730_000_000),
            action: .trash,
            target: "myfile.txt",
            bytes: 1024,
            dryRun: false
        )
        try await log.append(original)

        let entries = try await log.readAll()
        XCTAssertEqual(entries.count, 1, "should have exactly one entry")

        let read = try XCTUnwrap(entries.first)
        XCTAssertEqual(read.timestamp, original.timestamp)
        XCTAssertEqual(read.action, original.action)
        XCTAssertEqual(read.target, original.target)
        XCTAssertEqual(read.bytes, original.bytes)
        XCTAssertEqual(read.dryRun, original.dryRun)
    }

    func testReadAllPreservesAppendOrder() async throws {
        let logURL = fixture.appendingPathComponent("operations.log")
        let log = OperationLog(logURL: logURL)

        try await log.append(entry(target: "first"))
        try await log.append(entry(target: "second"))
        try await log.append(entry(target: "third"))

        let entries = try await log.readAll()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].target, "first")
        XCTAssertEqual(entries[1].target, "second")
        XCTAssertEqual(entries[2].target, "third")
    }

    func testReadAllSkipsCorruptLines() async throws {
        let logURL = fixture.appendingPathComponent("operations.log")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let entry1 = entry(target: "valid-one")
        let entry2 = entry(target: "valid-two")

        let line1 = try encoder.encode(entry1) + Data([0x0A])
        let corruptLine = Data("this is not json\n".utf8)
        let line3 = try encoder.encode(entry2) + Data([0x0A])

        var fileData = Data()
        fileData.append(line1)
        fileData.append(corruptLine)
        fileData.append(line3)
        try fileData.write(to: logURL)

        let log = OperationLog(logURL: logURL)
        let entries = try await log.readAll()

        XCTAssertEqual(entries.count, 2, "corrupt line should be skipped")
        XCTAssertEqual(entries[0].target, "valid-one")
        XCTAssertEqual(entries[1].target, "valid-two")
    }

    func testDefaultLogURLIsUnderUserLogs() {
        let dir = OperationLog.defaultLogsDirectory.path
        XCTAssertTrue(
            dir.hasSuffix("/Library/Logs/Burrow"),
            "defaultLogsDirectory.path should end in /Library/Logs/Burrow, got \(dir)"
        )

        // Production log rotates daily: operations-yyyy-MM-dd.log.
        let path = OperationLog.shared.logURL.path
        XCTAssertTrue(
            path.hasPrefix(dir + "/operations-") && path.hasSuffix(".log"),
            "shared.logURL should be a dated file inside the logs dir, got \(path)"
        )
        let name = (path as NSString).lastPathComponent
        XCTAssertNotNil(
            name.range(of: #"^operations-\d{4}-\d{2}-\d{2}\.log$"#, options: .regularExpression),
            "daily log name should match operations-yyyy-MM-dd.log, got \(name)"
        )
    }
}
