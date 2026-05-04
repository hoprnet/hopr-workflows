"""
cleanup-common.py

Shared utilities for the GCP Artifact Registry cleanup scripts.
Not intended to be run directly — loaded via importlib from the other scripts.
"""

from datetime import UTC, datetime, timedelta
from google.auth.exceptions import DefaultCredentialsError
from google.cloud import artifactregistry_v1
import asyncio
import itertools
import sys


def add_args(parser, repository_default="", project_required=False):
    """Adds all standard arguments shared by all cleanup scripts."""
    parser.add_argument("-p", "--project", required=project_required, help="GCP project ID")
    parser.add_argument("-l", "--location", default="europe-west3", help="Region of the Artifact Registry")
    parser.add_argument("-r", "--repository", default=repository_default, help="Artifact repository name")
    parser.add_argument("-n", "--dry-run", action="store_true", help="Simulate the deletion without making any changes")
    parser.add_argument("-d", "--days", type=int, default=60, help="Number of days to consider an item old (default: 60)")


def make_cutoff_date(days):
    """Returns a UTC datetime representing `days` days ago."""
    return datetime.now(UTC) - timedelta(days=days)


def make_artifact_client():
    """Creates an ArtifactRegistryClient, exiting on credential errors."""
    try:
        return artifactregistry_v1.ArtifactRegistryClient()
    except DefaultCredentialsError as e:
        print(f"Error with credentials: {str(e)}", file=sys.stderr)
        sys.exit(1)


def make_registry_parent(project, location, repository):
    """Builds the Artifact Registry resource parent path."""
    return f"projects/{project}/locations/{location}/repositories/{repository}"


async def delete_in_batches(items, delete_fn, batch_size=20):
    """Deletes items in batches, running each batch concurrently with a 60s timeout."""
    for batch in itertools.batched(items, batch_size):
        await asyncio.gather(
            *[asyncio.wait_for(delete_fn(item), timeout=60) for item in batch]
        )
