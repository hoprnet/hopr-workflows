"""Exercise the version action's Bump version shell step."""

import os
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


@pytest.mark.parametrize(
    "version, release_type, bumped",
    [
        ("1.0.0", "major", "2.0.0"),
        ("1.0.0", "minor", "1.1.0"),
        ("1.0.0", "patch", "1.0.1"),
        ("1.0.0", "rc", "1.1.0-rc.1"),
        ("1.0.0-rc.1", "major", "2.0.0"),
        ("1.0.0-rc.1", "minor", "1.1.0"),
        ("1.0.0-rc.1", "patch", "1.0.0"),
        ("1.0.0-rc.1", "rc", "1.0.0-rc.2"),
    ],
)
def test_bump_version(tmp_path, version, release_type, bumped):
    version_file = tmp_path / "version.toml"
    version_file.write_text(f'[package]\nversion = "{version}"\n')
    output = tmp_path / "output"
    env = {
        **os.environ,
        "FILE": str(version_file),
        "RELEASE_TYPE": release_type,
        "GITHUB_OUTPUT": str(output),
    }
    script = step_script("Bump version")
    # GitHub runs `shell: bash` as `bash -e -o pipefail`; the step relies on unset variables
    subprocess.run(["bash", "-eo", "pipefail", "-c", script], env=env, check=True)
    outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
    assert outputs["current_version"] == version
    assert outputs["bump_version"] == bumped
    assert version_file.read_text() == f'[package]\nversion = "{bumped}"\n'
