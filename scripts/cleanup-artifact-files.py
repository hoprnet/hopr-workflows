#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["google-cloud-artifact-registry==1.15.2","google-auth==2.38.0"]
# ///

"""
cleanup-artifacts.py.py

This script cleans up old artifacts from a Google Cloud Artifact Registry.
It lists artifacts in the specified registry, identifies artifacts older than
a specified number of days, and deletes them. The script can also run in dry-run
mode to simulate deletions without making any changes.

Dependencies:
- google-cloud-artifact-registry==1.15.2
- google-auth==2.38.0

Usage:
    ./cleanup-artifacts.py.py <project> <region> <repository> [-n | --dry-run] [-d | --days <days>]

Arguments:
    project: The GCP project ID.
    region: The region of the Artifact Registry.
    repository: The Artifact repository name.
    -n, --dry-run: Simulate the deletion without making any changes.
    -d, --days: Number of days to consider a file old (default: 60).

Example:
    ./cleanup-artifacts.py.py my-project europe-west3 rust-binaries -d 30 --dry-run
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


def list_files(client, parent, filter_str=None):
    """Lists Files in Artifact registry."""
    try:
        print(f"Listing Files in {parent} with filter: {filter_str}")
        request = artifactregistry_v1.ListFilesRequest(parent=parent, filter=filter_str)
        return [file for file in client.list_files(request=request)]
    except Exception as e:
        print(f"Error listing artifact files: {str(e)}", file=sys.stderr)
        sys.exit(1)


async def delete_old_files_list(client, files, dry_run):
    """Deletes a list of artifact files asynchronously."""
    await asyncio.gather(*[asyncio.wait_for(delete_old_file(client, file, dry_run), timeout=60) for file in files])


async def delete_old_file(client, file, dry_run):
    """Deletes an artifact file by its URI."""
    full_file_name = file.name.split("/")[-1]
    package = full_file_name.split(":")[0]
    version = full_file_name.split(":")[1]
    file_name = full_file_name.split(":")[2]

    if dry_run:
        print(f"Dry-run mode: Would delete artifact package: '{package}' version: '{version}' file_name: '{file_name}'")
        return
    try:
        print(f"Delete artifact package: '{package}' version: '{version}' file_name: '{file_name}'")
        request = artifactregistry_v1.DeleteFileRequest(name=file.name)
        client.delete_file(request=request)
    except Exception as e:
        print(f"Error deleting file: {str(e)}", file=sys.stderr)
        sys.exit(1)


# Parse command-line arguments
parser = argparse.ArgumentParser(description="Cleanup old artifacts.")
parser.add_argument("-p", "--project", help="GCP project ID")
parser.add_argument("-l", "--location", default="europe-west3", help="Region of the Artifact Registry")
parser.add_argument("-r", "--repository", default="rust-binaries", help="Artifact repository name")
parser.add_argument("-n", "--dry-run", action="store_true", help="Simulate the deletion without making any changes")
parser.add_argument("-d", "--days", type=int, default=60, help="Number of days to consider an file old (default: 60)")
args = parser.parse_args()

# Extract and validate command-line arguments
project = args.project
location = args.location
repository = args.repository
dry_run = args.dry_run
days = args.days
date = datetime.now(UTC) - timedelta(days=days)
packages = ["bloklid", "hopli"]

async def main():
    """Main function to clean up old Artifact Registry artifacts."""
    try:
        client = artifactregistry_v1.ArtifactRegistryClient()
    except DefaultCredentialsError as e:
        print(f"Error with credentials: {str(e)}", file=sys.stderr)
        sys.exit(1)

    # we are fine deleting files with a single "-commit.", "-pr.", "-build.", "-debug." or "<commit-hash>"
    # tag or with both
    name_filter = re.compile(r"^(.*\+commit\..*)|(.*\+pr\..*)|(.*\+debug\..*)")
    parent = f"projects/{project}/locations/{location}/repositories/{repository}"
    # List all files in the repository (client-side filtering is more robust for partial matching)
    artifact_files = list_files(client, parent)
    for package in packages:
        old_files = [
            file
            for file in artifact_files
            if file.update_time.timestamp_pb().ToDatetime().astimezone(UTC) < date
            # Ensure the file belongs to the correct package (extra safety) and matches pattern
            and f"/packages/{package}/" in file.owner
            and name_filter.match(file.name)
        ]
        print(f"Found {len(old_files)} old files for {package}")
        for batch in itertools.batched(old_files, 20):
            await delete_old_files_list(client, batch, dry_run)


asyncio.run(main())
