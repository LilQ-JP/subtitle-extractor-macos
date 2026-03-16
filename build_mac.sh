#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/Tools/versioning.sh"

VERSION_FILE="$SCRIPT_DIR/VERSION"
APP_VERSION="$(read_app_version_from_file "$VERSION_FILE")"

echo "Building Caption Studio $APP_VERSION..."
swift build -c release

APP_PATH="$("$SCRIPT_DIR/package_mac_app.sh" release "$APP_VERSION")"

echo "Build complete."
echo "Version: $APP_VERSION"
echo "Executable: $SCRIPT_DIR/.build/release/SubtitleExtractorMacApp"
echo "App bundle: $APP_PATH"
