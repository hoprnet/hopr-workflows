# Release Github version

This action performs the following steps:
- Generating the release notes
- Download the release binaries from Google Artifact registry
- Creates a github release
- Bumps the base branch to the next `release_type`.
- Sends a notification in Zulip

## Release Process

The release process follows a two-branch model: `main` for active development and `release/<MAJOR>.<MINOR>` for testing and maintenance.

```
(branch: main )
  │
  o  Cargo.toml = 1.0.0-rc.1
  ✔  PR merged [latest, latest-main]
  ✔  PR merged [latest, latest-main]
  ✔  Close Release (Version type after release: 'rc') [release-main, 1.0.0-rc.1]
  |  Bump commit 1.0.0-rc.2 [latest, latest-main]
  ✔  PR merged [latest, latest-main]
  ✔  PR merged [latest, latest-main]
  ✔  Close Release (Version type after release: 'rc') [release-main, 1.0.0-rc.2]
  |  Bump commit 1.0.0-rc.3 [latest, latest-main]
  ✔  PR merged [latest, latest-main]
  ✔  PR merged [latest, latest-main]
  ✔  Close Release (Version type after release: 'patch') [release-main, 1.0.0-rc.3]
  |  Bump commit 1.0.0 [latest, latest-main]
  ✔  PR merged [latest, latest-main]
  ✔  PR merged [latest, latest-main]
  ✔  Close Release (Version type after release: 'rc') [release-main, 1.0.0]
  |  Bump commit 1.1.0-rc.1 [latest, latest-main]
  ⑂  Promote Release from tag_name '1.0.0' ─────────────────────────────────────────── (branch: release/1.0) [latest-testing, release-testing]
  |                                                                                  │  Bump commit 1.0.1 [latest-testing]
  ✔  PR merged [latest, latest-main]                                                 |
  │                                                                                  ✔  PR merged [latest-testing]
  │                                                                                  ✔  PR merged [latest-testing]
  ✔  PR merged [latest, latest-main]                                                 |
  │                                                                                  ✔  Close Release (Version type after release: 'patch') [latest-testing, release-testing, tag: 1.0.1]
  |                                                                                  │  Bump commit 1.0.2 [latest-testing]
  │                                                                                  ✔  PR merged [latest-testing]
  │                                                                                  ✔  PR merged [latest-testing]
  ✔  PR merged [latest, latest-main]                                                 |
  ✔  Close Release (Version type after release: 'rc') [release-main, 1.1.0-rc.1]     |
  |  Bump commit 1.1.0-rc.2 [latest, latest-main]                                    |
  │                                                                                  ✔  PR merged [latest-testing]
  │                                                                                  ✔  Close Release (Version type after release: 'patch') [latest-testing, release-testing, tag: 1.0.2]
  |                                                                                  │  Bump commit 1.0.3 [latest-testing]
  ✔  PR merged [latest, latest-main]                                                 |
  ✔  PR merged [latest, latest-main]                                                 |
  ✔  Close Release (Version type after release: 'patch') [release-main, 1.1.0-rc.2]  |
  |  Bump commit 1.1.0 [latest, latest-main]                                         |
  ✔  PR merged [latest, latest-main]                                                 |
  ✔  PR merged [latest, latest-main]                                                 |
  ✔  Close Release (Version type after release: 'rc') [release-main, 1.1.0]          |
  |  Bump commit 1.2.0-rc.1 [latest, latest-main]                                    |
  ⑂  Promote Release from tag_name '1.1.0' ─────────────────────────────────────────── (branch: release/1.1) [latest-testing, release-testing]
  |                                                                                  │  Bump commit 1.1.1 [latest-testing]
  ✔  PR merged [latest, latest-main]                                                 |
  │                                                                                  ✔  PR merged [latest-testing]
  │                                                                                  ✔  PR merged [latest-testing]
  ✔  PR merged [latest, latest-main]                                                 |
  │                                                                                  ✔  Close Release (Version type after release: 'patch') [latest-testing, release-testing, tag: 1.1.1]
  |                                                                                  │  Bump commit 1.1.2 [latest-testing]
  │                                                                                  ✔  PR merged [latest-testing]
  │                                                                                  ✔  PR merged [latest-testing]
  ✔  PR merged [latest, latest-main]                                                 |
  ✔  Close Release (Version type after release: 'rc') [release-main, 1.2.0-rc.1]     |
  |  Bump commit 1.2.0-rc.2 [latest, latest-main]                                    |
```

### Release Types

| `release_type` | Example: before → after  | When to use                                       |
|----------------|--------------------------|---------------------------------------------------|
| `rc`           | `1.0.0` → `1.1.0-rc.1`  | Start a release candidate cycle on `main`         |
| `patch`        | `1.0.0` → `1.0.1`       | Bug fix on a `release/<MAJOR>.<MINOR>` branch     |
| `minor`        | `1.0.1` → `1.1.0`       | Finalize a minor release from a release candidate |
| `major`        | `1.1.0` → `2.0.0`       | Finalize a major release from a release candidate |

## Usage

```bash
      - name: Release version
        uses: hoprnet/hopr-workflows/actions/release-version@release-version-v2
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
