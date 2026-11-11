#!/usr/bin/env bash
# Bump the version of the given workspace crates with `cargo release version`.
#
# Configured through environment variables: PACKAGES (crate names separated by
# whitespace or newlines) and RELEASE_TYPE (major, minor, patch or rc).
# Writes `commit_files=<space separated changed files>` to $GITHUB_OUTPUT.
set -euo pipefail

validate_release_type() {
  case "$1" in
  major | minor | patch | rc) ;;
  *)
    echo "::error::Invalid release_type: '$1' (expected major, minor, patch or rc)" >&2
    return 1
    ;;
  esac
}

# Print one crate name per line; reject anything cargo could read as a flag or a shell fragment.
parse_packages() {
  local name found=0
  for name in $1; do
    if [[ ! $name =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]; then
      echo "::error::Invalid package name: '$name'" >&2
      return 1
    fi
    echo "$name"
    found=1
  done
  if [[ $found -eq 0 ]]; then
    echo "::error::No packages given to bump" >&2
    return 1
  fi
}

changed_files() {
  # Only what cargo release edits; other dirty tracked files must not enter the bump commit
  git diff --name-only -- 'Cargo.lock' '*Cargo.toml' | tr '\n' ' ' | sed 's/ $//'
}

main() {
  local release_type="${RELEASE_TYPE:-}"
  validate_release_type "$release_type"
  # A variable, not process substitution: set -e does not see a failure inside <( )
  local names
  names=$(parse_packages "${PACKAGES:-}")
  local -a package_args=()
  local name
  while IFS= read -r name; do
    package_args+=(--package "$name")
  done <<<"$names"

  cargo release version "$release_type" "${package_args[@]}" --execute --no-confirm

  echo "commit_files=$(changed_files)" >>"${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
