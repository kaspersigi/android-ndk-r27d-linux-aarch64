#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROGRAM = PROJECT_ROOT / "scripts/source-state.py"


class SourceStateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.sources = self.root / "sources"
        self.repository = self.sources / "component"
        self.repository.mkdir(parents=True)
        subprocess.run(["git", "init", "-q", self.repository], check=True)
        subprocess.run(
            [
                "git", "-C", self.repository, "remote", "add", "origin",
                "https://example.test/component",
            ],
            check=True,
        )
        (self.repository / "tracked.txt").write_text("original\n", encoding="utf-8")
        subprocess.run(["git", "-C", self.repository, "add", "tracked.txt"], check=True)
        subprocess.run(
            [
                "git", "-c", "user.name=Test", "-c", "user.email=test@example.test",
                "-C", self.repository, "commit", "-qm", "initial",
            ],
            check=True,
        )
        self.policy = self.root / "policy"
        self.policy.write_text("policy-v1\n", encoding="utf-8")
        self.manifest = self.root / "state.json"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def run_program(self, action: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable, str(PROGRAM), action, str(self.sources),
                str(self.manifest), "--policy-path", str(self.policy),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_source_and_policy_changes_are_rejected(self) -> None:
        self.assertEqual(self.run_program("verify").returncode, 0)

        (self.repository / "tracked.txt").write_text("unattested\n", encoding="utf-8")
        self.assertEqual(self.run_program("verify").returncode, 1)
        subprocess.run(
            ["git", "-C", self.repository, "checkout", "--", "tracked.txt"],
            check=True,
        )

        self.assertEqual(self.run_program("record").returncode, 0)
        self.assertEqual(self.run_program("verify").returncode, 0)

        (self.repository / "tracked.txt").write_text("changed\n", encoding="utf-8")
        self.assertEqual(self.run_program("verify").returncode, 1)
        subprocess.run(
            ["git", "-C", self.repository, "checkout", "--", "tracked.txt"],
            check=True,
        )

        (self.repository / "untracked.txt").write_text("unexpected\n", encoding="utf-8")
        self.assertEqual(self.run_program("verify").returncode, 1)
        (self.repository / "untracked.txt").unlink()

        subprocess.run(
            [
                "git", "-C", self.repository, "remote", "set-url", "origin",
                "https://example.test/replaced",
            ],
            check=True,
        )
        self.assertEqual(self.run_program("verify").returncode, 1)
        subprocess.run(
            [
                "git", "-C", self.repository, "remote", "set-url", "origin",
                "https://example.test/component",
            ],
            check=True,
        )

        self.policy.write_text("policy-v2\n", encoding="utf-8")
        self.assertEqual(self.run_program("verify").returncode, 1)
        self.policy.write_text("policy-v1\n", encoding="utf-8")

        (self.repository / "tracked.txt").write_text("new revision\n", encoding="utf-8")
        subprocess.run(
            ["git", "-C", self.repository, "add", "tracked.txt"], check=True
        )
        subprocess.run(
            [
                "git", "-c", "user.name=Test", "-c",
                "user.email=test@example.test", "-C", self.repository,
                "commit", "-qm", "new revision",
            ],
            check=True,
        )
        self.assertEqual(self.run_program("verify").returncode, 1)


if __name__ == "__main__":
    unittest.main()
