#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/Tools/versioning.sh"

CONFIG="${1:-debug}"
VERSION_FILE="$SCRIPT_DIR/VERSION"
REQUESTED_VERSION="${2:-}"
APP_DISPLAY_NAME="Caption Studio"
APP_EXECUTABLE_NAME="CaptionStudio"
APP_BUNDLE_IDENTIFIER="com.lilq.captionstudio"
PROJECT_TYPE_IDENTIFIER="com.lilq.captionstudio.project"
ARCH_DIR="$SCRIPT_DIR/.build/arm64-apple-macosx/$CONFIG"
EXECUTABLE="$ARCH_DIR/SubtitleExtractorMacApp"
RESOURCE_BUNDLE="$ARCH_DIR/SubtitleExtractorMacApp_SubtitleExtractorMacApp.bundle"
APP_DIR="$ARCH_DIR/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BACKEND_DIR="$RESOURCES_DIR/BackendCLI"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
ICON_PATH="$SCRIPT_DIR/Assets/AppIcon.icns"
ICON_COMPOSER_PATH="$SCRIPT_DIR/Assets/AppIcon.icon"
ICON_PNG_CANDIDATES=(
  "$SCRIPT_DIR/Assets/AppIcon.png"
  "$SCRIPT_DIR/Assets/AppIcon-1024.png"
  "$SCRIPT_DIR/Assets/AppIcon_1024.png"
)
ICON_GENERATOR="$SCRIPT_DIR/Tools/generate_app_icon.swift"
BACKEND_BUILDER="$SCRIPT_DIR/Tools/build_backend_cli.sh"
ACTOOL_PATH="$(xcrun --find actool 2>/dev/null || true)"
ICON_BUILD_DIR=""
ASSETS_CAR_PATH=""
ICON_FILE_VALUE="AppIcon"
ICON_NAME_VALUE=""
APP_VERSION="$(resolve_app_version "$VERSION_FILE" "$REQUESTED_VERSION")"

cleanup() {
  if [[ -n "$ICON_BUILD_DIR" && -d "$ICON_BUILD_DIR" ]]; then
    rm -rf "$ICON_BUILD_DIR"
  fi
}

trap cleanup EXIT

generate_icns_from_png() {
  local png_path="$1"
  local iconset_dir
  iconset_dir="$(mktemp -d "${TMPDIR:-/tmp}/subtitleextractor-iconset.XXXXXX.iconset")"

  mkdir -p "$iconset_dir"
  sips -z 16 16     "$png_path" --out "$iconset_dir/icon_16x16.png" >/dev/null
  sips -z 32 32     "$png_path" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$png_path" --out "$iconset_dir/icon_32x32.png" >/dev/null
  sips -z 64 64     "$png_path" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$png_path" --out "$iconset_dir/icon_128x128.png" >/dev/null
  sips -z 256 256   "$png_path" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$png_path" --out "$iconset_dir/icon_256x256.png" >/dev/null
  sips -z 512 512   "$png_path" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$png_path" --out "$iconset_dir/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$png_path" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$iconset_dir" -o "$ICON_PATH"
  rm -rf "$iconset_dir"
}

compile_icon_composer_asset() {
  local icon_source="$1"
  ICON_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/captionstudio-icon.XXXXXX")"
  "$ACTOOL_PATH" "$icon_source" \
    --app-icon AppIcon \
    --compile "$ICON_BUILD_DIR" \
    --output-partial-info-plist "$ICON_BUILD_DIR/assetcatalog_generated_info.plist" \
    --minimum-deployment-target 11.0 \
    --platform macosx \
    --target-device mac >/dev/null

  if [[ -f "$ICON_BUILD_DIR/AppIcon.icns" ]]; then
    ICON_PATH="$ICON_BUILD_DIR/AppIcon.icns"
    ICON_FILE_VALUE="AppIcon"
    ICON_NAME_VALUE="AppIcon"
  fi

  if [[ -f "$ICON_BUILD_DIR/Assets.car" ]]; then
    ASSETS_CAR_PATH="$ICON_BUILD_DIR/Assets.car"
  fi
}

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Executable not found: $EXECUTABLE" >&2
  exit 1
fi

mkdir -p "$SCRIPT_DIR/Assets"

if [[ -d "$ICON_COMPOSER_PATH" && -n "$ACTOOL_PATH" ]]; then
  compile_icon_composer_asset "$ICON_COMPOSER_PATH"
elif [[ ! -f "$ICON_PATH" ]]; then
  for candidate in "${ICON_PNG_CANDIDATES[@]}"; do
    if [[ -f "$candidate" ]]; then
      generate_icns_from_png "$candidate"
      break
    fi
  done
fi

if [[ ! -f "$ICON_PATH" && -f "$ICON_GENERATOR" ]]; then
  swift "$ICON_GENERATOR" "$ICON_PATH"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/$APP_EXECUTABLE_NAME"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  ditto --noextattr --noqtn "$RESOURCE_BUNDLE" "$RESOURCES_DIR/$(basename "$RESOURCE_BUNDLE")"
fi

if [[ "$CONFIG" == "release" || "${SUBTITLE_BUNDLE_BACKEND:-0}" == "1" ]]; then
  if [[ -x "$BACKEND_BUILDER" ]]; then
    BACKEND_OUTPUT="$("$BACKEND_BUILDER")"
    ditto --noextattr --noqtn "$BACKEND_OUTPUT" "$BACKEND_DIR"
  else
    echo "Bundled backend builder not found: $BACKEND_BUILDER" >&2
    exit 1
  fi
fi

if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
fi

if [[ -n "$ASSETS_CAR_PATH" && -f "$ASSETS_CAR_PATH" ]]; then
  cp "$ASSETS_CAR_PATH" "$RESOURCES_DIR/Assets.car"
fi

ICON_NAME_PLIST=""
if [[ -n "$ICON_NAME_VALUE" ]]; then
  ICON_NAME_PLIST=$(cat <<PLIST
  <key>CFBundleIconName</key>
  <string>$ICON_NAME_VALUE</string>
PLIST
)
fi

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>ja</string>
  <key>CFBundleDisplayName</key>
  <string>Caption Studio</string>
  <key>CFBundleExecutable</key>
  <string>CaptionStudio</string>
  <key>CFBundleIdentifier</key>
  <string>com.lilq.captionstudio</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Caption Studio Project</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>$PROJECT_TYPE_IDENTIFIER</string>
      </array>
    </dict>
  </array>
  <key>CFBundleIconFile</key>
  <string>$ICON_FILE_VALUE</string>
$ICON_NAME_PLIST
  <key>CFBundleName</key>
  <string>Caption Studio</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>$PROJECT_TYPE_IDENTIFIER</string>
      <key>UTTypeDescription</key>
      <string>Caption Studio Project</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.json</string>
      </array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>subtitleproject</string>
        </array>
        <key>public.mime-type</key>
        <string>application/json</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR" 2>/dev/null || true
find "$APP_DIR" -depth -name '__pycache__' -type d -exec rm -rf {} \;
find "$APP_DIR" -name '*.pyc' -delete
find "$APP_DIR" -name '.DS_Store' -delete
find "$APP_DIR" -name '._*' -delete

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "$APP_DIR"
