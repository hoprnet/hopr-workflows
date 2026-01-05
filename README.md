# hopr-workflows

GitHub workflows helping HOPR automate tasks via github actions


## Actions

- [Bump Version](./actions/bump-version/README.md): Bumps project version and commit.
- [Download Artifact Registry](./actions/download-artifact-registry/README.md): Downloads artifacts from Google Artifact Registry.
- [Generate Release Notes](./actions/generate-release-notes/README.md): Generate Release notes
- [Multi Architecture Manifest](./actions/multi-arch-manifest/README.md): Publishes a multi-arch docker manifest
- [Publish Rust Docs](./actions/publish-rust-docs/README.md): Publishes rust docs in GitHub Pages
- [Release Version](./actions/release-version/README.md): Creates a GitHub release
- [Set Build Version](./actions/set-build-version/README.md): Updates project version before building
- [Setup GCP](./actions/setup-gcp/README.md): Setup GCP tools and permissions
- [Setup Nix](./actions/setup-nix/README.md): Setup a Nix environment in the runner
- [Setup Node Js](./actions/setup-node-js/README.md): Setup Node Js and Yarn
- [Sign file](./actions/sign-file/README.md): Creates a GPG signature of the file and SHA256
- [Upload Artifact Registry](./actions/upload-artifact-registry/README.md): Upload files into the Google Artifact registry.


## Workflows

- [Build Binaries](./.github/workflows/build-binaries.yaml): Build the binaries for a project
- [Build Docker Image](./.github/workflows/build-docker-image.yaml): Build the docker platform specific image for the project
- [Build Docker Manifest](./.github/workflows/build-docker-manifest.yaml): Build the docker multi platform manifest image for the project
