#!/usr/bin/env bash
# Self-test for multi-arch-manifest.sh. No bats dependency: a recording `docker`
# stub is put on PATH, the script runs, and the captured `docker manifest create`
# line is asserted. Run: bash actions/multi-arch-manifest/test-multi-arch-manifest.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="${here}/multi-arch-manifest.sh"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# A `docker` stub recording invocations. MISSING (newline-separated image refs)
# makes `manifest inspect` report those members as absent. POSIX /bin/sh so it
# execs both locally and inside the Nix build sandbox (no /usr/bin/env there).
cat >"${workdir}/docker" <<'STUB'
#!/bin/sh
if [ "$1" = "manifest" ] && [ "$2" = "inspect" ]; then
  if [ -n "${MISSING:-}" ] && printf '%s\n' "${MISSING}" | grep -Fxq "$3"; then
    exit 1
  fi
  exit 0
fi
printf '%s\n' "$*" >> "${CAPTURE}"
STUB
chmod +x "${workdir}/docker"

fail=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - ${label}"
  else
    echo "FAIL - ${label}"
    echo "       expected: ${expected}"
    echo "       actual:   ${actual}"
    fail=1
  fi
}

# Run the script with the stub on PATH; echo back the captured `manifest create` line.
run() {
  local capture="${workdir}/capture"
  : >"${capture}"
  CAPTURE="${capture}" MISSING="${MISSING:-}" PATH="${workdir}:${PATH}" bash "${script}" "$@" >/dev/null
  grep '^manifest create' "${capture}" || true
}

reg="europe-west3-docker.pkg.dev/hoprassociation/docker-images"
img="hoprd"

# 1. No source_version: members and manifest both use the full version (regression guard).
check "full version, no source_version" \
  "manifest create ${reg}/${img}:5.0.1 --amend ${reg}/${img}:5.0.1-linux-arm64 --amend ${reg}/${img}:5.0.1-linux-amd64" \
  "$(run "${reg}" "${img}" "5.0.1")"

# 2. Empty source_version arg behaves like omitted (this is how the action passes it).
check "full version, empty source_version arg" \
  "manifest create ${reg}/${img}:5.0.1 --amend ${reg}/${img}:5.0.1-linux-arm64 --amend ${reg}/${img}:5.0.1-linux-amd64" \
  "$(run "${reg}" "${img}" "5.0.1" "")"

# 3. Major floating tag: manifest named :5, members from the full version.
check "major tag from full version" \
  "manifest create ${reg}/${img}:5 --amend ${reg}/${img}:5.0.1-linux-arm64 --amend ${reg}/${img}:5.0.1-linux-amd64" \
  "$(run "${reg}" "${img}" "5" "5.0.1")"

# 4. Major.minor floating tag: manifest named :5.0, same members.
check "major.minor tag from full version" \
  "manifest create ${reg}/${img}:5.0 --amend ${reg}/${img}:5.0.1-linux-arm64 --amend ${reg}/${img}:5.0.1-linux-amd64" \
  "$(run "${reg}" "${img}" "5.0" "5.0.1")"

# 5. A member missing is skipped but the manifest is still created from the rest.
MISSING="${reg}/${img}:5.0.1-linux-arm64" \
check "one member missing -> manifest from remaining" \
  "manifest create ${reg}/${img}:5 --amend ${reg}/${img}:5.0.1-linux-amd64" \
  "$(MISSING="${reg}/${img}:5.0.1-linux-arm64" run "${reg}" "${img}" "5" "5.0.1")"

# 6. All members missing: no manifest create at all, exit 0.
check "all members missing -> no manifest create" \
  "" \
  "$(MISSING="$(printf '%s\n%s' "${reg}/${img}:5.0.1-linux-arm64" "${reg}/${img}:5.0.1-linux-amd64")" run "${reg}" "${img}" "5" "5.0.1")"

# 7. Floating-tag extraction: the exact parameter expansions used in build-docker.yaml.
#    (major="${v%%.*}", minor="${v%.*}")
extract() { local v="$1"; echo "${v%%.*} ${v%.*}"; }
check "extraction 5.0.1 -> major minor" "5 5.0" "$(extract 5.0.1)"
check "extraction 5.10.3 -> major minor" "5 5.10" "$(extract 5.10.3)"

exit "${fail}"
