#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Starting SubtitleExtractorMacApp..."
swift build
APP_PATH="$("$SCRIPT_DIR/package_mac_app.sh" debug)"
open "$APP_PATH"
osascript -e 'tell application id "com.haru.SubtitleExtractorMacApp" to activate'
