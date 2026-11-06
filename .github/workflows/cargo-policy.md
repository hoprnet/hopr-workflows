# Cargo policy

Fails when any tracked `Cargo.toml` declares a `[patch]` section or a `git` dependency. Protected branches must resolve dependencies from a registry or a versioned in-repository path; patches and git sources pull unreleased code into published crates.

Rejected, in every manifest tracked by git:

- any `[patch]` section, with any source
- a `git` key in `[dependencies]`, `[dev-dependencies]`, `[build-dependencies]`, their `[workspace.*]` and `[target.<cfg>.*]` forms, and the deprecated underscore aliases (`dev_dependencies`, `build_dependencies`)
- a `git` key in the deprecated `[replace]` table (path-only replacements pass)
- a manifest that cannot be parsed

Each violation is printed with its manifest and section or dependency, and as a `::error file=` annotation. Untracked files are ignored.

## Usage

```yaml
jobs:
  cargo-policy:
    name: Cargo policy
    uses: hoprnet/hopr-workflows/.github/workflows/cargo-policy.yaml@<sha> # workflow-cargo-policy-v1.0.0
    permissions:
      contents: read
```

Pin to a commit SHA with the release tag in a trailing comment. Add the job to the caller's `merge-gate` `needs:` list.

## Trust model

The checked manifests come from the caller's checkout. The policy script does not: the job checks out this repository at `job.workflow_sha`, the commit of the called workflow file. A pull request therefore cannot change the check by editing files in its own tree. It can only change the `uses:` pin in the caller workflow, which is visible in review.

## Inputs

| Name             | Required | Default              | Description                                                     |
| ---------------- | -------- | -------------------- | --------------------------------------------------------------- |
| `runner`         | No       | `depot-ubuntu-22.04` | Runner for the job                                              |
| `python_version` | No       | `3.12`               | Python version for the script (3.11 or newer, for `tomllib`)    |

## Secrets

None.

## Permissions

The job declares `contents: read`. The caller job must grant at least that.
