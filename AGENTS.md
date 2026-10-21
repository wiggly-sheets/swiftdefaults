# AGENTS.md — SwiftDefaults

## Project map

- `SwiftDefaults/SwiftDefaultsApp.swift` — app entry, owns `SettingsViewModel`
- `SwiftDefaults/Models/DefaultSetting.swift` — `DefaultSetting`, `SettingType`, `SettingValue`
- `SwiftDefaults/Services/DefaultsEngine.swift` — thin async wrapper over `/usr/bin/defaults`
- `SwiftDefaults/ViewModels/SettingsViewModel.swift` — registry load, live state, apply/revert
- `SwiftDefaults/Views/` — `ContentView` (split view), `SidebarView`, `SettingRowView`
- `SwiftDefaults/Resources/tweaks.json` — the tweak registry (93 entries, 21 categories, 16 subcategories across 7 fully split categories)
- `SwiftDefaults/Info.plist` — bundle metadata (`LSMinimumSystemVersion` 15.0)
- `Package.swift` — SPM executable target `SwiftDefaults` plus test target `SwiftDefaultsTests`, macOS 15, resources via `.process("Resources")`
- `Makefile` — `help build test run app app-bundle-debug run-bundle-debug dmg release-artifacts release clean`; assembles the `.app` and the `SwiftDefaults_SwiftDefaults.bundle` resource bundle by hand, signs the bundle ad-hoc, builds the disk image and its checksum file
- `Tests/SwiftDefaultsTests/` — `ParsingTests`, `RegistryTests`, `TestSupport` (30 tests)
- `.github/workflows/ci.yml` — `make build` + `make test` on push to main and on pull requests
- `.github/workflows/swiftdefaults-release.yml` — tag `v*` only: tests gate, `make app` packages and signs the bundle, `make release-artifacts` writes the versioned DMG and its checksum file
- `docs/ARCHITECTURE.md` — MVVM flow and restart handling
- `CHANGELOG.md` — release notes
- `Assets/app-icon.png` — README hero image, rendered from `SwiftDefaults/Resources/AppIcon.icns`

## SPM layout

- Swift Package Manager is canonical. `SwiftDefaults.xcodeproj` exists but is not authoritative.
- Two targets: executable `SwiftDefaults` (path `SwiftDefaults/`) and test target `SwiftDefaultsTests` (path `Tests/SwiftDefaultsTests/`).
- Resources: `tweaks.json` is processed via `.process("Resources")`. The `.app` does not ship SwiftPM's generated bundle: the `Makefile` builds `SwiftDefaults_SwiftDefaults.bundle` by hand in the classic macOS layout (`Contents/Info.plist`, `Contents/Resources/tweaks.json`, `Contents/Resources/AppIcon.icns`) and places it in `Contents/Resources`. The app reads that copy and keeps `Bundle.module` only as a fallback, because `Bundle.module` fatalErrors when it finds neither. The bundle holds nothing in the app root: `codesign` seals only what lives in `Contents/`, so a file in the app root makes the signing fail with "unsealed contents present in the bundle root". `make app` signs the bundle ad-hoc (`codesign --force --sign - --options runtime`).
- Platforms: macOS 15+, Swift tools 6.0.

## Registry schema (`tweaks.json`)

Each entry is a `DefaultSetting`:

| Field | Required | Meaning |
|-------|----------|---------|
| `id` | yes | Stable kebab-case identifier |
| `category` | yes | Sidebar group (e.g. `Dock`, `Finder`) |
| `subcategory` | no | Second sidebar level inside `category`; all or nothing per category |
| `title` | yes | Human-readable name |
| `description` | yes | Plain-English explanation; prefix with `CAUTION:` for risky tweaks |
| `domain` | yes | Defaults domain (e.g. `com.apple.dock`, `NSGlobalDomain`) |
| `key` | yes | Key within the domain |
| `type` | yes | `boolean` \| `integer` \| `string` \| `float` |
| `onValue` / `offValue` | yes | Values written on toggle on/off (JSON bool, number, or string) |
| `defaultValue` | no | Shown for a key with nothing on disk; falls back to `offValue` |
| `options` | no | Documents valid values for multi-choice settings |
| `appToRestart` | no | App name shown as "Takes effect after X relaunches" |
| `requiresRelaunch` | no | True when a relaunch/logout is needed beyond one app |

### Adding a tweak

1. Append one JSON object to `SwiftDefaults/Resources/tweaks.json`.
2. Verify types match: `type: boolean` needs JSON bools in `onValue`/`offValue`; `integer` needs ints; `float` needs decimals; `string` needs strings.
3. Verify parse + count:
   `jq length SwiftDefaults/Resources/tweaks.json`
   `jq '[.[].category] | unique' SwiftDefaults/Resources/tweaks.json`
4. Verify `swift build` and `swift test` still pass (registry loads at runtime via `Bundle.module`).
5. Splitting a category into subcategories is all or nothing: either every entry in a category sets `subcategory` or none does. `validate()` rejects a half-split registry at load, naming the entry that is missing one.
6. Prefer `appToRestart` over `requiresRelaunch` when a single app relaunch suffices; use `CAUTION:` in the description for destructive or security-adjacent entries.

## Engine rules

- `/usr/bin/defaults` via `Process` only. Never `sh -c`, never interpolated shell strings.
- `DefaultsEngine` is a stateless `enum` with `async throws` functions: `read`, `readDomain`, `write`, `delete`, plus the helpers `rendered(_:)` and `indicatesAbsent(_:)`.
- `read` returns `nil` when the key or the domain is absent, matching `defaults` not-found output; any other nonzero exit throws `DefaultsError` with exit status and output. `delete` treats an already-absent key as success, because revert needs it.
- Type mapping is strict: `boolean → -bool`, `integer → -int`, `string → -string`, `float → -float`. Mismatches throw `typeMismatch(id:)`.
- Booleans do not have one textual form. `defaults read` prints `1`/`0` in most domains but `true`/`false` in others — `com.apple.dock autohide` returns `1`, `com.apple.finder CreateDesktop` returns `true`. Every place that parses or compares a boolean accepts both spellings (`SettingsViewModel.boolean(_:)`). The app's own canonical form, produced by the private `canonicalString` — exposed publicly as `displayString(_:)` — and used for staged edits, stays `1`/`0`.
- `readDomain` uses `defaults export <domain> -`, not `defaults read <domain>`. `read` prints old-style plist, in which an `NSData` value prints as `{length = 684, bytes = 0x...}` and the whole output fails to parse; `export` emits XML plist for the same data and parses cleanly, `NSData` included. `readDomain` therefore returns booleans as `1`/`0` even in domains where the per-key `read` prints `true`/`false`; both paths parse to the same boolean. Containers are rendered to openstep-shaped text by hand (`{k = v;}`, `(a, b)`) because Foundation cannot write openstep, and always start with `{` or `(` so `isPlistContainer` refuses to capture one as a `String`.
- `kCFPreferencesAnyApplication` has no domain of its own to export, so `refresh()` keeps its entry on the per-key path.
- String values keep edge spaces verbatim, and are written in the form macOS stores: a leading `~/` stays literal on disk and is expanded by the reading app, so nothing expands it here.
- Edits are staged in memory: `stage`/`stageOption` store canonical strings in `pendingValues`; nothing reaches disk until `applyPending` writes them all. Failures stay staged, and so do ids with no captured original — those are never written either and set an error message. `discardPending` drops staged edits.
- Revert semantics live in `SettingsViewModel`: the original is captured once (`capturedIds`) as a typed `SettingValue`, during the first read in `refresh()`; a value that does not match its declared type is not captured, and neither is one that reads back as a plist container (text starting with `{` or `(`), so those rows offer no Revert. Revert rewrites the captured value, or `delete`s the key when it was absent.
- `resetAll` discards pending edits and reverts every id this session applied (`appliedIds`).
- No force-unwrap, no background daemons, no bulk apply. One toggle stages one key; only `applyPending`, `resetAll` and `revert` write to disk.

## Build / verify

```bash
make build
make test
make app
jq length SwiftDefaults/Resources/tweaks.json
```

`make app` builds the release binary, assembles `SwiftDefaults.app`, stamps the version when `VERSION=` is given, signs the bundle ad-hoc and verifies the signature. `make dmg` and `make release-artifacts` need a version: `make release-artifacts VERSION=1.2.3`.

Tests live in `Tests/SwiftDefaultsTests/` (30 tests): `ParsingTests` covers boolean and numeric parsing, absence detection, staging and container rendering; `RegistryTests` covers the shipped registry and `validate()`. Run them with `make test`.

## Git conventions

- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`.
- Docs-only changes use `docs:` and must not touch `SwiftDefaults/` sources, `Package.swift`, or `Makefile`.
- Keep diffs surgical; do not reformat adjacent code.

## Do not do

- Do not treat `SwiftDefaults.xcodeproj` as canonical; SPM + Makefile are the build path.
- Do not add dependencies (no new packages, pods, or npm tooling).
- Do not add shell-outs beyond `/usr/bin/defaults` (and `killall`-style restarts only if explicitly requested).
- Do not force-restart apps or add auto-apply on launch.
- Do not persist staged edits or captured originals to disk without an explicit task (currently in-memory by design).
- Do not commit build artifacts (`.build/`, `SwiftDefaults.app`).
