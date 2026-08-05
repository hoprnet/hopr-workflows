# Build Library

Builds a Rust library for a specific architecture and publishes it to crates.io. On non-release builds (`version_type != release`) a dry-run is executed to validate the publish without actually uploading. On release builds the crate is published to crates.io with `cargo release publish --execute`.

Callers can provide a cacheable `build_command`, normally a `nix build` command. It runs after Cachix setup, and Cargo package verification is then disabled with `--no-verify` so the same sources and dependencies are not compiled again outside the Nix store. Without `build_command`, the workflow retains its original behavior and lets Cargo compile while verifying the package.

The workflow assumes the caller repository's default development shell provides `cargo release`, so the publish step runs through a single `nix develop` invocation with no nested `nix shell`.

## Usage

```yaml
jobs:
  build-library:
    uses: hoprnet/hopr-workflows/.github/workflows/build-library.yaml@build-library-v3
    with:
      source_branch: ${{ github.ref_name }}
      version_type: release
      package_name: my-crate
      architecture: x86_64-linux
      cachix_cache_name: hopr
      build_command: nix build -L .#lib-my-crate-x86_64-linux
      runner: depot-ubuntu-22.04-4
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

To verify (or publish) against explicit Rust target triples instead of the runner's host default, supply `targets`. GitHub Actions `workflow_call` inputs have no list type, so use either a space-separated inline string or a YAML block scalar — both work:

```yaml
with:
  targets: "x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu"
```

```yaml
with:
  targets: |
    x86_64-unknown-linux-gnu
    aarch64-unknown-linux-gnu
```

## Inputs

| Name                | Required | Default                       | Description                                                                                                                                                                                         |
| ------------------- | -------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `source_branch`     | Yes      | —                             | Source branch to build from                                                                                                                                                                         |
| `version_type`      | Yes      | —                             | Versioning strategy: `commit`, `pr`, or `release`. Only `release` publishes to crates.io                                                                                                            |
| `package_name`      | No       | —                             | Crate name to publish (e.g. `hopr-types`). When empty, defaults to `--workspace`.                                                                                                                   |
| `architecture`      | Yes      | —                             | Target architecture (e.g. `x86_64-linux`)                                                                                                                                                           |
| `cachix_cache_name` | No       | —                             | Cachix cache name                                                                                                                                                                                   |
| `nix_path`          | No       | `nixpkgs=channel:nixos-26.05` | Nix path to use                                                                                                                                                                                     |
| `build_file`        | No       | `Cargo.toml`                  | File to extract version from                                                                                                                                                                        |
| `build_command`     | No       | `""`                          | Cacheable command that builds the library before publication validation. When set, Cargo runs with `--no-verify` to avoid recompiling.                                                              |
| `timeout_minutes`   | No       | `60`                          | Timeout in minutes                                                                                                                                                                                  |
| `runner`            | Yes      | —                             | Runner label for the job                                                                                                                                                                            |
| `enabled`           | No       | `true`                        | Whether to run this job                                                                                                                                                                             |
| `targets`           | No       | `""`                          | Rust target triples passed as repeated `--target` flags to `cargo release publish`. Accepts a space-separated string or a YAML block scalar. Empty (default) verifies against the host triple only. |

## Secrets

| Name                | Required | Description                 |
| ------------------- | -------- | --------------------------- |
| `cachix_auth_token` | Yes      | Auth token for Cachix cache |

## Steps

1. **Harden Runner** — applies step-security hardening (no sudo, egress audit)
2. **Checkout repository** — checks out `source_branch`
3. **Setup Nix** — configures the Nix environment with Cachix
4. **Build library** _(when `build_command` is set)_ — runs the caller's cacheable build command
5. **Build dry-run library** _(non-release only)_ — validates the package through the caller's default dev shell; adds `--no-verify` when the cacheable build already ran
6. **Publish library** _(release only)_ — publishes through the caller's default dev shell; adds `--no-verify` when the cacheable build already ran
