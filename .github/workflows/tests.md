# Tests

Runs configurable test suites (unit, integration, nightly), benchmarks, and coverage reports as individual conditional jobs. Each coverage job depends on its corresponding test — it runs when the test passes or when the test is disabled (skipped). Coverage is gated to non-draft PRs, push, and merge_group events.

## Usage

```yaml
jobs:
  tests:
    name: Test
    uses: hoprnet/hopr-workflows/.github/workflows/tests.yaml@workflow-tests-v4
    with:
      source_branch: ${{ github.event.pull_request.head.ref || github.ref }}
      enable_unit_tests: true
      enable_integration_tests: true
      enable_unit_coverage: true
      enable_integration_coverage: true
      runner_unit: depot-ubuntu-24.04-16
      runner_integration: depot-ubuntu-24.04-8
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      codecov_token: ${{ secrets.CODECOV_TOKEN }}
```

### Coverage-only usage (e.g. post-merge pipeline)

```yaml
jobs:
  coverage:
    name: Coverage
    uses: hoprnet/hopr-workflows/.github/workflows/tests.yaml@workflow-tests-v4
    with:
      source_branch: ${{ github.ref_name }}
      enable_unit_tests: false
      enable_integration_tests: false
      enable_unit_coverage: true
      enable_integration_coverage: true
      runner_unit: depot-ubuntu-24.04-16
      runner_integration: depot-ubuntu-24.04-8
    secrets:
      cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
      codecov_token: ${{ secrets.CODECOV_TOKEN }}
```

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `source_branch` | Yes | — | Source branch to check out |
| `enable_unit_tests` | No | `true` | Enable unit tests |
| `enable_integration_tests` | No | `false` | Enable integration tests |
| `enable_nightly_tests` | No | `false` | Enable nightly tests |
| `enable_benchmarks` | No | `false` | Enable benchmarks |
| `enable_unit_coverage` | No | `false` | Enable unit coverage report |
| `enable_integration_coverage` | No | `false` | Enable integration coverage report |
| `unit_test_command` | No | `nix build -L .#test-unit` | Command for unit tests |
| `integration_test_command` | No | `nix build -L .#test-integration` | Command for integration tests |
| `nightly_test_command` | No | `nix build -L .#test-nightly` | Command for nightly tests |
| `benchmark_command` | No | `nix build .#bench-build` | Command for benchmarks |
| `unit_coverage_command` | No | `nix run .#coverage-unit` | Command for unit coverage |
| `integration_coverage_command` | No | `nix run .#coverage-integration` | Command for integration coverage |
| `runner_unit` | No | `ubuntu-latest` | Runner for unit tests, nightly tests, benchmarks, and unit coverage |
| `runner_integration` | No | `""` | Runner for integration tests and coverage. Falls back to `runner_unit` if empty |
| `test_timeout` | No | `60` | Timeout in minutes for test jobs |
| `benchmark_timeout` | No | `20` | Timeout in minutes for benchmark job |
| `coverage_timeout` | No | `60` | Timeout in minutes for coverage jobs |

## Secrets

| Name | Required | Description |
|------|----------|-------------|
| `cachix_auth_token` | Yes | Auth token for Cachix cache |
| `codecov_token` | No | Codecov token. Required when `enable_unit_coverage` or `enable_integration_coverage` is enabled |
