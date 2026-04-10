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
- [Nix Action](./actions/nix-action/README.md): All-in-one CI step: harden runner, checkout, Nix setup, and command execution
- [Setup Nix](./actions/setup-nix/README.md): Setup a Nix environment in the runner
- [Setup Node Js](./actions/setup-node-js/README.md): Setup Node Js and Yarn
- [Sign file](./actions/sign-file/README.md): Creates a GPG signature of the file and SHA256
- [Upload Artifact Registry](./actions/upload-artifact-registry/README.md): Upload files into the Google Artifact registry.

## Reusable Workflows

This repository provides reusable workflows designed to simplify the build and release process for HOPR projects. These workflows can be called from other repositories to standardize binary compilation, Docker image creation, multi-architecture support, and crate publishing.

### [Checks](./.github/workflows/checks.yaml)

Runs configurable code-quality checks (pre-commit, lint, deps, audit) via a matrix strategy. Each check can be individually enabled/disabled and its command overridden.

**Usage:**
```yaml
jobs:
  checks:
    name: Check
    uses: hoprnet/hopr-workflows/.github/workflows/checks.yaml@workflow-checks-v1
    with:
      source_branch: ${{ github.event.pull_request.head.ref || github.ref }}
      runner_small: self-hosted-hoprnet-small
      runner_large: self-hosted-hoprnet-bigger
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

**Inputs:**
- `source_branch` (Required): Source branch to check out.
- `pre_commit` (Optional): Enable pre-commit check (Default: `true`).
- `lint` (Optional): Enable lint check (Default: `true`).
- `deps` (Optional): Enable dependency check (Default: `true`).
- `audit` (Optional): Enable security audit (Default: `true`).
- `pre_commit_command` (Optional): Command for pre-commit (Default: `nix build -L .#pre-commit-check`).
- `lint_command` (Optional): Command for linting (Default: `nix run -L .#check`).
- `deps_command` (Optional): Command for dependency check (Default: `nix develop .#ci -c bash -c "cargo machete && cargo shear"`).
- `audit_command` (Optional): Command for security audit (Default: `nix run .#audit`).
- `runner_small` (Optional): Runner for lightweight checks (Default: `ubuntu-latest`).
- `runner_large` (Optional): Runner for heavy checks (Default: `ubuntu-latest`).

**Secrets:**
- `cachix_auth_token` (Required): Auth token for Cachix cache.

---

### [Tests](./.github/workflows/tests.yaml)

Runs configurable test suites (unit, integration, nightly) and optionally builds benchmarks and generates coverage reports. Tests and benchmarks run concurrently; coverage runs after tests pass. Set `unconditional: true` to run coverage regardless of test results.

**Usage:**
```yaml
jobs:
  tests:
    name: Test
    uses: hoprnet/hopr-workflows/.github/workflows/tests.yaml@workflow-tests-v1
    with:
      source_branch: ${{ github.event.pull_request.head.ref || github.ref }}
      unit_tests: true
      integration_tests: true
      unit_coverage: true
      integration_coverage: true
      runner: self-hosted-hoprnet-bigger
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      codecov_token: ${{ secrets.CODECOV_TOKEN }}
```

**Inputs:**
- `source_branch` (Required): Source branch to check out.
- `unit_tests` (Optional): Enable unit tests (Default: `true`).
- `integration_tests` (Optional): Enable integration tests (Default: `false`).
- `nightly_tests` (Optional): Enable nightly tests (Default: `false`).
- `benchmarks` (Optional): Enable benchmark builds on merge_group (Default: `false`).
- `unit_coverage` (Optional): Enable unit coverage report (Default: `false`).
- `integration_coverage` (Optional): Enable integration coverage report (Default: `false`).
- `unit_test_command` (Optional): Command for unit tests (Default: `nix build -L .#test-unit`).
- `integration_test_command` (Optional): Command for integration tests (Default: `nix build -L .#test-integration`).
- `nightly_test_command` (Optional): Command for nightly tests (Default: `nix build -L .#test-nightly`).
- `benchmark_command` (Optional): Command for benchmarks (Default: `nix build .#bench-build`).
- `unit_coverage_command` (Optional): Command for unit coverage (Default: `nix build -L .#coverage-unit && cp result coverage.lcov`).
- `integration_coverage_command` (Optional): Command for integration coverage (Default: `nix build -L .#coverage-integration && cp result coverage.lcov`).
- `runner` (Optional): Runner for all test jobs (Default: `ubuntu-latest`).
- `test_timeout` (Optional): Timeout in minutes for test jobs (Default: `60`).
- `benchmark_timeout` (Optional): Timeout in minutes for benchmark job (Default: `20`).
- `coverage_timeout` (Optional): Timeout in minutes for coverage jobs (Default: `60`).
- `unconditional` (Optional): When `true`, coverage runs regardless of test results. Use `unit_coverage` and `integration_coverage` to control which types run (Default: `false`).

**Secrets:**
- `cachix_auth_token` (Required): Auth token for Cachix cache.
- `codecov_token` (Optional): Codecov token. Required when `unit_coverage` or `integration_coverage` is enabled.

**Coverage-only usage (e.g. post-merge pipeline):**
```yaml
jobs:
  coverage:
    name: Coverage
    uses: hoprnet/hopr-workflows/.github/workflows/tests.yaml@workflow-tests-v1
    with:
      source_branch: ${{ github.ref_name }}
      unit_tests: false
      integration_tests: false
      unconditional: true
      unit_coverage: true
      runner: self-hosted-hoprnet-bigger
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      codecov_token: ${{ secrets.CODECOV_TOKEN }}
```

---

### [Zizmor](./.github/workflows/checks-zizmor.yaml)

Scans GitHub Actions workflow files for security issues using [zizmor](https://docs.zizmor.sh/) and uploads results as SARIF to the GitHub Security tab.

**Usage:**
```yaml
jobs:
  zizmor:
    uses: hoprnet/hopr-workflows/.github/workflows/checks-zizmor.yaml@workflow-checks-zizmor-v1
    permissions:
      contents: read
      security-events: write
    with:
      source_branch: ${{ github.event.pull_request.head.ref || github.ref }}
      runner: self-hosted-hoprnet-bigger
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

**Inputs:**
- `source_branch` (Required): Source branch to check out.
- `runner` (Optional): Runner for the job (Default: `ubuntu-latest`).
- `zizmor_command` (Optional): Command to run zizmor (Default: `nix develop -L .#ci -c bash -c "zizmor --format sarif . > results.sarif"`).

**Secrets:**
- `cachix_auth_token` (Required): Auth token for Cachix cache.

---

### [Build Binaries](./.github/workflows/build-binaries.yaml)

Compiles binaries for a specific architecture using Nix. It handles version naming, signing and upload files to artifact registry.

**Usage:**
```yaml
jobs:
  build:
    uses: hoprnet/hopr-workflows/.github/workflows/build-binaries.yaml@build-binaries-v2
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
- `binary` (Required): The name of the binary to output.
- `gcp_region`: GCP region for Artifact Registry.
- `gcp_repository`: GCP Artifact Registry repository name.
- `timeout_minutes` (Optional): Timeout for the job in minutes (Default: `60`).
- `runner` (Required): The runner label to use for the job.

**Secrets:**
- `gcp_service_account` (Required): Google Cloud Service Account with permissions to upload artifacts.
- `cachix_auth_token` (Required): Auth token for Cachix cache.
- `gpg_private_key` (Required): GPG Key to sign the artifacts.

**Outputs:**

- No outputs defined.

### [Build Docker](./.github/workflows/build-docker.yaml)

Constructs a platform-specific Docker image for the project and its multi-architecture manifest.

**Usage:**
```yaml
jobs:
  build-docker:
    name: Docker
    uses: hoprnet/hopr-workflows/.github/workflows/build-docker.yaml@build-docker-v1
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
            "build_command": "nix run -L .#docker-blokli-x86_64-linux",
            "smoke_test_command": "nix develop -c just smoke-test"
          }
        ]
      cachix_cache_name: "blokli"
      build_file: "bloklid/Cargo.toml"
      docker_image_name: "bloklid"
      docker_image_format: skopeo
      deployment_namespace: blokli
      deployment_label_selector: app.kubernetes.io/name=blokli
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
- `build_matrix`: It's a JSON array containing an object with the parameters for each matrix parallel execution.
- `cachix_cache_name` (Required): The name of the Cachix cache to use.
- `build_file` (Optional): File to extract version from (Default: `Cargo.toml`).
- `docker_image_name` (Required): The name of the image.
- `docker_image_format`: (Optional): Type of format generated for the docker image: `docker` or `skopeo` (Default: `docker`).
- `docker_gcp_registry` (Optional): Docker registry to push the image to (Default: `europe-west3-docker.pkg.dev/hoprassociation/docker-images`).
- `docker_hub_registry` (Optional): Docker registry to push the image to (Default: `docker.io/hoprnet`).
- `timeout_minutes` (Optional): Timeout for the job in minutes (Default: `60`).
- `runner` (Optional): Runner to use for the job (Default: `self-hosted-hoprnet-bigger`).
- `deployment_namespace` (Optional): Kubernetes namespace for the deployment to restart in staging.
- `deployment_label_selector` (Optional): Kubernetes label selector for the deployment to restart in staging.
- `fail_on_scan_vulnerabilities`: Whether to fail the build if vulnerabilities are found during the scan (Default: `true`)

**Secrets:**
- `gcp_service_account` (Required): Google Cloud Service Account with permissions to upload artifacts.
- `cachix_auth_token` (Required): Auth token for Cachix cache.
- `docker_hub_username` (Optional): Docker Hub username (Required for release builds).
- `docker_hub_token` (Optional): Docker Hub token (Required for release builds).

**Outputs:**
- `docker_build_version`: Docker image version built.
- `docker_debug_version`: Docker debug image version built.




### [Build Library](./.github/workflows/build-library.yaml)

Compiles a library for a specific architecture using Nix. Unlike the binary workflow, it does not sign or upload artifacts — it only runs the build command.

**Usage:**
```yaml
jobs:
  build-library:
    uses: hoprnet/hopr-workflows/.github/workflows/build-library.yaml@build-library-v1
    with:
      source_branch: ${{ github.ref_name }}
      architecture: x86_64-linux
      cachix_cache_name: hopr
      build_command: nix build .#my-library-x86_64-linux
      runner: self-hosted-hoprnet-bigger
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

**Inputs:**
- `source_branch` (Required): Source branch to build the library from.
- `architecture` (Required): The target architecture (e.g., `x86_64-linux`).
- `cachix_cache_name` (Required): The name of the Cachix cache to use.
- `build_file` (Optional): File to extract version from (Default: `Cargo.toml`).
- `build_command` (Required): The command to execute the build.
- `timeout_minutes` (Optional): Timeout for the job in minutes (Default: `60`).
- `runner` (Required): The runner label to use for the job.

**Secrets:**
- `cachix_auth_token` (Required): Auth token for Cachix cache.

**Outputs:**

- No outputs defined.
