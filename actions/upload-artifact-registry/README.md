# Upload Artifact Registry

This action upload files to Google Artifact registry, avoiding to interact directly with the gloud commands.

## Usage

```bash
      - name: Upload files
        uses: hoprnet/hopr-workflows/actions/upload-artifact-registry@upload-artifact-registry-v1
        with:
          source: ./artifacts
          project: hoprassociation
          region: europe-west3
          repository: rust-binaries
          package: hoprd
          version: 0.0.1
```

## Requirements

- Requires the action [Setup GCP](../setup-gcp/README.md) to be invoked previously with attribute `login_artifact_registry: true`

## Inputs

- `source`: The path of the artifacts to upload. If it's a directory it will upload all it's files
- `project`: The GCP project. Default value: `hoprassociation`.
- `region`: The GCP region. Default value: `europe-west3`.
- `repository`: The Google Artifact repository name. Default value: `rust-binaries`.
- `package`: The name of the package stored in Google Artifact Registry.
- `version`: The version of the package.

## Outputs

- `uploaded_files`: Comma-separated list of uploaded files