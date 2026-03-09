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

mkdir -p "$OUTPUT_DIR"

# Ad-hoc sign so the component package contains a coherent bundle signature.
codesign --force --deep --sign - "$APP_PATH" >/dev/null 2>&1 || true

rm -f "$PKG_PATH"
pkgbuild \
  --component "$APP_PATH" \
  --install-location /Applications \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  "$PKG_PATH"

echo "$PKG_PATH"
