"""Tests for multi-arch-manifest.sh.

A fake `docker` is placed on PATH. It records every non-`inspect` invocation and
can be told (via the MISSING env var) to report specific images as absent, so we
can assert exactly which `docker manifest create` command the script builds.
"""

import os
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

HERE = Path(__file__).parent
SCRIPT = HERE / "multi-arch-manifest.sh"
REGISTRY = "europe-west3-docker.pkg.dev/hoprassociation/docker-images"
IMAGE = "hoprd"


def member(version: str, arch: str) -> str:
    return f"{REGISTRY}/{IMAGE}:{version}-{arch}"


def create(tag: str, *members: str) -> str:
    amends = " ".join(f"--amend {m}" for m in members)
    return f"manifest create {REGISTRY}/{IMAGE}:{tag} {amends}"


@pytest.fixture
def run_script(tmp_path, monkeypatch):
    """Return a helper that runs the script with the fake docker and gives back
    the list of `docker manifest create` commands it issued."""
    capture = tmp_path / "docker-calls"
    stub = tmp_path / "docker"
    stub.write_text(
        textwrap.dedent(
            f"""\
            #!{sys.executable}
            import os, sys
            args = sys.argv[1:]
            if args[:2] == ["manifest", "inspect"]:
                missing = os.environ.get("MISSING", "").split()
                sys.exit(1 if args[2] in missing else 0)
            with open(os.environ["CAPTURE"], "a") as f:
                f.write(" ".join(args) + "\\n")
            """
        )
    )
    stub.chmod(0o755)
    monkeypatch.setenv("PATH", f"{tmp_path}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setenv("CAPTURE", str(capture))

    def run(version, source_version=None, missing=()):
        monkeypatch.setenv("MISSING", " ".join(missing))
        monkeypatch.setenv("REGISTRY", REGISTRY)
        monkeypatch.setenv("IMAGE", IMAGE)
        monkeypatch.setenv("VERSION", version)
        if source_version is None:
            monkeypatch.delenv("SOURCE_VERSION", raising=False)
        else:
            monkeypatch.setenv("SOURCE_VERSION", source_version)
        subprocess.run(["bash", str(SCRIPT)], check=True)
        calls = capture.read_text().splitlines() if capture.exists() else []
        return [c for c in calls if c.startswith("manifest create")]

    return run


@pytest.mark.parametrize(
    "version, source_version, expected_tag, member_version",
    [
        # No source_version: members and manifest both use the full version.
        ("5.0.1", None, "5.0.1", "5.0.1"),
        # Empty source_version behaves like omitted (this is how action.yaml passes it).
        ("5.0.1", "", "5.0.1", "5.0.1"),
        # Floating major tag, members from the full version.
        ("5", "5.0.1", "5", "5.0.1"),
        # Floating major.minor tag, same members.
        ("5.0", "5.0.1", "5.0", "5.0.1"),
    ],
)
def test_manifest_members(
    run_script, version, source_version, expected_tag, member_version
):
    assert run_script(version, source_version) == [
        create(
            expected_tag,
            member(member_version, "linux-arm64"),
            member(member_version, "linux-amd64"),
        )
    ]


def test_missing_member_is_skipped(run_script):
    calls = run_script("5", "5.0.1", missing=[member("5.0.1", "linux-arm64")])
    assert calls == [create("5", member("5.0.1", "linux-amd64"))]


def test_all_members_missing_creates_nothing(run_script):
    both = [member("5.0.1", "linux-arm64"), member("5.0.1", "linux-amd64")]
    assert run_script("5", "5.0.1", missing=both) == []
