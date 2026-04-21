# Nix Action

Composite action that consolidates common CI boilerplate into a single step: harden runner, checkout, Nix/Cachix setup (via [setup-nix](../setup-nix/README.md)), and command execution.

## Usage

```yaml
steps:
  - name: Run tests
    uses: hoprnet/hopr-workflows/actions/nix-action@nix-action-v1
    with:
      source_branch: ${{ inputs.source_branch }}
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      command: nix build -L .#my-tests
```

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `command` | Yes | — | Shell command(s) to execute (supports multi-line) |
| `source_branch` | No | `main` | Git branch to checkout |
| `cachix_cache_name` | No | `hoprnet` | Cachix cache name (passed to setup-nix) |
| `cachix_auth_token` | No | `""` | Cachix authentication token (passed to setup-nix) |
| `disable_sudo` | No | `"true"` | Disable sudo in harden-runner |
| `persist_credentials` | No | `"false"` | Persist git credentials after checkout |
