#!/usr/bin/env bash
# List the workspace crates a release run has to release and bump.
#
# Run from the workspace root. Configured through environment variables:
# METADATA_FILE (output of `cargo metadata --no-deps --format-version 1`),
# REPOSITORY (owner/name), GH_TOKEN, and optionally PACKAGE_NAME to limit the
# result to one crate.
#
# releases: published crates without a tag, as {name, version, manifest, tag_prefix}.
# bumps:    names of all published crates still at their published version, so a
#           rerun after a failed release or bump job still bumps them.
# Both are written as compact JSON to $GITHUB_OUTPUT.
set -euo pipefail

# HTTP status of the crates.io version endpoint (200 published, 404 unknown).
crates_io_status() {
  curl -sS -o /dev/null -w '%{http_code}' --proto '=https' --tlsv1.2 \
    -A 'hoprnet-workflows (tech@hoprnet.org)' "https://crates.io/api/v1/crates/$1/$2"
}

# A root package keeps the legacy 'v' tag, workspace members are tagged per crate.
tag_prefix_for() {
  if [[ $1 == "Cargo.toml" ]]; then echo "v"; else echo "$2-v"; fi
}

# Same lookup as set-build-version: every '^version =' line of the manifest.
manifest_version() {
  grep -E '^version\s*=' "$1" | awk -F\" '{print $2}' || true
}

# Succeeds when the tag exists, fails with 1 when it does not, 2 on any other error.
tag_exists() {
  local out
  if out=$(gh api "repos/${REPOSITORY}/git/ref/tags/$1" 2>&1); then
    return 0
  elif [[ $out == *"HTTP 404"* ]]; then
    return 1
  fi
  echo "::error::tag lookup for $1 failed: ${out}" >&2
  return 2
}

discover() {
  local metadata="${METADATA_FILE:?METADATA_FILE is required}"
  local root name version manifest status prefix manifest_ver rc
  local releases='[]' bumps='[]' rows
  root=$(jq -r '.workspace_root' "$metadata")
  # A variable, not process substitution: set -e does not see a failure inside <( )
  rows=$(jq -r --arg root "${root}/" --arg pkg "${PACKAGE_NAME:-}" '
    .packages[]
    | select(.publish != [] and ($pkg == "" or .name == $pkg))
    | [.name, .version, (.manifest_path | ltrimstr($root))] | @tsv' "$metadata")
  if [[ -n ${PACKAGE_NAME:-} && -z $rows ]]; then
    echo "::error::No publishable workspace crate named '${PACKAGE_NAME}'" >&2
    return 1
  fi
  while IFS=$'\t' read -r name version manifest; do
    [[ -n $name ]] || continue
    # crates.io is the source of truth for "released"; 404 means nothing was published
    status=$(crates_io_status "$name" "$version")
    if [[ $status == "404" ]]; then
      echo "Skipping ${name} ${version}: not on crates.io"
      continue
    elif [[ $status != "200" ]]; then
      echo "::error::crates.io lookup for ${name} ${version} returned HTTP ${status}" >&2
      return 1
    fi
    # release-version reads every '^version =' line, so exactly the package version must come out
    manifest_ver=$(manifest_version "$manifest")
    if [[ $manifest_ver != "$version" ]]; then
      echo "::error::${manifest} version lines read '${manifest_ver}', expected '${version}' (version.workspace is not supported)" >&2
      return 1
    fi
    bumps=$(jq -c --arg name "$name" '. + [$name]' <<<"$bumps")
    prefix=$(tag_prefix_for "$manifest" "$name")
    rc=0
    tag_exists "${prefix}${version}" || rc=$?
    if [[ $rc -eq 0 ]]; then
      echo "Skipping ${name} ${version}: tag ${prefix}${version} exists"
      continue
    elif [[ $rc -ne 1 ]]; then
      return 1
    fi
    releases=$(jq -c --arg name "$name" --arg version "$version" --arg manifest "$manifest" --arg prefix "$prefix" \
      '. + [{name: $name, version: $version, manifest: $manifest, tag_prefix: $prefix}]' <<<"$releases")
  done <<<"$rows"
  echo "Releases to create: ${releases}"
  echo "Crates to bump: ${bumps}"
  {
    echo "releases=${releases}"
    echo "bumps=${bumps}"
  } >>"${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  discover "$@"
fi
