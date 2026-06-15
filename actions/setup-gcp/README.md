# Setup GCP

This action compiles a set of tasks to install and authenticate against GCP

## Usage

```bash
      - name: Setup GCP
        id: gcp
        uses: hoprnet/hopr-workflows/actions/setup-gcp@setup-gcp-v4
        with:
          workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER_GITHUB }}
          service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}
          install_sdk: "true"
          login_artifact_registry: "true"
          login_gke: "true"
          gke_project: hopr-staging
          gke_cluster_name: cluster-staging
          artifact_registry: europe-west3-docker.pkg.dev
```

## Requirements

None

## Inputs

- `workload_identity_provider`: The workload identity provider to authenticate on GCP.
- `service_account`: The service account email linked to the workload identity provider on GCP.
- `install_sdk`: Determines if the GCloud cli command line needs to be installed.
- `login_artifact_registry`: Determines if the service account needs to login in the Google Artifact registry to be able to publish new artifacts.
- `login_gke`: Determines if the service account needs to be logged in into the Kubernetes cluster.
- `gke_project`: Id of the GCP project where the Kubernetes cluster exists.
- `gke_cluster_name`: Name of the GKE Cluster.
- `artifact_registry`: Google Artifact Registry host.

## Outputs

- `access_token`: GCP access token.
