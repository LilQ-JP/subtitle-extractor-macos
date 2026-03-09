#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building SubtitleExtractorMacApp..."
swift build -c release

APP_PATH="$("$SCRIPT_DIR/package_mac_app.sh" release)"

echo "Build complete."
echo "Executable: $SCRIPT_DIR/.build/release/SubtitleExtractorMacApp"
echo "App bundle: $APP_PATH"
