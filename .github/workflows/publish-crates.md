# Publish Crates

Publishes a single Rust crate to crates.io using `cargo release` in publish-only mode (no git tags, no git push). A dry-run is the default; set `version_type` to `release` to actually publish.

For workspace repos publishing multiple crates with dependencies between them, use a matrix strategy with `max-parallel: 1` to control publish ordering.

## Usage

```yaml
jobs:
  publish:
    uses: hoprnet/hopr-workflows/.github/workflows/publish-crates.yaml@<ref>
    with:
      source_branch: ${{ github.ref_name }}
      version_type: release
      package: my-crate
      cachix_cache_name: hopr
      runner: self-hosted-hoprnet-bigger
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      cargo_registry_token: ${{ secrets.CARGO_REGISTRY_TOKEN }}
```

### Multi-crate workspace example

```yaml
jobs:
  publish:
    strategy:
      max-parallel: 1
      matrix:
        package:
          - hopr-types
          - hopr-crypto
          - hopr-network
    uses: hoprnet/hopr-workflows/.github/workflows/publish-crates.yaml@<ref>
    with:
      source_branch: ${{ github.ref_name }}
      version_type: release
      package: ${{ matrix.package }}
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      cargo_registry_token: ${{ secrets.CARGO_REGISTRY_TOKEN }}
```

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `source_branch` | Yes | — | Source branch to check out |
| `version_type` | No | `pr` | Versioning strategy: `commit`, `pr`, or `release`. Only `release` publishes to crates.io; others perform a dry-run |
| `package` | Yes | — | Crate name to publish (e.g. `hopr-types`) |
| `cachix_cache_name` | No | — | Cachix cache name |
| `runner` | No | `ubuntu-latest` | Runner label for the job |
| `timeout_minutes` | No | `30` | Timeout in minutes |

## Secrets

| Name | Required | Description |
|------|----------|-------------|
| `cachix_auth_token` | Yes | Auth token for Cachix cache |
| `cargo_registry_token` | No | crates.io API token. Required when `version_type` is `release` |
