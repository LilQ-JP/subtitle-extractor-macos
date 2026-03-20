# Caption Studio for macOS

[日本語](README.md) | [English](README_EN.md)

Caption Studio is a macOS-native subtitle extraction, translation, and burn-in tool built with SwiftUI.  
It helps you pull hardcoded subtitles from videos, translate them locally, and export `SRT`, `FCPXML`, burned-in `MP4`, or burned-in `MOV` from one app.

## Best For

- Game streamers and clip editors who want multilingual subtitles
- VTuber clip channels that need fast subtitle extraction from existing videos
- Final Cut Pro users who want OCR-extracted subtitles in their editing workflow
- Creators who prefer local processing instead of uploading videos to cloud services

## App Stack

- Native macOS UI: SwiftUI + AppKit
- OCR and translation backend: Python
- Video export: AVFoundation
- Output formats:
  - `SRT`
  - `FCPXML`
  - Burned-in `MP4`
  - Burned-in `MOV`

## Core Features

- Video preview with scrubbing
- Drag-to-select subtitle extraction region
- Subtitle list editing after extraction
- Saved translated subtitles
- Chroma key overlay image support
- Manual adjustment of subtitle and video layout
- macOS fonts plus imported custom fonts
- Favorite font management
- Persistent app settings and overlay presets
- First-run setup and quick start tutorial
- Keyboard shortcuts

## Requirements

- macOS 14 or later
- Python 3
- Python backend modules

Packaged `app / zip / pkg` releases bundle the backend executable, so end users do not need Xcode or Python installed.  
Only translation requires `Ollama`.

## Setup

```bash
./Tools/setup_python_backend.sh
```

This creates a managed Python environment in `~/Library/Application Support/CaptionStudio/python-env` and installs the backend modules there.  
The app auto-detects that managed Python environment on launch.

If you prefer manual setup:

```bash
python3 -m pip install -r requirements.txt
```

If you want to use Ollama for translation:

```bash
ollama serve
ollama pull gemma3:4b
```

## Launch

Open in Xcode:

```bash
./open_in_xcode.sh
```

Run directly:

```bash
./run_editor.sh
```

Build a release app:

```bash
./build_mac.sh
```

Create a distributable installer:

```bash
./package_mac_pkg.sh release
```

## Distribution Artifacts

This repository can generate GitHub-ready `app / zip / pkg` artifacts.  
End users usually install the `.pkg`.

- App bundle: `release/<version>/Caption Studio.app`
- ZIP: `release/<version>/CaptionStudio-<version>-macOS.zip`
- PKG: `release/<version>/CaptionStudio-<version>-macOS.pkg`

The `.pkg` normally installs into `/Applications`, or `~/Applications` for user-level installs.

To build release artifacts:

```bash
./package_mac_pkg.sh release
```

To run a public-release preflight check:

```bash
./Tools/release_preflight.sh
```

To sign and notarize the release:

```bash
./notarize_release.sh
```

Required before notarization:

- `Developer ID Application` certificate in the login keychain
- `Developer ID Installer` certificate in the login keychain
- a `notarytool` credentials profile

Example `notarytool` credentials setup:

```bash
xcrun notarytool store-credentials "SubtitleExtractorNotary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID"
```

The default profile name is `SubtitleExtractorNotary`.  
If you use a different name:

```bash
NOTARY_PROFILE=YourProfile ./notarize_release.sh
```

For the full release flow, see [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).  
For launch copy and screenshot prep, see [LAUNCH_KIT.md](LAUNCH_KIT.md).
For dependency notices and release-history tracking, see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [CHANGELOG.md](CHANGELOG.md).

## Replacing the App Icon

Use either:

- `Assets/AppIcon.icns`
- `Assets/AppIcon.png`

Using a `1024x1024` PNG at `Assets/AppIcon.png` is the easiest route.  
When you run `./package_mac_pkg.sh release`, that icon will be reflected in the packaged app, zip, and pkg.

Versioning is driven by the root `VERSION` file.  
You can bump it with:

```bash
./Tools/bump_version.sh patch
```

Artifacts are grouped under `release/<version>/` and named like:

- `CaptionStudio-<version>-macOS.zip`
- `CaptionStudio-<version>-macOS.pkg`

## Settings

- Open Settings from the top-right `gear` button
- Open Settings from the macOS menu bar with `⌘,`
- Settings includes app language, workspace layout, Ollama diagnostics, and update controls
- Enable `Include prerelease builds` if you want beta or RC updates from GitHub Releases

## Shortcuts

- `⌘O`: Open video
- `⌘⇧O`: Open overlay
- `⌘⇧I`: Import SRT
- `⌘⇧E`: Extract subtitles
- `⌘↩`: Translate
- `Space`: Play / pause
- `⌘⇧N`: Add subtitle
- `⌘⌫`: Delete subtitle
- `⌘⇧L`: Shift timings
- `⌘⇧4`: Export MP4
- `⌘⇧5`: Export MOV
- `⌘/`: Open tutorial

## Support

If you want to support ongoing development, the repository is prepared for GitHub Sponsors.  
The funding entry point is configured in [.github/FUNDING.yml](.github/FUNDING.yml).
If GitHub Sponsors is not enabled for `LilQ-JP` yet, GitHub will not show the sponsor button until that account is activated.

## Licensing and Release Notes

- Apple frameworks such as `Vision` and `AVFoundation` are platform-provided components, not separate open source packages redistributed by this repository.
- `Ollama` is an optional local runtime with its own upstream license.
- Python dependencies from `requirements.txt` should be disclosed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) when you publish builds.
- Ollama model licenses are separate from the app and should be checked per model.
- Every GitHub Release should include human-readable update notes. The project now keeps a reusable history in [CHANGELOG.md](CHANGELOG.md) and a GitHub release-notes config in `.github/release.yml`.

## Notes

For general public distribution, always use the Developer ID signed and notarized `zip / pkg` artifacts.  
The current release flow is documented in `RELEASE_CHECKLIST.md` and automated by `notarize_release.sh`.
