# hopr-workflows

GitHub workflows helping HOPR automate tasks via github actions

## Setup Nix

Setups the installation environment for nix and uses the nix cache
````
      - name: Setup Nix
        uses: hoprnet/hopr-workflows/actions/setup-nix@nix-v1
        with:
          cache: my-cache-name
          authToken: "${{ secrets.CACHIX_AUTH_TOKEN }}"
          nix_path: "nixpkgs=channel:nixos-24.05"
````

## Setup Nodejs

Compiles a set of tasks needed to setup a Node js project
```
      - name: Setup Node.js
        uses: hoprnet/hopr-workflows/actions/setup-node-js@node-js-v1
        with:
          node_version: 20.x
```

## Setup GCP

Compiles a set of tasks to install and authenticate against GCP
````
      - name: Setup GCP
        id: gcp
        uses: hoprnet/hopr-workflows/actions/setup-gcp@gcp-v1
        with:
          google_credentials: ${{ secrets.GOOGLE_SERVICE_ACCOUNT_GITHUB_ACTIONS }}
          install_sdk: "true"
          login_artifact_registry: "true
          login_gke: true
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
The parameter `release_type` accepts: `rc`, `patch`, `minor` and `major`.

````
      - name: Bump version
        id: bump_version
        uses: hoprnet/hopr-workflows/actions/bump-version@bump-version-v1
        with:
          file: Cargo.toml
          release_type: patch
````

## Release Notes

Generates the release notes for the open release. It identifies the date where the last tag was created in the given branch, and then collects all the pull requests merged  in the given branch until now.
It provides a github (default) and json format.

````
      - name: Generate Release Notes
        uses: hoprnet/hopr-workflows/actions/generate-release-notes@release-notes-v1
        with:
          branch: ${{ github.ref }}
          format: github
````

## Release Version

Creates a new release in github using internally the `release-notes` and `bump-version` actions
The parameter `release_type` accepts: `rc`, `patch`, `minor` and `major`.

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

## Sign file

Creates a gpg signature and sha of the file 
```
      - name: Sign binary
        uses: hoprnet/hopr-workflows/actions/sign-file@sign-file-v1
        with:
          file: ./binary-file
          gpg_private_key: ${{ secrets.MY_GPG_PRIVATE_KEY }}

```

## Publish rust docs

Publishes the rust docs in github pages
````
      - name: Publish docs
        uses: hoprnet/hopr-workflows/actions/publish-rust-docs@publish-rust-docs-v1
        with:
          source_repo: ${{ github.repository }}
          source_branch: ${{ github.event.pull_request.head.ref || github.ref }}
          publish: true
          nix_cache: my_nix_cache_name
          nix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
````

## Download Artifact Registry

Download files from artifact registry
````
      - name: Download files
        uses: hoprnet/hopr-workflows/actions/download-artifact-registry@download-artifact-registry-v1
        with:
          destination: ./artifacts
          project: hoprassociation
          region: europe-west3
          repository: rust-binaries
          package: hoprd
          version: 0.0.1

````

## Upload Artifact Registry

Upload files from artifact registry
````
      - name: Download files
        uses: hoprnet/hopr-workflows/actions/upload-artifact-registry@upload-artifact-registry-v1
        with:
          source: ./artifacts
          project: hoprassociation
          region: europe-west3
          repository: rust-binaries
          package: hoprd
          version: 0.0.1

````