# Discover crates

Lists the crates of a Cargo workspace that a release run has to release and bump. It works for virtual workspaces, which have no root `version`.

For each publishable crate (`publish != []` in `cargo metadata`) the action asks crates.io whether the crate's current version is published, then checks for the tag `<crate>-v<version>` (`v<version>` for a root package).

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

- `package_name`: Limit the result to one crate. Default: all publishable crates.
- `github_token`: Token for the tag lookup. Default: `github.token`.

## Outputs

- `releases`: JSON list of `{name, version, manifest, tag_prefix}` for published crates without a tag. Feed it to a matrix that runs `release-version` with `file: <manifest>`, `release_tag_prefix: <tag_prefix>` and `bump_version: 'false'`. Without that last input every matrix job bumps and pushes on its own, and the bump from `bumps` then bumps a second time.
- `bumps`: JSON list of crate names that are published and still at their published version. A rerun after a failed release or bump job keeps tagged crates in this list. Run the bump job only after all release jobs succeeded (`needs` the release matrix): a bump before the release moves the version, crates.io then reports 404 for it, and that release is never created. Pass it to bump-version as `workspace: 'true'` with `packages: ${{ join(fromJSON(needs.build.outputs.bumps), ' ') }}`.

The action fails when `package_name` matches no publishable crate, when crates.io or the tag lookup returns an unexpected status, and when a manifest's `version =` lines do not read exactly the package version (`version.workspace = true`, dotted dependency tables).

The logic is in `discover-crates.sh`; `test_discover_crates.py` tests it with fake `curl` and `gh`.
