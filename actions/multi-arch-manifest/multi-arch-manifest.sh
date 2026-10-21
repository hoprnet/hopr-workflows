#!/usr/bin/env bash
# Create (and push) a multi-arch docker manifest.
#
# Configured through environment variables: REGISTRY, IMAGE, VERSION and,
# optionally, SOURCE_VERSION.
#
# The manifest is named $REGISTRY/$IMAGE:$VERSION. Its per-arch members are
# taken from $REGISTRY/$IMAGE:$SOURCE_VERSION-<arch>. SOURCE_VERSION defaults
# to VERSION; set it to point a floating tag (e.g. a bare major "5") at the
# platform images that were pushed under the full version ("5.0.1").
set -euo pipefail

registry="${REGISTRY:?REGISTRY is required}"
image="${IMAGE:?IMAGE is required}"
version="${VERSION:?VERSION is required}"
source_version="${SOURCE_VERSION:-$version}"

docker_manifest="${registry}/${image}:${version}"
source_ref="${registry}/${image}:${source_version}"
images=()
for arch in linux-arm64 linux-amd64; do
  img="${source_ref}-${arch}"
  if docker manifest inspect "$img" >/dev/null 2>&1; then
    images+=(--amend "$img")
  else
    echo "[WARN] Missing or not accessible: $img"
  fi
done

if [ "${#images[@]}" -eq 0 ]; then
  echo "[WARN] No images found to create the manifest."
  exit 0 # Exit without error if no images are found as the debug image might not be built
else
  echo "[INFO] Creating multi-arch docker manifest: ${docker_manifest}"
  docker manifest create "${docker_manifest}" "${images[@]}"
  docker manifest push "${docker_manifest}"
fi
