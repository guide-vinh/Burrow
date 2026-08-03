import Foundation
import os

/// Append-only JSONL audit log for every destructive Burrow operation.
/// Required by SPEC section 6. Production writes one file per day —
/// `~/Library/Logs/Burrow/operations-2026-08-03.log` — so a long-lived
/// install doesn't accumulate a single unreadable log; tests inject a
/// fixed tmpdir URL and keep the one-file behavior.
actor OperationLog {

    // MARK: - Nested types

    enum LogError: Swift.Error {
        /// `open(2)` returned -1; the associated value is the captured `errno`.
        case openFailed(errno: Int32)
        /// JSON encoding raised an error.
        case encodeFailed(underlying: Swift.Error)
    }

    // MARK: - Singleton

    /// Production singleton, writes daily files under the default logs dir.
    static let shared = OperationLog()

    // MARK: - Properties

    /// Injected by tests; nil in production (daily rotation).
    private let fixedLogURL: URL?

    /// Directory holding every log file.
    let logsDirectory: URL

    private let logger = Logger(subsystem: "fun.burrow", category: "OperationLog")

    // MARK: - Init

    /// Production initializer — daily files in `~/Library/Logs/Burrow/`.
    init() {
        self.fixedLogURL = nil
        self.logsDirectory = Self.defaultLogsDirectory
    }

    /// Test initializer: every append goes to exactly this file, no
    /// daily rotation.
    init(logURL: URL) {
        self.fixedLogURL = logURL
        self.logsDirectory = logURL.deletingLastPathComponent()
    }

    // MARK: - Paths

    /// `~/Library/Logs/Burrow`.
    /// Uses `NSHomeDirectory()` — never hardcodes a user name.
    static var defaultLogsDirectory: URL {
        let home = NSHomeDirectory() as NSString
        return URL(fileURLWithPath: home.appendingPathComponent("Library/Logs/Burrow"))
    }

    /// File that receives appends right now: the injected fixture in
    /// tests, or today's `operations-yyyy-MM-dd.log` in production.
    nonisolated var logURL: URL {
        if let fixedLogURL { return fixedLogURL }
        return logsDirectory.appendingPathComponent("operations-\(Self.dayStamp()).log")
    }

    private nonisolated static func dayStamp(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Append

    /// Append one entry as a single JSONL line. Creates the parent
    /// directory on first write. Atomic: the entire JSON + "\n" is
    /// written in one FileHandle.write call so concurrent appenders
    /// (across processes or threads) cannot interleave bytes.
    func append(_ entry: OperationLogEntry) throws {
        // 1. Ensure parent directory exists (idempotent).
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )

        // 2. Encode to JSON with ISO-8601 timestamps.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let encodedJSON: Data
        do {
            encodedJSON = try encoder.encode(entry)
        } catch {
            throw LogError.encodeFailed(underlying: error)
        }

        // 3. Build payload: JSON bytes + UTF-8 newline (0x0A).
        var payload = encodedJSON
        payload.append(contentsOf: [0x0A])

        // 4. Open file at POSIX level with O_APPEND for kernel-atomic appends.
        let path = logURL.path
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644 as mode_t)
        guard fd != -1 else {
            let capturedErrno = errno
            logger.error(
                "Failed to open log file errno \(capturedErrno, privacy: .public) at \(path, privacy: .private)"
            )
            throw LogError.openFailed(errno: capturedErrno)
        }

        // 5. Wrap the fd; closeOnDealloc closes it when handle leaves scope.
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: payload)

        // 6. Debug log with appropriate privacy levels.
        logger.debug(
            "Logged action \(entry.action.rawValue, privacy: .public) target \(entry.target, privacy: .private)"
        )
    }

    // MARK: - Read

    /// Read all entries across every log file — the legacy single
    /// `operations.log` (pre-rotation installs) first, then daily files
    /// oldest-first. Append order is preserved within each file.
    /// Returns an empty array if no log file exists yet.
    func readAll() throws -> [OperationLogEntry] {
        var entries: [OperationLogEntry] = []
        for url in logFilesOldestFirst() {
            entries.append(contentsOf: try read(file: url))
        }
        return entries
    }

    /// Every log file in chronological order. In fixed-URL (test) mode
    /// this is just the injected file.
    private func logFilesOldestFirst() -> [URL] {
        if let fixedLogURL { return [fixedLogURL] }

        guard let names = try? FileManager.default
            .contentsOfDirectory(atPath: logsDirectory.path) else {
            return []
        }
        // yyyy-MM-dd stamps sort chronologically as plain strings.
        let daily = names
            .filter { $0.hasPrefix("operations-") && $0.hasSuffix(".log") }
            .sorted()
        let legacy = names.contains("operations.log") ? ["operations.log"] : []
        return (legacy + daily).map { logsDirectory.appendingPathComponent($0) }
    }

    private func read(file url: URL) throws -> [OperationLogEntry] {
        // 1. Missing log is valid initial state — not an error.
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        // 2. Read the whole file.
        let data = try Data(contentsOf: url)

        // 3. Split by newline (0x0A), skip empty trailing chunk.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let chunks = data.split(separator: 0x0A, omittingEmptySubsequences: true)

        // 4. Decode each chunk; skip corrupt lines rather than aborting.
        var entries: [OperationLogEntry] = []
        entries.reserveCapacity(chunks.count)

        for chunk in chunks {
            do {
                let entry = try decoder.decode(OperationLogEntry.self, from: Data(chunk))
                entries.append(entry)
            } catch {
                logger.error(
                    "Skipping corrupt log line: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return entries
    }
}
