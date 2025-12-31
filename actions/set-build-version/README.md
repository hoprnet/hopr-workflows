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
- `architecture`: Target architecture for the docker image

## Outputs

- `current_version`: Current version extracted from file.
- `commit_version`: Version with commit hash. Example: `1.2.3+commit.9a4f81a`.
- `debug_version`: Debug version with commit hash. Example: `1.2.3+debug.9a4f81a`.
- `pr_version`: Version with pull request number. Example: `1.2.3+commit.9a4f81a`.
- `release_version`: Release version. Example: `1.2.3`.
- `build_version`: Contains the value of output `commit_version`, `pr_version` or `release_version` depending on the `version_type` provided.
- `docker_build_version`: Docker compatible build version. The character `+` is replaced by `-`. Platform agnostic tag. Example: `1.2.3-commit.9a4f81a`.
- `docker_build_version_platform`: Docker compatible build version. The character `+` is replaced by `-`. Platform specific tag. Example: `1.2.3-commit.9a4f81a-linux-amd64`.
- `docker_debug_version_platform`: Docker compatible debug version. The character `+` is replaced by `-`. Platform specific tag. Example: `1.2.3-debug.9a4f81a-linux-amd64`.
- `docker_platform`: Docker platform based on architecture. Posible values: `linux-arm64` or `linux-amd64`.
- `publish_artifact_registry`: Whether to publish the artifact in the Google Artifact registry. Enabled when the `version_type` is `pr` or `release` and when it's `commit` and the PR has the label `publish-binaries` attached.
- `publish_github_release`: Whether to publish the artifact in the GitHub Release. Enabled when the `version_type` is `release`.
- `build_flavor_debug`: Whether the build flavor debug needs to be built. Enabled when the label `build-flavor-debug` is attached to the PR and the `version_type` is `commit`.
