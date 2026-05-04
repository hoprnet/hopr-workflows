#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["google-cloud-artifact-registry==1.15.2","google-auth==2.38.0"]
# ///

"""
cleanup-artifacts.py

This script cleans up old artifacts from a Google Cloud Artifact Registry.
It lists artifacts in the specified registry, identifies artifacts older than
a specified number of days, and deletes them. The script can also run in dry-run
mode to simulate deletions without making any changes.

Dependencies:
- google-cloud-artifact-registry==1.15.2
- google-auth==2.38.0

Usage:
    ./cleanup-artifacts.py <project> <region> <repository> [-n | --dry-run] [-d | --days <days>]

Arguments:
    project: The GCP project ID.
    region: The region of the Artifact Registry.
    repository: The Artifact repository name.
    -n, --dry-run: Simulate the deletion without making any changes.
    -d, --days: Number of days to consider a file old (default: 60).

Example:
    ./cleanup-artifacts.py my-project europe-west3 rust-binaries -d 30 --dry-run
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
import sys


def list_files(client, parent):
    """Lists Files in Artifact registry."""
    try:
        print(f"Listing Files in {parent}")
        request = artifactregistry_v1.ListFilesRequest(parent=parent)
        return list(client.list_files(request=request))
    except Exception as e:
        print(f"Error listing artifact files: {str(e)}", file=sys.stderr)
        sys.exit(1)


async def delete_old_file(client, file, dry_run):
    """Deletes an artifact file by its resource name."""
    full_file_name = file.name.split("/")[-1]
    package = full_file_name.split(":")[0]
    version = full_file_name.split(":")[1]
    file_name = full_file_name.split(":")[2]

    if dry_run:
        print(
            f"Dry-run mode: Would delete artifact package: '{package}' version: '{version}' file_name: '{file_name}'"
        )
        return
    try:
        print(
            f"Delete artifact package: '{package}' version: '{version}' file_name: '{file_name}'"
        )
        request = artifactregistry_v1.DeleteFileRequest(name=file.name)
        client.delete_file(request=request)
    except Exception as e:
        print(f"Error deleting file: {str(e)}", file=sys.stderr)
        sys.exit(1)


# Parse command-line arguments
parser = argparse.ArgumentParser(description="Cleanup old artifacts.")
add_args(parser, repository_default="rust-binaries", project_required=True)
args = parser.parse_args()

project = args.project
location = args.location
repository = args.repository
dry_run = args.dry_run
date = make_cutoff_date(args.days)
packages = ["bloklid", "hopli"]

# we are fine deleting files with a single "-commit.", "-pr.", "-build.", "-debug." or "<commit-hash>"
# tag or with both
name_filter = re.compile(r"^(.*\+commit\..*)|(.*\+pr\..*)|(.*\+debug\..*)")


async def main():
    """Main function to clean up old Artifact Registry artifacts."""
    client = make_artifact_client()

    parent = make_registry_parent(project, location, repository)
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
        await delete_in_batches(
            old_files, lambda file: delete_old_file(client, file, dry_run)
        )


asyncio.run(main())
