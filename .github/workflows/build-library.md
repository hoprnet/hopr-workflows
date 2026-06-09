# Build Library

Builds a Rust library for a specific architecture using Nix and publishes it to crates.io. On non-release builds (`version_type != release`) a dry-run is executed to validate the publish without actually uploading. On release builds the crate is published to crates.io with `cargo release publish --execute`.

The workflow assumes the caller repository's default development shell already provides `cargo release`, so the publish step runs through a single `nix develop` invocation with no nested `nix shell`.

## Usage

```yaml
jobs:
  build-library:
    uses: hoprnet/hopr-workflows/.github/workflows/build-library.yaml@build-library-v2
    with:
      source_branch: ${{ github.ref_name }}
      version_type: release
      package_name: my-crate
      architecture: x86_64-linux
      cachix_cache_name: hopr
      runner: depot-ubuntu-22.04-4
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      cargo_registry_token: ${{ secrets.CARGO_REGISTRY_TOKEN }}
```

## Inputs

| Name                | Required | Default                       | Description                                                                              |
| ------------------- | -------- | ----------------------------- | ---------------------------------------------------------------------------------------- |
| `source_branch`     | Yes      | —                             | Source branch to build from                                                              |
| `version_type`      | Yes      | —                             | Versioning strategy: `commit`, `pr`, or `release`. Only `release` publishes to crates.io |
| `package_name`      | Yes      | —                             | Crate name to publish (e.g. `hopr-types`)                                                |
| `architecture`      | Yes      | —                             | Target architecture (e.g. `x86_64-linux`)                                                |
| `cachix_cache_name` | No       | —                             | Cachix cache name                                                                        |
| `nix_path`          | No       | `nixpkgs=channel:nixos-26.05` | Nix path to use                                                                          |
| `build_file`        | No       | `Cargo.toml`                  | File to extract version from                                                             |
| `timeout_minutes`   | No       | `60`                          | Timeout in minutes                                                                       |
| `runner`            | Yes      | —                             | Runner label for the job                                                                 |
| `enabled`           | No       | `true`                        | Whether to run this job                                                                  |

## Secrets

| Name                   | Required | Description                                                    |
| ---------------------- | -------- | -------------------------------------------------------------- |
| `cachix_auth_token`    | Yes      | Auth token for Cachix cache                                    |
| `cargo_registry_token` | No       | crates.io API token. Required when `version_type` is `release` |

## Steps

1. **Harden Runner** — applies step-security hardening (no sudo, egress audit)
2. **Checkout repository** — checks out `source_branch`
3. **Setup Nix** — configures the Nix environment with Cachix
4. **Updates build version** — stamps the version using [set-build-version](../actions/set-build-version/README.md)
5. **Build dry-run library** _(non-release only)_ — runs `cargo release publish --all-features` without `--execute` to validate the package through the caller's default dev shell
6. **Publish library** _(release only)_ — runs `cargo release publish --execute --all-features --no-confirm` through the caller's default dev shell
