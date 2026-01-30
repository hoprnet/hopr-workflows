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
          zulip_email: ${{ secrets.ZULIP_EMAIL }}
          zulip_api_key: ${{ secrets.ZULIP_API_KEY }}
          zulip_channel: "MyChannel"
          zulip_topic: "Releases"
          gcp_service_account: ${{ secrets.GOOGLE_SERVICE_ACCOUNT_GITHUB_ACTIONS }}
          attach_binaries: 'true'
          github_token: "${{ secrets.GH_RUNNER_TOKEN }}"
```

## Requirements

- Requirements defined at [Download Artifact Registry](../download-artifact-registry/README.md) action.
- Requirements defined at [Release Notes](../generate-release-notes/README.md) action.
- Requirements defined at [Bump version](../bump-version/README.md) action.

## Inputs

- `source_branch`: Source branch for release notes
- `file`: The filepath to the `Cargo.toml` file.
- `release_type`: The type of release that the project is about to bump to. Possible values are : `rc`, `patch`, `minor` and `major`.
- `zulip_email`: Email of the user used to send Zulip notifications.
- `zulip_api_key`: Api key of the zulip user.
- `zulip_channel`: Zulip channel for notifications.
- `zulip_topic`: Zulip topic for notifications.
- `gcp_service_account`: GCP Service Account JSON for Artifact Registry access
- `attach_binaries`: Whether to attach binaries from Artifact Registry
- `github_token`: GitHub Token from the Bot with permission to make direct commits into the branch

## Outputs

- `current_version`: Current version released
- `bump_version`: Version bumped
