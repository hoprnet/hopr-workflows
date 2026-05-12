# Benchmarks

Builds, runs, and publishes benchmarks to [Bencher.dev](https://bencher.dev), with integrated Zulip notifications on performance regressions or failures. Supports both PR and merge/push event contexts.

## Jobs

| Job                | Condition                                                      |
| ------------------ | -------------------------------------------------------------- |
| `build-benchmarks` | When `should_build` is `true`                                  |
| `run-benchmarks`   | When `should_run` is `true` and build succeeded or was skipped |

## Usage

```yaml
jobs:
  benchmarks:
    name: Benchmarks
    permissions:
      contents: read
      checks: write
      pull-requests: write
    uses: hoprnet/hopr-workflows/.github/workflows/benchmarks.yaml@<commit-hash>
    with:
      source_branch: ${{ github.event.pull_request.head.ref || github.ref_name }}
      runner: depot-ubuntu-22.04-4
      bencher_project: ${{ github.event.repository.name }}
      should_build: true
      should_run: true
      build_command: "nix build -L .#bench-build"
      run_command: "nix run .#bench-run"
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      bencher_api_token: ${{ secrets.BENCHER_API_TOKEN }}
      ZULIP_API_KEY: ${{ secrets.ZULIP_API_KEY }}
      ZULIP_EMAIL: ${{ secrets.ZULIP_EMAIL }}
```

## Inputs

| Name              | Required | Default                 | Description                              |
| ----------------- | -------- | ----------------------- | ---------------------------------------- |
| `source_branch`   | Yes      | —                       | Source branch to check out               |
| `runner`          | Yes      | —                       | Runner label for both jobs               |
| `bencher_project` | Yes      | —                       | Bencher.dev project name                 |
| `should_build`    | Yes      | —                       | Whether to build the benchmarks          |
| `should_run`      | Yes      | —                       | Whether to run benchmarks after building |
| `build_command`   | Yes      | —                       | Command to build the benchmarks          |
| `run_command`     | Yes      | —                       | Command to run the benchmarks            |
| `zulip_stream`    | No       | `HOPRd`                 | Zulip stream for notifications           |
| `zulip_topic`     | No       | `Benchmark regressions` | Zulip topic for notifications            |

## Secrets

| Name                | Required | Description                             |
| ------------------- | -------- | --------------------------------------- |
| `cachix_auth_token` | Yes      | Auth token for Cachix cache             |
| `bencher_api_token` | No       | Bencher.dev API token                   |
| `ZULIP_API_KEY`     | No       | Zulip API key for failure notifications |
| `ZULIP_EMAIL`       | No       | Zulip email for failure notifications   |

## Notifications

On failure, a Zulip message is sent to `zulip_stream` / `zulip_topic` with a link to the Bencher run (PR context) or Bencher report (merge/push context). Notifications are skipped when `ZULIP_API_KEY` or `ZULIP_EMAIL` are not set.
