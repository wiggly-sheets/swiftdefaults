# Architecture — SwiftDefaults

## MVVM flow

```
tweaks.json → SettingsViewModel → ContentView / SettingRowView
                      ↕
               DefaultsEngine → /usr/bin/defaults
```

- **Model** (`DefaultSetting`): one registry entry — domain, key, type, on/off values, optional restart hints, optional `subcategory`. `SettingValue` is an untagged bool/int/double/string enum decoding straight from JSON.
- **ViewModel** (`SettingsViewModel`, `@MainActor`): loads the registry from the bundle, holds `settings`, `isOn[id]`, `currentValues[id]`, `pendingValues[id]`, `selectedCategory`, and `searchText`. Exposes `load()`, `refresh()`, `stage(setting:on:)`, `stageOption(setting:stringValue:)`, `applyPending()`, `resetAll()`, `revert(setting:)`, `discardPending()`, and `canRevert(setting:)`. Nothing writes to disk until `applyPending` runs.
- **View** (`ContentView`, `SidebarView`, `SettingRowView`): `NavigationSplitView` with a category sidebar and a searchable list. Each row shows a status dot, title, description, optional restart hint, Revert button (only after a change), and a toggle.
- **Engine** (`DefaultsEngine`): stateless async wrapper over `/usr/bin/defaults` via `Process`. `read` returns raw output, or nil when the key or the domain is absent; `write` maps types to `-bool`/`-int`/`-string`/`-float`; `delete` removes a key and treats an already-absent key as success. All errors surface as `DefaultsError` strings to `errorMessage`.

## Registry-driven UI

The UI has no hardcoded tweaks. Categories derive from the registry and are grouped into `System`/`Input`/`Apps` (plus `Other` for anything ungrouped) by `groupedCategories`, which returns `CategoryGroup` → `Category` → `Subcategory` (name plus item count). A category whose entries all set `subcategory` nests one level deeper in the sidebar, showing each subcategory with its item count; every other category stays a flat row. Both the nested subcategory rows and the category row itself tag with the plain category name, because the detail list selects by category and shows all of its entries. Groups (`System`, `Input`, `Apps`) start expanded and nested categories start expanded too, so the structure is readable on launch. The split is all or nothing per category — `validate()` refuses to load a registry where some entries in a category set `subcategory` and others do not, because a half-split section reads as a bug. Search filters title/description/key/category/domain/id, and toggle state resolves by comparing live `defaults read` output against the canonical `onValue` string. Adding a tweak is a JSON-only change; the app picks it up on next launch with no Swift edits.

## Restart handling

The app never restarts other processes. Restart behavior is advisory:

1. `applyPending` writes each staged value and updates the toggle immediately from the staged value.
2. If the entry sets `appToRestart`, the row shows "Takes effect after X relaunches" so the user can relaunch that app themselves.
3. If the entry sets `requiresRelaunch`, the change needs a wider relaunch or logout (e.g. keyboard, quarantine, appearance keys).
4. Entries without either hint take effect on next read by the owning app.

## Staging model

Edits are staged locally first: `stage` / `stageOption` validate and store canonical strings in `pendingValues` without touching disk. String values keep their edge spaces verbatim and stay in the form macOS stores: a leading `~/` is written literally, as `com.apple.screencapture` keeps it, and the reading app expands it. `applyPending` writes each staged value, skips ids with no captured original, keeps failures staged, and reports the first error. `discardPending` drops staged edits. `refresh` re-reads live values but preserves pending edits unless disk now matches them (then resolved). The detail list is disabled while an apply or reset runs, so a second stage cannot interleave.

## Revert model

The original is captured once (`capturedIds`) as a typed `SettingValue`, during the first read in `refresh()`; a value that does not match its declared type is not captured, so no Revert is offered. `revert` rewrites the captured value, or `delete`s the key when it was absent — restoring the system default for keys the app created. After a successful revert the id leaves `capturedIds`/`originalValues`, so `canRevert`, `canRevertAll`, and `isResetDisabled` reset. `resetAll` discards pending edits and reverts every id this session applied (`appliedIds`).
