# Download Artifact Registry

This action download files from Google Artifact registry, avoiding to interact directly with the gloud commands.

## Usage

```bash
      - name: Download files
        uses: hoprnet/hopr-workflows/actions/download-artifact-registry@download-artifact-registry-v1
        with:
          destination: ./artifacts
          project: hoprassociation
          region: europe-west3
          repository: rust-binaries
          package: hoprd
          version: 0.0.1
```

## Requirements

- Requires the action [Setup GCP](../setup-gcp/README.md) to be invoked previously with attribute `login_artifact_registry: true`

## Inputs

- `destination`: The filepath where the artifacts will be downloaded. If the directory does no exist it will be created.
- `project`: The GCP project. Default value: `hoprassociation`.
- `region`: The GCP region. Default value: `europe-west3`.
- `repository`: The Google Artifact repository name. Default value: `rust-binaries`.
- `package`: The name of the package stored in Google Artifact Registry.
- `version`: The version of the package.

## Outputs

- `downloaded_files`: Comma-separated list of downloaded files