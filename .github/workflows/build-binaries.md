# Build Binaries

Compiles binaries for a specific architecture using Nix. Handles version stamping, optional signing (GPG on Linux, Apple certificate on macOS), and upload to Google Artifact Registry for release builds.

## Jobs

| Job     | Condition                                                                                  |
| ------- | ------------------------------------------------------------------------------------------ |
| `build` | Always (when `enabled`)                                                                    |
| `sign`  | When signing keys are available (`gpg_private_key` on Linux, `apple_certificate` on macOS) |

The `sign` job also uploads the binary (and signature/checksum) to Google Artifact Registry when `version_type` is `release`.

## Usage

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
      runner: depot-ubuntu-22.04-4
    secrets:
      gcp_service_account: ${{ secrets.GOOGLE_HOPRASSOCIATION_CREDENTIALS_REGISTRY }}
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      gpg_private_key: ${{ secrets.GPG_HOPRNET_PRIVATE_KEY }}
```

## Inputs

| Name                  | Required | Default                       | Description                                                           |
| --------------------- | -------- | ----------------------------- | --------------------------------------------------------------------- |
| `source_branch`       | Yes      | —                             | Source branch to build from                                           |
| `version_type`        | Yes      | —                             | Versioning strategy: `commit`, `pr`, or `release`                     |
| `architecture`        | Yes      | —                             | Target architecture (e.g. `x86_64-linux`, `aarch64-darwin`)           |
| `cachix_cache_name`   | No       | —                             | Cachix cache name                                                     |
| `nix_path`            | No       | `nixpkgs=channel:nixos-26.05` | Nix path to use                                                       |
| `build_file`          | No       | `Cargo.toml`                  | File to extract version from                                          |
| `build_command`       | Yes      | —                             | Command to build the binary. Output expected in `./result/bin/`       |
| `build_debug_command` | No       | —                             | Command to build the debug binary. Output expected in `./result/bin/` |
| `binary`              | Yes      | —                             | Binary name used for artifact naming                                  |
| `gcp_region`          | No       | `europe-west3`                | GCP region for Artifact Registry                                      |
| `gcp_repository`      | No       | `rust-binaries`               | GCP Artifact Registry repository name                                 |
| `timeout_minutes`     | No       | `60`                          | Timeout in minutes                                                    |
| `runner`              | Yes      | —                             | Runner label for the job                                              |
| `enabled`             | No       | `true`                        | Whether to run this job                                               |

## Secrets

| Name                                    | Required | Description                                                       |
| --------------------------------------- | -------- | ----------------------------------------------------------------- |
| `cachix_auth_token`                     | Yes      | Auth token for Cachix cache                                       |
| `gcp_service_account`                   | No       | GCP service account JSON with Artifact Registry write permissions |
| `gcp_workload_identity_provider`        | No       | Workload Identity provider for GCP authentication                 |
| `gcp_workload_identity_service_account` | No       | Service account for Workload Identity                             |
| `gpg_private_key`                       | No       | GPG private key to sign Linux binaries                            |
| `gpg_private_key_password`              | No       | GPG private key password                                          |
| `apple_certificate`                     | No       | Apple developer certificate (p12, base64) for macOS signing       |
| `apple_certificate_password`            | No       | Apple developer certificate password                              |

## Outputs

| Name                        | Description                                           |
| --------------------------- | ----------------------------------------------------- |
| `publish_artifact_registry` | Whether the binary was published to Artifact Registry |
| `build_version`             | Version string used in the build                      |
| `enable_sign`               | Whether signing was performed                         |
