# hopr-workflows

This repository contains a collection of custom GitHub Actions and Reusable Workflows designed to streamline and automate CI/CD processes, release management, and artifact handling for the HOPR repositories.

## Actions

- [Bump Version](./actions/bump-version/README.md): Bumps project version and commit.
- [Download Artifact Registry](./actions/download-artifact-registry/README.md): Downloads artifacts from Google Artifact Registry.
- [Generate Release Notes](./actions/generate-release-notes/README.md): Generate Release notes
- [Multi Architecture Manifest](./actions/multi-arch-manifest/README.md): Publishes a multi-arch docker manifest
- [Publish Rust Docs](./actions/publish-rust-docs/README.md): Publishes rust docs in GitHub Pages
- [Release Version](./actions/release-version/README.md): Creates a GitHub release
- [Set Build Version](./actions/set-build-version/README.md): Updates project version before building
- [Setup GCP](./actions/setup-gcp/README.md): Setup GCP tools and permissions
- [Nix Action](./actions/nix-action/README.md): All-in-one CI step: harden runner, checkout, Nix setup, and command execution
- [Setup Nix](./actions/setup-nix/README.md): Setup a Nix environment in the runner
- [Setup Node Js](./actions/setup-node-js/README.md): Setup Node Js and Yarn
- [Sign file](./actions/sign-file/README.md): Creates a GPG signature of the file and SHA256
- [Upload Artifact Registry](./actions/upload-artifact-registry/README.md): Upload files into the Google Artifact registry.

## Reusable Workflows

- [Benchmarks](./.github/workflows/benchmarks.md): Builds, runs, and publishes benchmarks to Bencher.dev with Zulip notifications on regressions.
- [Build Binaries](./.github/workflows/build-binaries.md): Compiles binaries for a specific architecture using Nix, with optional signing and upload to Artifact Registry.
- [Build Docker](./.github/workflows/build-docker.md): Builds platform-specific Docker images and their multi-architecture manifest, with vulnerability scanning and optional staging deployment.
- [Build Library](./.github/workflows/build-library.md): Builds a Rust library using Nix and publishes the crate to crates.io (dry-run on non-release builds).
- [Checks](./.github/workflows/checks.md): Runs configurable code-quality checks (pre-commit, lint, deps, audit) via a matrix strategy.
- [Checks Zizmor](./.github/workflows/checks-zizmor.md): Scans GitHub Actions workflow files for security issues using zizmor and uploads SARIF to the GitHub Security tab.
- [Tests](./.github/workflows/tests.md): Runs configurable test suites (unit, integration, nightly), benchmarks, and coverage reports.
