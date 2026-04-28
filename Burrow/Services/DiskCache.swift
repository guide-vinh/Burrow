import Foundation
import SQLite3
import os

// MARK: - Logger

private let logger = Logger(subsystem: "fun.burrow", category: "DiskCache")

// MARK: - DiskCache

/// Actor wrapping an SQLite connection for persistent disk-scan caching.
/// Per PHASE3B_DECISIONS §5: single actor, serialized writes.
/// Per PHASE3B_DECISIONS §6: best-effort — errors are logged and methods
/// silently return default values; the cache never blocks a scan.
actor DiskCache {

    // MARK: - Singleton

    /// Production singleton backed by `productionDatabaseURL`.
    static let shared = DiskCache(databaseURL: DiskCache.productionDatabaseURL)

    // MARK: - Production path

    /// `~/Library/Application Support/fun.burrow/disk-cache.sqlite`.
    static let productionDatabaseURL: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return support
            .appendingPathComponent("fun.burrow", isDirectory: true)
            .appendingPathComponent("disk-cache.sqlite", isDirectory: false)
    }()

    // MARK: - Private state

    private let databaseURL: URL
    private var db: OpaquePointer?
    private var disabled = false

    // MARK: - SQLite helpers

    /// Matches C macro `SQLITE_TRANSIENT` — tells SQLite to copy the string
    /// before the call returns, so Swift string lifetime doesn't matter.
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: - Init

    /// Creates (or opens) the SQLite database at `databaseURL`. The parent
    /// directory is created if missing. Schema migration is applied
    /// automatically. If any step fails the cache disables itself and all
    /// public methods become no-ops.
    init(databaseURL: URL) {
        self.databaseURL = databaseURL
        openDatabase()
    }

    // MARK: - Public API

    /// Returns the cached entry for `path`, or nil if not found / cache disabled.
    func entry(at path: String) -> CachedEntry? {
        guard !disabled, let db else { return nil }

        let sql = "SELECT path, parent_path, inode, mtime, size, child_count, is_directory, last_scanned FROM disk_cache WHERE path = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("entry(at:) prepare failed: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return rowToEntry(stmt)
    }

    /// Inserts or replaces a single entry in the cache.
    func upsert(_ entry: CachedEntry) {
        guard !disabled, let db else { return }
        performUpsert(entry, db: db)
    }

    /// Inserts or replaces a batch of entries inside a single transaction.
    /// On any error the transaction is rolled back and the error is logged.
    func upsertBatch(_ entries: [CachedEntry]) {
        guard !disabled, let db, !entries.isEmpty else { return }

        guard execSQL("BEGIN IMMEDIATE;", db: db) else { return }

        let sql = upsertSQL()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("upsertBatch prepare failed: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            _ = execSQL("ROLLBACK;", db: db)
            return
        }
        defer { sqlite3_finalize(stmt) }

        for entry in entries {
            bindEntry(entry, to: stmt)
            let result = sqlite3_step(stmt)
            if result != SQLITE_DONE {
                logger.error("upsertBatch step failed: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
                _ = execSQL("ROLLBACK;", db: db)
                return
            }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }

        _ = execSQL("COMMIT;", db: db)
    }

    /// Returns all immediate children of `parentPath` from the cache.
    func children(of parentPath: String) -> [CachedEntry] {
        guard !disabled, let db else { return [] }

        let sql = "SELECT path, parent_path, inode, mtime, size, child_count, is_directory, last_scanned FROM disk_cache WHERE parent_path = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("children(of:) prepare failed: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, parentPath, -1, SQLITE_TRANSIENT)

        var result: [CachedEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let entry = rowToEntry(stmt) {
                result.append(entry)
            }
        }
        return result
    }

    /// Deletes all rows from the cache table.
    func flush() {
        guard !disabled, let db else { return }
        _ = execSQL("DELETE FROM disk_cache;", db: db)
    }

    /// Closes the underlying SQLite connection. Idempotent.
    func close() {
        guard let db else { return }
        sqlite3_close(db)
        self.db = nil
    }

    // MARK: - Schema

    private static let createTableSQL = """
        CREATE TABLE IF NOT EXISTS disk_cache (
            path          TEXT     PRIMARY KEY NOT NULL,
            parent_path   TEXT,
            inode         INTEGER  NOT NULL,
            mtime         REAL     NOT NULL,
            size          INTEGER  NOT NULL,
            child_count   INTEGER  NOT NULL,
            is_directory  INTEGER  NOT NULL,
            last_scanned  REAL     NOT NULL
        );
        """

    private static let createIndexSQL = """
        CREATE INDEX IF NOT EXISTS idx_disk_cache_parent ON disk_cache(parent_path);
        """

    // MARK: - Helpers

    /// Opens the database and applies schema migration.
    private func openDatabase() {
        let dir = databaseURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("DiskCache: failed to create parent directory: \(error.localizedDescription, privacy: .public)")
            disabled = true
            return
        }

        var rawDB: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(databaseURL.path, &rawDB, flags, nil)
        guard openResult == SQLITE_OK, let openedDB = rawDB else {
            let msg = rawDB.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            logger.error("DiskCache: sqlite3_open_v2 failed (\(openResult, privacy: .public)): \(msg, privacy: .public)")
            if let rawDB { sqlite3_close(rawDB) }
            disabled = true
            return
        }
        db = openedDB

        // Apply WAL + safety pragmas
        _ = execSQL("PRAGMA journal_mode = WAL;", db: openedDB)
        _ = execSQL("PRAGMA synchronous = NORMAL;", db: openedDB)
        _ = execSQL("PRAGMA foreign_keys = OFF;", db: openedDB)

        // Schema migration via user_version
        let version = userVersion(db: openedDB)
        switch version {
        case 0:
            // Fresh database — apply v1 schema
            guard execSQL(Self.createTableSQL, db: openedDB),
                  execSQL(Self.createIndexSQL, db: openedDB),
                  execSQL("PRAGMA user_version = 1;", db: openedDB) else {
                logger.error("DiskCache: failed to apply v1 schema")
                disabled = true
                return
            }
        case 1:
            break // Already at v1, nothing to do
        default:
            logger.error("DiskCache: unsupported schema version \(version, privacy: .public) — disabling cache")
            disabled = true
        }
    }

    /// Reads the current `PRAGMA user_version` value.
    private func userVersion(db: OpaquePointer) -> Int32 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else {
            return -1
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return sqlite3_column_int(stmt, 0)
    }

    /// Executes a SQL string that returns no rows. Returns true on success.
    @discardableResult
    private func execSQL(_ sql: String, db: OpaquePointer) -> Bool {
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if result != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            logger.error("DiskCache execSQL failed (\(result, privacy: .public)): \(msg, privacy: .public)")
            sqlite3_free(errMsg)
            return false
        }
        return true
    }

    /// Returns the UPSERT SQL string used for both single and batch upserts.
    private func upsertSQL() -> String {
        """
        INSERT INTO disk_cache (path, parent_path, inode, mtime, size, child_count, is_directory, last_scanned)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            parent_path  = excluded.parent_path,
            inode        = excluded.inode,
            mtime        = excluded.mtime,
            size         = excluded.size,
            child_count  = excluded.child_count,
            is_directory = excluded.is_directory,
            last_scanned = excluded.last_scanned;
        """
    }

    /// Binds a `CachedEntry` to all 8 parameters of the upsert prepared statement.
    private func bindEntry(_ entry: CachedEntry, to stmt: OpaquePointer?) {
        guard let stmt else { return }
        sqlite3_bind_text(stmt, 1, entry.path, -1, SQLITE_TRANSIENT)
        if let parent = entry.parentPath {
            sqlite3_bind_text(stmt, 2, parent, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_int64(stmt, 3, Int64(bitPattern: entry.inode))
        sqlite3_bind_double(stmt, 4, entry.mtime.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 5, entry.size)
        sqlite3_bind_int(stmt, 6, Int32(entry.childCount))
        sqlite3_bind_int(stmt, 7, entry.isDirectory ? 1 : 0)
        sqlite3_bind_double(stmt, 8, entry.lastScanned.timeIntervalSince1970)
    }

    /// Performs a single upsert using the given open db connection.
    private func performUpsert(_ entry: CachedEntry, db: OpaquePointer) {
        let sql = upsertSQL()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("upsert prepare failed: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            return
        }
        defer { sqlite3_finalize(stmt) }

        bindEntry(entry, to: stmt)

        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE {
            logger.error("upsert step failed (\(result, privacy: .public)): \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
        }
    }

    /// Maps a prepared-statement row to a `CachedEntry`.
    /// Columns must be in the order: path, parent_path, inode, mtime,
    /// size, child_count, is_directory, last_scanned.
    private func rowToEntry(_ stmt: OpaquePointer?) -> CachedEntry? {
        guard let stmt else { return nil }

        guard let pathCStr = sqlite3_column_text(stmt, 0) else { return nil }
        let path = String(cString: pathCStr)

        let parentPath: String?
        if let parentCStr = sqlite3_column_text(stmt, 1) {
            parentPath = String(cString: parentCStr)
        } else {
            parentPath = nil
        }

        let inode = UInt64(bitPattern: sqlite3_column_int64(stmt, 2))
        let mtime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let size = sqlite3_column_int64(stmt, 4)
        let childCount = Int(sqlite3_column_int(stmt, 5))
        let isDirectory = sqlite3_column_int(stmt, 6) != 0
        let lastScanned = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))

        return CachedEntry(
            path: path,
            parentPath: parentPath,
            inode: inode,
            mtime: mtime,
            size: size,
            childCount: childCount,
            isDirectory: isDirectory,
            lastScanned: lastScanned
        )
    }
}
