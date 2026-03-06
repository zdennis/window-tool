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

# Ensure working tree is clean
if [ -n "$(git status --porcelain)" ]; then
  echo "Error: Working tree is not clean. Commit or stash changes first." >&2
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
    IFS='.' read -r major minor patch <<< "$version"

    case "$arg" in
      patch) patch=$((patch + 1)) ;;
      minor) minor=$((minor + 1)); patch=0 ;;
      major) major=$((major + 1)); minor=0; patch=0 ;;
    esac

    new_version="v${major}.${minor}.${patch}"
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

# Check tag doesn't already exist
if git tag --list | grep -qx "$new_version"; then
  echo "Error: Tag $new_version already exists." >&2
  exit 1
fi

echo "Tagging $new_version..."
git tag "$new_version"
git push origin "$new_version"
echo "Released $new_version"
