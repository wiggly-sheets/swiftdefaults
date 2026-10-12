# Architecture — SwiftDefaults

## MVVM flow

```
tweaks.json → SettingsViewModel → ContentView / SettingRowView
                      ↕
               DefaultsEngine → /usr/bin/defaults
```

- **Model** (`DefaultSetting`): one registry entry — domain, key, type, on/off values, optional restart hints. `SettingValue` is an untagged bool/int/double/string enum decoding straight from JSON.
- **ViewModel** (`SettingsViewModel`, `@MainActor`): loads the registry from the bundle, holds `settings`, `isOn[id]`, `selectedCategory`, and `searchText`. Exposes `load()`, `refresh()`, `apply(setting:on:)`, `revert(setting:)`, and `canRevert(setting:)`.
- **View** (`ContentView`, `SidebarView`, `SettingRowView`): `NavigationSplitView` with a category sidebar and a searchable list. Each row shows a status dot, title, description, optional restart hint, Revert button (only after a change), and a toggle.
- **Engine** (`DefaultsEngine`): stateless async wrapper over `/usr/bin/defaults` via `Process`. `read` returns raw output or nil; `write` maps types to `-bool`/`-int`/`-string`/`-float`; `delete` removes a key. All errors surface as `DefaultsError` strings to `errorMessage`.

## Registry-driven UI

The UI has no hardcoded tweaks. Categories derive from the registry (`["All"] + unique sorted categories`), search filters title/description/key, and toggle state resolves by comparing live `defaults read` output against the canonical `onValue` string. Adding a tweak is a JSON-only change; the app picks it up on next launch with no Swift edits.

## Restart handling

The app never restarts other processes. Restart behavior is advisory:

1. `apply` writes the value and updates the toggle immediately.
2. If the entry sets `appToRestart`, the row shows "Takes effect after X relaunches" so the user can relaunch that app themselves.
3. If the entry sets `requiresRelaunch`, the change needs a wider relaunch or logout (e.g. keyboard, quarantine, appearance keys).
4. Entries without either hint take effect on next read by the owning app.

## Revert model

On first `apply` per setting id, the ViewModel captures the live value (`originalValues[id]`, `capturedIds`). Revert writes back the captured value when it matches on/off, falls back to `defaultValue` when set, and otherwise deletes the key — restoring the system default for keys the app created.
