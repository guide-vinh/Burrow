# ROADMAP

## Phase 1 — MVP Cleaner (target: 2-3 weekends)

The "I can replace `mo clean` with a click" milestone. See SPEC.md §9 for
the concrete task list.

Acceptance: scan + trash + dry-run + FDA onboarding + signed DMG release.

## Phase 2 — Smart Uninstall (1-2 weekends)

Drag an app to the window, see all 47 of its leftover files, pick what to
remove. Plus the project artifact purge (`mo purge` equivalent) for
`node_modules`, `target`, `build`, `venv`, `dist`, etc., across user-
configurable scan roots.

Acceptance: drag-drop works, leftover list is accurate against AppCleaner
on the same set of apps, project purge respects a `> 7 days` age filter.

## Phase 3 — Disk Analyzer + Privileged Helper (3-4 weekends)

Two parallel tracks.

### Phase 3a — Disk Analyzer (✅ shipped)

Squarified treemap of `~/`, click-to-zoom, breadcrumb path, hash-derived
deterministic colors, in-memory cache for fast zoom across the same
scan. Insights side panel surfaces top-5 largest and oldest-never-opened
entries (atime-aware, degrades gracefully on `noatime` volumes). Move
to Trash routes through `SafeFileOps`, fully audit-logged.

- [x] `DiskScanner` actor with `AsyncThrowingStream` progress
- [x] Squarified treemap algorithm (Bruls et al. 1999)
- [x] `AnalyzeViewModel` driving treemap + insights
- [x] `TreemapCanvas`, `InsightsPanel`, `Breadcrumb`, `AnalyzeView`
- [x] Wired into the sidebar (Analyze tab)

### Phase 3b — Cache + perf (✅ shipped)

Per-folder sizes cached in SQLite keyed by `(inode, mtime)`. Cache
lives at `~/Library/Application Support/fun.burrow/disk-cache.sqlite`,
WAL journal mode, schema versioned via PRAGMA user_version. Best-effort:
SQLite errors fall back to non-cached scan rather than block. The
Analyze tab's overflow menu surfaces "Reset Cache" for the user.

- [x] `DiskCache` actor wrapping system `libsqlite3` (no GRDB)
- [x] `DiskScanner` consults the cache: `(inode, mtime)`-matched
      directories short-circuit via `enumerator.skipDescendants()`
- [x] Successful scans batch-upsert directories; failed/cancelled
      scans leave cache untouched
- [x] "Reset Cache" entry in the Analyze tab overflow menu

Performance acceptance (1M files / 500 GB target, 30s first / 3s
incremental) is a Task-9-style real-machine smoke test deferred to the
user — autopilot synthetic tests verify correctness and that the second
scan processes strictly fewer entries than the first.

### Phase 3c — Privileged helper (open)

`BurrowHelper` XPC target installed via `SMJobBless`. Implements rebuild
Spotlight, flush DNS, clear icon services cache. The main app's
"Optimize" tab calls into it. Acceptance: helper survives a reboot and
can be uninstalled cleanly.

## Phase 4 — Live Status (2 weekends)

Real-time CPU / memory / disk / network / battery tiles in the main
window, plus an optional menu bar extra via `NSStatusItem`. Health
score combining CPU load, memory pressure, disk usage, and uptime
(matching Mole's algorithm).

Acceptance: tiles update at 1 Hz without measurable CPU cost. Menu bar
icon respects light/dark mode.

## Phase 5 — Polish

Localization (vi-VN, zh-CN, en-US, ja-JP). Sparkle 2 auto-update.
Onboarding tour. Homebrew Cask formula. App icon + brand polish.

## Out of scope

See SPEC.md §10.
