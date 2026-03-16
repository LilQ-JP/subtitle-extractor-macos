#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/versioning.sh"

VERSION_FILE="$ROOT_DIR/VERSION"
VERSION="$(resolve_app_version "$VERSION_FILE" "${1:-}")"
OUTPUT_DIR="${2:-$(versioned_release_dir "$ROOT_DIR/release" "$VERSION")}"
PROFILE_NAME="${NOTARY_PROFILE:-SubtitleExtractorNotary}"
APP_PATH="$OUTPUT_DIR/Caption Studio.app"
ZIP_PATH="$OUTPUT_DIR/$(versioned_artifact_name "$VERSION" "macOS.zip")"
PKG_PATH="$OUTPUT_DIR/$(versioned_artifact_name "$VERSION" "macOS.pkg")"
APP_PLIST="$APP_PATH/Contents/Info.plist"
FAILURES=0
WARNINGS=0

ok() {
  printf 'OK   %s\n' "$1"
}

warn() {
  printf 'WARN %s\n' "$1"
  WARNINGS=$((WARNINGS + 1))
}

fail() {
  printf 'FAIL %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

read_plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

has_developer_id_app_signature() {
  local output=""
  output="$(codesign -dv --verbose=4 "$1" 2>&1 || true)"
  if grep -Fq 'Authority=Developer ID Application:' <<<"$output"; then
    return 0
  fi

  spctl -a -vv "$1" 2>&1 | grep -Fq 'origin=Developer ID Application:'
}

has_adhoc_signature() {
  codesign -dv --verbose=4 "$1" 2>&1 | grep -Fq 'Signature=adhoc'
}

has_developer_id_installer_signature() {
  pkgutil --check-signature "$1" 2>&1 | grep -Fq 'Developer ID Installer:'
}

has_stapled_ticket() {
  xcrun stapler validate "$1" >/dev/null 2>&1
}

has_app_certificate() {
  security find-identity -v -p codesigning 2>/dev/null | grep -Fq 'Developer ID Application:'
}

has_installer_certificate() {
  security find-identity -v -p basic 2>/dev/null | grep -Fq 'Developer ID Installer:'
}

has_notary_profile() {
  xcrun notarytool history --keychain-profile "$PROFILE_NAME" >/dev/null 2>&1
}

printf 'Release preflight for %s\n' "$VERSION"
printf 'Output directory: %s\n' "$OUTPUT_DIR"
printf '\n'

if [[ -d "$APP_PATH" ]]; then
  ok "App bundle exists: $APP_PATH"
else
  fail "Missing app bundle: $APP_PATH"
fi

if [[ -f "$ZIP_PATH" ]]; then
  ok "ZIP exists: $ZIP_PATH"
else
  fail "Missing ZIP archive: $ZIP_PATH"
fi

if [[ -f "$PKG_PATH" ]]; then
  ok "PKG exists: $PKG_PATH"
else
  fail "Missing PKG installer: $PKG_PATH"
fi

if [[ -f "$APP_PLIST" ]]; then
  SHORT_VERSION="$(read_plist_value "$APP_PLIST" CFBundleShortVersionString)"
  BUILD_VERSION="$(read_plist_value "$APP_PLIST" CFBundleVersion)"
  if [[ "$SHORT_VERSION" == "$VERSION" ]]; then
    ok "App short version matches VERSION ($SHORT_VERSION)"
  else
    fail "App short version mismatch: expected $VERSION, found ${SHORT_VERSION:-missing}"
  fi

  if [[ "$BUILD_VERSION" == "$VERSION" ]]; then
    ok "App build version matches VERSION ($BUILD_VERSION)"
  else
    fail "App build version mismatch: expected $VERSION, found ${BUILD_VERSION:-missing}"
  fi
fi

if [[ -d "$APP_PATH" ]]; then
  if has_developer_id_app_signature "$APP_PATH"; then
    ok "App is signed with Developer ID Application"
  elif has_adhoc_signature "$APP_PATH"; then
    warn "App is only ad-hoc signed"
  else
    warn "App is not signed with Developer ID Application"
  fi

  if has_stapled_ticket "$APP_PATH"; then
    ok "App bundle has a stapled notarization ticket"
  else
    warn "App bundle is not stapled/notarized yet"
  fi
fi

if [[ -f "$PKG_PATH" ]]; then
  if has_developer_id_installer_signature "$PKG_PATH"; then
    ok "PKG is signed with Developer ID Installer"
  else
    warn "PKG is not signed with Developer ID Installer"
  fi

  if has_stapled_ticket "$PKG_PATH"; then
    ok "PKG has a stapled notarization ticket"
  else
    warn "PKG is not stapled/notarized yet"
  fi
fi

if has_app_certificate; then
  ok "Developer ID Application certificate is available in login keychain"
else
  warn "Developer ID Application certificate is missing from login keychain"
fi

if has_installer_certificate; then
  ok "Developer ID Installer certificate is available in login keychain"
else
  warn "Developer ID Installer certificate is missing from login keychain"
fi

if has_notary_profile; then
  ok "notarytool profile '$PROFILE_NAME' is available"
else
  warn "notarytool profile '$PROFILE_NAME' is missing"
fi

printf '\n'
if (( FAILURES > 0 || WARNINGS > 0 )); then
  printf 'Preflight summary: %d fail, %d warn\n' "$FAILURES" "$WARNINGS"
  exit 1
fi

printf 'Preflight summary: all checks passed\n'
