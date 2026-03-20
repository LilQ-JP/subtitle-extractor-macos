# Changelog

All notable user-facing changes to Caption Studio should be recorded here.

The format is intentionally lightweight so GitHub Releases can reuse it directly.

## 1.0.8 - 2026-03-18

### Fixed

- Reduced false-positive OCR subtitles in no-subtitle sections by filtering weak one-off recognition groups
- Added undo coverage for subtitle deletion and canvas edits such as video position, zoom, and subtitle frame changes

### Added

- Added `THIRD_PARTY_NOTICES.md` for GitHub-facing dependency and runtime license disclosure
- Added `CHANGELOG.md` and `.github/release.yml` so each GitHub release can include clear update notes

## 1.0.7 - 2026-03-17

### Fixed

- Preserved overlay settings, presets, fonts, and app preferences across app updates
- Migrated persistent settings into `Application Support/CaptionStudio/PersistentState.json`

## 1.0.6 - 2026-03-17

### Fixed

- Fixed in-app update downloads getting stuck before completion
- Stored downloaded installer files safely so restart/update flow can continue

## 1.0.5 - 2026-03-17

### Improved

- Made subtitle timing edits easier to commit and adjust
- Added fine timing nudge controls in the subtitle editor

### Fixed

- Preserved manual subtitle timing gaps instead of collapsing them away

## 1.0.4 - 2026-03-16

### Added

- Stable and prerelease update channel handling
- Public release checklist and release preflight tooling
- Launch copy kit and GitHub Sponsors preparation

## 1.0.3 - 2026-03-16

### Fixed

- Fixed reopen crash when launching the app again after it was already running
- Restored `.subtitleproject` open/import behavior from Finder and the app

## 1.0.2 - 2026-03-16

### Added

- First-run quick start tutorial
- Tutorial reopening from settings and keyboard shortcut

## 1.0.1 - 2026-03-16

### Fixed

- Fixed long-video translation jobs hanging near completion when many subtitle items were produced

## 1.0.0 - 2026-03-10

### Added

- Initial public macOS packaging and distribution setup
