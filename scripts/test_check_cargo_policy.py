"""Tests for the Cargo dependency policy check."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_cargo_policy as policy

SCRIPT = Path(__file__).resolve().parent / "check_cargo_policy.py"
GIT_URL = "https://github.com/hoprnet/blokli-client"


def violations_for(manifest: str) -> list[str]:
    """Return the messages reported for a manifest given as TOML text."""
    return [
        v.message for v in policy.find_violations("Cargo.toml", tomllib.loads(manifest))
    ]


def run_cli(files: dict[str, str]) -> subprocess.CompletedProcess[str]:
    """Track *files* in a throwaway git repository and run the script on it."""
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        subprocess.run(["git", "-C", directory, "init", "-q"], check=True)
        for name, content in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
            subprocess.run(["git", "-C", directory, "add", name], check=True)
        return subprocess.run(
            [sys.executable, str(SCRIPT), directory], capture_output=True, text=True
        )


class PatchSectionTest(unittest.TestCase):
    def test_crates_io_patch_with_git_branch_is_rejected(self) -> None:
        messages = violations_for(
            f'[patch.crates-io]\nblokli-client = {{ git = "{GIT_URL}", branch = "x" }}\n'
        )
        self.assertEqual(len(messages), 1, messages)
        self.assertIn("[patch.crates-io]", messages[0])
        self.assertIn("not allowed", messages[0])

    def test_patch_for_git_source_is_rejected(self) -> None:
        messages = violations_for(
            f'[patch."{GIT_URL}"]\nblokli-client = {{ path = "../blokli-client" }}\n'
        )
        self.assertEqual(len(messages), 1)
        self.assertIn(f'[patch."{GIT_URL}"]', messages[0])

    def test_patch_using_a_registry_version_is_still_rejected(self) -> None:
        messages = violations_for('[patch.crates-io]\nserde = { version = "1.0.0" }\n')
        self.assertEqual(len(messages), 1)
        self.assertIn("[patch.crates-io]", messages[0])


class GitDependencyTest(unittest.TestCase):
    def assert_rejected(self, manifest: str, section: str) -> None:
        messages = violations_for(manifest)
        self.assertEqual(len(messages), 1, messages)
        self.assertIn(section, messages[0])
        self.assertIn("'blokli-client'", messages[0])
        self.assertIn("git source", messages[0])

    def test_rev_tag_and_branch_are_rejected(self) -> None:
        for key, value in (("rev", "0123456"), ("tag", "v0.5.0"), ("branch", "main")):
            with self.subTest(key=key):
                self.assert_rejected(
                    f'[dependencies]\nblokli-client = {{ git = "{GIT_URL}", {key} = "{value}" }}\n',
                    "[dependencies]",
                )

    def test_dependency_sub_table_is_rejected(self) -> None:
        self.assert_rejected(
            f'[dependencies.blokli-client]\ngit = "{GIT_URL}"\n', "[dependencies]"
        )

    def test_every_dependency_table_is_covered(self) -> None:
        cases = {
            "[dev-dependencies]": "[dev-dependencies]",
            "[build-dependencies]": "[build-dependencies]",
            "[workspace.dependencies]": "[workspace.dependencies]",
            "[target.'cfg(unix)'.dependencies]": '[target."cfg(unix)".dependencies]',
            "[target.x86_64-unknown-linux-gnu.build-dependencies]": "[target.x86_64-unknown-linux-gnu.build-dependencies]",
            "[dev_dependencies]": "[dev_dependencies]",
            "[target.'cfg(unix)'.build_dependencies]": '[target."cfg(unix)".build_dependencies]',
        }
        for header, section in cases.items():
            with self.subTest(header=header):
                self.assert_rejected(
                    f'{header}\nblokli-client = {{ git = "{GIT_URL}" }}\n', section
                )

    def test_git_replace_override_is_rejected(self) -> None:
        messages = violations_for(
            f'[replace]\n"blokli-client:0.35.0" = {{ git = "{GIT_URL}" }}\n'
        )
        self.assertEqual(len(messages), 1, messages)
        self.assertIn("[replace]", messages[0])
        self.assertIn("'blokli-client:0.35.0'", messages[0])

    def test_path_replace_override_passes(self) -> None:
        self.assertEqual(
            violations_for(
                '[replace]\n"blokli-client:0.35.0" = { path = "../blokli-client" }\n'
            ),
            [],
        )

    def test_every_violation_is_reported(self) -> None:
        messages = violations_for(
            f"""
[dependencies]
blokli-client = {{ git = "{GIT_URL}" }}

[dev-dependencies]
other-client = {{ git = "https://github.com/hoprnet/other-client" }}

[patch.crates-io]
third-client = {{ version = "0.1.0" }}
"""
        )
        self.assertEqual(len(messages), 3, messages)


class AllowedDependencyTest(unittest.TestCase):
    def test_registry_and_path_dependencies_pass(self) -> None:
        self.assertEqual(
            violations_for(
                """
[package]
name = "example"
version = "0.1.0"

[dependencies]
serde = "1.0.44"
tokio = { version = "1.53.1", features = ["macros"] }
hopr-internal = { path = "../hopr-internal" }
hopr-versioned = { path = "../hopr-versioned", version = "0.1.0" }

[dev-dependencies]
tokio-test = "0.4.4"

[build-dependencies]
cc = "1.0.0"
"""
            ),
            [],
        )

    def test_workspace_inheritance_passes(self) -> None:
        self.assertEqual(
            violations_for(
                '[workspace.dependencies]\nserde = "1.0.44"\n\n[dependencies]\nserde = { workspace = true }\n'
            ),
            [],
        )


class ManifestDiscoveryTest(unittest.TestCase):
    def test_only_tracked_manifests_are_checked(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "-C", directory, "init", "-q"], check=True)
            (root / "crate").mkdir()
            (root / "untracked").mkdir()
            for name in ("Cargo.toml", "crate/Cargo.toml", "untracked/Cargo.toml"):
                (root / name).write_text('[package]\nname = "x"\n', encoding="utf-8")
            subprocess.run(
                ["git", "-C", directory, "add", "Cargo.toml", "crate"], check=True
            )

            found = sorted(
                p.relative_to(root).as_posix() for p in policy.tracked_manifests(root)
            )

            self.assertEqual(found, ["Cargo.toml", "crate/Cargo.toml"])


class CommandLineTest(unittest.TestCase):
    """The exit code is what the reusable workflow's check step relies on."""

    def test_patch_section_fails_and_names_manifest_and_section(self) -> None:
        result = run_cli(
            {
                "crate/Cargo.toml": '[package]\nname = "x"\n\n[patch.crates-io]\nserde = { version = "1.0.0" }\n'
            }
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("crate/Cargo.toml: [patch.crates-io] section", result.stdout)

    def test_git_dependency_fails_and_names_manifest_and_dependency(self) -> None:
        result = run_cli(
            {"Cargo.toml": f'[dependencies]\nserde = {{ git = "{GIT_URL}" }}\n'}
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(
            "Cargo.toml: [dependencies] dependency 'serde' uses a git source",
            result.stdout,
        )

    def test_clean_manifest_passes(self) -> None:
        result = run_cli(
            {"Cargo.toml": '[package]\nname = "x"\n\n[dependencies]\nserde = "1.0.0"\n'}
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unparseable_manifest_fails(self) -> None:
        result = run_cli({"Cargo.toml": "[patch.crates-io\n"})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("cannot be parsed", result.stdout)

    def test_no_manifests_passes(self) -> None:
        result = run_cli({"README.md": "hello\n"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
