#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run negative-access checks against a disposable, private home-directory file.

Applications and system resources are readable by design, so a fixture under
/Applications would not test protection of private user documents.
"""
import subprocess
import tempfile
from pathlib import Path

with tempfile.TemporaryDirectory(prefix=".tunguska-sandbox-test-", dir=Path.home()) as directory:
    fixture = Path(directory) / "unselected.txt"
    fixture.write_text("Tunguska sandbox regression fixture")
    subprocess.run([str(Path("build/SandboxTests.app/Contents/MacOS/SandboxTests").resolve()), str(fixture)], check=True)
    assert fixture.read_text() == "Tunguska sandbox regression fixture"
    assert not fixture.with_name(fixture.name + ".write-attempt").exists()
