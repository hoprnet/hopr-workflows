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
    ./cleanup-docker-images.py <registry> [-n | --dry-run] [-d | --days <days>]

Arguments:
    registry: The Docker image registry in the format `location-docker.pkg.dev/project/repo`.
    -n, --dry-run: Simulate the deletion without making any changes.
    -d, --days: Number of days to consider an image old (default: 60).

Example:
    ./cleanup-docker-images.py europe-west3-docker.pkg.dev/my-project/my-repo -d 30 --dry-run
"""

from datetime import UTC, datetime, timedelta
from google.auth.exceptions import DefaultCredentialsError
from google.cloud import artifactregistry_v1
import argparse
import shlex
import asyncio
import itertools
import re
import subprocess
import sys


def list_docker_images(client, parent):
    """Lists Docker images under the specified parent path."""
    try:
        print(f"Listing Docker images in {parent}")
        request = artifactregistry_v1.ListDockerImagesRequest(parent=parent)
        return [image for image in client.list_docker_images(request=request)]
    except Exception as e:
        print(f"Error listing Docker images: {str(e)}", file=sys.stderr)
        sys.exit(1)


async def delete_docker_images_list(images, dry_run):
    """Deletes a list of Docker images asynchronously."""
    await asyncio.gather(*[asyncio.wait_for(delete_docker_image(img, dry_run), timeout=60) for img in images])


async def delete_docker_image(img, dry_run):
    """Deletes a Docker image by its URI."""
    image_name = img.uri.split("/")[-1].split('@')[0]
    image_tag = image_name + ':' + ','.join(img.tags) if img.tags else img.uri.split("/")[-1]
    if dry_run:
        print(f"Dry-run mode: Would delete image tag(s): {image_tag}")
        return
    try:
        # Use gcloud CLI because Docker image deletion is not supported by the Artifact Registry client
        cmd = f"gcloud artifacts docker images delete {img.uri} --delete-tags -q"
        # Run process capturing output to check for specific error messages
        subprocess.run(shlex.split(cmd), check=True, capture_output=True, text=True)
        print(f"Deleted Docker image {image_tag}")
    except subprocess.CalledProcessError as e:
        if "manifest is referenced by parent manifests" in e.stderr:
            print(f"Skipped {image_tag}: Referenced by another image", file=sys.stderr)
        else:

            print(f"Error deleting Docker image: {e.stderr.strip()}", file=sys.stderr)

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Cleanup old Docker images.")
parser.add_argument("registry", help="Docker image registry")
parser.add_argument("-n", "--dry-run", action="store_true", help="Simulate the deletion without making any changes")
parser.add_argument("-d", "--days", type=int, default=60, help="Number of days to consider an image old (default: 60)")
args = parser.parse_args()

# Extract and validate command-line arguments
registry = args.registry
dry_run = args.dry_run
days = args.days
date = datetime.now(UTC) - timedelta(days=days)
images = ["hoprd", "bloklid", "hopli",  "cover-traffic", "discovery-platform", "availability-monitor", "hopr-admin", "hopr-pluto"]
# Docker images generated without Nix and with referenced images which cannot be deleted
# images = ["hoprd-operator", "uhttp-latency-monitor", "hopr-pluto", "network-hoprnet-org", "network-hoprnet-org-be", "webapi-hoprnet-org"]

# Example registry URL: europe-west3-docker.pkg.dev/my-project/my-repo
registry_pattern = re.compile(r"^(?P<location>[a-z0-9-]+)-docker\.pkg\.dev/(?P<project>[^/]+)/(?P<repo>[^/]+)$")
match = registry_pattern.match(registry)

if not match:
    print(f"Invalid registry format: {registry}", file=sys.stderr)
    sys.exit(1)

# Extract location, project, and repository from the registry URL
location = match.group("location")
project = match.group("project")
repo = match.group("repo")


async def main():
    """Main function to clean up old Docker images."""
    try:
        client = artifactregistry_v1.ArtifactRegistryClient()
    except DefaultCredentialsError as e:
        print(f"Error with credentials: {str(e)}", file=sys.stderr)
        sys.exit(1)

    # Construct the parent path for listing Docker images
    parent = f"projects/{project}/locations/{location}/repositories/{repo}"
    docker_images = list_docker_images(client, parent)

    # we are fine deleting images without tags, with a single "-commit.", "-pr.", "-build.", "-debug." or "<commit-hash>"
    # tag or with both
    tag_filter = re.compile(r"^(.*-commit\..*)|(.*-pr\..*)|(.*-debug\..*)|([a-fA-F0-9]{7}$)|(.*-build\..*)")
    old_images = [
        img
        for img in docker_images
        if img.update_time.timestamp_pb().ToDatetime().astimezone(UTC) < date
        # this check will also allow untagged images
        and all(tag_filter.match(tag) for tag in img.tags)
    ]

    for image in images:
        filtered_images = [img for img in old_images if img.uri.startswith(f"{registry}/{image}@")]
        tagged_filtered_images = [img for img in filtered_images if len(img.tags) > 0]
        untagged_filtered_images = [img for img in filtered_images if len(img.tags) == 0]

        print(f"Found {len(filtered_images)} old images for {image}")
        print(f"Found {len(tagged_filtered_images)} tagged images for {image}")
        print(f"Found {len(untagged_filtered_images)} untagged images for {image}")
        for batch in itertools.batched(tagged_filtered_images, 20):
            await delete_docker_images_list(batch, dry_run)
        for batch in itertools.batched(untagged_filtered_images, 20):
            await delete_docker_images_list(batch, dry_run)


asyncio.run(main())
