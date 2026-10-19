# Changelog

All notable changes to SwiftDefaults are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
