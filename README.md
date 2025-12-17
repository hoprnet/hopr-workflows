# hopr-workflows

GitHub workflows helping HOPR automate tasks via github actions

## Setup Nodejs

Compiles a set of tasks needed to setup a Node js project
```
      - name: Setup Node.js
        uses: hoprnet/hopr-workflows/actions/setup-node-js@node-js-v1
        with:
          node-version: 20.x
```

## Setup GCP

Compiles a set of tasks to install and authenticate against GCP
````
      - name: Setup GCP
        id: gcp
        uses: hoprnet/hopr-workflows/actions/setup-gcp@gcp-v1
        with:
          google-credentials: ${{ secrets.GOOGLE_SERVICE_ACCOUNT_GITHUB_ACTIONS }}
          install-sdk: "true"
          login-artifact-registry: "true
          login-gke: true
          project: <gcp-project-name>
````

## Set build version

Updates the version of the project based on the type of build desired.
 - In pull requests commits: `x.y.z+commit.123456`
 - In pull requests merge: `x.y.z+pr.1234`
 - In close release: `x.y.z`
Do not commit the change.
The parameter `version_type` accepts: `commit`, `pr` and `release`.

````
      - name: Updates build version
        id: version
        uses: hoprnet/hopr-workflows/actions/set-build-version@build-version-v1
        with:
          file: Cargo.toml
          version_type: 'commit'
````

## Bump version

Bumps the version of the project for the new release
Does commit the change on the base branch. 
The parameter `release_type` accepts: `patch`, `minor` and `major`.

````
      - name: Bump version
        id: bump_version
        uses: hoprnet/hopr-workflows/actions/bump-version@build-version-v1
        with:
          file: Cargo.toml
          release_type: patch
````

## Release Notes

Generates the release notes for the open release. It identifies the date where the last tag was created in the given branch, and then collects all the pull requests merged  in the given branch until now.
It provides a github (default) and json format.

````
      - name: Generate Release Notes
        uses: hoprnet/hopr-workflows/actions/generate-release-notes@bump-version-v1
        with:
          branch: ${{ github.ref }}
          format: github
````

## Release Version

Creates a new release in github using internally the `release-notes` and `bump-version` actions
The parameter `release_type` accepts: `patch`, `minor` and `major`.

```
      - name: Release version
        uses: hoprnet/hopr-workflows/actions/release-version@release-version-v1
        with:
          file: Cargo.toml
          release_type: patch
          zulip_api_key: ${{ secrets.ZULIP_API_KEY }}
          zulip_email: ${{ secrets.ZULIP_EMAIL }}
          zulip_channel: "MyChannel"
          zulip_topic: "Releases"

```