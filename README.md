<p align="center">
  <img src="Burrow/Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" height="128" alt="Burrow icon" />
</p>

<h1 align="center">Burrow</h1>

<p align="center">
  Native macOS cleaner inspired by <a href="https://github.com/tw93/Mole">tw93/Mole</a>.<br/>
  Trash-first, JSON-driven, under 10&nbsp;MB, runs on macOS&nbsp;12+.
</p>

**Status:** Clean and Uninstall ship in v0.1.x. Analyze is paused behind a
"coming soon" placeholder while the cache layer is hardened — see
[ROADMAP.md](ROADMAP.md). Auto-update via Sparkle is wired up.

## Install

📥 **[Download Burrow-0.1.0.dmg](https://github.com/guide-vinh/Burrow/releases/download/v0.1.0/Burrow-0.1.0.dmg)** — signed + notarized, 1.6 MB.

Or browse all releases: <https://github.com/guide-vinh/Burrow/releases/latest>.

Open the DMG, drag **Burrow.app** to /Applications, launch. The app
checks for updates daily through Sparkle; force-check anytime via
**Burrow → Check for Updates…**.

## Why

Mole is excellent, but it's a CLI and runs `rm -rf`. CleanMyMac is 80 MB
and pushes a subscription. AppCleaner only does uninstall. DaisyDisk
only visualises. Burrow aims to combine clean + uninstall + analyze +
status in one native SwiftUI app, free and open source, that runs on a
4-year-old Intel MacBook with a full disk.

## Highlights

- **Native SwiftUI**, no Electron, no bundled runtime, target ≤ 10 MB
- **Trash-first** deletion via `NSWorkspace.recycle` — restorable from Finder
- **macOS 12 Monterey** minimum — supports older Intel Macs
- **JSON-driven** rule catalog — community PRs add caches without writing Swift
- **Per-rule risk levels** — low (caches), medium (saved state), high (user data)
- **Dry-run mode** — preview every byte before anything moves
- **Treemap disk analyzer** — squarified visualization of `~/` with
  click-to-zoom, top-largest + oldest-never-opened insights

## Feature parity with Mole

| Mole command | Burrow tab | Phase |
|---|---|---|
| `mo clean` | Clean | 1 |
| `mo uninstall` | Uninstall | 2 |
| `mo purge` | Uninstall (Projects subtab) | 2 |
| `mo installer` | Clean (Installers rule) | 1 |
| `mo analyze` | Analyze | 3 |
| `mo optimize` | Status (Optimize panel) | 3 |
| `mo status` | Status | 4 |

## Build from source

```
make hooks      # one-time, install commit-msg hook
make build      # Debug build
make run        # Debug + launch
make test       # unit tests
make release    # full release (prompts for version): sign + notarize + GitHub + appcast
```

## Contributing

Two easy paths into the project:

**Add a rule.** Edit `catalog/CleanRules.json` (later
`Burrow/Resources/CleanRules.json`). Found a new app whose cache should
be cleaned? Open a PR — no Swift required. The JSON schema is
documented in [SPEC.md §5](SPEC.md#5-rule-catalog-schema).

**Take a phase.** [ROADMAP.md](ROADMAP.md) lists what's next. Phase 2
(Smart Uninstall) and Phase 3 (Disk Analyzer with treemap) are the
biggest open chunks.

## Known Phase 1 limitations

Things that are intentionally deferred or scoped out for the v0.1.0
release. Each is tracked here so contributors don't re-discover them.

- **Catalog is a 2-category stub** (Chrome cache + system logs). The
  full 40+ category catalog is the highest-value Phase 1 follow-up;
  contributions welcome via JSON.
- **`requiresAppQuit` warn-before-delete** is parsed by the catalog
  loader but the engine doesn't gate on it yet. Phase 5 polish adds
  a confirmation sheet before deleting from a running app's data.
- **`.command` rule kind** parses cleanly but is skipped at scan time
  with a warning log. Execution of external programs (e.g.
  `brew cleanup`) lands with the privileged helper in Phase 3.
- **PathResolver glob** supports a single `*` per segment only; no `**`
  recursive globbing. Recursive scans (e.g. all `node_modules` under
  `~`) are deferred to Phase 2's user-configurable scan roots.
- **`exclude` paths** are matched byte-equal against the resolved file
  paths. macOS-canonicalized paths (`/private/var` instead of `/var`)
  are not normalized; production catalog excludes target
  `~/Library/...` which doesn't symlink, so this is unlikely to bite —
  but flagged for the record.
- **Operation log write failures** are caught and logged but do not
  stop the apply loop. Audit-trail gaps are possible if the log file
  cannot be written; the app continues to honor the user's intent.
- **`SafeFileOps.permanentlyDelete`** exists for the Empty Trash flow
  but has no UI consumer or test in Phase 1.
- **`FullDiskAccess.openSystemSettings()`** is not unit-tested — it
  opens a real System Settings window every run.
- **TCC permissions need a process restart** to take effect. macOS
  may show "Quit & Reopen" when the user toggles FDA, but ad-hoc
  signed dev builds often don't relaunch cleanly. The onboarding
  sheet exposes a "Quit Burrow" button so the user can quit + manually
  relaunch in two clicks. Signed/notarized release builds (Task 10)
  should let the system "Quit & Reopen" handle this automatically.
- **No window-state persistence** — sidebar selection and window
  position reset on every launch.
- **`@main App` body** can't be exercised by unit tests; verification
  is `make run` + visual inspection until UI tests are added in
  Phase 5.
- **Empty scan result** shows "Zero kB" instead of `—` in the size
  column. UX nit, fix in Phase 5 polish.
- **Analyze tab insights show empty "Oldest never opened"** when scanning
  a `noatime`-mounted volume. macOS does not record `atime` reliably on
  volumes mounted with `noatime`; Burrow detects this and shows
  "Last-access tracking disabled on this volume." instead of misleading
  results.
- **Analyze tab cache** lives at `~/Library/Application Support/fun.burrow/disk-cache.sqlite`
  and is keyed by `(inode, mtime)`. If you ever need to flush it, the
  Analyze tab's "⋯" menu has a "Reset Cache" action. The cache is
  best-effort — if SQLite errors out, scans transparently fall back to
  cold mode.

## Credits

- [tw93/Mole](https://github.com/tw93/Mole) — the path catalog in this
  repo derives from Mole's `lib/clean/*.sh`. Without 5 years of Mole
  community PRs this would be a year of trial and error. **Star their
  repo.**
- [AppCleaner](https://freemacsoft.net/appcleaner/) and
  [DaisyDisk](https://daisydiskapp.com/) for design inspiration.

## License

[MIT](LICENSE) — same as Mole.
