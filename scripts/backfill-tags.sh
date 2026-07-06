#!/usr/bin/env bash
#
# One-time migration to the tagging convention described in the top-level
# README:
#
#   - anchor every live <component>-vN alias with an immutable
#     <component>-vN.0.0 tag at the same commit, so release-tags.sh has a
#     semver baseline to bump from
#   - delete tags of removed or misspelled components and the legacy
#     repo-wide X.Y.Z tags created by the retired auto-tag workflow
#
# Dry-run by default; pass --execute to create/delete tags and push.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# The plan below is computed from local tags; make sure they mirror the
# remote before turning them into remote creates/deletes.
git fetch --force --prune --prune-tags origin

EXECUTE="${1:-}"

# Live components: every action directory plus the reusable workflow tag
# families (must match COMPONENT_PATHS in release-tags.sh).
LIVE_COMPONENTS=(
  build-binaries
  build-docker
  build-library
  workflow-benchmarks
  workflow-checks
  workflow-checks-zizmor
  workflow-tests
)
for dir in actions/*/; do
  LIVE_COMPONENTS+=("$(basename "$dir")")
done

is_live() {
  local component="$1" live
  for live in "${LIVE_COMPONENTS[@]}"; do
    [[ $component == "$live" ]] && return 0
  done
  return 1
}

ANCHORS=()
DELETIONS=()
while read -r tag; do
  if [[ $tag =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    DELETIONS+=("$tag")
    continue
  fi
  if [[ ! $tag =~ ^(.+)-v([0-9]+)$ ]]; then
    continue
  fi
  component="${BASH_REMATCH[1]}"
  major="${BASH_REMATCH[2]}"
  if ! is_live "$component"; then
    DELETIONS+=("$tag")
    continue
  fi
  # If release-tags.sh already released this major, the alias has moved
  # past its pre-automation commit and a synthetic anchor would only
  # mislead; the semver baseline exists either way.
  if [[ -n "$(git tag -l "${component}-v${major}.*.*")" ]]; then
    continue
  fi
  anchor="${component}-v${major}.0.0"
  if [[ -z "$(git tag -l "$anchor")" ]]; then
    ANCHORS+=("$anchor $tag")
  fi
done < <(git tag)

echo "=== Anchor tags to create (at the commit of the current alias) ==="
printf '%s\n' "${ANCHORS[@]:-<none>}"
echo
echo "=== Tags to delete (dead component families and legacy repo tags) ==="
printf '%s\n' "${DELETIONS[@]:-<none>}"

if [[ $EXECUTE != "--execute" ]]; then
  echo
  echo "Dry-run only. Re-run with --execute to apply and push."
  exit 0
fi

for entry in "${ANCHORS[@]}"; do
  read -r anchor alias_tag <<<"$entry"
  git tag -a "$anchor" -m "$anchor" "${alias_tag}^{commit}"
  git push origin "$anchor"
done

for tag in "${DELETIONS[@]}"; do
  git push origin --delete "$tag"
  git tag -d "$tag"
done
