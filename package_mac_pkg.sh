#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/Tools/versioning.sh"

CONFIG="${1:-release}"
VERSION_FILE="$SCRIPT_DIR/VERSION"
VERSION="$(resolve_app_version "$VERSION_FILE" "${2:-}")"
OUTPUT_DIR="${3:-$(versioned_release_dir "$SCRIPT_DIR/release" "$VERSION")}"

echo "Building Caption Studio ($CONFIG)..."
swift build -c "$CONFIG"

APP_PATH="$("$SCRIPT_DIR/package_mac_app.sh" "$CONFIG" "$VERSION")"
PKG_PATH="$OUTPUT_DIR/$(versioned_artifact_name "$VERSION" "macOS.pkg")"
ZIP_PATH="$OUTPUT_DIR/$(versioned_artifact_name "$VERSION" "macOS.zip")"
APP_EXPORT_PATH="$OUTPUT_DIR/Caption Studio.app"
IDENTIFIER="com.lilq.captionstudio.pkg"
PAYLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/subtitleextractor-pkg.XXXXXX")"
STAGED_APP_DIR="$PAYLOAD_DIR"
COMPONENT_PLIST="$(mktemp "${TMPDIR:-/tmp}/subtitleextractor-components.XXXXXX.plist")"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$STAGED_APP_DIR"
trap 'rm -rf "$PAYLOAD_DIR"; rm -f "$COMPONENT_PLIST"' EXIT

rm -rf "$APP_EXPORT_PATH"
ditto --noextattr --noqtn "$APP_PATH" "$APP_EXPORT_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_EXPORT_PATH" "$ZIP_PATH"

ditto --noextattr --noqtn "$APP_PATH" "$STAGED_APP_DIR/$(basename "$APP_PATH")"
xattr -cr "$STAGED_APP_DIR/$(basename "$APP_PATH")" 2>/dev/null || true
find "$STAGED_APP_DIR/$(basename "$APP_PATH")" -name '._*' -delete
codesign --force --deep --sign - "$STAGED_APP_DIR/$(basename "$APP_PATH")" >/dev/null 2>&1 || true

pkgbuild --analyze --root "$PAYLOAD_DIR" "$COMPONENT_PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleHasStrictIdentifier true" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleOverwriteAction upgrade" "$COMPONENT_PLIST"

rm -f "$PKG_PATH"
pkgbuild \
  --root "$PAYLOAD_DIR" \
  --component-plist "$COMPONENT_PLIST" \
  --install-location Applications \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  "$PKG_PATH"

echo "Version: $VERSION"
echo "App bundle: $APP_EXPORT_PATH"
echo "ZIP archive: $ZIP_PATH"
echo "PKG installer: $PKG_PATH"
