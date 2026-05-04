#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["google-cloud-artifact-registry==1.15.2","google-auth==2.38.0"]
# ///

"""
cleanup-docker-images.py

This script cleans up old Docker images from a Google Cloud Artifact Registry.
It lists Docker images in the specified registry, identifies images older than
a specified number of days, and deletes them. The script can also run in dry-run
mode to simulate deletions without making any changes.

Dependencies:
- google-cloud-artifact-registry==1.15.2
- google-auth==2.38.0

Usage:
    ./cleanup-docker-images.py -p <project> [-l <location>] [-r <repository>] [-n] [-d <days>]

Arguments:
    -p, --project: The GCP project ID.
    -l, --location: The region of the Artifact Registry (default: europe-west3).
    -r, --repository: The Docker repository name in Artifact Registry.
    -n, --dry-run: Simulate the deletion without making any changes.
    -d, --days: Number of days to consider an image old (default: 60).

Example:
    ./cleanup-docker-images.py -p my-project -l europe-west3 -r hoprnet-gcr -d 30 --dry-run
"""

import importlib.util
import os

_spec = importlib.util.spec_from_file_location(
    "cleanup_common",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "cleanup-common.py"),
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
add_args = _mod.add_args
make_cutoff_date = _mod.make_cutoff_date
make_artifact_client = _mod.make_artifact_client
make_registry_parent = _mod.make_registry_parent
delete_in_batches = _mod.delete_in_batches

from datetime import UTC
from google.cloud import artifactregistry_v1
import argparse
import asyncio
import re
import shlex
import subprocess
import sys


def make_docker_registry(location, project, repository):
    """Builds the Docker image registry URL for GCP Artifact Registry."""
    return f"{location}-docker.pkg.dev/{project}/{repository}"


def list_docker_images(client, parent):
    """Lists Docker images under the specified parent path."""
    try:
        print(f"Listing Docker images in {parent}")
        request = artifactregistry_v1.ListDockerImagesRequest(parent=parent)
        return list(client.list_docker_images(request=request))
    except Exception as e:
        print(f"Error listing Docker images: {str(e)}", file=sys.stderr)
        sys.exit(1)


async def delete_docker_image(img, dry_run):
    """Deletes a Docker image by its URI."""
    image_name = img.uri.split("/")[-1].split("@")[0]
    image_tag = (
        image_name + ":" + ",".join(img.tags) if img.tags else img.uri.split("/")[-1]
    )
    if dry_run:
        print(f"Dry-run mode: Would delete image tag(s): {image_tag}")
        return
    try:
        # Use gcloud CLI because Docker image deletion is not supported by the Artifact Registry client
        cmd = f"gcloud artifacts docker images delete {img.uri} --delete-tags -q"
        subprocess.run(shlex.split(cmd), check=True, capture_output=True, text=True)
        print(f"Deleted Docker image {image_tag}")
    except subprocess.CalledProcessError as e:
        if "manifest is referenced by parent manifests" in e.stderr:
            print(f"Skipped {image_tag}: Referenced by another image", file=sys.stderr)
        else:
            print(f"Error deleting Docker image: {e.stderr.strip()}", file=sys.stderr)


# Parse command-line arguments
parser = argparse.ArgumentParser(description="Cleanup old Docker images.")
add_args(parser, project_required=True)
args = parser.parse_args()

project = args.project
location = args.location
repository = args.repository
dry_run = args.dry_run
date = make_cutoff_date(args.days)
registry = make_docker_registry(location, project, repository)
images = [
    "hoprd",
    "bloklid",
    "hopli",
    "cover-traffic",
    "discovery-platform",
    "availability-monitor",
    "hopr-admin",
    "hopr-pluto",
]
# Docker images generated without Nix and with referenced images which cannot be deleted
# images = ["hoprd-operator", "uhttp-latency-monitor", "hopr-pluto", "network-hoprnet-org", "network-hoprnet-org-be", "webapi-hoprnet-org"]


async def main():
    """Main function to clean up old Docker images."""
    client = make_artifact_client()

    parent = make_registry_parent(project, location, repository)
    docker_images = list_docker_images(client, parent)

    # we are fine deleting images without tags, with a single "-commit.", "-pr.", "-build.", "-debug." or "<commit-hash>"
    # tag or with both
    tag_filter = re.compile(
        r"^(.*-commit\..*)|(.*-pr\..*)|(.*-debug\..*)|([a-fA-F0-9]{7}$)|(.*-build\..*)"
    )
    old_images = [
        img
        for img in docker_images
        if img.update_time.timestamp_pb().ToDatetime().astimezone(UTC) < date
        # this check will also allow untagged images
        and all(tag_filter.match(tag) for tag in img.tags)
    ]

    for image in images:
        filtered_images = [
            img for img in old_images if img.uri.startswith(f"{registry}/{image}@")
        ]
        tagged_filtered_images = [img for img in filtered_images if len(img.tags) > 0]
        untagged_filtered_images = [img for img in filtered_images if len(img.tags) == 0]

        print(f"Found {len(filtered_images)} old images for {image}")
        print(f"Found {len(tagged_filtered_images)} tagged images for {image}")
        print(f"Found {len(untagged_filtered_images)} untagged images for {image}")
        await delete_in_batches(tagged_filtered_images, lambda img: delete_docker_image(img, dry_run))
        await delete_in_batches(untagged_filtered_images, lambda img: delete_docker_image(img, dry_run))


asyncio.run(main())
