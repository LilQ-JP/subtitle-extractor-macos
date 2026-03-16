#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/Tools/versioning.sh"

VERSION_FILE="$SCRIPT_DIR/VERSION"
VERSION="$(resolve_app_version "$VERSION_FILE" "${1:-}")"
OUTPUT_DIR="${2:-$(versioned_release_dir "$SCRIPT_DIR/release" "$VERSION")}"
PROFILE_NAME="${NOTARY_PROFILE:-SubtitleExtractorNotary}"
APP_CERTIFICATE="${DEVELOPER_ID_APPLICATION:-}"
INSTALLER_CERTIFICATE="${DEVELOPER_ID_INSTALLER:-}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.lilq.captionstudio}"
PKG_IDENTIFIER="${PKG_IDENTIFIER:-com.lilq.captionstudio.pkg}"
APP_PATH="$OUTPUT_DIR/Caption Studio.app"
ZIP_PATH="$OUTPUT_DIR/$(versioned_artifact_name "$VERSION" "macOS.zip")"
PKG_PATH="$OUTPUT_DIR/$(versioned_artifact_name "$VERSION" "macOS.pkg")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/subtitle-notary.XXXXXX")"
WORK_APP_PATH="$TMP_DIR/Caption Studio.app"
PAYLOAD_DIR="$TMP_DIR/payload"
COMPONENT_PLIST="$TMP_DIR/components.plist"
UNSIGNED_PKG_PATH="$TMP_DIR/CaptionStudio-unsigned.pkg"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

detect_app_certificate() {
  security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
    head -n 1
}

detect_installer_certificate() {
  security find-identity -v -p basic 2>/dev/null |
    sed -n 's/.*"\(Developer ID Installer:.*\)"/\1/p' |
    head -n 1
}

fail_with_instructions() {
  local message="$1"
  echo "$message" >&2
  exit 1
}

stage_clean_app_bundle() {
  local source_app="$1"
  local target_root="$2"

  rm -rf "$target_root/$(basename "$source_app")"
  COPYFILE_DISABLE=1 tar -C "$(dirname "$source_app")" -cf - "$(basename "$source_app")" | (
    cd "$target_root"
    COPYFILE_DISABLE=1 tar -xf -
  )
}

strip_problematic_artifacts() {
  local target="$1"

  find "$target" -depth -name '__pycache__' -type d -exec rm -rf {} +
  find "$target" -name '*.pyc' -delete
  find "$target" -name '.DS_Store' -delete
  find "$target" -name '._*' -delete

  while IFS= read -r -d '' path; do
    xattr -d com.apple.FinderInfo "$path" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$path" 2>/dev/null || true
    xattr -d com.apple.ResourceFork "$path" 2>/dev/null || true
  done < <(find "$target" -print0)

  xattr -cr "$target" 2>/dev/null || true
}

sign_embedded_macho_files() {
  local root="$1"
  local certificate="$2"
  local path=""
  local macho_type=""

  while IFS= read -r -d '' path; do
    macho_type="$(file -b "$path" 2>/dev/null || true)"
    if [[ "$macho_type" == *"Mach-O"* ]]; then
      codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$certificate" \
        "$path"
    fi
  done < <(find "$root" -type f -print0)

  while IFS= read -r -d '' path; do
    codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$certificate" \
      "$path"
  done < <(find "$root" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.bundle' -o -name '*.xpc' \) -print0)
}

if [[ -z "$APP_CERTIFICATE" ]]; then
  APP_CERTIFICATE="$(detect_app_certificate)"
fi

if [[ -z "$INSTALLER_CERTIFICATE" ]]; then
  INSTALLER_CERTIFICATE="$(detect_installer_certificate)"
fi

if [[ -z "$APP_CERTIFICATE" ]]; then
  fail_with_instructions "Developer ID Application 証明書が見つかりません。Apple Developer で作成して login keychain に入れてから再実行してください。"
fi

if [[ -z "$INSTALLER_CERTIFICATE" ]]; then
  fail_with_instructions "Developer ID Installer 証明書が見つかりません。Apple Developer で作成して login keychain に入れてから再実行してください。"
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE_NAME" >/dev/null 2>&1; then
  fail_with_instructions "notarytool の認証プロファイル '$PROFILE_NAME' が見つかりません。先に xcrun notarytool store-credentials \"$PROFILE_NAME\" ... を実行してください。"
fi

echo "Building release app..."
swift build -c release >/dev/null
BUILT_APP_PATH="$("$SCRIPT_DIR/package_mac_app.sh" release "$VERSION")"

mkdir -p "$OUTPUT_DIR"
stage_clean_app_bundle "$BUILT_APP_PATH" "$TMP_DIR"
strip_problematic_artifacts "$WORK_APP_PATH"

if [[ -d "$WORK_APP_PATH/Contents/Resources/BackendCLI" ]]; then
  echo "Signing bundled backend binaries..."
  sign_embedded_macho_files "$WORK_APP_PATH/Contents/Resources/BackendCLI" "$APP_CERTIFICATE"
fi

echo "Signing app with: $APP_CERTIFICATE"
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$APP_CERTIFICATE" \
  "$WORK_APP_PATH"

codesign --verify --deep --strict "$WORK_APP_PATH"

echo "Submitting app for notarization..."
TMP_ZIP_PATH="$TMP_DIR/CaptionStudio-for-notary.zip"
ditto -c -k --sequesterRsrc --keepParent "$WORK_APP_PATH" "$TMP_ZIP_PATH"
xcrun notarytool submit "$TMP_ZIP_PATH" --keychain-profile "$PROFILE_NAME" --wait
xcrun stapler staple "$WORK_APP_PATH"
xcrun stapler validate "$WORK_APP_PATH"

echo "Creating distributable ZIP..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$WORK_APP_PATH" "$ZIP_PATH"

echo "Syncing signed app bundle into release directory..."
rm -rf "$APP_PATH"
ditto --noextattr --noqtn "$WORK_APP_PATH" "$APP_PATH"

echo "Building installer package..."
mkdir -p "$PAYLOAD_DIR"
ditto --noextattr --noqtn "$WORK_APP_PATH" "$PAYLOAD_DIR/Caption Studio.app"
pkgbuild --analyze --root "$PAYLOAD_DIR" "$COMPONENT_PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleHasStrictIdentifier true" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleOverwriteAction upgrade" "$COMPONENT_PLIST"
pkgbuild \
  --root "$PAYLOAD_DIR" \
  --component-plist "$COMPONENT_PLIST" \
  --install-location Applications \
  --identifier "$PKG_IDENTIFIER" \
  --version "$VERSION" \
  "$UNSIGNED_PKG_PATH"

echo "Signing installer with: $INSTALLER_CERTIFICATE"
productsign \
  --sign "$INSTALLER_CERTIFICATE" \
  "$UNSIGNED_PKG_PATH" \
  "$PKG_PATH"

pkgutil --check-signature "$PKG_PATH"

echo "Submitting installer for notarization..."
xcrun notarytool submit "$PKG_PATH" --keychain-profile "$PROFILE_NAME" --wait
xcrun stapler staple "$PKG_PATH"
xcrun stapler validate "$PKG_PATH"

echo "Signed and notarized app bundle staged at: $WORK_APP_PATH"
echo "Version: $VERSION"
echo "Notarized zip: $ZIP_PATH"
echo "Notarized pkg: $PKG_PATH"
