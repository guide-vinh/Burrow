# UI ARCHITECTURE

> The contract for how SwiftUI code is organized in Burrow. Read this
> before writing any view code. Every rule here exists because we hit
> the failure mode it prevents in some other project.

---

## 1. North star

A new contributor should be able to:

- Find any view by its name without searching (predictable folder layout)
- Change a color once and have it propagate everywhere (design tokens)
- Add a new screen without touching existing screens (composition over inheritance)
- Read a screen file in 5 minutes and understand what it does (small files, descriptive names)

If a change you're about to make would violate any of those, stop and find
a different approach.

---

## 2. Folder structure

```
Burrow/
├── Burrow/
│   ├── App/
│   │   ├── BurrowApp.swift              ← @main, WindowGroup
│   │   └── RootView.swift                ← NavigationView shell, tab routing
│   │
│   ├── Models/
│   │   ├── CleanCategory.swift           ← matches CleanRules.json
│   │   ├── CleanRule.swift
│   │   ├── RiskLevel.swift
│   │   ├── CategoryGroup.swift
│   │   ├── ScanItem.swift
│   │   ├── ScanResult.swift
│   │   ├── InstalledApp.swift            ← Phase 2
│   │   └── OperationLogEntry.swift
│   │
│   ├── Core/
│   │   ├── PathResolver.swift            ← tilde + glob expansion
│   │   └── SafeFileOps.swift             ← THE deletion gate
│   │
│   ├── Services/
│   │   ├── RuleEngine.swift              ← actor, scan + apply
│   │   ├── AppScanner.swift              ← actor, Phase 2
│   │   ├── OperationLog.swift            ← actor, JSONL audit log
│   │   └── FullDiskAccess.swift          ← FDA detection (per SPEC section 4)
│   │
│   ├── ViewModels/
│   │   ├── CleanViewModel.swift          ← @MainActor ObservableObject
│   │   ├── UninstallViewModel.swift      ← Phase 2
│   │   ├── AnalyzeViewModel.swift        ← Phase 3
│   │   └── StatusViewModel.swift         ← Phase 4
│   │
│   ├── Views/
│   │   ├── Clean/
│   │   │   ├── CleanView.swift           ← the screen, composes children
│   │   │   ├── CleanHeader.swift
│   │   │   ├── CleanFooter.swift
│   │   │   ├── CategoryGroupSection.swift
│   │   │   └── CategoryRow.swift
│   │   │
│   │   ├── Uninstall/                    ← Phase 2
│   │   ├── Analyze/                      ← Phase 3
│   │   ├── Status/                       ← Phase 4
│   │   ├── Onboarding/
│   │   │   └── FullDiskAccessSheet.swift
│   │   │
│   │   └── Shared/
│   │       ├── Components/
│   │       │   ├── RiskPill.swift
│   │       │   ├── BurrowCheckbox.swift
│   │       │   ├── PrimaryButton.swift
│   │       │   ├── DestructiveButton.swift
│   │       │   ├── OutlineButton.swift
│   │       │   ├── SidebarRow.swift
│   │       │   ├── BurrowToggle.swift     ← iOS-style switch
│   │       │   ├── EmptyState.swift
│   │       │   ├── SectionLabel.swift     ← caps small label
│   │       │   └── BrandLogo.swift
│   │       │
│   │       ├── Modifiers/
│   │       │   ├── CardStyle.swift        ← surface-secondary card
│   │       │   ├── SidebarStyle.swift
│   │       │   └── HoverEffect.swift
│   │       │
│   │       └── Style/
│   │           ├── DesignTokens.swift     ← colors, spacing, radii
│   │           ├── Typography.swift       ← Font extensions
│   │           ├── Iconography.swift      ← SF Symbol mapping
│   │           └── ColorExtensions.swift  ← Color from hex helper
│   │
│   ├── Resources/
│   │   ├── CleanRules.json
│   │   ├── AppLeftovers.json
│   │   └── Assets.xcassets/
│   │
│   └── Info.plist
│
└── BurrowTests/
    ├── PathResolverTests.swift
    ├── SafeFileOpsTests.swift
    ├── RuleEngineTests.swift
    └── ModelsTests.swift
```

### Folder rules

- **One file per type.** No exceptions. `RiskLevel` enum and its
  extensions live together in `RiskLevel.swift`. A second public type
  goes in its own file.
- **Folders match feature domain, not technical layer**, except at the
  top level. `Views/Clean/` holds *all* views for the Clean tab — the
  screen, header, footer, rows. They're cohesive; keep them adjacent.
- **`Shared/` is for reuse across ≥ 2 screens.** Don't preemptively put
  things there. If `RiskPill` only appears in Clean, it lives under
  `Views/Clean/Components/RiskPill.swift` until Phase 2 needs it too,
  at which point you move it.
- **No nested groups beyond what's shown.** Three levels of folder is
  the limit (`Views/Clean/Components/`).

---

## 3. Naming conventions

| Kind | Pattern | Example |
|---|---|---|
| Screen views | `<Feature>View` | `CleanView`, `UninstallView` |
| Sub-views of a screen | `<Feature><Part>` | `CleanHeader`, `CleanFooter` |
| Reusable components | `<Noun>` (no `View` suffix) | `RiskPill`, `BurrowCheckbox` |
| View models | `<Feature>ViewModel` | `CleanViewModel` |
| Models (Codable structs from JSON) | singular noun | `CleanCategory`, `CleanRule` |
| Actors | `<Noun>` | `RuleEngine`, `AppScanner` |
| Modifiers | `<Adjective>Style` or `<Verb>Effect` | `CardStyle`, `HoverEffect` |
| Files | match the principal type's name | `RiskPill.swift` contains `struct RiskPill` |

Naming bans:

- ❌ `Manager` — vague. Prefer `Service`, `Engine`, `Scanner`, or a
  domain noun.
- ❌ `Helper`, `Util`, `Utility` — vague. Find a real noun.
- ❌ `MyCleaner`, `BurrowCleaner` — Burrow IS the cleaner, redundant.
- ❌ `XCleanRules.json` — no leading X to mean "data".

Naming preferences:

- ✅ `Burrow` prefix on shared components when the unprefixed name would
  collide with a SwiftUI type. `Toggle` exists in SwiftUI, so
  `BurrowToggle` wraps it. But `Pill` doesn't exist, so just `RiskPill`.
- ✅ Domain language over technical language. "Category", "Rule",
  "Leftover" come from the cleaner domain. Don't translate them to
  "Item", "Record", "Entity".

---

## 4. Design tokens

### Source of truth: `DesignTokens.swift`

Every color, spacing value, corner radius, and font size used in views
comes from here. Views never literal a hex code or pixel value.

```swift
// DesignTokens.swift — the entire visual contract of the app

import SwiftUI

// MARK: - Color

extension Color {

    // Surface
    static let surfacePrimary    = Color(hex: 0xFFFEFC)
    static let surfaceSecondary  = Color(hex: 0xFAF7F4)
    static let surfaceTertiary   = Color(hex: 0xF2EDE8)
    static let surfaceInverse    = Color(hex: 0xFF7A59)
    static let surfaceInverseSoft = Color(hex: 0xFFE4DC)

    // Foreground
    static let fgPrimary    = Color(hex: 0x2A2522)
    static let fgSecondary  = Color(hex: 0x6B6360)
    static let fgMuted      = Color(hex: 0x9C928C)
    static let fgInverse    = Color.white

    // Accent (warm coral)
    static let accentPrimary       = Color(hex: 0xFF7A59)
    static let accentPrimaryHover  = Color(hex: 0xE85D3C)
    static let accentSoft          = Color(hex: 0xFFF1ED)

    // Destructive
    static let destructive      = Color(hex: 0xDC2626)
    static let destructiveHover = Color(hex: 0xB91C1C)

    // Borders
    static let borderSubtle = Color(hex: 0xEDE6DF)

    // Risk level pairs (background, foreground)
    enum Risk {
        static let lowBG  = Color(hex: 0xE8F5E9)
        static let lowFG  = Color(hex: 0x2E7D32)
        static let medBG  = Color(hex: 0xFFF4E5)
        static let medFG  = Color(hex: 0xB45309)
        static let highBG = Color(hex: 0xFEE2E2)
        static let highFG = Color(hex: 0xB91C1C)
    }
}

// MARK: - Spacing — 4pt grid

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Radii

enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let pill: CGFloat = 9999
}
```

### Color extension for hex literals

`ColorExtensions.swift`:

```swift
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex & 0xFF0000) >> 16) / 255
        let g = Double((hex & 0x00FF00) >> 8)  / 255
        let b = Double(hex & 0x0000FF)         / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
```

This is the **only** place in the codebase that's allowed to convert hex
to Color. Every view uses the named tokens above.

### Typography

Bundling the Geist font from the Pencil mockup adds ~600 KB and licensing
overhead. Use SF Pro Rounded instead — Apple's friendliest system font,
available on every macOS, free, and matches the warm tone of coral
better than default SF Pro.

`Typography.swift`:

```swift
import SwiftUI

extension Font {
    // Display & headlines
    static let displayXL  = Font.system(size: 32, weight: .semibold, design: .rounded)
    static let titleL     = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let titleM     = Font.system(size: 16, weight: .semibold, design: .rounded)

    // Body
    static let bodyM      = Font.system(size: 14, weight: .regular, design: .rounded)
    static let bodyS      = Font.system(size: 13, weight: .regular, design: .rounded)
    static let bodySMed   = Font.system(size: 13, weight: .medium,  design: .rounded)

    // Caption / labels
    static let captionM   = Font.system(size: 12, weight: .regular, design: .rounded)
    static let captionS   = Font.system(size: 11, weight: .regular, design: .rounded)
    static let pill       = Font.system(size: 10, weight: .semibold, design: .rounded)

    // Mono — sizes
    static let monoM      = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let monoS      = Font.system(size: 11, weight: .regular, design: .monospaced)
}
```

Use these tokens, never inline `.font(.system(size: 14))`. If a new
weight/size is needed, add a token here first, with a name explaining
its intent.

### Iconography

Map the lucide names from the Pencil mockup to SF Symbols. SF Symbols
ship with macOS for free; lucide would need bundling.

`Iconography.swift`:

```swift
import Foundation

/// Maps a category icon string from CleanRules.json (lucide-style name)
/// to an SF Symbol available on macOS 12+.
enum Iconography {

    static func sfSymbol(for token: String) -> String {
        switch token {
        case "trash", "trash-2":         return "trash"
        case "doc-zipper":               return "doc.zipper"
        case "doc-text", "scroll-text":  return "doc.text"
        case "alert-triangle":           return "exclamationmark.triangle"
        case "macwindow":                return "macwindow"
        case "eye":                      return "eye"
        case "iphone":                   return "iphone"
        case "globe", "compass":         return "globe"
        case "flame":                    return "flame"
        case "hammer":                   return "hammer"
        case "shippingbox", "package":   return "shippingbox"
        case "mug", "beer":              return "mug"
        case "message":                  return "message"
        case "music":                    return "music.note"
        case "video":                    return "video"
        case "photo":                    return "photo"
        case "settings":                 return "gear"
        case "magnifyingglass":          return "magnifyingglass"
        case "network":                  return "network"
        case "tornado":                  return "tornado"          // brand
        case "sparkles":                 return "sparkles"          // Clean nav
        case "package-x":                return "xmark.bin"         // Uninstall nav
        case "chart-pie":                return "chart.pie"         // Analyze nav
        case "activity":                 return "waveform.path.ecg" // Status nav
        case "code":                     return "chevron.left.forwardslash.chevron.right"
        default:                          return "questionmark.circle"
        }
    }
}
```

`CleanRules.json` uses tokens like `"icon": "globe"`. Models pass that
string straight through. The View calls `Iconography.sfSymbol(for: ...)`
and feeds the result to `Image(systemName:)`. Keep mapping in one place.

---

## 5. View composition rules

### Screen views are composers, not implementers

`CleanView.swift` should be small (~80 lines) and read like a table of
contents:

```swift
struct CleanView: View {
    @StateObject private var vm = CleanViewModel()

    var body: some View {
        VStack(spacing: 0) {
            CleanHeader(vm: vm)
            Divider().background(Color.borderSubtle)
            CleanBody(vm: vm)
            Divider().background(Color.borderSubtle)
            CleanFooter(vm: vm)
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(Color.surfacePrimary)
        .task { vm.loadCatalog() }
    }
}
```

If `CleanView.body` exceeds 30 lines, extract a sub-view.

### Sub-views own their layout, parents own their position

A `CategoryRow` knows how to lay itself out internally (icon, title, pill,
size). The parent (`CategoryGroupSection`) decides where rows sit. A row
never sets its own width to a magic number; it accepts `.frame(maxWidth:
.infinity)` when its parent demands it.

### State ownership: the closest common ancestor

If two sibling views share state, lift it to the smallest ancestor that
sees both. Don't use a global singleton "to make it easy". A view model
is fine; SwiftUI environment objects are reserved for app-wide state
like theme or auth (none in Burrow's Phase 1).

### `@StateObject` for owners, `@ObservedObject` for borrowers

`CleanView` *owns* `CleanViewModel`, so it uses `@StateObject`.
`CleanHeader` *receives* it, so it uses `@ObservedObject`. Mixing this
up causes view models to be re-created on every redraw — measurable
perf bug.

### Bindings flow down, callbacks flow up

A `BurrowCheckbox` exposes:

```swift
struct BurrowCheckbox: View {
    @Binding var isOn: Bool
}
```

NOT:

```swift
struct BurrowCheckbox: View {
    let viewModel: SomeViewModel  // ❌ component knows the VM
}
```

Components are dumb. They take primitive bindings or values. The screen
or view model wires them together.

### Modifiers for visual treatments

If you find yourself repeating the same `.padding().background().clip
Shape()` block in 3 places, extract a `ViewModifier`:

```swift
// Modifiers/CardStyle.swift
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
```

Then any view: `.cardStyle()`.

### Previews

**Every** component in `Shared/Components/` ships with a preview that
shows all relevant states. Standard format:

```swift
#Preview("RiskPill — all levels") {
    VStack(spacing: 8) {
        RiskPill(level: .low)
        RiskPill(level: .medium)
        RiskPill(level: .high)
    }
    .padding()
}
```

Screen views ship a preview with mock data so the layout can be inspected
without running the app:

```swift
#Preview {
    CleanView()
        .environment(\.colorScheme, .light)
}

#Preview("Dark") {
    CleanView()
        .environment(\.colorScheme, .dark)
}
```

---

## 6. Reusable components — exact spec

Each component lives in `Views/Shared/Components/`. Specs below.

### RiskPill

```swift
struct RiskPill: View {
    let level: RiskLevel

    var body: some View {
        Text(level.rawValue.uppercased())
            .font(.pill)
            .tracking(0.5)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .background(level.background)
            .foregroundStyle(level.foreground)
            .clipShape(Capsule())
    }
}

private extension RiskLevel {
    var background: Color {
        switch self { case .low: .Risk.lowBG; case .medium: .Risk.medBG; case .high: .Risk.highBG }
    }
    var foreground: Color {
        switch self { case .low: .Risk.lowFG; case .medium: .Risk.medFG; case .high: .Risk.highFG }
    }
}
```

### BurrowCheckbox

```swift
struct BurrowCheckbox: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? Color.accentPrimary : Color.surfacePrimary)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(isOn ? Color.clear : Color.fgMuted, lineWidth: 1.5)
                    }
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.fgInverse)
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }
}
```

### PrimaryButton

```swift
struct PrimaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.bodySMed)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 10)
            .background(Color.accentPrimary)
            .foregroundStyle(Color.fgInverse)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
```

`DestructiveButton` and `OutlineButton` follow the same pattern with
their own backgrounds. Build them in the same file or sibling files —
your call, but be consistent.

### SidebarRow

```swift
struct SidebarRow: View {
    let icon: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm + 2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 16, height: 16)
                Text(title).font(isActive ? .bodySMed : .bodyS)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isActive ? Color.fgPrimary : Color.fgSecondary)
            .padding(.horizontal, Spacing.md)
            .frame(height: 36)
            .background(isActive ? Color.surfaceTertiary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
```

### EmptyState

For "no junk found", "FDA needed", "scan to begin" states.

```swift
struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: (label: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Color.fgMuted)
            Text(title).font(.titleM).foregroundStyle(Color.fgPrimary)
            Text(subtitle)
                .font(.bodyS)
                .foregroundStyle(Color.fgSecondary)
                .multilineTextAlignment(.center)
            if let action {
                PrimaryButton(action.label, action: action.run)
                    .padding(.top, Spacing.sm)
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: 360)
    }
}
```

### BrandLogo

```swift
struct BrandLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.accentPrimary)
            Image(systemName: "tornado")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.fgInverse)
        }
        .frame(width: 32, height: 32)
    }
}
```

---

## 7. Anti-patterns — call these out in PR review

### ❌ Inline magic numbers

```swift
.padding(.horizontal, 17)  // why 17?
.cornerRadius(11)          // why 11?
```

✅ Use tokens.

### ❌ Hex literals outside DesignTokens

```swift
.foregroundStyle(Color(red: 0.93, green: 0.18, blue: 0.18))
```

✅ Add to tokens with a name.

### ❌ Big monolithic view files

```swift
// CleanView.swift — 800 lines, 12 nested ViewBuilders, 4 helper funcs
```

✅ Extract sub-views aggressively. 200 lines is the soft cap; > 300 is
a code smell. > 500 is a bug.

### ❌ ViewModels pulling SwiftUI types

```swift
import SwiftUI            // ← view models should not import SwiftUI
class CleanViewModel: ObservableObject {
    @Published var iconColor: Color   // ← Color is a UI concern
}
```

✅ View models hold pure data. Views map data → visuals.

The exception: `import SwiftUI` is OK if you only use `ObservableObject`
and `@Published`. But never expose `Color`, `Font`, `Image` from a VM.

### ❌ Force unwraps in views

```swift
Image(systemName: rule.icon!)  // crashes if optional is nil
```

✅ Use `??` with a sensible default token.

### ❌ Tasks fired from View bodies

```swift
var body: some View {
    Text("Hello").onAppear { Task { await someExpensiveLoad() } }
}
```

This re-fires every redraw if not careful.

✅ Use `.task { ... }` modifier — it's tied to view identity, cancelled
on disappear.

### ❌ `print()` for debugging

✅ Use `os.Logger`. Strip nothing — it's free and structured.

```swift
private let logger = Logger(subsystem: "fun.burrow", category: "Clean")
logger.debug("Scan finished in \(duration, privacy: .public)s")
```

---

## 8. Accessibility minimums (Phase 1)

These are non-negotiable, even before the polish phase:

- Every interactive element has an accessibility label. Buttons that show
  only an icon get an explicit `.accessibilityLabel("Scan")`.
- Color is never the *only* signal. Risk pills also use uppercase text;
  destructive button uses an icon plus text "Move to Trash".
- Tab order follows visual order. SwiftUI does this automatically with
  proper view hierarchy — don't break it with absolute positioning.
- Minimum tap target on macOS is 28×28pt. Sidebar rows are 36pt; buttons
  are at least 32pt. Don't shrink.
- Test with VoiceOver enabled: ⌘F5 to toggle. Walk through the Clean tab
  before opening a PR.

---

## 9. Localization-readiness (defer strings, not work)

Don't run `genstrings` yet — Phase 5 polish does that. But:

- All user-facing strings live in their view, never in models or core.
- Wrap every visible string in `Text(_:)`. `String(localized: "...")`
  is even better but optional in Phase 1.
- No string concatenation for user-facing copy. Use string interpolation
  in a single `Text()`, e.g.
  `Text("\(count) selected · \(size, format: .byteCount(style: .file))")`.

This way, when Phase 5 hits, we extract — we don't rewrite.

---

## 10. Definition of done — Clean tab (Phase 1)

The Clean tab ships when **all** of these are true:

- [ ] Builds clean on Xcode 15+ with macOS 12 deployment target, zero warnings
- [ ] All `Models/` and `Core/` types have unit tests, ≥ 80% line coverage
- [ ] `CleanRules.json` loads without error, all 40+ categories deserialize
- [ ] Scan completes on a real Mac in < 5 seconds for the full catalog
- [ ] Sizes shown in the UI match `du -sh` on the same path within 5%
- [ ] "Move to Trash" actually moves files to `~/.Trash` and they're
      restorable from Finder
- [ ] Dry-run mode does not modify the file system (verify with
      `xattr -p com.apple.metadata:kMDItemUseCount` before/after)
- [ ] Onboarding sheet appears on first launch when FDA is not granted
- [ ] After granting FDA, the sheet does not reappear
- [ ] App quits cleanly (no zombie tasks, no leaked file handles)
- [ ] VoiceOver can navigate the entire screen end-to-end
- [ ] Light + Dark mode both render correctly
- [ ] App bundle size < 5 MB (universal Release build)

---

End of UI architecture contract. If you encounter a situation this
document doesn't cover, propose an addition in the PR description.
