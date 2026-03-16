#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_ENV_DIR="$HOME/Library/Application Support/CaptionStudio/python-env"
ENV_DIR="${CAPTION_STUDIO_PYTHON_ENV:-$DEFAULT_ENV_DIR}"
PYTHON_BIN="${CAPTION_STUDIO_PYTHON_BIN:-}"

select_python() {
  if [[ -n "$PYTHON_BIN" ]]; then
    echo "$PYTHON_BIN"
    return 0
  fi

  local candidates=(
    "/opt/homebrew/bin/python3"
    "/usr/local/bin/python3"
    "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"
  )

  if command -v python3 >/dev/null 2>&1; then
    candidates+=("$(command -v python3)")
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

PYTHON_BIN="$(select_python || true)"
if [[ -z "$PYTHON_BIN" ]]; then
  echo "Python 3 が見つかりません。Homebrew か python.org の Python 3 を先に入れてください。" >&2
  exit 1
fi

echo "Using Python: $PYTHON_BIN"
echo "Installing managed environment at: $ENV_DIR"

mkdir -p "$(dirname "$ENV_DIR")"
"$PYTHON_BIN" -m venv "$ENV_DIR"

VENV_PYTHON="$ENV_DIR/bin/python3"
if [[ ! -x "$VENV_PYTHON" ]]; then
  echo "venv の作成に失敗しました: $VENV_PYTHON" >&2
  exit 1
fi

export PIP_DISABLE_PIP_VERSION_CHECK=1

"$VENV_PYTHON" -m pip install --upgrade pip setuptools wheel
"$VENV_PYTHON" -m pip install -r "$ROOT_DIR/requirements.txt"

"$VENV_PYTHON" - <<'PY'
import json
import sys

checks = {}

try:
    import cv2  # noqa: F401
    checks["cv2"] = "ok"
except Exception as error:  # pragma: no cover
    checks["cv2"] = f"error: {error}"

try:
    from PIL import ImageFont  # noqa: F401
    checks["Pillow"] = "ok"
except Exception as error:  # pragma: no cover
    checks["Pillow"] = f"error: {error}"

print(json.dumps({"python": sys.executable, "checks": checks}, ensure_ascii=False))
PY

echo
echo "Setup complete."
echo "Caption Studio will auto-detect: $VENV_PYTHON"
