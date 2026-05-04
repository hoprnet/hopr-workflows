#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["google-cloud-artifact-registry==1.15.2","google-auth==2.38.0"]
# ///

"""
cleanup-npm-packages.py

This script cleans up old npm package versions from a Google Cloud Artifact Registry.
It lists all packages in the specified repository, identifies versions older than
a specified number of days whose version string contains "-commit" or "-pr", and
deletes them. The script can also run in dry-run mode to simulate deletions without
making any changes.

Dependencies:
- google-cloud-artifact-registry==1.15.2
- google-auth==2.38.0

Usage:
    ./cleanup-npm-packages.py -p <project> [-l <location>] [-r <repository>] [-n] [-d <days>]

Arguments:
    -p, --project: The GCP project ID.
    -l, --location: The region of the Artifact Registry (default: europe-west3).
    -r, --repository: The Artifact repository name (default: npm).
    -n, --dry-run: Simulate the deletion without making any changes.
    -d, --days: Number of days to consider a version old (default: 60).

Example:
    ./cleanup-npm-packages.py -p my-project -l europe-west3 -r npm -d 30 --dry-run
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
from urllib.parse import unquote
from google.cloud import artifactregistry_v1
import argparse
import asyncio
import re
import sys


def list_packages(client, parent):
    """Lists packages in an Artifact Registry npm repository."""
    try:
        print(f"Listing packages in {parent}")
        request = artifactregistry_v1.ListPackagesRequest(parent=parent)
        return list(client.list_packages(request=request))
    except Exception as e:
        print(f"Error listing packages: {str(e)}", file=sys.stderr)
        sys.exit(1)


def list_versions(client, parent):
    """Lists versions of a package in Artifact Registry."""
    try:
        # FULL view is required to populate create_time; the default view returns only the name
        request = artifactregistry_v1.ListVersionsRequest(
            parent=parent,
            view=artifactregistry_v1.VersionView.FULL,
        )
        return list(client.list_versions(request=request))
    except Exception as e:
        print(f"Error listing versions for {parent}: {str(e)}", file=sys.stderr)
        return []


async def delete_old_version(client, version, dry_run):
    """Deletes a package version by its resource name."""
    parts = version.name.split("/")
    package = unquote(parts[-3]) if len(parts) >= 3 else "unknown"
    ver = unquote(parts[-1]) if parts else "unknown"

    if dry_run:
        print(f"Dry-run mode: Would delete npm package '{package}' version '{ver}'")
        return
    try:
        print(f"Deleting npm package '{package}' version '{ver}'")
        request = artifactregistry_v1.DeleteVersionRequest(name=version.name)
        client.delete_version(request=request)
    except Exception as e:
        print(
            f"Error deleting version '{ver}' of '{package}': {str(e)}", file=sys.stderr
        )


# Parse command-line arguments
parser = argparse.ArgumentParser(description="Cleanup old npm package versions.")
add_args(parser, repository_default="npm", project_required=True)
args = parser.parse_args()

project = args.project
location = args.location
repository = args.repository
dry_run = args.dry_run
date = make_cutoff_date(args.days)

# Match versions containing -commit./-pr. (current format)
version_filter = re.compile(r"-(commit|pr)\.")


async def main():
    """Main function to clean up old npm package versions."""
    client = make_artifact_client()

    parent = make_registry_parent(project, location, repository)
    packages = list_packages(client, parent)
    print(f"Found {len(packages)} packages")

    for package in packages:
        versions = list_versions(client, package.name)
        package_name = unquote(package.name.split("/")[-1])
        # Debug: uncomment to inspect the first 5 versions per package
        # print(f"  Package '{package_name}': {len(versions)} versions total")
        # for v in versions[:5]:
        #     ver_str = unquote(v.name.split("/")[-1])
        #     create_dt = v.create_time.timestamp_pb().ToDatetime().astimezone(UTC)
        #     tags = [t.name.split("/")[-1] for t in v.related_tags]
        #     age_ok = create_dt < date
        #     pattern_ok = bool(version_filter.search(ver_str))
        #     print(f"    ver='{ver_str}' create={create_dt.date()} age_ok={age_ok} pattern_ok={pattern_ok} tags={tags}")
        old_versions = [
            version
            for version in versions
            if version.create_time.timestamp_pb().ToDatetime().astimezone(UTC) < date
            and version_filter.search(unquote(version.name.split("/")[-1]))
            and not version.related_tags
        ]
        print(f"Found {len(old_versions)} old versions for '{package_name}'")
        await delete_in_batches(
            old_versions, lambda version: delete_old_version(client, version, dry_run)
        )


asyncio.run(main())
