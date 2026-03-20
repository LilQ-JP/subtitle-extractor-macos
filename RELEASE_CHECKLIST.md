# Release Checklist

## 1. Decide the version

```bash
./Tools/bump_version.sh patch
```

If you need a specific version:

```bash
./Tools/bump_version.sh 1.0.4
```

## 2. Run tests

```bash
swift test
```

## 3. Update changelog and release summary

- add the user-facing changes to `CHANGELOG.md`
- prepare the GitHub Release summary from the same points
- if needed, tune `.github/release.yml` categories for auto-generated notes

## 4. Build release artifacts

```bash
./package_mac_pkg.sh release
```

Artifacts are created under `release/<version>/`.

- `Caption Studio.app`
- `CaptionStudio-<version>-macOS.zip`
- `CaptionStudio-<version>-macOS.pkg`

## 5. Run public-release preflight

```bash
./Tools/release_preflight.sh
```

This checks:

- artifact presence
- app bundle version alignment
- Developer ID signatures
- stapled notarization tickets
- local certificate availability
- `notarytool` profile availability

If this step shows warnings, the build is not ready for general public distribution yet.

## 6. Sign and notarize

```bash
./notarize_release.sh
```

Required before running this step:

- `Developer ID Application` certificate in login keychain
- `Developer ID Installer` certificate in login keychain
- `SubtitleExtractorNotary` profile stored with `notarytool`

## 7. Run preflight again

```bash
./Tools/release_preflight.sh
```

General public release is ready when this passes with no warnings.

## 8. Publish on GitHub Releases

- tag: `v<version>`
- attach:
  - `CaptionStudio-<version>-macOS.zip`
  - `CaptionStudio-<version>-macOS.pkg`
- copy the matching user-facing notes from `CHANGELOG.md`
- or use GitHub's generated notes with `.github/release.yml` and then trim the wording manually

Release type:

- `Pre-release`: only users who enable prerelease updates in the app should receive it through in-app update checks.
- `Latest release`: stable users receive it through in-app update checks.

## Release Notes Template

```md
## Highlights
- 

## Fixes
- 

## Known Notes
- 
```
