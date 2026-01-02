# Setup GCP

This action compiles a set of tasks to install and authenticate against GCP

## Usage

```bash
      - name: Setup GCP
        id: gcp
        uses: hoprnet/hopr-workflows/actions/setup-gcp@setup-gcp-v1
        with:
          google_credentials: ${{ secrets.GOOGLE_SERVICE_ACCOUNT_GITHUB_ACTIONS }}
          install_sdk: "true"
          login_artifact_registry: "true"
          login_gke: "true"
          project: "gcp-project-id"
```

## Requirements

None

## Inputs

- `google_credentials`: This is the Google service account in JSON format with permissions to interact from GitHub in GCP.
- `install_sdk`: Determines if the GCloud cli command line needs to be installed.
- `login_artifact_registry`: Determines if the service account needs to login in the Google Artifact registry to be able to publish new artifacts.
- `login_gke`: Determines if the service account needs to be logged in into the Kubernetes cluster
- `project`: Id of the GCP project where the Kubernetes cluster exists.

## Outputs

- `access_token`: GCP access token
