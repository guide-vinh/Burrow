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
