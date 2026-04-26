import Foundation
import os

/// Append-only JSONL audit log for every destructive Burrow operation.
/// Required by SPEC section 6. Lives at `~/Library/Logs/Burrow/operations.log`
/// by default; tests inject a tmpdir URL.
actor OperationLog {

    // MARK: - Nested types

    enum LogError: Swift.Error {
        /// `open(2)` returned -1; the associated value is the captured `errno`.
        case openFailed(errno: Int32)
        /// JSON encoding raised an error.
        case encodeFailed(underlying: Swift.Error)
    }

    // MARK: - Singleton

    /// Production singleton, points at the default user log path.
    static let shared = OperationLog()

    // MARK: - Properties

    let logURL: URL

    private let logger = Logger(subsystem: "fun.burrow", category: "OperationLog")

    // MARK: - Init

    /// Inject a custom URL for tests. Default is
    /// `~/Library/Logs/Burrow/operations.log`.
    init(logURL: URL = OperationLog.defaultLogURL) {
        self.logURL = logURL
    }

    // MARK: - Default path

    /// `~/Library/Logs/Burrow/operations.log`.
    /// Uses `NSHomeDirectory()` — never hardcodes a user name.
    static var defaultLogURL: URL {
        let home = NSHomeDirectory() as NSString
        let logsDir = home.appendingPathComponent("Library/Logs/Burrow")
        return URL(fileURLWithPath: (logsDir as NSString)
            .appendingPathComponent("operations.log"))
    }

    // MARK: - Append

    /// Append one entry as a single JSONL line. Creates the parent
    /// directory on first write. Atomic: the entire JSON + "\n" is
    /// written in one FileHandle.write call so concurrent appenders
    /// (across processes or threads) cannot interleave bytes.
    func append(_ entry: OperationLogEntry) throws {
        // 1. Ensure parent directory exists (idempotent).
        let parentDir = logURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentDir,
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

    /// Read all entries currently in the file, in append order. Returns
    /// an empty array if the log file does not exist.
    func readAll() throws -> [OperationLogEntry] {
        // 1. Missing log is valid initial state — not an error.
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return []
        }

        // 2. Read the whole file.
        let data = try Data(contentsOf: logURL)

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
