# hopr-workflows

This repository contains a collection of custom GitHub Actions and Reusable Workflows designed to streamline and automate CI/CD processes, release management, and artifact handling for the HOPR repositories.

## Actions

- [Bump Version](./actions/bump-version/README.md): Bumps project version and commit.
- [Download Artifact Registry](./actions/download-artifact-registry/README.md): Downloads artifacts from Google Artifact Registry.
- [Generate Release Notes](./actions/generate-release-notes/README.md): Generate Release notes
- [Multi Architecture Manifest](./actions/multi-arch-manifest/README.md): Publishes a multi-arch docker manifest
- [Publish Rust Docs](./actions/publish-rust-docs/README.md): Publishes rust docs in GitHub Pages
- [Release Version](./actions/release-version/README.md): Creates a GitHub release
- [Set Build Version](./actions/set-build-version/README.md): Updates project version before building
- [Setup GCP](./actions/setup-gcp/README.md): Setup GCP tools and permissions
- [Setup Nix](./actions/setup-nix/README.md): Setup a Nix environment in the runner
- [Setup Node Js](./actions/setup-node-js/README.md): Setup Node Js and Yarn
- [Sign file](./actions/sign-file/README.md): Creates a GPG signature of the file and SHA256
- [Upload Artifact Registry](./actions/upload-artifact-registry/README.md): Upload files into the Google Artifact registry.


## Reusable Workflows

This repository provides reusable workflows designed to simplify the build and release process for HOPR projects. These workflows can be called from other repositories to standardize binary compilation, Docker image creation, and multi-architecture support.

### [Build Binaries](./.github/workflows/build-binaries.yaml)

Compiles binaries for a specific architecture using Nix. It handles version naming, signing and upload files to artifact registry.

**Usage:**
```yaml
jobs:
  build:
    uses: hoprnet/hopr-workflows/.github/workflows/build-binaries.yaml@build-binaries-v1
    with:
      source_branch: ${{ github.ref_name }}
      version_type: commit
      architecture: x86_64-linux
      cachix_cache_name: hopr
      build_command: nix build .#binary-hoprd-x86_64-linux
      binary: hoprd
      runner: self-hosted-hoprnet-bigger
    secrets:
      gcp_service_account: ${{ secrets.GOOGLE_HOPRASSOCIATION_CREDENTIALS_REGISTRY}}
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      gpg_private_key: ${{ secrets.GPG_HOPRNET_PRIVATE_KEY }}
```

**Inputs:**
- `source_branch` (Required): Source branch to build the binary from.
- `version_type` (Required): The strategy for versioning (e.g., `commit`, `pr`, `release`).
- `architecture` (Optional): The target architecture (Default: `x86_64-linux`).
- `cachix_cache_name` (Required): The name of the Cachix cache to use.
- `build_file` (Optional): File to extract version from (Default: `Cargo.toml`).
- `build_command` (Required): The command to execute the build.
- `build_debug_command` (Optional): Additional build debug flavor to use.
- `binary` (Required): The name of the binary to output.
- `timeout_minutes` (Optional): Timeout for the job in minutes (Default: `60`).
- `runner` (Required): The runner label to use for the job.
- `deployment_namespace`: Kubernetes namespace for the deployment to restart in staging
- `deployment_label_selector`: Kubernetes label selector for the deployment to restart in staging
- `fail_on_scan_vulnerabilities`: Whether to fail the build if vulnerabilities are found during the scan (Default: `true`)

**Secrets:**
- `gcp_service_account` (Required): Google Cloud Service Account with permissions to upload artifacts.
- `cachix_auth_token` (Required): Auth token for Cachix cache.
- `gpg_private_key` (Required): GPG Key to sign the artifacts.

**Outputs:**

- No outputs defined.

### [Build Docker Image](./.github/workflows/build-docker-image.yaml)

Constructs a platform-specific Docker image for the project. This workflow is designed to run in a parallel matrix for different architectures to later be combined into a manifest.

**Usage:**
```yaml
jobs:
  docker_image:
    uses: hoprnet/hopr-workflows/.github/workflows/build-docker-image.yaml@build-docker-image-v1
    with:
      source_branch: ${{ github.ref_name }}
      version_type: commit
      architecture: x86_64-linux
      cachix_cache_name: hopr
      build_command: nix build .#docker-hoprd-x86_64-linux
      docker_image_name: hoprd
      smoke_test_command: nix develop -c just smoke-test
    secrets:
      gcp_service_account: ${{ secrets.GOOGLE_HOPRASSOCIATION_CREDENTIALS_REGISTRY}}
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      docker_hub_username: ${{ secrets.DOCKER_HUB_USERNAME }}
      docker_hub_token: ${{ secrets.DOCKER_HUB_TOKEN }}
```

**Key Features:**
- Builds Docker images using Nix or standard commands.
- Scan docker images for vulnerabilities.
- Support for pushing to Google Artifact Registry and Docker Hub.
- Outputs version tags for downstream jobs.

**Inputs:**
- `source_branch` (Required): Source branch to build the docker image from.
- `version_type` (Required): The strategy for versioning (e.g., `commit`, `pr`, `release`).
- `architecture` (Optional): The target architecture (Default: `x86_64-linux`).
- `cachix_cache_name` (Required): The name of the Cachix cache to use.
- `build_file` (Optional): File to extract version from (Default: `Cargo.toml`).
- `build_command` (Required): Command to build the image.
- `build_debug_command` (Optional): Additional build debug flavor to use.
- `smoke_test_command` (Optional): Command to run basic verifications on the built image.
- `docker_image_name` (Required): The name of the image.
- `docker_gcp_registry` (Optional): Docker registry to push the image to (Default: `europe-west3-docker.pkg.dev/hoprassociation/docker-images`).
- `docker_hub_registry` (Optional): Docker registry to push the image to (Default: `docker.io/hoprnet`).
- `timeout_minutes` (Optional): Timeout for the job in minutes (Default: `60`).
- `runner` (Optional): Runner to use for the job (Default: `self-hosted-hoprnet-bigger`).
- `deployment_namespace` (Optional): Kubernetes namespace for the deployment to restart in staging.
- `deployment_label_selector` (Optional): Kubernetes label selector for the deployment to restart in staging.

**Secrets:**
- `gcp_service_account` (Required): Google Cloud Service Account with permissions to upload artifacts.
- `cachix_auth_token` (Required): Auth token for Cachix cache.
- `docker_hub_username` (Optional): Docker Hub username (Required for release builds).
- `docker_hub_token` (Optional): Docker Hub token (Required for release builds).

**Outputs:**
- `docker_build_version`: Docker image version built.
- `docker_debug_version`: Docker debug image version built.

### [Build Docker Manifest](./.github/workflows/build-docker-manifest.yaml)

Combines previously built platform-specific images into a single Multi-Architecture Docker Manifest. This allows users to pull a single tag and get the correct image for their hardware.

**Usage:**
```yaml
jobs:
  docker_manifest:
    uses: hoprnet/hopr-workflows/.github/workflows/build-docker-manifest.yaml@build-docker-manifest-v1
    with:
      version_type: release
      docker_image_name: hoprd
      docker_build_version: ${{ needs.build-docker.outputs.docker_build_version }}
      docker_debug_version: ${{ needs.build-docker.outputs.docker_debug_version }}
    secrets:
      gcp_service_account: ${{ secrets.GOOGLE_HOPRASSOCIATION_CREDENTIALS_REGISTRY}}
      docker_hub_username: ${{ secrets.DOCKER_HUB_USERNAME }}
      docker_hub_token: ${{ secrets.DOCKER_HUB_TOKEN }}
```

**Key Features:**
- Creates multi-arch manifests for standard and debug versions.
- Supports handling `latest` tags for specific build types (e.g., PRs).
- Conditionally publishes to Docker Hub for `release` versions.

**Inputs:**
- `version_type` (Required): Determines publishing behavior (e.g., `release` triggers Docker Hub push).
- `docker_image_name` (Required): The name of the image series.
- `docker_build_version` (Required): The version tag to unify.
- `docker_debug_version` (Optional): The debug version tag to unify.
- `docker_gcp_registry` (Optional): Docker registry to push the image to (Default: `europe-west3-docker.pkg.dev/hoprassociation/docker-images`).
- `docker_hub_registry` (Optional): Docker registry to push the image to (Default: `docker.io/hoprnet`).

**Secrets:**
- `gcp_service_account` (Required): Google Cloud Service Account with permissions to upload artifacts.
- `docker_hub_username` (Optional): Docker Hub username (Required for release builds).
- `docker_hub_token` (Optional): Docker Hub token (Required for release builds).

**Outputs:**

- No outputs defined.
