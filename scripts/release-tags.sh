#!/usr/bin/env bash
#
# Create per-component release tags for every action or reusable workflow
# changed between two commits (see "Tags" in the top-level README):
#
#   <component>-vX.Y.Z   immutable release tag
#   <component>-vX       moving alias to the latest release of that major
#
# The bump level is derived from the conventional commit messages in the
# range: feat! / BREAKING CHANGE -> major, feat -> minor, anything else
# -> patch. A scope naming a different component does not raise this
# component's bump level.
#
# Usage: release-tags.sh <base_sha> <head_sha> [--dry-run]

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BASE_SHA="${1:?usage: release-tags.sh <base_sha> <head_sha> [--dry-run]}"
HEAD_SHA="${2:?usage: release-tags.sh <base_sha> <head_sha> [--dry-run]}"
DRY_RUN="${3:-}"

# On the first push to a branch (or a force push) the "before" commit is
# unknown; fall back to the head commit's parent.
if ! git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null; then
  BASE_SHA="$(git rev-parse "${HEAD_SHA}~1")"
fi

# Each releasable component and the path that triggers its release.
# Actions are discovered from their directories; reusable workflows keep
# their historical tag family names, hence the explicit mapping.
declare -A COMPONENT_PATHS=(
  ["build-binaries"]=".github/workflows/build-binaries.yaml"
  ["build-docker"]=".github/workflows/build-docker.yaml"
  ["build-library"]=".github/workflows/build-library.yaml"
  ["workflow-benchmarks"]=".github/workflows/benchmarks.yaml"
  ["workflow-checks"]=".github/workflows/checks.yaml"
  ["workflow-checks-zizmor"]=".github/workflows/checks-zizmor.yaml"
  ["workflow-tests"]=".github/workflows/tests.yaml"
)
for dir in actions/*/; do
  name="$(basename "$dir")"
  COMPONENT_PATHS[$name]="actions/$name"
done

# A scoped commit only applies to the component named in the scope;
# workflow components also accept their file stem (e.g. "tests" for
# "workflow-tests"). Unscoped commits apply to every touched component.
scope_applies() {
  local scope="$1" component="$2"
  [[ -z $scope || $scope == "$component" || "workflow-$scope" == "$component" ]]
}

bump_for_component() {
  local component="$1" path="$2"
  local bump="patch"
  local sha subject body type scope bang
  while read -r sha; do
    subject="$(git log -1 --format=%s "$sha")"
    body="$(git log -1 --format=%b "$sha")"
    if [[ $subject =~ ^([a-z]+)(\(([^\)]+)\))?(!)?: ]]; then
      type="${BASH_REMATCH[1]}"
      scope="${BASH_REMATCH[3]}"
      bang="${BASH_REMATCH[4]}"
    else
      continue
    fi
    if ! scope_applies "$scope" "$component"; then
      continue
    fi
    if [[ -n $bang || $body == *"BREAKING CHANGE"* ]]; then
      bump="major"
    elif [[ $type == "feat" && $bump != "major" ]]; then
      bump="minor"
    fi
  done < <(git log --format=%H "${BASE_SHA}..${HEAD_SHA}" -- "$path")
  echo "$bump"
}

# Latest released version of a component. Falls back to the highest
# pre-automation major alias (<component>-vN) counted as N.0.0.
current_version() {
  local component="$1"
  local latest
  latest="$(git tag -l "${component}-v*" | grep -E "^${component}-v[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -1 || true)"
  if [[ -n $latest ]]; then
    echo "${latest#"${component}"-v}"
    return
  fi
  latest="$(git tag -l "${component}-v*" | grep -E "^${component}-v[0-9]+$" | sort -V | tail -1 || true)"
  if [[ -n $latest ]]; then
    echo "${latest#"${component}"-v}.0.0"
  fi
}

next_version() {
  local version="$1" bump="$2"
  local major minor patch
  IFS=. read -r major minor patch <<<"$version"
  case "$bump" in
  major) echo "$((major + 1)).0.0" ;;
  minor) echo "${major}.$((minor + 1)).0" ;;
  patch) echo "${major}.${minor}.$((patch + 1))" ;;
  esac
}

release_component() {
  local component="$1" version="$2"
  local release_tag="${component}-v${version}"
  local alias_tag="${component}-v${version%%.*}"
  if [[ $DRY_RUN == "--dry-run" ]]; then
    echo "[dry-run] would create ${release_tag} and move ${alias_tag} to ${HEAD_SHA}"
    return
  fi
  echo "Creating ${release_tag} and moving ${alias_tag} to ${HEAD_SHA}"
  git tag -a "$release_tag" -m "$release_tag" "$HEAD_SHA"
  git tag -f "$alias_tag" "$HEAD_SHA"
  # Atomic so a failed push cannot publish the release tag while leaving
  # the alias on the previous release.
  git push --atomic origin "refs/tags/${release_tag}" "+refs/tags/${alias_tag}"
}

for component in $(printf '%s\n' "${!COMPONENT_PATHS[@]}" | sort); do
  path="${COMPONENT_PATHS[$component]}"
  if git diff --quiet "$BASE_SHA" "$HEAD_SHA" -- "$path"; then
    continue
  fi
  current="$(current_version "$component")"
  if [[ -z $current ]]; then
    version="1.0.0"
  else
    bump="$(bump_for_component "$component" "$path")"
    version="$(next_version "$current" "$bump")"
  fi
  release_component "$component" "$version"
done
