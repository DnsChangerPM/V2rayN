#!/usr/bin/env bash
# Computes the next release version.
#
# Usage:
#   next-version.sh <tags-file> <bump> <explicit> <prerelease> <prerelease-number>
#
#   tags-file          file with one existing tag per line (may be empty)
#   bump               auto | patch | minor | major | none
#   explicit           explicit version (wins over bump when non empty)
#   prerelease         none | alpha | beta | rc
#   prerelease-number  numeric suffix for the prerelease
#
# Prints `key=value` pairs ready for $GITHUB_OUTPUT (when set) and always
# writes them to stdout as a GitHub Actions step summary friendly block.
set -euo pipefail

TAGS_FILE="${1:-}"
BUMP="${2:-auto}"
EXPLICIT="${3:-}"
PRERELEASE="${4:-none}"
Prenum="${5:-1}"

SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'

# Collect the highest stable tag (vX.Y.Z).
latest_stable="0.0.0"
if [[ -f "$TAGS_FILE" ]]; then
  while IFS= read -r tag; do
    tag="${tag#refs/tags/}"
    tag="${tag#v}"
    [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    if [[ "$(printf '%s\n%s\n' "$latest_stable" "$tag" | sort -V | tail -n1)" == "$tag" ]]; then
      latest_stable="$tag"
    fi
  done < "$TAGS_FILE"
fi

suggest() {
  local base="$1"
  IFS='.' read -r major minor patch <<< "$base"
  case "$BUMP" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch|auto) echo "${major}.${minor}.$((patch + 1))" ;;
    none) echo "$base" ;;
    *) echo "${major}.${minor}.$((patch + 1))" ;;
  esac
}

if [[ -n "$EXPLICIT" ]]; then
  version="$EXPLICIT"
else
  version="$(suggest "$latest_stable")"
fi

# Strip a leading v just in case.
version="${version#v}"

# Append the prerelease suffix.
if [[ "$PRERELEASE" != "none" ]]; then
  version="$version-$PRERELEASE.$Prenum"
fi

if [[ ! "$version" =~ $SEMVER_RE ]]; then
  echo "::error::'$version' is not a valid semantic version (expected X.Y.Z or X.Y.Z-alpha.1)" >&2
  exit 1
fi

tag="v$version"

# Does the tag already exist?
if [[ -f "$TAGS_FILE" ]] && grep -qxF "$tag" "$TAGS_FILE"; then
  echo "::error::tag $tag already exists - choose another version" >&2
  exit 1
fi

major="${version%%.*}"
rest="${version#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"
patch="${patch%%[+-]*}"

emit() {
  echo "$1=$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "$1=$2" >> "$GITHUB_OUTPUT"
  fi
}

emit "version" "$version"
emit "tag" "$tag"
emit "major" "$major"
emit "minor" "$minor"
emit "patch" "$patch"
emit "latest_stable" "$latest_stable"
emit "suggested" "$(suggest "$latest_stable")"
emit "is_prerelease" "$([[ "$PRERELEASE" != "none" ]] && echo true || echo false)"
emit "file_version" "${major}.${minor}.${patch}.0"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Version"
    echo ""
    echo "| field | value |"
    echo "| --- | --- |"
    echo "| previous tag | \`v$latest_stable\` |"
    echo "| auto suggestion | \`$(suggest "$latest_stable")\` |"
    echo "| **chosen version** | **\`$version\`** |"
    echo "| release tag | \`$tag\` |"
  } >> "$GITHUB_STEP_SUMMARY"
fi
