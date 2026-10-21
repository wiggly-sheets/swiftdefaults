# Changelog

All notable changes to SwiftDefaults are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The Makefile follows the shared build vocabulary: `make` prints the targets, and `make build`, `make test`, `make app`, `make dmg`, `make release-artifacts`, `make release VERSION=x.y.z` and `make clean` do the work. SwiftDefaults is Apple silicon only, so there is no per-architecture target.
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
