import XCTest
@testable import Burrow

final class DiskCacheTests: XCTestCase {

    // MARK: - Fixture

    private var testDBURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testDBURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("burrow-disk-cache-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testDBURL)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Builds a `CachedEntry` with sensible defaults; caller overrides only what matters.
    private func makeEntry(
        path: String,
        parent: String? = nil,
        inode: UInt64 = 1,
        mtime: Date = Date(timeIntervalSince1970: 1_700_000_000),
        size: Int64 = 1024,
        childCount: Int = 0,
        isDirectory: Bool = false,
        lastScanned: Date = Date(timeIntervalSince1970: 1_700_000_500)
    ) -> CachedEntry {
        CachedEntry(
            path: path,
            parentPath: parent,
            inode: inode,
            mtime: mtime,
            size: size,
            childCount: childCount,
            isDirectory: isDirectory,
            lastScanned: lastScanned
        )
    }

    // MARK: - Test 1: Fresh database opens cleanly

    /// Verify that opening a cache against a non-existent path creates the
    /// database file and that `entry(at:)` returns nil for any path.
    func testFreshDatabaseOpensCleanly() async {
        let cache = DiskCache(databaseURL: testDBURL)
        let exists = FileManager.default.fileExists(atPath: testDBURL.path)
        XCTAssertTrue(exists, "Database file should be created on init")

        let result = await cache.entry(at: "/some/path")
        XCTAssertNil(result, "Fresh cache should return nil for any path")

        await cache.close()
    }

    // MARK: - Test 2: Upsert then read round-trip

    /// Upsert one CachedEntry then read it back; all 8 fields must match exactly.
    func testUpsertThenEntryRoundTrip() async {
        let mtime = Date(timeIntervalSince1970: 1_700_000_000)
        let lastScanned = Date(timeIntervalSince1970: 1_700_000_500)
        let original = makeEntry(
            path: "/test/file.txt",
            parent: "/test",
            inode: 42,
            mtime: mtime,
            size: 2048,
            childCount: 3,
            isDirectory: true,
            lastScanned: lastScanned
        )

        let cache = DiskCache(databaseURL: testDBURL)
        await cache.upsert(original)
        let fetched = await cache.entry(at: "/test/file.txt")
        await cache.close()

        XCTAssertNotNil(fetched)
        guard let fetched else { return }
        XCTAssertEqual(fetched.path, original.path)
        XCTAssertEqual(fetched.parentPath, original.parentPath)
        XCTAssertEqual(fetched.inode, original.inode)
        XCTAssertEqual(fetched.mtime.timeIntervalSince1970,
                       original.mtime.timeIntervalSince1970,
                       accuracy: 0.001)
        XCTAssertEqual(fetched.size, original.size)
        XCTAssertEqual(fetched.childCount, original.childCount)
        XCTAssertEqual(fetched.isDirectory, original.isDirectory)
        XCTAssertEqual(fetched.lastScanned.timeIntervalSince1970,
                       original.lastScanned.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    // MARK: - Test 3: Upsert replaces on conflict

    /// Upserting the same path twice should replace the row; the second
    /// write wins on all fields.
    func testUpsertReplacesOnConflict() async {
        let cache = DiskCache(databaseURL: testDBURL)
        await cache.upsert(makeEntry(path: "/a", size: 100))
        await cache.upsert(makeEntry(path: "/a", size: 200))

        let result = await cache.entry(at: "/a")
        await cache.close()

        XCTAssertEqual(result?.size, 200, "Second upsert should overwrite size")
    }

    // MARK: - Test 4: upsertBatch inserts all entries

    /// Batch-inserting 50 entries should make all of them retrievable.
    func testUpsertBatchInsertsAll() async {
        let entries = (0..<50).map { i in
            makeEntry(path: "/batch/\(i)", parent: "/batch", inode: UInt64(i))
        }

        let cache = DiskCache(databaseURL: testDBURL)
        await cache.upsertBatch(entries)

        var missingCount = 0
        for entry in entries {
            let fetched = await cache.entry(at: entry.path)
            if fetched == nil { missingCount += 1 }
        }
        await cache.close()

        XCTAssertEqual(missingCount, 0, "All 50 batch entries should be retrievable")
    }

    // MARK: - Test 5: children returns only direct children

    /// `children(of:)` must return only immediate children, not grandchildren.
    func testChildrenReturnsOnlyDirectChildren() async {
        let cache = DiskCache(databaseURL: testDBURL)
        await cache.upsert(makeEntry(path: "/parent", parent: nil, isDirectory: true))
        await cache.upsert(makeEntry(path: "/parent/a", parent: "/parent", isDirectory: true))
        await cache.upsert(makeEntry(path: "/parent/b", parent: "/parent"))
        await cache.upsert(makeEntry(path: "/parent/a/grandchild", parent: "/parent/a"))

        let kids = await cache.children(of: "/parent")
        await cache.close()

        XCTAssertEqual(kids.count, 2, "Should return exactly 2 direct children")
        let paths = Set(kids.map { $0.path })
        XCTAssertTrue(paths.contains("/parent/a"))
        XCTAssertTrue(paths.contains("/parent/b"))
        XCTAssertFalse(paths.contains("/parent/a/grandchild"), "Grandchild must not appear")
    }

    // MARK: - Test 6: children empty for unknown parent

    /// Querying children of a path that has no rows in the cache returns [].
    func testChildrenEmptyForUnknownParent() async {
        let cache = DiskCache(databaseURL: testDBURL)
        let kids = await cache.children(of: "/nonexistent")
        await cache.close()

        XCTAssertTrue(kids.isEmpty, "children(of:) should return [] for unknown parent")
    }

    // MARK: - Test 7: flush removes all rows

    /// After `flush()`, every previously upserted path returns nil and
    /// `children(of:)` returns [].
    func testFlushRemovesAllRows() async {
        let cache = DiskCache(databaseURL: testDBURL)
        let entries = (0..<5).map { i in makeEntry(path: "/flush/\(i)") }
        await cache.upsertBatch(entries)

        await cache.flush()

        for entry in entries {
            let result = await cache.entry(at: entry.path)
            XCTAssertNil(result, "After flush, \(entry.path) should return nil")
        }
        let kids = await cache.children(of: "/flush")
        XCTAssertTrue(kids.isEmpty, "After flush, children should be empty")

        await cache.close()
    }

    // MARK: - Test 8: close is idempotent

    /// Calling `close()` twice must not crash or throw.
    func testCloseIsIdempotent() async {
        let cache = DiskCache(databaseURL: testDBURL)
        await cache.close()
        await cache.close() // second call — must be a no-op
    }

    // MARK: - Test 9: entry after close returns nil

    /// Per best-effort policy: after `close()`, `entry(at:)` returns nil.
    func testEntryAfterCloseReturnsNil() async {
        let cache = DiskCache(databaseURL: testDBURL)
        await cache.upsert(makeEntry(path: "/alive"))
        await cache.close()

        let result = await cache.entry(at: "/alive")
        XCTAssertNil(result, "entry(at:) should return nil after close()")
    }

    // MARK: - Test 10: reopen sees prior writes

    /// Closing and reopening the same database file must preserve written rows,
    /// verifying that writes are actually persisted to disk.
    func testReopenSeesPriorWrites() async {
        let mtime = Date(timeIntervalSince1970: 1_700_001_000)
        let entry = makeEntry(path: "/a", parent: nil, inode: 99, mtime: mtime, size: 512)

        let first = DiskCache(databaseURL: testDBURL)
        await first.upsert(entry)
        await first.close()

        let second = DiskCache(databaseURL: testDBURL)
        let fetched = await second.entry(at: "/a")
        await second.close()

        XCTAssertNotNil(fetched, "Reopened cache should find the previously written entry")
        guard let fetched else { return }
        XCTAssertEqual(fetched.inode, 99)
        XCTAssertEqual(fetched.size, 512)
        XCTAssertEqual(fetched.mtime.timeIntervalSince1970, mtime.timeIntervalSince1970, accuracy: 0.001)
    }
}
