# SPDX-License-Identifier: GPL-2.0-or-later
"""Release gates must reject changed sources/binaries and permissive signatures."""
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import release
import verify_app


class ReleaseGates(unittest.TestCase):
    def test_source_and_bundle_must_match(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            source = folder / "source.tar.gz"
            source.write_bytes(b"matching source fixture")
            app = folder / "Tunguska.app"
            app.mkdir()
            executable = app / "executable"
            executable.write_bytes(b"built binary fixture")
            manifest = {"source_archive": source.name, "source_sha256": release.sha256(source),
                        "bundle_hashes": release.bundle_hashes(app)}
            release.verify_inputs(folder, manifest)
            source.write_bytes(b"wrong source")
            with self.assertRaisesRegex(ValueError, "source archive"):
                release.verify_inputs(folder, manifest)
            source.write_bytes(b"matching source fixture")
            executable.write_bytes(b"changed binary")
            with self.assertRaisesRegex(ValueError, "App bundle changed"):
                release.verify_inputs(folder, manifest)
            manifest["source_archive"] = "../source.tar.gz"
            with self.assertRaisesRegex(ValueError, "source archive"):
                release.verify_inputs(folder, manifest)

    def test_signing_requires_developer_id(self):
        with patch.object(release, "capture", return_value="0 valid identities found"):
            with self.assertRaisesRegex(ValueError, "Developer ID Application"):
                release.choose_identity("-")
        listing = '1) ' + 'A' * 40 + ' "Developer ID Application: Example (TEAMID)"\n'
        with patch.object(release, "capture", return_value=listing):
            self.assertEqual(release.choose_identity('A' * 40)[1], "Developer ID Application: Example (TEAMID)")
            with self.assertRaises(ValueError):
                release.choose_identity("Example")

    def test_security_configuration_fails_closed(self):
        def verify_fixture(entitlements, signature, developer_id=False):
            def tool(*args):
                output = plistlib.dumps(entitlements) if "--entitlements" in args else b""
                return subprocess.CompletedProcess(args, 0, output, signature.encode())
            with tempfile.TemporaryDirectory() as directory:
                app = Path(directory)
                resources = app / "Contents" / "Resources"
                resources.mkdir(parents=True)
                for name in ("LICENSE", "AUTHORS", "NOTICE.md", "boot.ternobj", "boot-3cc.ternobj"):
                    (resources / name).write_bytes(b"fixture")
                with patch.object(verify_app, "run", side_effect=tool):
                    return verify_app.verify(app, developer_id)
        signature = "CodeDirectory v=20500 flags=0x10002(adhoc,runtime)\nSignature=adhoc\n"
        verify_fixture(verify_app.EXPECTED_ENTITLEMENTS, signature)
        with self.assertRaisesRegex(ValueError, "Hardened runtime"):
            verify_fixture(verify_app.EXPECTED_ENTITLEMENTS, "CodeDirectory flags=0x2(adhoc)")
        for extra in ("com.apple.security.network.client", "com.apple.security.cs.disable-library-validation", "com.apple.security.get-task-allow"):
            with self.assertRaisesRegex(ValueError, "Unexpected entitlements"):
                verify_fixture(dict(verify_app.EXPECTED_ENTITLEMENTS, **{extra: True}), signature)
        with self.assertRaisesRegex(ValueError, "Developer ID"):
            verify_fixture(verify_app.EXPECTED_ENTITLEMENTS, signature, developer_id=True)


if __name__ == "__main__":
    unittest.main()
