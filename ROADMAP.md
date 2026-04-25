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

The visualizer: squarified treemap of `~/`, click-to-zoom, breadcrumb
path, per-folder size cached in a SQLite db keyed by inode + mtime so
re-scans are incremental.

The privileged helper: `BurrowHelper` XPC target installed via
`SMJobBless`. Implements rebuild Spotlight, flush DNS, clear icon
services cache. The main app's "Optimize" tab calls into it.

Acceptance: treemap renders 1M files / 500 GB home directory in under 30
seconds on first scan, under 3 seconds incremental. Helper survives a
reboot and can be uninstalled cleanly.

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
