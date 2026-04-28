# Phase 3b — Incremental Scan Cache — Journal

User authorized 3b directly: "ok just do 3b first". Operating per
PHASE3B_DECISIONS.md (system libsqlite3, Application Support DB,
inode+mtime invalidation, cache best-effort).

3 waves planned:
1. DiskCache service (CachedEntry model + actor + tests)
2. DiskScanner integration (consult cache during enumeration)
3. UI flush hook + docs

## Setup

- Reference doc PHASE3B_DECISIONS.md committed before any code work.
- Entry test count: 159 passing.
- Entry coverage on Phase 3a non-view modules: all ≥75%.

## Wave 1 — DiskCache service — DONE

**Files added:** 3
- `Burrow/Models/CachedEntry.swift` (14 lines)
- `Burrow/Services/DiskCache.swift` (332 lines, libsqlite3 wrapper actor)
- `BurrowTests/DiskCacheTests.swift` (230 lines, 10 tests)

**Tests:** 169 passing (was 159; +10).
**Coverage on DiskCache.swift:** 77.17% (196/254) — clears 75% bar.
**Build:** clean, zero compiler warnings.

### What got built

`actor DiskCache` against `import SQLite3`:
- Lazy production singleton at `~/Library/Application Support/fun.burrow/disk-cache.sqlite`.
- Test-friendly `init(databaseURL:)` for tmpdir isolation.
- Schema v1 (DECISIONS §3) with WAL journal, NORMAL synchronous,
  PRAGMA user_version migration.
- API per DECISIONS §11: `entry(at:)`, `upsert(_)`, `upsertBatch(_)`,
  `children(of:)`, `flush()`, `close()`.
- Best-effort error policy (DECISIONS §6): on any SQLite failure,
  log via os.Logger and return default (nil/empty/no-op). Public
  methods are non-throwing.
- Schema future-version detection (DECISIONS §7): user_version > 1
  disables the cache rather than trusting unknown schema.

### Issues encountered
- None requiring intervention. Sonnet completed in one pass.

### Deviations
- File ended at 332 lines vs ~250 estimate; extra lines are private
  `bindEntry`, `rowToEntry`, `performUpsert` helpers that decompose the
  upsert path cleanly. No logic added beyond spec.
- Test 10 (reopen) used `guard let` unwrap to satisfy XCTAssertEqual's
  `accuracy:` overload (TimeInterval, not TimeInterval?).

### Decisions confirmed
- Project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16 folder
  sync) — new files auto-pick up without project.pbxproj edits.
  Same auto-discovery seen during Phase 3a.
- SourceKit emits a Swift 6 future-mode warning at line 54 (`init`
  calling actor-isolated `openDatabase()`). Real Swift 5 compiler is
  silent; this is forward-compat noise. Refactor deferred to whenever
  the project flips to Swift 6 mode.

## Wave 2 — DiskScanner cache integration — DONE

**Files changed:** 2 modified
- `Burrow/Services/DiskScanner.swift` (+~60 lines)
- `BurrowTests/DiskScannerTests.swift` (+83 lines, 3 tests)

**Tests:** 172 passing (was 169; +3).
**Coverage:**
- DiskScanner.swift: 88.98% (412/463) — was 84.32%, IMPROVED
- DiskCache.swift:   80.31% (204/254) — was 77.17%, IMPROVED
**Build:** clean, zero compiler warnings.

### What got built

- `DiskScanner.init(cache: DiskCache = DiskCache.shared)` — preserves
  `DiskScanner.shared` while letting tests inject a tmpdir-backed cache.
- Cache-hit short-circuit (DECISIONS §10): inside `runScan`, when an
  enumerated URL is a directory and `(cached.inode == liveInode &&
  abs(cached.mtime - liveMtime) < 1s)`, synthesize a DiskEntry from the
  cached row, mirror the bubble-up + childCount logic, and call
  `enumerator.skipDescendants()`. Counts as 1 entriesScanned + adds
  cached.size to totalBytes.
- Cache hits/misses tracked per scan, logged via `os.Logger` at
  `.info`. Helps eyeball perf wins post-hoc.
- After a successful scan: batch-upsert all directory entries to the
  cache. Files NOT cached (DECISIONS §9). Failed/cancelled scans skip
  the upsert (preserves the invariant: cached rows reflect a complete
  subtree).

### Tests added
- `testFirstScanWritesCache` — first scan populates cache rows for
  directories.
- `testSecondScanReusesCacheForUnchangedSubtrees` — second scan reports
  same totalBytes but fewer entriesScanned (proof of cache hit).
- `testCacheInvalidatesWhenFileChanges` — modify file in subtree +
  touch dir mtime → second scan reflects new larger size.

### Issues encountered
- Sonnet found `.fileSystemFileNumberKey` is not a Swift-exposed
  `URLResourceKey` static member on macOS 12. Worked around using
  `FileManager.attributesOfItem(atPath:)[.systemFileNumber]` via a
  private `static func inodeOf(_:)` helper. Behavior equivalent.
- Test 3 (mtime invalidation) needed a `Task.sleep(nanoseconds:
  1_200_000_000)` + explicit `setAttributes([.modificationDate: Date()])`
  on the directory to defeat APFS mtime granularity. No flakiness in 5
  consecutive runs.

### Deviations from PHASE3B_DECISIONS.md
- §10 spec named `URLResourceKey.fileSystemFileNumberKey`; actual
  implementation uses `FileManager` attributes due to macOS 12 SDK
  exposure. Functionally identical.

### Decisions confirmed
- Cache injection via `init(cache:)` parameter (no setter) — mirrors
  the AnalyzeViewModel closure-injection pattern from Phase 3a.

## Wave 3 — UI flush hook + docs — DONE

**Files changed:** 4 modified
- `Burrow/ViewModels/AnalyzeViewModel.swift` (+8 lines: resetCache())
- `Burrow/Views/Analyze/AnalyzeView.swift` (+13 lines: overflow Menu)
- `ROADMAP.md` (Phase 3b → ✅ shipped)
- `README.md` (status update + cache-location entry)

**Tests:** 172 passing / 172 total — unchanged (no new tests; UI hook
exercises existing cache flush method).
**Build:** clean.

### What got built
- `AnalyzeViewModel.resetCache() async` — calls `DiskCache.shared.flush()`,
  logs via os.Logger. Does NOT clear in-memory state (visibleEntries,
  breadcrumb, insights stay) so the user can keep navigating until
  they explicitly hit Rescan.
- AnalyzeView header gains a SwiftUI `Menu` triggered by an
  `ellipsis.circle` icon button placed right of the existing Rescan
  button. Menu currently has one entry: "Reset Cache" with
  `role: .destructive`. `.menuStyle(.borderlessButton)` to keep it
  visually quiet.

### Doc updates
- ROADMAP §"Phase 3b" rewritten: open → ✅ shipped, with checkbox list
  of the four delivered building blocks. Performance-target sentence
  reframed as "Task-9-style deferred smoke test" (per DECISIONS §13).
- README "Highlights": no change (the existing treemap analyzer bullet
  covers 3a + 3b together — the cache is invisible perf, not a user-
  facing feature).
- README "Known limitations": "in-memory only" entry replaced with
  "cache location + Reset Cache hint + best-effort fallback".
- README status line: "Phases 1–3a complete" → "Phases 1, 2, 3a, 3b".

### Issues encountered
- None.

### Decisions confirmed
- "Reset Cache" UX placement: SwiftUI `Menu` next to Rescan button,
  not a Settings/Preferences pane. Reset is rare but should be reachable
  from the same context where the user noticed something was wrong.

## Phase 3b — Autopilot session summary

**Tasks delivered:** Wave 1 (DiskCache service), Wave 2 (DiskScanner
integration), Wave 3 (UI flush hook + docs).

**Commits (this session):**
- `eff9d9b` docs: add phase 3b planning documents
- `c11258a` add: disk cache actor backed by sqlite
- `37ace86` improve: wire disk cache into scanner
- (this commit) docs: mark phase 3b complete + reset-cache UI

**Test count progression:** 159 (entry) → 169 → 172 → 172.

**Coverage on new + touched non-view modules** (all ≥75% bar):
- DiskCache.swift:    80.31% (204/254)
- DiskScanner.swift:  88.98% (412/463)  ← improved from 84.32%

**Stop conditions triggered:** none.
**Compiler warnings:** zero.
**SourceKit Swift-6-future-mode warnings:** one (DiskCache init calling
actor-isolated openDatabase). Real Swift 5 compiler silent. Not blocking.

**Compliance:** No GRDB or any new SPM dependency. No macOS 13+ APIs.
SafeFileOps gate untouched. All Phase 1/2/3a tests still passing.

**Performance validation:** synthetic 5K-file tests verify the cache
*does* short-circuit (second scan reports fewer entriesScanned, same
totalBytes, same final tree). The 30s/3s ROADMAP targets remain a
real-~/ smoke test for the user (see Task 9 deferral note in
PHASE3_JOURNAL.md).
