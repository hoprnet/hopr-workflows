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

| Name                      | Required | Default                       | Description                                                                                                                                                                                         |
| ------------------------- | -------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `source_branch`           | Yes      | —                             | Source branch to build from                                                                                                                                                                         |
| `version_type`            | Yes      | —                             | Versioning strategy: `commit`, `pr`, or `release`. Only `release` publishes to crates.io                                                                                                            |
| `package_name`            | No       | —                             | Crate name to publish (e.g. `hopr-types`). When empty, defaults to `--workspace`.                                                                                                                   |
| `architecture`            | Yes      | —                             | Target architecture (e.g. `x86_64-linux`)                                                                                                                                                           |
| `cachix_cache_name`       | No       | —                             | Cachix cache name                                                                                                                                                                                   |
| `cachix_extra_pull_names` | No       | —                             | Comma-separated list of additional Cachix caches to pull (substitute) from, read-only                                                                                                               |
| `nix_path`                | No       | `nixpkgs=channel:nixos-26.05` | Nix path to use                                                                                                                                                                                     |
| `build_file`              | No       | `Cargo.toml`                  | File to extract version from                                                                                                                                                                        |
| `build_command`           | No       | `""`                          | Cacheable command that builds the library before publication validation. When set, Cargo runs with `--no-verify` to avoid recompiling.                                                              |
| `timeout_minutes`         | No       | `60`                          | Timeout in minutes                                                                                                                                                                                  |
| `runner`                  | Yes      | —                             | Runner label for the job                                                                                                                                                                            |
| `enabled`                 | No       | `true`                        | Whether to run this job                                                                                                                                                                             |
| `targets`                 | No       | `""`                          | Rust target triples passed as repeated `--target` flags to `cargo release publish`. Accepts a space-separated string or a YAML block scalar. Empty (default) verifies against the host triple only. |
| `github_release`          | No       | `false`                       | On release builds, create a GitHub release per crate this run published and bump those crates afterwards. Needs the `github_app_private_key` secret. See [Releasing crates](#releasing-crates).     |
| `release_type`            | No       | `patch`                       | `cargo release version` level for the bump: `major`, `minor`, `patch` or `rc`. `patch` on an `-rc.N` version drops the suffix.                                                                      |
| `bump_version`            | No       | `true`                        | Commit the version bump of the released crates after the releases exist                                                                                                                             |
| `zulip_channel`           | No       | —                             | Zulip channel for release notifications                                                                                                                                                             |
| `zulip_topic`             | No       | —                             | Zulip topic for release notifications                                                                                                                                                               |

## Secrets

| Name                           | Required              | Description                                                                                    |
| ------------------------------ | --------------------- | ---------------------------------------------------------------------------------------------- |
| `cachix_auth_token`            | Yes                   | Auth token for Cachix cache                                                                    |
| `github_app_private_key`       | With `github_release` | Private key of the `hoprnet-ci` GitHub App. It creates the releases and pushes the bump commit |
| `zulip_api_key`, `zulip_email` | No                    | Zulip credentials for release notifications                                                    |

## Steps

1. **Harden Runner** — applies step-security hardening (no sudo, egress audit)
2. **Checkout repository** — checks out `source_branch`
3. **Setup Nix** — configures the Nix environment with Cachix
4. **Build library** _(when `build_command` is set)_ — runs the caller's cacheable build command
5. **Build dry-run library** _(non-release only)_ — validates the package through the caller's default dev shell; adds `--no-verify` when the cacheable build already ran
6. **Publish library** _(release only)_ — publishes through the caller's default dev shell; adds `--no-verify` when the cacheable build already ran
7. **Discover released crates** _(release + `github_release` only)_ — lists crates that still need a GitHub release; see [Releasing crates](#releasing-crates)

## Releasing crates

With `version_type: release` and `github_release: true` the workflow replaces a separate `release-version` job. It works for single crates and for monorepos whose workspace root has no `version`.

1. **Discover released crates** — after publishing, lists the publishable workspace crates (`publish != []` in `cargo metadata`) that are on crates.io and have no tag yet. The tag is `<crate>-v<version>`, or `v<version>` for a root package.
2. **Release** _(one job per crate)_ — runs [release-version](../../actions/release-version/README.md) with `file: <crate manifest>` and `bump_version: false`. The first run in a repository creates a release for every crate that has no tag. Crates with `version.workspace = true` are not supported: discovery fails because `release-version` needs a literal `version` line in the manifest.
3. **Bump released crates** — runs `cargo release version <release_type>` for the released crates only and pushes one commit to `source_branch`, so the next pull request sees unpublished versions. The commit uses the GitHub App token, which bypasses the default branch ruleset. If a release job fails, no bump happens. Rerun the workflow: publishing skips crates already on crates.io and discovery finds the untagged ones.
