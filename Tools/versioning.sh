#!/bin/bash
set -euo pipefail

validate_app_version() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must use MAJOR.MINOR.PATCH format: $version" >&2
    return 1
  fi
}

read_app_version_from_file() {
  local version_file="$1"
  local default_version="${2:-1.0.0}"

  if [[ ! -f "$version_file" ]]; then
    validate_app_version "$default_version"
    printf '%s\n' "$default_version"
    return
  fi

  local version
  version="$(tr -d '[:space:]' < "$version_file")"
  if [[ -z "$version" ]]; then
    echo "VERSION file is empty: $version_file" >&2
    return 1
  fi

  validate_app_version "$version"
  printf '%s\n' "$version"
}

resolve_app_version() {
  local version_file="$1"
  local requested_version="${2:-}"

  if [[ -n "$requested_version" ]]; then
    validate_app_version "$requested_version"
    printf '%s\n' "$requested_version"
    return
  fi

  read_app_version_from_file "$version_file"
}

versioned_release_dir() {
  local release_root="$1"
  local version="$2"
  validate_app_version "$version"
  printf '%s/%s\n' "$release_root" "$version"
}

versioned_artifact_name() {
  local version="$1"
  local suffix="$2"
  validate_app_version "$version"
  printf 'CaptionStudio-%s-%s\n' "$version" "$suffix"
}

bump_app_version() {
  local current_version="$1"
  local bump_kind="$2"
  validate_app_version "$current_version"

  local major minor patch
  IFS='.' read -r major minor patch <<< "$current_version"

  case "$bump_kind" in
    patch)
      patch=$((patch + 1))
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    *)
      echo "Unknown bump kind: $bump_kind" >&2
      return 1
      ;;
  esac

  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}
