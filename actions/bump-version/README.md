# Bump version

This action modifies the `Cargo.toml` file to bump the `version` attribute based on the parameter `release_type`.
It also commits the change on the `${{ github.ref_name}}` branch. If the branch is protected, then it's recommended to add a bypass rule for the `bot` user.

## Usage
```bash
      - name: Bump version
        id: bump_version
        uses: hoprnet/hopr-workflows/actions/bump-version@bump-version-v1
        with:
          file: Cargo.toml
          release_type: patch
```

## Requirements

- Requires the repository to use `Cargo.toml` for versioning
- Requires the repository to use Nix environment. Requires the action [Setup Nix](../setup-nix/README.md) to be invoked previously.
- Requires the nix flake to have an application named `generate-lockfile` so it can update the dependences of the `Cargo.lock` file.

## Inputs

- `file`: The filepath to the `Cargo.toml` file
- `release_type`: The type of release that the project is about to bump to. Possible values are : `rc`, `patch`, `minor` and `major`.

## Outputs

- `current_version`: Current version extracted from file
- `bump_version`: Version bumped
