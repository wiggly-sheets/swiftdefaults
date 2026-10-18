<div align="center">

  <h1>SwiftDefaults</h1>

  <p><b>Tweak macOS without touching Terminal.</b></p>

  <p>
    A native Mac utility for browsing and toggling system defaults.<br/>
    Open source, revert-safe.
  </p>

<p>
  Pre-release. No signed build yet.
</p>

  <p>
    <a href="#download"><b>Download</b></a>
    &nbsp;·&nbsp;
    <a href="#installation">Install guide</a>
    &nbsp;·&nbsp;
    <a href="#build-from-source">Build from source</a>
    &nbsp;·&nbsp;
    <a href="#security">Security</a>
  </p>

</div>

---

Your Mac hides dozens of useful settings behind `defaults write` commands. SwiftDefaults catalogs them, explains each in plain English, and applies them with one toggle.

> [!NOTE]
> Every change is revertible. SwiftDefaults remembers the value present before your first toggle and restores it on Revert — deleting the key when it did not exist, so the system default returns.

You do not need to know what a domain or plist key is. But if you want to check, each row names its domain and key, so anything can be verified with `defaults read` first.

> [!CAUTION]
> Pre-release. There is no signed DMG or Homebrew cask yet. Build from source for now; see [Roadmap](#roadmap).

---

## Features

### Categorized tweaks

93 tweaks across 21 categories (Dock, Finder, Screenshots, Window Manager, Keyboard, and more):

- Human-readable title plus plain-English description per tweak
- Sidebar navigation with category counts
- Search across title, description, and key

### Staged edits, one Apply

- Flip a switch to stage the new value; nothing writes until Apply
- Apply writes all pending edits via `/usr/bin/defaults`, keeping failures staged
- Reset discards pending edits and restores captured originals
- Live state: each launch reads current values with `defaults read`
- Status dot shows whether the "on" value is active

### Revert safety

- First toggle captures the original value for that setting
- **Revert** button restores the captured value, or deletes the key when it did not exist
- Revert appears only after a change, per row

### Restart guidance

- Rows declaring `appToRestart` show "Takes effect after X relaunches"
- Rows needing a wider relaunch flag `requiresRelaunch`
- The app never force-restarts anything for you

### Registry-driven

- All tweaks live in one JSON file: `SwiftDefaults/Resources/tweaks.json`
- Adding a tweak is a JSON edit, no Swift changes needed
- Option lists (`options`) document valid values for multi-choice settings

---

## Download

> [!NOTE]
> No downloadable release exists yet. Signed DMG and Homebrew are on the [Roadmap](#roadmap).

Until then, [build from source](#build-from-source) — it takes two commands.

---

## Installation

Two ways to run SwiftDefaults: a double-clickable `.app` bundle, or straight from the terminal.

### Run from terminal (fastest)

```bash
git clone https://github.com/wiggly-sheets/swiftdefaults.git
cd swiftdefaults
make run
```

This builds a debug binary and launches it via `swift run`.

### Install manually

Build the app bundle, then move it to Applications:

```bash
make app-bundle
cp -r SwiftDefaults.app /Applications/
```

Then double-click **SwiftDefaults** in Applications. No Xcode required — only the Swift toolchain.

---

## Updating

No updater yet. To update a source install:

```bash
cd swiftdefaults
git pull
make run
```

If you copied `SwiftDefaults.app` to Applications, rebuild and replace it:

```bash
git pull
make app-bundle
cp -r SwiftDefaults.app /Applications/
```

Your revert history is per-launch (in memory), so updating resets it. Applied system settings are untouched by updates.

---

## Build from source

### Prerequisites

- macOS 15 or later (Apple Silicon; see [Requirements](#requirements))
- Swift 6 toolchain (`swift --version` should print 6.x; ships with Xcode 16+ or swift.org)
- No Xcode project step needed — Swift Package Manager is canonical

### Step 1: Clone the repo

```bash
git clone https://github.com/wiggly-sheets/swiftdefaults.git
cd swiftdefaults
```

### Step 2: Build and run

```bash
make run
```

Or step by step:

```bash
swift build
swift run
```

### Make targets

| Target | Command | Output |
|--------|---------|--------|
| `build` | `swift build` | Debug binary in `.build/debug/` |
| `run` | `swift run` | Builds and launches the app |
| `release` | `swift build -c release` | Optimized binary in `.build/release/` |
| `app-bundle` | builds + assembles `.app` | `SwiftDefaults.app` in repo root |
| `clean` | `swift package clean` | Clears build artifacts |

`make app-bundle` wraps the release binary with `Info.plist` and `tweaks.json` into a launchable `SwiftDefaults.app`.

### Running the tests

No test suite exists yet. When one lands, it will run via:

```bash
swift test
```

### Sanity-checking the registry

```bash
jq length SwiftDefaults/Resources/tweaks.json
jq '[.[].category] | unique' SwiftDefaults/Resources/tweaks.json
```

---

## Requirements

- macOS 15.0 or later
- Apple Silicon (arm64) — this is the only tested configuration
- Write access to user defaults (no Full Disk Access, no sandbox entitlements beyond default)

---

## Privacy

SwiftDefaults runs entirely on your Mac. The registry, live reads, and revert history stay in memory or the local bundle. Nothing is uploaded, and file contents are never read.

---

## Security

SwiftDefaults writes system settings, so caution applies:

- **Revert by default**: every toggle captures the prior value; Revert restores it or deletes a key the app created.
- **Explicit engine only**: writes go through `/usr/bin/defaults` with typed flags (`-bool`, `-int`, `-string`, `-float`). No shell strings, no `sh -c`.
- **You choose what goes**: the app shows what each toggle does; nothing applies at launch or in bulk.
- **Open source**: the full write path (`DefaultsEngine`) and registry are in this repo to read or build yourself.
- **Notarization: not yet** — releases are unsigned until the [Roadmap](#roadmap) items land. Building from source is the verifiable path today.

> [!CAUTION]
> Some entries carry their own `CAUTION` in the description (e.g. quarantine warnings, auto-empty Bin, experimental appearance keys). Read the row before toggling. A few tweaks need their target app relaunched, or a logout, to take effect.

Found a wrong default value or a risky entry? Please open an issue with the tweak `id`, your macOS version, and the `defaults read <domain> <key>` output.

---

## Roadmap

- [ ] Signed + notarized DMG on GitHub Releases
- [ ] Homebrew cask
- [ ] Test suite (`swift test`)
- [ ] Dry-run preview (show command before executing)
- [ ] Import/export profiles

---

## License

MIT — see [LICENSE](LICENSE).

---

## Support

TODO: add a support link (e.g. GitHub Sponsors or Buy Me a Coffee) once the first release ships.
