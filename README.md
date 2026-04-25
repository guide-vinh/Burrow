# 🐹 Burrow

> Native macOS cleaner inspired by [tw93/Mole](https://github.com/tw93/Mole).
> Trash-first, JSON-driven, under 10 MB, runs on macOS 12+.

**Status:** specification stage. See [SPEC.md](SPEC.md) and
[ROADMAP.md](ROADMAP.md). First release `v0.1.0` is in progress.

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

## Status

Phase 1 in progress. Watch [Releases](../../releases) for the first DMG.

## Contributing

Two easy paths into the project:

**Add a rule.** Edit `catalog/CleanRules.json` (later
`Burrow/Resources/CleanRules.json`). Found a new app whose cache should
be cleaned? Open a PR — no Swift required. The JSON schema is
documented in [SPEC.md §5](SPEC.md#5-rule-catalog-schema).

**Take a phase.** [ROADMAP.md](ROADMAP.md) lists what's next. Phase 2
(Smart Uninstall) and Phase 3 (Disk Analyzer with treemap) are the
biggest open chunks.

## Credits

- [tw93/Mole](https://github.com/tw93/Mole) — the path catalog in this
  repo derives from Mole's `lib/clean/*.sh`. Without 5 years of Mole
  community PRs this would be a year of trial and error. **Star their
  repo.**
- [AppCleaner](https://freemacsoft.net/appcleaner/) and
  [DaisyDisk](https://daisydiskapp.com/) for design inspiration.

## License

[MIT](LICENSE) — same as Mole.
