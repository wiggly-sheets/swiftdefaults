# AGENTS.md — SwiftDefaults

## Project map

- `SwiftDefaults/SwiftDefaultsApp.swift` — app entry, owns `SettingsViewModel`
- `SwiftDefaults/Models/DefaultSetting.swift` — `DefaultSetting`, `SettingType`, `SettingValue`
- `SwiftDefaults/Services/DefaultsEngine.swift` — thin async wrapper over `/usr/bin/defaults`
- `SwiftDefaults/ViewModels/SettingsViewModel.swift` — registry load, live state, apply/revert
- `SwiftDefaults/Views/` — `ContentView` (split view), `SidebarView`, `SettingRowView`
- `SwiftDefaults/Resources/tweaks.json` — the tweak registry (96 entries, 21 categories)
- `SwiftDefaults/Info.plist` — bundle metadata (`LSMinimumSystemVersion` 15.0)
- `Package.swift` — SPM executable target, macOS 15, resources via `.process("Resources")`
- `Makefile` — `build run clean release app-bundle`
- `docs/ARCHITECTURE.md` — MVVM flow and restart handling

## SPM layout

- Swift Package Manager is canonical. `SwiftDefaults.xcodeproj` exists but is not authoritative.
- Single executable target `SwiftDefaults`, path `SwiftDefaults/`.
- Resources: `tweaks.json` is processed via `.process("Resources")` and loaded with `Bundle.module` (under `SWIFT_PACKAGE`) falling back to `Bundle.main`.
- Platforms: macOS 15+, Swift tools 6.0.

## Registry schema (`tweaks.json`)

Each entry is a `DefaultSetting`:

| Field | Required | Meaning |
|-------|----------|---------|
| `id` | yes | Stable kebab-case identifier |
| `category` | yes | Sidebar group (e.g. `Dock`, `Finder`) |
| `title` | yes | Human-readable name |
| `description` | yes | Plain-English explanation; prefix with `CAUTION:` for risky tweaks |
| `domain` | yes | Defaults domain (e.g. `com.apple.dock`, `NSGlobalDomain`) |
| `key` | yes | Key within the domain |
| `type` | yes | `boolean` \| `integer` \| `string` \| `float` |
| `onValue` / `offValue` | yes | Values written on toggle on/off (JSON bool, number, or string) |
| `defaultValue` | no | Fallback used by revert when the original is unrecognized |
| `options` | no | Documents valid values for multi-choice settings |
| `appToRestart` | no | App name shown as "Takes effect after X relaunches" |
| `requiresRelaunch` | no | True when a relaunch/logout is needed beyond one app |

### Adding a tweak

1. Append one JSON object to `SwiftDefaults/Resources/tweaks.json`.
2. Verify types match: `type: boolean` needs JSON bools in `onValue`/`offValue`; `integer` needs ints; `float` needs decimals; `string` needs strings.
3. Verify parse + count:
   `jq length SwiftDefaults/Resources/tweaks.json`
   `jq '[.[].category] | unique' SwiftDefaults/Resources/tweaks.json`
4. Verify `swift build` still passes (registry loads at runtime via `Bundle.module`).
5. Prefer `appToRestart` over `requiresRelaunch` when a single app relaunch suffices; use `CAUTION:` in the description for destructive or security-adjacent entries.

## Engine rules

- `/usr/bin/defaults` via `Process` only. Never `sh -c`, never interpolated shell strings.
- `DefaultsEngine` is a stateless `enum` with `async throws` functions: `read`, `write`, `delete`.
- `read` returns `nil` on nonzero exit (key absent); `write`/`delete` throw `DefaultsError` with exit status and output.
- Type mapping is strict: `boolean → -bool`, `integer → -int`, `string → -string`, `float → -float`. Mismatches throw `typeMismatch(id:)`.
- Booleans compare in canonical form: `defaults read` prints booleans as `1`/`0`.
- Revert semantics live in `SettingsViewModel`: capture original once (`capturedIds`), restore it on revert, `delete` the key when it did not exist.
- No force-unwrap, no background daemons, no bulk apply. One toggle writes one key.

## Build / verify

```bash
swift build
swift build -c release
jq length SwiftDefaults/Resources/tweaks.json
make app-bundle
```

No test suite yet; when adding one, use `swift test`.

## Git conventions

- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`.
- Docs-only changes use `docs:` and must not touch `SwiftDefaults/` sources, `Package.swift`, or `Makefile`.
- Keep diffs surgical; do not reformat adjacent code.

## Do not do

- Do not treat `SwiftDefaults.xcodeproj` as canonical; SPM + Makefile are the build path.
- Do not add dependencies (no new packages, pods, or npm tooling).
- Do not add shell-outs beyond `/usr/bin/defaults` (and `killall`-style restarts only if explicitly requested).
- Do not force-restart apps or add auto-apply on launch.
- Do not persist revert history to disk without an explicit task (currently in-memory by design).
- Do not commit build artifacts (`.build/`, `SwiftDefaults.app`).
