#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_SOURCE_DIR="$ROOT_DIR/Sources/SubtitleExtractorMacApp/Resources/Python"
OUTPUT_DIR="${1:-$ROOT_DIR/.backend-dist/SubtitleBackendCLI}"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/subtitle-backend-cli.XXXXXX")"
DIST_DIR="$BUILD_ROOT/dist"
WORK_DIR="$BUILD_ROOT/build"
SPEC_DIR="$BUILD_ROOT/spec"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

if ! python3 -m PyInstaller --version >/dev/null 2>&1; then
  echo "PyInstaller が見つかりません。'python3 -m pip install pyinstaller' を実行してください。" >&2
  exit 1
fi

python3 -m PyInstaller \
  --noconfirm \
  --clean \
  --onedir \
  --name SubtitleBackendCLI \
  --paths "$PYTHON_SOURCE_DIR" \
  --distpath "$DIST_DIR" \
  --workpath "$WORK_DIR" \
  --specpath "$SPEC_DIR" \
  --exclude-module meikiocr \
  --exclude-module torch \
  --exclude-module torchvision \
  --exclude-module scipy \
  --exclude-module pandas \
  --exclude-module streamlit \
  --exclude-module whisper \
  --exclude-module openai \
  --exclude-module sympy \
  --exclude-module numba \
  --exclude-module jupyter \
  --exclude-module matplotlib \
  --exclude-module tensorboard \
  "$PYTHON_SOURCE_DIR/backend_cli.py"

rm -rf "$OUTPUT_DIR"
mkdir -p "$(dirname "$OUTPUT_DIR")"
ditto --noextattr --noqtn "$DIST_DIR/SubtitleBackendCLI" "$OUTPUT_DIR"
xattr -cr "$OUTPUT_DIR" 2>/dev/null || true
find "$OUTPUT_DIR" -depth -name '__pycache__' -type d -exec rm -rf {} \;
find "$OUTPUT_DIR" -name '*.pyc' -delete
find "$OUTPUT_DIR" -name '._*' -delete

echo "$OUTPUT_DIR"
