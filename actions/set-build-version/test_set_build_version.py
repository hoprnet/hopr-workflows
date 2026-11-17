"""Exercise the version action's Gather versions shell step."""

import os
import re
import subprocess
import textwrap
from pathlib import Path

import pytest

ACTION = Path(__file__).with_name("action.yaml")


def step_script(name):
    step = ACTION.read_text().split(f"    - name: {name}\n", 1)[1]
    run_block = step.split("      run: |\n", 1)[1].split("    - name:", 1)[0]
    # The step's env: block follows run: and is YAML, not bash
    return textwrap.dedent(run_block.split("      env:\n", 1)[0])


@pytest.mark.parametrize("file_type", ["toml", "json"])
@pytest.mark.parametrize(
    "version_type, version, major, minor, prerelease",
    [
        ("release", "5.0.1", "5", "5.0", "false"),
        ("release", "5.0.0", "5", "5.0", "false"),
        ("release", "12.34.56", "12", "12.34", "false"),
        ("release", "0.1.2", "0", "0.1", "false"),
        ("release", "5.0.1-rc.1", "", "", "true"),
        ("release", "5.0.1-beta.1", "", "", "true"),
        ("release", "5.0.1-alpha.1", "", "", "true"),
        ("release", "5.0.1-alpha", "", "", "true"),
        ("release", "5.0.1-rc.1.20261120010203", "", "", "true"),
        ("release", "5.0.1-0.20261117010203", "", "", "true"),
        ("release", "5.0.1+build.1", "", "", "false"),
        ("release", "5.0", "", "", "false"),
        ("commit", "5.0.1", "", "", "false"),
        ("commit", "5.0.1-beta.1", "", "", "false"),
        ("pr", "5.0.1", "", "", "false"),
    ],
)
def test_version_outputs(
    tmp_path, file_type, version_type, version, major, minor, prerelease
):
    script = step_script("Gather versions")
    version_file = tmp_path / f"version.{file_type}"
    version_file.write_text(
        f'version = "{version}"\n'
        if file_type == "toml"
        else f'{{"version": "{version}"}}\n'
    )
    values = {
        "github.event_name": "pull_request",
        "github.event.pull_request.merged": "false",
        "github.event.pull_request.head.sha": "1234567890abcdef",
        "github.event.pull_request.number": "42",
        "github.event.pull_request.merge_commit_sha": "",
    }
    script = re.sub(r"\$\{\{\s*(.*?)\s*\}\}", lambda match: values[match[1]], script)
    output = tmp_path / "output"
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("GITHUB_PR_LABEL_")
    }
    env.update(
        GITHUB_OUTPUT=str(output),
        FILE=str(version_file),
        VERSION_TYPE=version_type,
        ARCHITECTURE="x86_64-linux",
        PR_MERGE_COMMIT_SHA="",
        IS_FORK_PR="false",
    )
    subprocess.run(["bash", "-euo", "pipefail", "-c", script], env=env, check=True)
    outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
    assert outputs["major_version"] == major
    assert outputs["minor_version"] == minor
    assert outputs["release_version"] == version
    assert outputs["prerelease"] == prerelease
    delimiter = "+" if file_type == "toml" else "-"
    expected = {
        "release": version,
        "commit": f"{version}{delimiter}commit.1234567",
        "pr": f"{version}{delimiter}pr.42",
    }[version_type]
    assert outputs["build_version"] == expected
    assert outputs["docker_build_version"] == expected.replace("+", "-", 1)
    assert outputs["docker_build_version_platform"] == (
        f"{expected.replace('+', '-', 1)}-linux-amd64"
    )


@pytest.mark.parametrize(
    "version, rewritten",
    [
        ("1.1.0", True),
        ("1.1.0-alpha.1", True),
        ("1.1.0-beta.2", True),
        ("1.1.0-rc.3", True),
        ("1.1.0-rc.3+pr.5", True),
        ("1.1.0-rc.1.20261120010203", True),
        ("1.0.1-0.20261117010203", True),
        # Outside the release spec, left untouched
        ("1.1.0-gamma.1", False),
        ("1.1.0-alpha.01", False),
    ],
)
def test_toml_build_version_rewrite(tmp_path, version, rewritten):
    script = step_script("Update build version")
    version_file = tmp_path / "version.toml"
    version_file.write_text(f'[package]\nversion = "{version}"\n')
    build_version = f"{version}+commit.1234567"
    env = {**os.environ, "FILE": str(version_file), "BUILD_VERSION": build_version}
    subprocess.run(["bash", "-euo", "pipefail", "-c", script], env=env, check=True)
    expected = build_version if rewritten else version
    assert version_file.read_text() == f'[package]\nversion = "{expected}"\n'
