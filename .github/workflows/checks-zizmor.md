# Zizmor

Scans GitHub Actions workflow files for security issues using [zizmor](https://docs.zizmor.sh/) and uploads results as SARIF to the GitHub Security tab. The `security-events: write` permission required for the upload is declared at the job level — no extra permissions are needed from the caller.

## Usage

```yaml
jobs:
  zizmor:
    uses: hoprnet/hopr-workflows/.github/workflows/checks-zizmor.yaml@workflow-checks-zizmor-v1
    permissions:
      contents: read
      security-events: write
    with:
      repo_sha: ${{ github.event.pull_request.head.sha || github.sha }}
      runner: depot-ubuntu-22.04-4
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

## Inputs

| Name                      | Required | Default                                                                    | Description                                                                           |
| ------------------------- | -------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `repo_sha`                | Yes      | —                                                                          | Commit SHA to check out (use `github.event.pull_request.head.sha \|\| github.sha`)    |
| `cachix_cache_name`       | No       | `<repository name>`                                                        | Cachix cache name                                                                     |
| `cachix_extra_pull_names` | No       | —                                                                          | Comma-separated list of additional Cachix caches to pull (substitute) from, read-only |
| `runner`                  | No       | `depot-ubuntu-22.04`                                                       | Runner for the job                                                                    |
| `zizmor_command`          | No       | `nix develop -L .#ci -c bash -c "zizmor --format sarif . > results.sarif"` | Command to run zizmor                                                                 |
| `nix_path`                | No       | `nixpkgs=channel:nixos-26.05`                                              | Nix path to use                                                                       |

## Secrets

| Name                | Required | Description                 |
| ------------------- | -------- | --------------------------- |
| `cachix_auth_token` | No       | Auth token for Cachix cache |

## Pull requests from forks

The analysis runs, but the SARIF upload to the Security tab (needs `security-events: write`) is skipped because the token is read-only. Findings fail the job: the finding count is written to the run summary and `results.sarif` is kept as a run artifact (`zizmor-sarif`). The Security tab check runs on merge queue and push.
