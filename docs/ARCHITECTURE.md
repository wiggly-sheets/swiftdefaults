# Architecture — SwiftDefaults

## MVVM flow

```
tweaks.json → SettingsViewModel → ContentView / SettingRowView
                      ↕
               DefaultsEngine → /usr/bin/defaults
```

- **Model** (`DefaultSetting`): one registry entry — domain, key, type, on/off values, optional restart hints, optional `subcategory`. `SettingValue` is an untagged bool/int/double/string enum, but registry values decode through the entry's declared type rather than their JSON spelling, so a whole number written as `10` stays a float.
- **ViewModel** (`SettingsViewModel`, `@MainActor`): loads the registry from the bundle, holds `settings`, `isOn[id]`, `currentValues[id]`, `pendingValues[id]`, `selectedCategory`, and `searchText`. Exposes `load()`, `refresh()`, `stage(setting:on:)`, `stageOption(setting:stringValue:)`, `applyPending()`, `resetAll()`, `revert(setting:)`, `discardPending()`, and `canRevert(setting:)`. Nothing writes to disk until `applyPending`, `resetAll` or `revert` runs.
- **View** (`ContentView`, `SidebarView`, `SettingRowView`): `NavigationSplitView` with a category sidebar and a searchable list. Each row shows a status dot, title, description and optional restart hint, a Revert button that appears only once this session has written that key, and one control chosen by type: a toggle for booleans, a segmented or menu picker for a setting with `options` (plus a folder chooser when every option is a path), a text field for free-form strings, and a stepper for numbers.
- **Engine** (`DefaultsEngine`): stateless async wrapper over `/usr/bin/defaults` via `Process`, argument list only, never a shell string. `readDomain` returns every key a domain holds as text from one `defaults export <domain> -`; `read` returns one key's raw output, or nil when the key or the domain is absent; `write` maps the declared type to `-bool`/`-int`/`-string`/`-float` and throws `typeMismatch` on a mismatch; `delete` removes a key and treats an already-absent key as success, because revert deletes keys that were never set. Errors surface as message strings in `errorMessage`; the one exception is an unreadable domain, which `refresh` turns into a per-key fallback rather than a failure.

## Registry-driven UI

The UI has no hardcoded tweaks. Categories derive from the registry and are grouped into `System`/`Input`/`Apps` (plus `Other` for anything ungrouped) by `groupedCategories`, which returns `CategoryGroup` → `Category` → `Subcategory` (name plus item count). A category whose entries all set `subcategory` nests one level deeper in the sidebar, showing each subcategory with its item count; every other category stays a flat row. Both the nested subcategory rows and the category row itself tag with the plain category name, because the detail list selects by category and shows all of its entries. Groups (`System`, `Input`, `Apps`) start expanded and nested categories start expanded too, so the structure is readable on launch. The split is all or nothing per category — `validate()` refuses to load a registry where some entries in a category set `subcategory` and others do not, because a half-split section reads as a bug. Search filters title/description/key/category/domain/id. The status dot and the toggle follow `stagedIsOn`, which prefers the staged value and falls back to the live one, and `matchesOn` compares the two by declared type rather than as text, because the same boolean prints as `1` in one domain and `true` in another. Adding a tweak is a JSON-only change; the app picks it up on next launch with no Swift edits.

## Reading live values

`refresh` groups entries by domain and reads each domain with a single `defaults export <domain> -`, which prints XML plist. `defaults read` prints old-style plist instead, and an `NSData` value in it prints as `{length = 684, bytes = 0x...}`, which no plist parser accepts — so the per-key path is the fallback, not the default. A domain whose export will not parse throws `unreadableDomain` and falls back to per-key `defaults read`, so one bad domain costs spawns, not correctness. `kCFPreferencesAnyApplication` is a CFPreferences pseudo-domain with nothing of its own to export, so its entries always take the per-key path.

What is on disk is not what the app stages. The export path renders each value to text that approximates `defaults read`, and containers are hand-rolled as `{ k = v; }` and `( a, b )` because Foundation cannot write the openstep format. A whole float prints as `100` and `NSData` prints as `{ length = 684 }`. Every container begins with `{` or `(`, so `isPlistContainer` refuses to capture it as a String and revert never writes a plist back as one. The app's own canonical form, produced by the private `canonicalString` — exposed publicly as `displayString(_:)` — and held in `pendingValues`, is booleans as `1`/`0` and whole floats without the fraction.

Booleans have two spellings on disk. `defaults read` prints `1`/`0` in some domains — `com.apple.dock autohide` — and `true`/`false` in others, `com.apple.finder CreateDesktop`, where the plist holds the string `"true"`; the export path prints `1`/`0` either way. `boolean(_:)` accepts all four spellings and `matchesOn` parses through the declared type, so neither path compares a string against `onValue`.

Absence is text, not an exit code. `indicatesAbsent(_:)` matches `Could not find key`, `not found` and `does not exist` in the merged stdout/stderr, and both `read` and `delete` use it. That text match is the shortcut: `defaults` exits nonzero for a missing key and reports the reason only in English, so a localised `defaults` would read as a failure.

## Restart handling

The app never restarts other processes. Restart behavior is advisory:

1. `applyPending` writes each staged value and updates the toggle immediately from the staged value.
2. If the entry sets `appToRestart`, the row shows "Takes effect after X relaunches" so the user can relaunch that app themselves.
3. If the entry sets `requiresRelaunch`, the change needs a wider relaunch or logout (e.g. keyboard, quarantine, appearance keys).
4. Entries without either hint take effect on next read by the owning app.

## Staging model

Edits are staged locally first: `stage` / `stageOption` validate and store canonical strings in `pendingValues` without touching disk. String values keep their edge spaces verbatim and stay in the form macOS stores: a leading `~/` is written literally, as `com.apple.screencapture` keeps it, and the reading app expands it. `applyPending` writes each staged value; a value that will not parse, an id with no captured original, and a write that errors all stay staged with a message in `errorMessage`, and none of them reaches disk. `discardPending` drops staged edits. `refresh` re-reads live values but preserves pending edits unless disk now matches them (then resolved). Apply and reset run their spawns in task groups of eight and publish `currentValues` and `isOn` once per batch, so an N-key run costs a constant number of view invalidations instead of one per key. `applyPending` publishes `pendingValues` once at the end, `resetAll` republishes it with each batch, and `refresh` publishes `isOn`, `currentValues` and `pendingValues` once when it finishes. The detail list is disabled while an apply or reset runs, so a second stage cannot interleave.

## Revert model

The original is captured once (`capturedIds`) as a typed `SettingValue`, during the first read in `refresh()`; a value that does not match its declared type is not captured, and neither is one that reads back as a plist container, since any text parses as a String and a lossy restore is worse than no button. `revert` rewrites the captured value, or `delete`s the key when it was absent — restoring the system default for keys the app created. `defaultValue` never enters that choice: it is display-only, the fallback `fallbackString` shows for a key with nothing on disk. `canRevert` reads `appliedIds`, not `capturedIds`, so the button appears only for a key this session actually wrote, and after a successful revert the id leaves `capturedIds`, `appliedIds` and `originalValues`, which resets `canRevert`, `canRevertAll`, and `isResetDisabled`. `resetAll` discards pending edits and reverts every id this session applied (`appliedIds`).

## Files and targets

Swift Package Manager is the canonical build. `Package.swift` declares two targets: the executable `SwiftDefaults` (path `SwiftDefaults/`) and the test target `SwiftDefaultsTests` (path `Tests/SwiftDefaultsTests/`). The tests live in `Tests/SwiftDefaultsTests/`: `ParsingTests` covers the pure parsing, staging and rendering contracts, `RegistryTests` covers the shipped registry and `validate()`, and `TestSupport` holds the shared fixtures. Nothing in the suite spawns `defaults` or touches a real domain.

Two workflows build on that. `.github/workflows/ci.yml` runs `swift build` and `swift test` on pushes to `main` and on pull requests, then validates the tweak registry and the packaged app bundle. `.github/workflows/swiftdefaults-release.yml` triggers on `v*` tags only: it runs the tests as a gate, packages the app, stamps the version, signs the bundle ad-hoc, builds `SwiftDefaults-<version>.dmg` with a `.sha256` checksum file, and publishes both ad-hoc signed and without notarization.

The packaged `.app` ships the registry bundle in two locations: the app root, where `Bundle.module` looks on SwiftPM 6.0–6.3, and `Contents/Resources`. The app reads the copy in `Contents/Resources` and keeps `Bundle.module` only as a fallback, because `Bundle.module` fatalErrors when it finds no bundle. The copy in the app root is spare: the release workflow drops it before signing, because `codesign` seals only what lives in `Contents/`. The `Makefile` builds `SwiftDefaults_SwiftDefaults.bundle` by hand, because SwiftPM's own generated bundle layout differs between toolchains — flat on 6.2, `Contents/Resources` on 6.4 — so copying SwiftPM's output is unreliable; `swift run` is unaffected, because SwiftPM puts the bundle next to the debug binary.
