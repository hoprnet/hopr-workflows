# Bump version

This action modifies the `Cargo.toml` file to bump the `version` attribute based on the parameter `release_type`.
It also commits the change on the `${{ github.ref_name}}` branch. If the branch is protected, then it's recommended to add a bypass rule for the `bot` user.
Repository-local Git hooks still run for the automated version-bump commit when configured. A missing `.pre-commit-config.yaml` does not block the commit or push.

## Usage

```bash
      - name: Bump version
        id: bump_version
        uses: hoprnet/hopr-workflows/actions/bump-version@bump-version-v2
        with:
          file: Cargo.toml
          release_type: patch
          github_token: ${{ secrets.GH_RUNNER_TOKEN }}
```

## Requirements

- Requires the repository to use `Cargo.toml` for versioning
- Requires the repository to use Nix environment. Requires the action [Setup Nix](../setup-nix/README.md) to be invoked previously.
- Workspace mode needs `cargo-release` in the default dev shell
- Requires the nix flake to have an application named `generate-lockfile` so it can update the dependences of the `Cargo.lock` file.

## Inputs

- `file`: The filepath to the `Cargo.toml` file
- `release_type`: The type of release that the project is about to bump to. Possible values are : `rc`, `patch`, `minor` and `major`.
- `github_token`: The github token used to bump the version
- `workspace`: Optional, default `false`. `true` bumps Cargo workspace crates with `cargo release version <release_type> --package <crate>...` instead of editing `file`. An empty `packages` then bumps nothing and pushes no commit; it never falls back to `file`.
- `packages`: Workspace mode only. Crates to bump, separated by whitespace or newlines. Also updates dependents' version requirements and `Cargo.lock`. Only `Cargo.lock` and `Cargo.toml` files enter the commit.
- `branch`: Optional. Branch the bump commit is pushed to. Default: `github.ref_name`.

## Outputs

- `current_version`: Current version extracted from file
- `bump_version`: Version bumped

## Rust workspace mode

```yaml
- name: Bump released crates
  uses: hoprnet/hopr-workflows/actions/bump-version@bump-version-v2
  with:
    workspace: "true"
    packages: |
      my-crate-a
      my-crate-b
    release_type: patch
    github_token: ${{ steps.bot-token.outputs.token }}
```

In workspace mode the outputs `current_version` and `bump_version` are empty. `release_type: rc` follows cargo-release: `0.7.0` becomes `0.7.1-rc.1`, whereas the single-file mode gives `0.8.0-rc.1`. `patch` on `0.7.1-rc.1` gives `0.7.1`.

Run the bump only after every release job succeeded. A crate is no longer found by crates.io-based discovery once its version moved, so bumping before its release exists loses that release.

The logic is in `bump-rust-packages.sh`. Its functions (`validate_release_type`, `parse_packages`, `changed_files`) are tested by `test_bump_rust_packages.py`, which runs in `nix flake check`.
