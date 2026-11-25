# Discover crates

Lists the crates of a Cargo workspace that a release run has to release and bump. It works for virtual workspaces, which have no root `version`.

For each crate that may be published to crates.io (`publish` is unset or includes `crates-io` in `cargo metadata`), the action asks crates.io whether the crate's current version is published. It then checks for a GitHub release of the tag `<crate>-v<version>` (`v<version>` for a root package). This is the same condition `release-version` uses to refuse an existing release.

## Usage

```yaml
- name: Discover crates
  id: crates
  uses: hoprnet/hopr-workflows/actions/discover-crates@discover-crates-v1
```

## Requirements

- Run after the publish step, in a checkout of the release branch.
- Requires the Nix environment ([Setup Nix](../setup-nix/README.md)). `cargo metadata` runs in the default dev shell.

## Inputs

- `package_name`: Limit the result to one crate. Default: all publishable crates. The action fails when no publishable crate has this name.
- `github_token`: Token for the release lookup. Default: `github.token`.

## Outputs

- `releases`: JSON list of `{name, version, manifest, tag_prefix}` for published crates without a GitHub release.
- `bumps`: JSON list of crate names that are published and still at their published version. Crates that already have a release stay in this list, so a rerun after a failed release or bump job still bumps them.

## Wiring

1. Run a matrix over `releases` that calls `release-version` with `file: <manifest>`, `release_tag_prefix: <tag_prefix>`, `source_branch` set to the release branch and `bump_version: 'false'`.
   - Without `source_branch`, `release-version` checks out `main`.
   - Without `bump_version: 'false'`, every matrix job bumps and pushes on its own, and the bump from `bumps` then bumps a second time.
2. Run one bump job after the matrix. Pass `workspace: 'true'` and `packages: ${{ join(fromJSON(needs.build.outputs.bumps), ' ') }}` to [bump-version](../bump-version/README.md).
3. Gate the bump job on the matrix result. The matrix is skipped when `releases` is empty, and a plain `needs` would then skip the bump too. Use:

   ```yaml
   if: >-
     always() && needs.build.result == 'success' &&
     needs.release.result != 'failure' && needs.release.result != 'cancelled' &&
     needs.build.outputs.bumps != '[]'
   ```

   Never bump before every release exists. A bump moves the version, crates.io then reports 404 for the new version, and the release for the old one is never created.

## Failures

The action fails when `package_name` matches no publishable crate, when crates.io or the release lookup returns an unexpected status, and when a manifest's `version =` lines do not read exactly the package version (`version.workspace = true`, dotted dependency tables).

The logic is in `discover-crates.sh`; `test_discover_crates.py` tests it with fake `curl` and `gh`.
