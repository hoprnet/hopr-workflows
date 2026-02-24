# Release Github version

This action performs the following steps:
- Generating the release notes
- Download the release binaries from Google Artifact registry
- Creates a github release
- Bumps the base branch to the next `release_type`.
- Sends a notification in Zulip

## Usage

```bash
      - name: Release version
        uses: hoprnet/hopr-workflows/actions/release-version@release-version-v1
        with:
          source_branch: main
          file: Cargo.toml
          release_type: patch
          package_name: my-package
          cachix_cache_name: my-repo
          cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
          zulip_email: ${{ secrets.ZULIP_EMAIL }}
          zulip_api_key: ${{ secrets.ZULIP_API_KEY }}
          zulip_channel: "MyChannel"
          zulip_topic: "Releases"
          gcp_service_account: ${{ secrets.GOOGLE_SERVICE_ACCOUNT_GITHUB_ACTIONS }}
          github_token: "${{ secrets.GH_RUNNER_TOKEN }}"
```

## Requirements

- Requirements defined at [Download Artifact Registry](../download-artifact-registry/README.md) action.
- Requirements defined at [Release Notes](../generate-release-notes/README.md) action.
- Requirements defined at [Bump version](../bump-version/README.md) action.

## Inputs

- `source_branch`: Source branch for release notes
- `file`: The filepath to the version file (e.g. `Cargo.toml` or `package.json`).
- `release_type`: The type of release that the project is about to bump to. Possible values are : `rc`, `patch`, `minor` and `major`.
- `package_name`: Package name from Google Artifact Registry to download binaries from and publish in the release.
- `cachix_cache_name` (Required): The name of the Cachix cache to use.
- `cachix_auth_token` (Required): Auth token for Cachix cache.
- `zulip_email`: Email of the user used to send Zulip notifications.
- `zulip_api_key`: Api key of the zulip user.
- `zulip_channel`: Zulip channel for notifications.
- `zulip_topic`: Zulip topic for notifications.
- `gcp_service_account`: GCP Service Account JSON for Artifact Registry access
- `github_token`: GitHub Token from the Bot with permission to make direct commits into the branch

## Outputs

- `current_version`: Current version released
- `bump_version`: Version bumped
