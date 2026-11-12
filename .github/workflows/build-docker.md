# Build Docker

Builds platform-specific Docker images using Nix and creates a multi-architecture manifest. Supports pushing to Google Artifact Registry and Docker Hub, scanning for vulnerabilities (Trivy).

## Jobs

| Job          | Description                                                                          |
| ------------ | ------------------------------------------------------------------------------------ |
| `build`      | Matrix build: one job per entry in `build_matrix`                                    |
| `smoke-test` | Runs a smoke-test command against the built image (optional)                         |
| `manifest`   | Creates and pushes the multi-arch manifest (incl. floating release tags, see below). Skipped on fork PRs |
| `scan`       | Scans the image for vulnerabilities with Trivy, attests the SBOM |

## Usage

```yaml
jobs:
  build-docker:
    name: Docker
    uses: hoprnet/hopr-workflows/.github/workflows/build-docker.yaml@<commit-hash>
    needs: build-binaries
    permissions:
      contents: read
      id-token: write
    with:
      repo_sha: ${{ github.event.pull_request.head.sha || github.sha }}
      version_type: "commit"
      build_matrix: >-
        [
          {
            "runner": "depot-ubuntu-22.04-4",
            "architecture": "x86_64-linux",
            "build_command": "nix run -L .#docker-hoprd-x86_64-linux",
            "smoke_test_command": "nix develop -c just smoke-test"
          }
        ]
      cachix_cache_name: "hopr"
      docker_image_name: "hoprd"
      docker_image_format: skopeo
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      docker_hub_username: ${{ secrets.DOCKER_HUB_USERNAME }}
      docker_hub_token: ${{ secrets.DOCKER_HUB_TOKEN }}
```

### `build_matrix` schema

Each entry in the JSON array must include:

| Key                   | Required | Description                               |
| --------------------- | -------- | ----------------------------------------- |
| `runner`              | Yes      | Runner label for this matrix entry        |
| `architecture`        | Yes      | Target architecture (e.g. `x86_64-linux`) |
| `build_command`       | Yes      | Command to build the Docker image         |
| `build_debug_command` | No       | Command to build a debug variant          |
| `smoke_test_command`  | No       | Command to run a smoke test after build   |

## Inputs

| Name                           | Required | Default                                                     | Description                                                                           |
| ------------------------------ | -------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `repo_sha`                | Yes      | —                             | Commit SHA to check out (use `github.event.pull_request.head.sha \|\| github.sha`) |
| `version_type`                 | Yes      | —                                                           | Versioning strategy: `commit`, `pr`, or `release`                                     |
| `build_matrix`                 | Yes      | —                                                           | JSON array of matrix entries (see schema above)                                       |
| `cachix_cache_name`            | No       | —                                                           | Cachix cache name                                                                     |
| `cachix_extra_pull_names`      | No       | —                                                           | Comma-separated list of additional Cachix caches to pull (substitute) from, read-only |
| `nix_path`                     | No       | `nixpkgs=channel:nixos-26.05`                               | Nix path to use                                                                       |
| `build_file`                   | No       | `Cargo.toml`                                                | File to extract version from                                                          |
| `docker_image_name`            | Yes      | —                                                           | Docker image name                                                                     |
| `docker_image_format`          | No       | `docker`                                                    | Image format: `docker` or `skopeo`                                                    |
| `docker_gcp_registry`          | No       | `europe-west3-docker.pkg.dev/hoprassociation/docker-images` | GCP Docker registry                                                                   |
| `docker_hub_registry`          | No       | `docker.io/hoprnet`                                         | Docker Hub registry                                                                   |
| `docker_bucket_sboms`          | No       | `docker-images-sboms`                                       | GCS bucket for SBOM files (vulnerability analysis)                                    |
| `timeout_minutes`              | No       | `60`                                                        | Timeout in minutes                                                                    |
| `fail_on_scan_vulnerabilities` | No       | `true`                                                      | Fail the build when vulnerabilities are found                                         |
| `concurrency_group_suffix`     | No       | `""`                                                        | Extra string appended to the concurrency group key                                    |
| `job_runner`                   | No       | `depot-ubuntu-22.04-4`                                      | Runner for non-matrix jobs (manifest, scan).                                          |
| `enabled`                      | No       | `true`                                                      | Set to `false` to skip every job (callers use it to label-gate the build)             |

## Secrets

| Name                  | Required | Description                                                          |
| --------------------- | -------- | -------------------------------------------------------------------- |
| `gcp_service_account` | Yes      | GCP service account with Artifact Registry and GCS write permissions |
| `cachix_auth_token`   | No       | Auth token for Cachix cache                                          |
| `docker_hub_username` | No       | Docker Hub username (required for release builds)                    |
| `docker_hub_token`    | No       | Docker Hub token (required for release builds)                       |

## Tags

On every build the multi-arch manifest is pushed under the full version
(`docker_build_version`). A stable `release` build (a clean `X.Y.Z`, not a
pre-release such as `-rc.N` or `-beta.N`) also pushes floating manifests for the
bare major and the major.minor, pointing at the same platform images, so consumers
can pin to a line and pick up patches:

| Version type           | Version tags pushed (per registry)    |
| ---------------------- | ------------------------------------- |
| `commit` / `pr`        | full version only                     |
| `release` (e.g. 5.0.1) | `5.0.1`, `5.0`, `5`                   |
| `release` pre-release  | full version only (e.g. `5.0.1-rc.1`) |

The floating versions come from the `set-build-version` action's `major_version`
and `minor_version` outputs. Manifest members use the full `docker_build_version`
via `source_version`; no separate `5-linux-*` or `5.0-linux-*` images are built.
The workflow must pin a manifest action revision that supports `source_version`.
Older revisions ignore that input, look for nonexistent floating-tag platform
images, and skip publishing the floating manifests.

Separately, the `manifest` job also maintains tracking (non-version) tags: `edge`
on deploy-commit builds, `latest` / `latest-main` / `latest-testing` for PR builds,
and `release-main` / `release-testing` for releases.

## Outputs

| Name                   | Description                      |
| ---------------------- | -------------------------------- |
| `docker_build_version` | Docker image version built       |
| `docker_debug_version` | Docker debug image version built |

## Pull requests from forks

A PR from a fork runs on the plain `pull_request` event: secrets are empty, the `GITHUB_TOKEN` is read-only and there is no OIDC token, so nothing that needs GCP can run. Fork PRs are detected with `github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name != github.repository`. On a fork PR:

- The image is built, and the archive is uploaded as a run artifact (`docker-image-<architecture>`, 1 day retention) so `scan` and `smoke-test` use the locally built image instead of pulling it from Artifact Registry.
- `Setup GCP`, the image and debug image publishing, the `manifest` job, the SBOM attestation and the SBOM upload to GCS are skipped.
- The Trivy scan and the smoke test still run, against the local image. The smoke test command receives the same `SOURCE_IMAGE` reference, which is tagged on the local image; it must not pull it.

Internal PRs, `merge_group`, push and release runs keep publishing as before. Required checks for skipped jobs (`Multi-Arch`) report as skipped.

