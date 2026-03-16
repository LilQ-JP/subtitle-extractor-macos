#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"

source "$SCRIPT_DIR/versioning.sh"

CURRENT_VERSION="$(read_app_version_from_file "$VERSION_FILE")"
REQUEST="${1:-patch}"

case "$REQUEST" in
  patch|minor|major)
    NEXT_VERSION="$(bump_app_version "$CURRENT_VERSION" "$REQUEST")"
    ;;
  *)
    NEXT_VERSION="$REQUEST"
    validate_app_version "$NEXT_VERSION"
    ;;
esac

printf '%s\n' "$NEXT_VERSION" > "$VERSION_FILE"

echo "Updated version: $CURRENT_VERSION -> $NEXT_VERSION"
echo "Next package command: ./package_mac_pkg.sh release $NEXT_VERSION"
