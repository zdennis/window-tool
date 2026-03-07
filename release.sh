#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: release.sh [patch|minor|major|<version>]

Bump and tag a new release on the main branch.

Arguments:
  patch       Bump the patch version (e.g., v0.1.0 -> v0.1.1)
  minor       Bump the minor version (e.g., v0.1.0 -> v0.2.0)
  major       Bump the major version (e.g., v0.1.0 -> v1.0.0)
  <version>   Set an explicit version (e.g., 13.1.2 -> v13.1.2)

If no argument is given, prints the current version.
EOF
}

get_latest_tag() {
  git tag --list 'v*' --sort=-v:refname | head -n1
}

current_branch() {
  git rev-parse --abbrev-ref HEAD
}

# Ensure we're on main
if [ "$(current_branch)" != "main" ]; then
  echo "Error: Must be on the main branch to release. Currently on: $(current_branch)" >&2
  exit 1
fi

# Ensure no uncommitted changes to tracked files (untracked files are ignored)
if git diff --quiet && git diff --cached --quiet; then
  : # clean
else
  echo "Error: Working tree has uncommitted changes. Commit or stash changes first." >&2
  exit 1
fi

latest_tag=$(get_latest_tag)

if [ $# -eq 0 ]; then
  if [ -z "$latest_tag" ]; then
    echo "No releases yet."
  else
    echo "Current version: $latest_tag"
  fi
  exit 0
fi

arg="$1"

case "$arg" in
  -h|--help|help)
    usage
    exit 0
    ;;
  patch|minor|major)
    if [ -z "$latest_tag" ]; then
      echo "Error: No existing tag found. Create an initial tag first with an explicit version." >&2
      exit 1
    fi

    # Parse current version
    version="${latest_tag#v}"
    IFS='.' read -r cur_major cur_minor cur_patch <<< "$version"

    case "$arg" in
      patch) cur_patch=$((cur_patch + 1)) ;;
      minor) cur_minor=$((cur_minor + 1)); cur_patch=0 ;;
      major) cur_major=$((cur_major + 1)); cur_minor=0; cur_patch=0 ;;
    esac

    new_version="v${cur_major}.${cur_minor}.${cur_patch}"
    ;;
  *)
    # Explicit version — validate it looks like semver
    clean_version="${arg#v}"
    if ! echo "$clean_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "Error: Invalid version format: $arg (expected M.m.p, e.g., 1.2.3)" >&2
      exit 1
    fi

    new_version="v${clean_version}"

    printf "Tag as %s? [y/N] " "$new_version"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
    ;;
esac

# Ensure local main is up to date with remote
git fetch origin main --quiet
local_sha=$(git rev-parse HEAD)
remote_sha=$(git rev-parse origin/main)
if [ "$local_sha" != "$remote_sha" ]; then
  echo "Error: Local main ($local_sha) differs from origin/main ($remote_sha)." >&2
  echo "Pull or push first to sync." >&2
  exit 1
fi

# Build to ensure we're tagging a known-good binary
echo "Building..."
if ! ./build.sh; then
  echo "Error: Build failed. Fix build errors before releasing." >&2
  exit 1
fi

# Check tag doesn't already exist
if git tag --list | grep -qx "$new_version"; then
  echo "Error: Tag $new_version already exists." >&2
  exit 1
fi

short_sha=$(git rev-parse --short HEAD)
echo "Tagging $new_version at $short_sha..."
git tag "$new_version"
git push origin "$new_version"
echo "Released $new_version ($short_sha)"
