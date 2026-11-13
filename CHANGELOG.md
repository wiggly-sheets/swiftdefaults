# Changelog

All notable changes to SwiftDefaults are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Liquid Glass now renders natively on macOS 26 and 27, built against the macOS 27.2 SDK. The toolbar's Apply and Reset buttons use the native glass button styles and share a `GlassEffectContainer`, the pending-count chip morphs in and out of that group with a matched-geometry glass transition, and the row status dot is a tinted glass bead. macOS 15 and later still build and run the same binary with the plain controls; the glass path is gated with `#available(macOS 26.0, *)`.
- `make build`, `make test`, `make run`, `make app` and `make app-bundle-debug` restate the installed SDK version in `LC_BUILD_VERSION`. SwiftPM otherwise records the 15.0 deployment target there, which makes macOS treat the app as linked against an old SDK and skip the Liquid Glass design for the window chrome. `vtool -show-build` on a `make app` binary now reports `minos 15.0, sdk 27.2`.

### Changed

- The Makefile follows the shared build vocabulary: `make` prints the targets, and `make build`, `make test`, `make app`, `make dmg`, `make release-artifacts`, `make release VERSION=x.y.z` and `make clean` do the work. SwiftDefaults is Apple silicon only, so there is no per-architecture target.
- `make run` now installs the shipping bundle into `~/Applications` and launches it; `make verify` checks the registry, the icon, the architecture, the version and the signature; `make test` checks the changelog shape; and `make release` moves `[Unreleased]` to the released version, tests, builds, verifies, commits the bump and creates the tag.
- The Makefile owns the packaging now. `make app` assembles the bundle, stamps the version and signs it ad-hoc, `make dmg` builds `release/SwiftDefaults-<version>.dmg`, and `make release-artifacts` writes `release/SwiftDefaults-<version>.dmg.sha256` next to it. The release workflow calls those targets instead of running `hdiutil`, `shasum` and `PlistBuddy` itself.
- `make release VERSION=x.y.z` refuses a dirty working tree and a version whose tag already exists, builds the artifacts, creates the annotated tag `v<x.y.z>` locally and prints the command that pushes the commit and the tag. It never pushes by itself.
- The app reads the tweak registry from `Contents/Resources/SwiftDefaults_SwiftDefaults.bundle` and keeps `Bundle.module` only as a fallback, because `Bundle.module` fatalErrors when it finds no bundle. The bundle no longer holds the spare copy in the app root, because `codesign` seals only what lives in `Contents/`.

## [1.0.1] - 2026-10-19

### Changed

- The release asset is now versioned: `SwiftDefaults-<version>.dmg` replaces `SwiftDefaults.dmg`. Update any pinned download URL.

### Fixed

- Domain reads use `defaults export <domain> -` instead of `defaults read <domain>`, so domains containing `NSData` parse correctly. 13 of 24 domains previously failed to bulk-parse and fell back to per-key reads.
- Plist containers (dictionaries, arrays) render to openstep-shaped text, so dictionary and array values are no longer captured and rewritten flat.
- Booleans accept both `1`/`0` and `true`/`false`. Rows now report the correct state and can be reverted.
- First launch spawns far fewer `defaults` processes.

## [1.0.0] - 2026-10-17

### Added

- Initial release: 93 tweaks in 21 categories.
- Staged edits applied with one Apply button.
- Per-setting Revert, restoring the value captured when the app read your settings at launch.
- Restart guidance, naming the app to relaunch where needed.
- DMG build for macOS 15+.

[Unreleased]: https://github.com/wiggly-sheets/swiftdefaults/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/wiggly-sheets/swiftdefaults/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/wiggly-sheets/swiftdefaults/releases/tag/v1.0.0
