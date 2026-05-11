# Checks

Runs configurable code-quality checks (pre-commit, lint, deps, audit) via a matrix strategy. Each check can be individually enabled/disabled and its command overridden. All checks run in parallel with `fail-fast: false`.

## Usage

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

## Inputs

| Name                 | Required | Default                                                      | Description                                 |
| -------------------- | -------- | ------------------------------------------------------------ | ------------------------------------------- |
| `source_branch`      | Yes      | —                                                            | Source branch to check out                  |
| `pre_commit`         | No       | `true`                                                       | Enable pre-commit check                     |
| `lint`               | No       | `true`                                                       | Enable lint check                           |
| `deps`               | No       | `true`                                                       | Enable dependency check                     |
| `audit`              | No       | `true`                                                       | Enable security audit                       |
| `pre_commit_command` | No       | `nix build -L .#pre-commit-check`                            | Command for pre-commit                      |
| `lint_command`       | No       | `nix run -L .#check`                                         | Command for linting                         |
| `deps_command`       | No       | `nix develop .#ci -c bash -c "cargo machete && cargo shear"` | Command for dependency check                |
| `audit_command`      | No       | `nix run .#audit`                                            | Command for security audit                  |
| `runner_small`       | No       | `ubuntu-latest`                                              | Runner for lightweight checks (pre-commit)  |
| `runner_large`       | No       | `ubuntu-latest`                                              | Runner for heavy checks (lint, deps, audit) |
| `disable_sudo`       | No       | `true`                                                       | Disable sudo in harden-runner               |

## Secrets

| Name                | Required | Description                 |
| ------------------- | -------- | --------------------------- |
| `cachix_auth_token` | Yes      | Auth token for Cachix cache |

## Job matrix

| Check      | Runner         | Timeout |
| ---------- | -------------- | ------- |
| Pre-commit | `runner_small` | 15 min  |
| Lint       | `runner_large` | 30 min  |
| Deps       | `runner_large` | 10 min  |
| Audit      | `runner_large` | 15 min  |
