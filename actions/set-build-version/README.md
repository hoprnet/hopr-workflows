# Build version

This action modifies the `Cargo.toml` file to set the `version` attribute based on the parameter `version_type`.
It does not commit the change on the branch, the modification is done only to build the binary with the custom `version`.

Updates the `version` of the project based on the type of build desired.
 - In pull requests commits: `x.y.z+commit.123456`
 - In pull requests merge: `x.y.z+pr.1234`
 - In close release: `x.y.z` . It basically does not modify anything

## Usage
```bash
      - name: Updates build version
        id: version
        uses: hoprnet/hopr-workflows/actions/set-build-version@build-version-v1
        with:
          file: Cargo.toml
          version_type: 'commit'
```

## Requirements

- Requires the repository to use `Cargo.toml` for versioning
- Requires the repository to use Nix environment. Requires the action [Setup Nix](../setup-nix/README.md) to be invoked previously.
- Requires the nix flake to have an application named `generate-lockfile` so it can update the dependences of the `Cargo.lock` file.

## Inputs

- `file`: The filepath to the `Cargo.toml` file
- `version_type`: The type of version the project is about to build. Posible values are : `commit`, `pr` and `release`.

## Outputs

- `current_version`: Current version extracted from file
- `commit_version`: Version with commit hash
- `pr_version`: Version with pull request number
- `release_version`: Release version
- `build_version`: Build version based on version type
- `docker_version`: Docker compatible build version
- `publish_artifact_registry`: Whether to publish the artifact in the Google Artifact registry. Enabled when the `version_type` is `pr` or `release` and when it's `commit` and the PR has the label `publish-binaries` attached.
- `publish_github_release`: Whether to publish the artifact in the GitHub Release. Enabled when the `version_type` is `release`

