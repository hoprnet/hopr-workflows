"""Tests for bump-rust-packages.sh.

A fake `cargo` is placed on PATH. It records its arguments and edits a tracked
file inside a throwaway git repository, so the script's changed-file output is
checked against real `git diff` results.
"""

import os
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

SCRIPT = Path(__file__).with_name("bump-rust-packages.sh")


@pytest.fixture
def repo(tmp_path, monkeypatch):
    """A git repo with two tracked files and a fake cargo that edits them."""
    work = tmp_path / "work"
    work.mkdir()
    (work / "Cargo.lock").write_text("lock 1\n")
    (work / "a").mkdir()
    (work / "a" / "Cargo.toml").write_text('version = "1.0.0"\n')
    for cmd in (
        ["init", "-q"],
        ["add", "."],
        ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"],
    ):
        subprocess.run(["git", *cmd], cwd=work, check=True)

    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    calls = tmp_path / "cargo-calls"
    stub = bin_dir / "cargo"
    stub.write_text(
        textwrap.dedent(
            f"""\
            #!{sys.executable}
            import os, sys
            with open(os.environ["CALLS"], "a") as f:
                f.write(" ".join(sys.argv[1:]) + "\\n")
            if os.environ.get("CARGO_EXIT"):
                sys.exit(int(os.environ["CARGO_EXIT"]))
            if os.environ.get("CARGO_EDIT") == "1":
                open("a/Cargo.toml", "w").write('version = "1.0.1"\\n')
                open("Cargo.lock", "w").write("lock 2\\n")
            """
        )
    )
    stub.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setenv("CALLS", str(calls))
    monkeypatch.setenv("GITHUB_OUTPUT", str(tmp_path / "output"))
    return work


def run(repo, **env):
    full_env = {**os.environ, **env}
    return subprocess.run(
        ["bash", str(SCRIPT)],
        cwd=repo,
        env=full_env,
        capture_output=True,
        text=True,
    )


def calls():
    path = Path(os.environ["CALLS"])
    return path.read_text().splitlines() if path.exists() else []


def output():
    path = Path(os.environ["GITHUB_OUTPUT"])
    return path.read_text() if path.exists() else ""


def source(function, *args):
    """Run one function of the script in isolation (the script must be sourceable)."""
    return subprocess.run(
        ["bash", "-c", f'source "{SCRIPT}"; {function} "$@"', "bash", *args],
        capture_output=True,
        text=True,
    )


def test_bumps_each_package_with_the_release_type(repo):
    result = run(repo, PACKAGES="crate-a crate_b", RELEASE_TYPE="patch", CARGO_EDIT="1")
    assert result.returncode == 0, result.stderr
    assert calls() == [
        "release version patch --package crate-a --package crate_b --execute --no-confirm"
    ]


def test_accepts_newline_separated_packages(repo):
    result = run(repo, PACKAGES="crate-a\ncrate-b\n", RELEASE_TYPE="rc")
    assert result.returncode == 0, result.stderr
    assert calls() == [
        "release version rc --package crate-a --package crate-b --execute --no-confirm"
    ]


def test_outputs_the_files_cargo_changed(repo):
    run(repo, PACKAGES="crate-a", RELEASE_TYPE="patch", CARGO_EDIT="1")
    assert output().strip() == "commit_files=Cargo.lock a/Cargo.toml"


def test_outputs_empty_list_when_nothing_changed(repo):
    result = run(repo, PACKAGES="crate-a", RELEASE_TYPE="patch")
    assert result.returncode == 0, result.stderr
    assert output().strip() == "commit_files="


@pytest.mark.parametrize("release_type", ["", "prerelease", "patch; rm -rf /", "PATCH"])
def test_rejects_unknown_release_type(repo, release_type):
    result = run(repo, PACKAGES="crate-a", RELEASE_TYPE=release_type)
    assert result.returncode == 1
    assert "release_type" in result.stderr
    assert calls() == []


@pytest.mark.parametrize("packages", ["", "  \n ", "ok bad;name", "$(id)", "--workspace"])
def test_rejects_empty_or_unsafe_packages(repo, packages):
    result = run(repo, PACKAGES=packages, RELEASE_TYPE="patch")
    assert result.returncode == 1
    assert "package" in result.stderr.lower()
    assert calls() == []


def test_propagates_cargo_failure(repo):
    result = run(repo, PACKAGES="crate-a", RELEASE_TYPE="patch", CARGO_EXIT="3")
    assert result.returncode == 3
    assert output() == ""


def test_parse_packages_prints_one_name_per_line():
    result = source("parse_packages", "a  b\nc\t d")
    assert result.returncode == 0
    assert result.stdout.split() == ["a", "b", "c", "d"]


def test_validate_release_type_accepts_the_four_levels():
    for level in ("major", "minor", "patch", "rc"):
        assert source("validate_release_type", level).returncode == 0
    assert source("validate_release_type", "other").returncode == 1
