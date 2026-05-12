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
      source_branch: ${{ github.event.pull_request.head.ref || github.ref }}
      runner: depot-ubuntu-22.04-4
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

## Inputs

| Name             | Required | Default                                                                    | Description                |
| ---------------- | -------- | -------------------------------------------------------------------------- | -------------------------- |
| `source_branch`  | Yes      | —                                                                          | Source branch to check out |
| `runner`         | No       | `depot-ubuntu-22.04`                                                       | Runner for the job         |
| `zizmor_command` | No       | `nix develop -L .#ci -c bash -c "zizmor --format sarif . > results.sarif"` | Command to run zizmor      |

## Secrets

| Name                | Required | Description                 |
| ------------------- | -------- | --------------------------- |
| `cachix_auth_token` | Yes      | Auth token for Cachix cache |
