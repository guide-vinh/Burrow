# SPEC — Burrow

> **Read this entire document before writing a single line of Swift.**
> This is the source of truth for architectural decisions. ROADMAP.md
> describes *what* to build and in what order; this document describes *how*.

---

## 1. Vision

Burrow is a native macOS cleaner inspired by [tw93/Mole](https://github.com/tw93/Mole).
Mole is a CLI; Burrow is a GUI. The goal is feature parity with Mole's clean /
uninstall / analyze / status commands, in a SwiftUI app under 10 MB that runs
on a 4-year-old Intel MacBook Pro with a full disk.

Target user: a developer whose disk is at 95 % capacity, has never heard of
`du -sh`, and gives up on CleanMyMac because it's 80 MB and pushes a
subscription.

---

## 2. Hard constraints

These are non-negotiable. Violations are bugs.

| Constraint | Why |
|---|---|
| Min target **macOS 12.0 Monterey** | User base on Intel Macs that can't go higher |
| **Not sandboxed** | Sandboxing forbids reading `~/Library/` outside the app's container |
| Distributed **outside Mac App Store** | Consequence of the above |
| **Move to Trash by default** | Permanent deletion only on explicit opt-in |
| **MIT license** | Same as Mole; required for path-catalog reuse |
| **App bundle ≤ 10 MB** | A cleaner app must not itself eat the disk |
| **No external runtime** (no Electron, no Tauri, no Node) | Defeats the size constraint |
| **All destructive ops go through one validator** | Auditability |
| **Path catalog lives in JSON, not Swift** | Community PRs without compile step |

---

## 3. Tech stack

| Layer | Choice | Rationale |
|---|---|---|
| Language | Swift 5.7+ | Bundled with Xcode 14+, compatible with macOS 12 |
| UI | SwiftUI 3 (macOS 12 baseline) | Native, lightweight, future-proof |
| Concurrency | Swift Concurrency (`async/await` + `actor`) | Available on macOS 12+ |
| State | `ObservableObject` + `@Published` + `@StateObject` | `@Observable` macro is macOS 14+ |
| Navigation | `NavigationView` with `.columns` style | `NavigationSplitView` is macOS 13+ |
| File ops | `FileManager` + `URL` resource values | No POSIX, no `system()` |
| Trash | `NSWorkspace.recycle` | Apple-blessed, restorable from Finder |
| Menu bar (Phase 4) | `NSStatusItem` (AppKit) | `MenuBarExtra` is macOS 13+ |
| Privileged ops (Phase 3) | `SMJobBless` helper tool | Deprecated but works on 12–15 |
| Auto-update | [Sparkle 2](https://sparkle-project.org/) | De facto standard outside MAS |
| Logging | `os.Logger` | Free, structured, no dep |
| Build | Xcode project (`.xcodeproj`) | SPM works but Xcode handles entitlements better |

### macOS 12 compatibility notes

When Claude Code suggests an API, check this list first:

```
✅ async/await, Task, actor             (macOS 10.15+)
✅ ObservableObject, @Published         (macOS 10.15+)
✅ NavigationView, NavigationLink       (macOS 10.15+, deprecated 13+)
✅ ScrollView, LazyVStack, List         (macOS 12+)
✅ NSWorkspace.recycle                  (macOS 10.6+)
✅ FileManager.enumerator               (always)
✅ os.Logger                            (macOS 11+)
✅ AsyncStream                          (macOS 12+)
✅ withTaskGroup                        (macOS 12+)

❌ @Observable macro                    (macOS 14+)  → use ObservableObject
❌ NavigationSplitView                  (macOS 13+)  → use NavigationView
❌ NavigationStack                      (macOS 13+)  → use NavigationView
❌ MenuBarExtra                         (macOS 13+)  → use NSStatusItem
❌ ContentUnavailableView               (macOS 14+)  → build custom empty state
❌ SMAppService                         (macOS 13+)  → use SMJobBless
❌ url.appending(path:)                 (macOS 13+)  → use appendingPathComponent
❌ .containerBackground                 (macOS 14+)  → use .background
❌ TipKit                               (macOS 14+)  → not used
❌ Symbol effects (.symbolEffect)       (macOS 14+)  → static SF Symbols only
```

Set `MACOSX_DEPLOYMENT_TARGET = 12.0` in the Xcode project. Xcode will
underline anything from a higher version.

---

## 4. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  SwiftUI Views     CleanView · UninstallView · AnalyzeView   │
└────────────────────────────┬─────────────────────────────────┘
                             │ @Published
┌────────────────────────────▼─────────────────────────────────┐
│  ViewModels        @MainActor ObservableObjects              │
└────────────────────────────┬─────────────────────────────────┘
                             │ async
┌────────────────────────────▼─────────────────────────────────┐
│  Engine            actor RuleEngine, actor AppScanner        │
└──────┬───────────────────┬───────────────────┬───────────────┘
       │                   │                   │
       ▼                   ▼                   ▼
  PathResolver        SafeFileOps        BurrowHelper (XPC, P3)
  (tilde + glob)      (validate +        SMJobBless privileged
                       trash + size)     mdutil/dscacheutil
```

### Module responsibilities

**`Models/`** — Pure Codable structs that map to `CleanRules.json`
(`CleanCategory`, `CleanRule`, `RiskLevel`, `CategoryGroup`) plus runtime
types (`ScanResult`, `ScanItem`, `InstalledApp`, `OperationLogEntry`). No
behaviour, only data.

**`Core/PathResolver`** — Static functions to expand `~` and resolve glob
patterns containing `*`. Required because rules use shell-style paths.

**`Core/SafeFileOps`** — *The* single point where the file system is
mutated. Three responsibilities: validate (deny-list of protected paths),
trash (move to `~/.Trash` via `NSWorkspace.recycle`), and size (recursive
allocated-size measurement). If anything wants to delete, it calls here.

**`Core/RuleEngine`** — `actor` that loads `CleanRules.json` and exposes
`scan(category)` and `apply(scanResult, dryRun:)`. Uses `withTaskGroup`
to scan all categories in parallel. Writes every operation to
`OperationLog`.

**`Services/AppScanner`** — `actor` that enumerates `/Applications`,
`~/Applications`, `/Applications/Utilities`, parses each `.app/Contents/
Info.plist`, and (for the Uninstall feature) finds leftover files by
expanding patterns from `AppLeftovers.json` against an app's bundle ID.

**`Services/OperationLog`** — `actor` writing JSONL entries to
`~/Library/Logs/Burrow/operations.log`. Append-only, used for forensics
and the "what did I delete?" history view.

**`Services/FullDiskAccess`** — Probes a path that requires FDA
(`~/Library/Safari/CloudTabs.db` is reliable). Routes user to System
Settings via the `x-apple.systempreferences:` URL scheme on first run.

**`ViewModels/`** — One per tab. `@MainActor`, `ObservableObject`. Holds
`@Published` UI state and forwards user actions to the engine.

**`Views/`** — One per tab. Stateless w.r.t. data; binds to its view
model.

---

## 5. Rule catalog schema

The two JSON files in `catalog/` (to be moved into the Xcode project's
`Resources/` folder) are the most valuable artifact in this repo. They
encode 5 years of Mole community knowledge.

### CleanRules.json

```json
{
  "schemaVersion": 1,
  "categories": [
    {
      "id": "browser.chrome",
      "title": "Google Chrome",
      "summary": "Cache, code cache, GPU and shader caches",
      "group": "browser",
      "icon": "globe",
      "risk": "low",
      "defaultEnabled": true,
      "requiresAppQuit": "com.google.Chrome",
      "rules": [
        { "kind": "directoryContents",
          "path": "~/Library/Caches/Google/Chrome" },
        { "kind": "glob",
          "path": "~/Library/Application Support/Google/Chrome/*/Cache" }
      ]
    }
  ]
}
```

Three rule kinds:

- **`directoryContents`** — empty the directory but keep the dir itself
- **`glob`** — resolve `*` segments and remove each match
- **`command`** — run an external program (e.g. `brew cleanup`)

Optional fields per rule:

- `olderThanDays` — only delete entries last accessed > N days ago
- `includeHidden` — include dotfiles (Trash needs this; Mole had a bug here)
- `needsPrivilege` — requires root, route through helper tool
- `exec`, `args` — for `kind: command`

Per-category fields:

- `risk` — `low` (caches), `medium` (saved state), `high` (user data); UI
  shows a coloured pill and refuses to default-enable medium/high
- `defaultEnabled` — pre-checked for the user
- `requiresAppQuit` — bundle ID; if running, scan but warn before delete
- `exclude` — paths to skip even when matched by a rule

### AppLeftovers.json

Templates for Phase 2 smart uninstall. `{bundleId}` and `{name}` are
substituted at scan time.

```json
{
  "userPaths": [
    "~/Library/Application Support/{bundleId}",
    "~/Library/Caches/{bundleId}",
    "~/Library/Preferences/{bundleId}.plist",
    "~/Library/Saved Application State/{bundleId}.savedState",
    "~/Library/Containers/{bundleId}",
    "~/Library/Group Containers/group.{bundleId}",
    "~/Library/LaunchAgents/{bundleId}.plist"
  ],
  "systemPaths": [
    "/Library/LaunchDaemons/{bundleId}.plist",
    "/Library/PrivilegedHelperTools/{bundleId}",
    "/private/var/db/receipts/{bundleId}.bom"
  ]
}
```

In addition to template expansion, the scanner walks
`~/Library/Group Containers`, `~/Library/Containers`, and
`~/Library/Application Scripts` looking for entries whose name *contains*
the bundle ID. This catches Apple-style `<teamID>.<bundleID>` group
containers without requiring the team ID up front.

---

## 6. Safety model

The single most important rule: **`SafeFileOps` is the only module that
calls `removeItem` or `recycle`**. Every URL passes through `validate(_:)`
first.

`validate(_:)` rejects URLs whose `standardizedFileURL.path`:

1. equals or is under `/System`, `/usr`, `/bin`, `/sbin`, `/Applications`,
   `/Library/Apple`, `/private/etc`, `/private/var/db/sudo`,
   `/private/var/db/dslocal`
2. equals the *root* of `~/Documents`, `~/Desktop`, `~/Downloads`,
   `~/Movies`, `~/Music`, `~/Pictures`, `~/Public` (children are fine — we
   want to delete `~/Downloads/old.dmg`, not `~/Downloads`)
3. does not exist (caller bug, fail loudly)

If a rule's resolved path fails validation, log a warning and skip.
Never let a single bad rule abort the whole scan.

### Default action: trash, not delete

`SafeFileOps.trash(_:)` calls `NSWorkspace.recycle` which moves the URL
to the user's `~/.Trash`. The user can restore from Finder. This is the
single biggest safety upgrade over Mole's `rm -rf`.

`SafeFileOps.permanentlyDelete(_:)` exists but is only called from one
place: the "Empty Trash" rule. Every other code path uses `trash(_:)`.

### Dry run

Every destructive function takes `dryRun: Bool`. When true, it computes
the size and returns the outcome without touching the file system. The
UI surfaces a global "Dry run" toggle that flips this on every call.

### Operation log

Every trash / delete / exec operation writes a JSONL line to
`~/Library/Logs/Burrow/operations.log` with timestamp, action, target,
bytes, and dryRun flag. Used by the future "History" view and by users
trying to remember what they let the app do.

---

## 7. Distribution and signing

Release process:

1. Build Universal Binary (`arm64 + x86_64`) via Xcode Archive
2. Sign with **Developer ID Application** certificate (requires Apple
   Developer Program, $99/year)
3. Enable **Hardened Runtime** with these entitlements only:
   - `com.apple.security.files.user-selected.read-write` (drag-drop apps)
   - `com.apple.security.automation.apple-events` (for `requiresAppQuit`)
4. Submit for **notarization** with `notarytool`
5. **Staple** the ticket onto the `.app`
6. Wrap in DMG with `create-dmg`
7. Upload to GitHub Releases + update Homebrew Cask formula

A GitHub Action handles steps 1-7 on every git tag matching `v*`. The
Apple Developer ID cert is stored as a GitHub secret (base64 of `.p12`).

### Privileged helper (Phase 3)

The `BurrowHelper` target is a separate executable installed to
`/Library/PrivilegedHelperTools/fun.burrow.helper` via `SMJobBless`. The
main app sends XPC messages; the helper runs the privileged work.

Helper-only operations:

- `mdutil -E /` (rebuild Spotlight index)
- `killall -HUP mDNSResponder` (reset DNS)
- `rm -rf /Library/Caches/com.apple.iconservices.store`
- Reading system-wide log directories under `/Library/Logs/`

Both binaries must be signed with the same Team ID; helper's
`Info.plist` lists the main app's designated requirement and vice
versa. This is fiddly — see [Apple's EvenBetterAuthorizationSample]
(https://github.com/erikberglund/SwiftPrivilegedHelper) for a working
modern example.

---

## 8. UI structure

Sidebar with four destinations, each a separate view.

```
┌──────────┬─────────────────────────────────────────┐
│  Clean   │                                         │
│  Uninst. │                                         │
│  Analyze │           [tab content here]            │
│  Status  │                                         │
│          │                                         │
└──────────┴─────────────────────────────────────────┘
```

Use `NavigationView { sidebar; detail }` (NOT `NavigationSplitView`).
Set `.navigationViewStyle(.columns)`.

### Clean view (Phase 1, MVP)

Three vertical zones:

1. **Header**: app icon + reclaim total + "Dry run" toggle + "Scan" button
2. **Body**: `ScrollView` with sections grouped by `CategoryGroup`. Each
   section has a "Select all" toggle and rows of categories with risk
   pill, summary, and size on the right.
3. **Footer**: `n selected · ~X.X GB` and a primary "Move to Trash"
   button (text changes to "Preview" in dry-run mode).

### Uninstall view (Phase 2)

Two columns. Left: searchable list of installed apps with icons,
versions, last-opened dates, and bundle sizes. Right: when an app is
selected, the `.app` bundle row + a list of detected leftover files
with checkboxes, all pre-checked.

### Analyze view (Phase 3)

A treemap (custom `Canvas` drawing using a squarified treemap algorithm)
of the user's home directory, with click-to-zoom and a breadcrumb path.
Right panel shows largest files / oldest never-opened files.

### Status view (Phase 4)

Live tiles for CPU / memory / disk / network / battery, similar to
Mole's `mo status` TUI. Pulls metrics from `host_statistics64`,
`IOPSCopyPowerSourcesByType`, and `getifaddrs`. Optional menu bar
extra (`NSStatusItem`).

---

## 9. Phase 1 deliverables (do these first)

Concrete tasks to ship `v0.1.0`. Each one should be a separate commit.

1. Init Xcode project. Bundle ID `fun.burrow.app`. Min target macOS 12.
   Disable App Sandbox. Add Hardened Runtime entitlements. Universal binary.
2. Add `catalog/CleanRules.json` and `catalog/AppLeftovers.json` to the
   project's Resources copy phase.
3. Implement `Models/` (Codable structs, no behaviour).
4. Implement `Core/PathResolver` with unit tests using a tmpdir fixture.
   Test cases: tilde expansion, single `*`, `*` mid-path, no-match returns
   empty.
5. Implement `Core/SafeFileOps` with unit tests. Test the deny-list with
   `/System`, `~/Documents`. Test trash with a fixture file.
6. Implement `Services/OperationLog` and write a smoke test that
   round-trips an entry through the file.
7. Implement `Core/RuleEngine` actor. Unit-test scan against a synthetic
   category pointing at a tmpdir.
8. Implement `Services/FullDiskAccess`.
9. Implement `ViewModels/CleanViewModel`.
10. Implement `Views/CleanView` and `BurrowApp` entry point.
11. Wire up an onboarding sheet that shows on first launch if FDA is
    not granted, with a "Open Settings" button.
12. Set up a release workflow: GitHub Action that signs, notarizes,
    staples, builds DMG, uploads to a draft release on tag push.

Acceptance criteria for `v0.1.0`:

- Builds clean on Xcode 15+ with zero warnings under macOS 12 deployment target
- All unit tests pass
- Scan all 40+ categories on a real machine in < 5 seconds
- "Move to Trash" actually moves to Trash and the user can restore from Finder
- Dry run reports a non-zero size and changes nothing on disk
- Onboarding correctly detects missing FDA and recovers after grant

---

## 10. Things explicitly out of scope

Don't let scope creep waste time on:

- Mac App Store version (impossible due to sandbox)
- iOS / iPadOS port (Burrow is a desktop tool)
- Memory "freeing" / RAM cleaner (placebo)
- Internet speed test
- Antivirus / malware scanning
- Login items management (System Settings handles this)
- Telemetry without explicit opt-in
- Cloud sync of settings
- Plugin system (revisit in Phase 5+ if there's demand)
