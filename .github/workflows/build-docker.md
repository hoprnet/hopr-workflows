# Build Docker

Builds platform-specific Docker images using Nix and creates a multi-architecture manifest. Supports pushing to Google Artifact Registry and Docker Hub, scanning for vulnerabilities (Trivy), and optionally restarting a Kubernetes deployment in staging.

## Jobs

| Job | Description |
|-----|-------------|
| `build` | Matrix build: one job per entry in `build_matrix` |
| `smoke-test` | Runs a smoke-test command against the built image (optional) |
| `manifest` | Creates and pushes the multi-arch manifest |
| `scan` | Scans the image for vulnerabilities with Trivy, uploads SARIF to GitHub Security tab |
| `deploy` | Restarts a Kubernetes deployment in staging (optional) |

## Usage

```yaml
jobs:
  build-docker:
    name: Docker
    uses: hoprnet/hopr-workflows/.github/workflows/build-docker.yaml@build-docker-v2
    needs: build-binaries
    permissions:
      contents: read
      security-events: write
      id-token: write
    with:
      source_branch: ${{ github.event.pull_request.head.ref || github.ref }}
      version_type: "commit"
      build_matrix: >-
        [
          {
            "runner": "self-hosted-hoprnet-bigger",
            "architecture": "x86_64-linux",
            "build_command": "nix run -L .#docker-hoprd-x86_64-linux",
            "smoke_test_command": "nix develop -c just smoke-test"
          }
        ]
      cachix_cache_name: "hopr"
      docker_image_name: "hoprd"
      docker_image_format: skopeo
    secrets:
      gcp_service_account: ${{ secrets.GOOGLE_HOPRASSOCIATION_CREDENTIALS_REGISTRY }}
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      docker_hub_username: ${{ secrets.DOCKER_HUB_USERNAME }}
      docker_hub_token: ${{ secrets.DOCKER_HUB_TOKEN }}
```

### `build_matrix` schema

Each entry in the JSON array must include:

| Key | Required | Description |
|-----|----------|-------------|
| `runner` | Yes | Runner label for this matrix entry |
| `architecture` | Yes | Target architecture (e.g. `x86_64-linux`) |
| `build_command` | Yes | Command to build the Docker image |
| `build_debug_command` | No | Command to build a debug variant |
| `smoke_test_command` | No | Command to run a smoke test after build |

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `source_branch` | Yes | — | Source branch to build from |
| `version_type` | Yes | — | Versioning strategy: `commit`, `pr`, or `release` |
| `build_matrix` | Yes | — | JSON array of matrix entries (see schema above) |
| `cachix_cache_name` | No | — | Cachix cache name |
| `build_file` | No | `Cargo.toml` | File to extract version from |
| `docker_image_name` | Yes | — | Docker image name |
| `docker_image_format` | No | `docker` | Image format: `docker` or `skopeo` |
| `docker_gcp_registry` | No | `europe-west3-docker.pkg.dev/hoprassociation/docker-images` | GCP Docker registry |
| `docker_hub_registry` | No | `docker.io/hoprnet` | Docker Hub registry |
| `docker_bucket_sboms` | No | `docker-images-sboms` | GCS bucket for SBOM files (vulnerability analysis) |
| `timeout_minutes` | No | `60` | Timeout in minutes |
| `deployment_namespace` | No | — | Kubernetes namespace for staging restart |
| `deployment_label_selector` | No | — | Kubernetes label selector for staging restart |
| `fail_on_scan_vulnerabilities` | No | `true` | Fail the build when vulnerabilities are found |
| `concurrency_group_suffix` | No | `""` | Extra string appended to the concurrency group key |
| `job_runner` | No | `depot-ubuntu-22.04-4` | Runner for non-matrix jobs (manifest, scan, deploy) |

## Secrets

| Name | Required | Description |
|------|----------|-------------|
| `gcp_service_account` | Yes | GCP service account with Artifact Registry and GCS write permissions |
| `cachix_auth_token` | Yes | Auth token for Cachix cache |
| `docker_hub_username` | No | Docker Hub username (required for release builds) |
| `docker_hub_token` | No | Docker Hub token (required for release builds) |

## Outputs

| Name | Description |
|------|-------------|
| `docker_build_version` | Docker image version built |
| `docker_debug_version` | Docker debug image version built |
