# Multi architecture docker manifest

This action generates and publishes a docker manifest that groups all the platform specific images from a specific version.
This action should be invoked after the docker build image is created for each platform. Supported platforms for docker images are : `linux-arm64` and `linux-amd64`

## Usage

```bash
      - name: Create multi-arch docker manifest
        uses: hoprnet/hopr-workflows/actions/multi-arch-manifest@multi-arch-manifest-v1
        with:
          registry: europe-west3-docker.pkg.dev/hoprassociation/docker-images
          image: blokli
          version: 0.0.1
```

## Requirements

- Docker command line needs to be installed.
- Requires the action [Setup GCP](../setup-gcp/README.md) to be invoked previously with attribute `login_artifact_registry: true`.

## Inputs

- `registry`: The Google Artifact registry.
- `image`: The docker image name.
- `version`: The docker version.

## Outputs

None
