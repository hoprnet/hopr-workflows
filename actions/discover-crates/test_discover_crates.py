"""Tests for discover-crates.sh.

Fake `curl` and `gh` are placed on PATH. `curl` answers crates.io lookups from
the CRATES env var ("name/version=status", unlisted means 404). `gh` answers tag
lookups from TAGS (existing tags) and fails with an HTTP 500 when GH_FAIL=1.
The `cargo metadata` document is written by the tests.
"""

import json
import os
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

SCRIPT = Path(__file__).with_name("discover-crates.sh")


@pytest.fixture
def env(tmp_path, monkeypatch):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "curl").write_text(
        textwrap.dedent(
            f"""\
            #!{sys.executable}
            import os, sys
            url = sys.argv[-1]
            key = "/".join(url.split("/")[-2:])
            table = dict(p.split("=") for p in os.environ.get("CRATES", "").split())
            print(table.get(key, "404"), end="")
            """
        )
    )
    (bin_dir / "gh").write_text(
        textwrap.dedent(
            f"""\
            #!{sys.executable}
            import os, sys
            if os.environ.get("GH_FAIL") == "1":
                print("gh: Server Error (HTTP 500)", file=sys.stderr)
                sys.exit(1)
            tag = sys.argv[-1].rsplit("/", 1)[-1]
            if tag in os.environ.get("TAGS", "").split():
                print("{{}}")
                sys.exit(0)
            print("gh: Not Found (HTTP 404)", file=sys.stderr)
            sys.exit(1)
            """
        )
    )
    for stub in bin_dir.iterdir():
        stub.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
    work = tmp_path / "work"
    work.mkdir()
    monkeypatch.setenv("GITHUB_OUTPUT", str(tmp_path / "output"))
    return work


def crate(work, name, version, manifest, text=None, publish=None):
    path = work / manifest
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text if text is not None else f'version = "{version}"\n')
    return {
        "name": name,
        "version": version,
        "publish": publish,
        "manifest_path": str(path),
    }


def run(work, packages, **extra):
    metadata = work / "metadata.json"
    metadata.write_text(json.dumps({"workspace_root": str(work), "packages": packages}))
    full_env = {
        **os.environ,
        "METADATA_FILE": str(metadata),
        "REPOSITORY": "hoprnet/demo",
        "GH_TOKEN": "x",
        **extra,
    }
    return subprocess.run(
        ["bash", str(SCRIPT)],
        cwd=work,
        env=full_env,
        capture_output=True,
        text=True,
    )


def outputs():
    lines = Path(os.environ["GITHUB_OUTPUT"]).read_text().splitlines()
    return {k: json.loads(v) for k, v in (line.split("=", 1) for line in lines)}


def test_published_untagged_crate_is_released_and_bumped(env):
    pkg = crate(env, "demo-a", "1.0.0", "a/Cargo.toml")
    result = run(env, [pkg], CRATES="demo-a/1.0.0=200")
    assert result.returncode == 0, result.stderr
    assert outputs() == {
        "releases": [
            {
                "name": "demo-a",
                "version": "1.0.0",
                "manifest": "a/Cargo.toml",
                "tag_prefix": "demo-a-v",
            }
        ],
        "bumps": ["demo-a"],
    }


def test_tagged_crate_is_only_bumped(env):
    pkg = crate(env, "demo-a", "1.0.0", "a/Cargo.toml")
    run(env, [pkg], CRATES="demo-a/1.0.0=200", TAGS="demo-a-v1.0.0")
    assert outputs() == {"releases": [], "bumps": ["demo-a"]}


def test_crate_not_on_crates_io_is_skipped(env):
    pkg = crate(env, "demo-a", "1.0.0", "a/Cargo.toml")
    run(env, [pkg])
    assert outputs() == {"releases": [], "bumps": []}


def test_unpublishable_crate_is_ignored(env):
    pkg = crate(env, "demo-a", "1.0.0", "a/Cargo.toml", publish=[])
    run(env, [pkg], CRATES="demo-a/1.0.0=200")
    assert outputs() == {"releases": [], "bumps": []}


def test_package_name_limits_the_crates(env):
    a = crate(env, "demo-a", "1.0.0", "a/Cargo.toml")
    b = crate(env, "demo-b", "2.0.0", "b/Cargo.toml")
    run(env, [a, b], CRATES="demo-a/1.0.0=200 demo-b/2.0.0=200", PACKAGE_NAME="demo-b")
    assert outputs()["bumps"] == ["demo-b"]


def test_root_package_uses_the_plain_v_prefix(env):
    pkg = crate(env, "demo", "3.1.0", "Cargo.toml")
    run(env, [pkg], CRATES="demo/3.1.0=200")
    assert outputs()["releases"][0]["tag_prefix"] == "v"


def test_unexpected_crates_io_status_fails_closed(env):
    pkg = crate(env, "demo-a", "1.0.0", "a/Cargo.toml")
    result = run(env, [pkg], CRATES="demo-a/1.0.0=500")
    assert result.returncode == 1
    assert "HTTP 500" in result.stdout + result.stderr


def test_tag_lookup_error_other_than_404_fails_closed(env):
    pkg = crate(env, "demo-a", "1.0.0", "a/Cargo.toml")
    result = run(env, [pkg], CRATES="demo-a/1.0.0=200", GH_FAIL="1")
    assert result.returncode == 1
    assert "tag lookup" in result.stdout + result.stderr


@pytest.mark.parametrize(
    "text",
    [
        "version.workspace = true\n",
        'version = "1.0.0"\n\n[dependencies.foo]\nversion = "0.4.0"\n',
    ],
)
def test_manifest_version_that_release_version_cannot_read_fails(env, text):
    pkg = crate(env, "demo-a", "1.0.0", "a/Cargo.toml", text=text)
    result = run(env, [pkg], CRATES="demo-a/1.0.0=200")
    assert result.returncode == 1
    assert "a/Cargo.toml" in result.stdout + result.stderr


def source(function, *args, **extra):
    return subprocess.run(
        ["bash", "-c", f'source "{SCRIPT}"; {function} "$@"', "bash", *args],
        capture_output=True,
        text=True,
        env={**os.environ, **extra},
    )


def test_tag_prefix_for():
    assert source("tag_prefix_for", "Cargo.toml", "demo").stdout.strip() == "v"
    assert source("tag_prefix_for", "x/Cargo.toml", "demo").stdout.strip() == "demo-v"


def test_manifest_version_reads_every_version_line(tmp_path):
    manifest = tmp_path / "Cargo.toml"
    manifest.write_text('version = "1.2.3"\nversion = "4.5.6"\n')
    assert source("manifest_version", str(manifest)).stdout.split() == [
        "1.2.3",
        "4.5.6",
    ]
    manifest.write_text("version.workspace = true\n")
    assert source("manifest_version", str(manifest)).stdout.strip() == ""


def test_crates_io_status_returns_the_http_code(env):
    result = source("crates_io_status", "demo-a", "1.0.0", CRATES="demo-a/1.0.0=200")
    assert result.stdout.strip() == "200"


def test_unreadable_metadata_fails_instead_of_listing_nothing(env):
    (env / "metadata.json").write_text("not json")
    result = subprocess.run(
        ["bash", str(SCRIPT)],
        cwd=env,
        env={
            **os.environ,
            "METADATA_FILE": str(env / "metadata.json"),
            "REPOSITORY": "o/r",
        },
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert not Path(os.environ["GITHUB_OUTPUT"]).exists()
