# Nix Action

Composite action that consolidates common CI boilerplate into a single step: harden runner, checkout, optional Nix install (via [setup-nix](../setup-nix/README.md)), optional Cachix setup, and command execution.

## Usage

```yaml
steps:
  - name: Run tests
    uses: hoprnet/hopr-workflows/actions/nix-action@nix-action-v1
    with:
      source_branch: ${{ inputs.source_branch }}
      use_cachix: "true"
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      github_access_token: ${{ secrets.GITHUB_TOKEN }}
      command: nix build -L .#my-tests
```

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `command` | Yes | — | Shell command(s) to execute (supports multi-line) |
| `source_branch` | No | `main` | Git branch to checkout |
| `install_nix` | No | `"true"` | Whether to install Nix via `setup-nix` |
| `use_cachix` | No | `"false"` | Whether to set up Cachix |
| `cachix_cache_name` | No | `hoprnet` | Cachix cache name |
| `cachix_auth_token` | No | `""` | Cachix authentication token |
| `github_access_token` | No | `""` | GitHub token for Nix install |
| `disable_sudo` | No | `"true"` | Disable sudo in harden-runner |
| `persist_credentials` | No | `"false"` | Persist git credentials after checkout |
