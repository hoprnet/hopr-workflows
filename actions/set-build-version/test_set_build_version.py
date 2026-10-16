"""Exercise the version action's Gather versions shell step."""

import os
import re
import subprocess
import textwrap
from pathlib import Path

import pytest

ACTION = Path(__file__).with_name("action.yaml")


@pytest.mark.parametrize("file_type", ["toml", "json"])
@pytest.mark.parametrize(
    "version_type, version, major, minor",
    [
        ("release", "5.0.1", "5", "5.0"),
        ("release", "5.0.0", "5", "5.0"),
        ("release", "12.34.56", "12", "12.34"),
        ("release", "0.1.2", "0", "0.1"),
        ("release", "5.0.1-rc.1", "", ""),
        ("release", "5.0.1-beta.1", "", ""),
        ("release", "5.0.1-alpha", "", ""),
        ("release", "5.0.1+build.1", "", ""),
        ("release", "5.0", "", ""),
        ("commit", "5.0.1", "", ""),
        ("pr", "5.0.1", "", ""),
    ],
)
def test_version_outputs(tmp_path, file_type, version_type, version, major, minor):
    step = ACTION.read_text().split("    - name: Gather versions\n", 1)[1]
    script = textwrap.dedent(
        step.split("      run: |\n", 1)[1].split("    - name:", 1)[0]
    )
    version_file = tmp_path / f"version.{file_type}"
    version_file.write_text(
        f'version = "{version}"\n'
        if file_type == "toml"
        else f'{{"version": "{version}"}}\n'
    )
    values = {
        "inputs.file": str(version_file),
        "inputs.version_type": version_type,
        "inputs.architecture": "x86_64-linux",
        "github.event_name": "pull_request",
        "github.event.pull_request.merged": "false",
        "github.event.pull_request.head.sha": "1234567890abcdef",
        "github.event.pull_request.number": "42",
        "github.event.pull_request.merge_commit_sha": "",
    }
    script = re.sub(
        r"\$\{\{\s*(.*?)\s*\}\}", lambda match: values[match[1]], script
    )
    output = tmp_path / "output"
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("GITHUB_PR_LABEL_")
    }
    env["GITHUB_OUTPUT"] = str(output)
    subprocess.run(["bash", "-euo", "pipefail", "-c", script], env=env, check=True)
    outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
    assert outputs["major_version"] == major
    assert outputs["minor_version"] == minor
    assert outputs["release_version"] == version
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
