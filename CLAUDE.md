# Burrow

A native macOS (SwiftUI) disk-cleanup app. Three pillars: **Analyze** disk usage,
**Clean** caches/junk, and **Uninstall** apps with their leftovers. Every destructive
action moves files to the Trash (reversible) and is recorded in an audit log.

- Bundle id: `fun.burrow` · Min target: macOS · Updater: Sparkle
- Companion docs: `SPEC.md` (behavior contract), `UI_ARCHITECTURE.md` (view layer),
  `ROADMAP.md` (planned work), `README.md`.

## Build / test / run

```
make build     # Build Debug
make run       # Build Debug and launch
make test      # Run unit tests (BurrowTests)
make release   # Full signed + notarized release (prompts for version)
make hooks     # Install git commit-msg hook
```

Xcode project: `Burrow.xcodeproj` (no SPM manifest; dependencies vendored under `build/SourcePackages`).

## Layout

```
Burrow/
  App/         BurrowApp.swift (entry), RootView.swift (3-tab shell)
  Core/        PathResolver (~ + glob expansion), SafeFileOps (the ONLY file mutator)
  Models/      Codable structs & value types (see "Key models")
  Services/    Scanners + engines (see "Services")
  ViewModels/  AnalyzeViewModel, CleanViewModel, UninstallViewModel (MVVM, @MainActor)
  Views/       Analyze/, Clean/, Uninstall/, Onboarding/, Settings/, Shared/
  Resources/   CleanRules.json (clean catalog), AppLeftovers.json (uninstall catalog), Assets
  Algorithms/  TreemapLayout (squarified treemap for Analyze)
BurrowTests/   Mirror of Services/Models/ViewModels (XCTest)
scripts/       release.sh, appcast.xml, ExportOptions.plist, icon generator
```

## Three features

| Tab | ViewModel | Engine(s) | Catalog |
|-----|-----------|-----------|---------|
| Analyze | `AnalyzeViewModel` | `DiskScanner`, `DiskCache`, `TreemapLayout` | — |
| Clean | `CleanViewModel` | `RuleEngine` + specialized scanners | `CleanRules.json` |
| Uninstall | `UninstallViewModel` | `AppScanner` | `AppLeftovers.json` |

## Clean pipeline (most relevant for adding cache categories)

1. `CleanViewModel.loadCatalog()` decodes `CleanRules.json` → `CleanCatalog` of `CleanCategory`.
2. `filterInstalled()` drops categories whose rule paths don't exist on disk.
3. `RuleEngine.scanAll(_:)` scans categories in parallel; each `CleanRule` resolves to
   `ScanItem`s (url + bytes) via `PathResolver`, filtered by the `SafeFileOps` deny-list.
4. UI groups categories by `CategoryGroup` → `CategoryGroupSection` → `CategoryRow`.
5. Apply: `RuleEngine.apply(_:dryRun:)` → `SafeFileOps.trash` (move to Trash) → `OperationLog`.

**Rule kinds** (`CleanRule.swift`): `directoryContents`, `glob`, `command`.
⚠️ `command` is **not executed** (Phase 1 — `RuleEngine.resolveRule` skips it). Anything
needing a CLI invocation (e.g. `docker system prune`) cannot use a rule and needs a
dedicated scanner/action instead.

### Adding a simple Clean category (no Swift)

Append an object to the `categories` array in `Burrow/Resources/CleanRules.json`:

```json
{
  "id": "developer.<name>", "title": "...", "summary": "...",
  "group": "developer", "icon": "<SFSymbol>", "risk": "low|medium|high",
  "defaultEnabled": true,
  "rules": [ { "kind": "directoryContents", "path": "~/..." },
             { "kind": "glob", "path": "~/.../*" } ]
}
```
It auto-loads, auto-filters by existence, scans, and displays — no code changes.

### Adding a specialized scanner (when rules aren't enough)

Pattern set by `NodeModulesScanner` / `FlutterProjectScanner`:
- A `Models/<X>Entry.swift` value type (url, bytes, mtimes, label).
- A `Services/<X>Scanner.swift` `actor` that walks the filesystem.
- `CleanViewModel` gets `@Published` arrays + a `scan<X>()` run inside `scanAll()`, plus
  its own `Views/Clean/<X>Section.swift`. Apply still routes through `SafeFileOps.trash`.

## Safety invariants (do not break)

- **`SafeFileOps` is the single mutation point.** `validate(_:)` enforces a deny-list
  (system dirs, and user roots like Documents/Desktop/Downloads) before any trash/delete.
- Everything is **moved to Trash** (`NSWorkspace.recycle`), never hard-deleted, except the
  explicit "Empty Trash" path (`permanentlyDelete`).
- Every action (including dry-runs) is appended to `OperationLog`.
- `olderThanDays` filters on mtime; files whose age can't be read are conservatively skipped.

## Conventions

- Commit messages: subject + `Co-Authored-By` footer only — no multi-paragraph bodies
  unless asked.
- SwiftUI tooltips: use the custom `Tooltip` modifier (`Views/Shared/Modifiers`), not
  `.help` (flaky in lazy containers).
- Logging: `os.Logger(subsystem: "fun.burrow", category: ...)`; user paths logged
  `.private`.
