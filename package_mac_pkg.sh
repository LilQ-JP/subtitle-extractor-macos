#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="${1:-release}"
VERSION="${2:-1.0.0}"
OUTPUT_DIR="${3:-$SCRIPT_DIR/release}"

APP_PATH="$("$SCRIPT_DIR/package_mac_app.sh" "$CONFIG")"
PKG_PATH="$OUTPUT_DIR/SubtitleExtractorMacApp-macOS.pkg"
IDENTIFIER="com.haru.SubtitleExtractorMacApp.pkg"
PAYLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/subtitleextractor-pkg.XXXXXX")"
STAGED_APP_DIR="$PAYLOAD_DIR"
COMPONENT_PLIST="$PAYLOAD_DIR/components.plist"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$STAGED_APP_DIR"
trap 'rm -rf "$PAYLOAD_DIR"' EXIT

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

echo "$PKG_PATH"
