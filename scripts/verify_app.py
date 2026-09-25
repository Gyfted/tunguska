#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Fail closed when an app's signature or security configuration is wrong."""
import argparse
import plistlib
import subprocess
from pathlib import Path

EXPECTED_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
}


def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def verify(app, developer_id=False, notarized=False):
    app = Path(app).resolve()
    run("codesign", "--verify", "--deep", "--strict", str(app))
    entitlements = plistlib.loads(run("codesign", "-d", "--entitlements", "-", "--xml", str(app)).stdout)
    if entitlements != EXPECTED_ENTITLEMENTS:
        raise ValueError("Unexpected entitlements: only App Sandbox and user-selected file access are permitted")
    signature = run("codesign", "-d", "--verbose=4", str(app)).stderr.decode()
    if "runtime" not in next((line for line in signature.splitlines() if line.startswith("CodeDirectory ")), ""):
        raise ValueError("Hardened runtime is missing")
    if developer_id or notarized:
        if "Authority=Developer ID Application:" not in signature or "Timestamp=" not in signature:
            raise ValueError("A timestamped Developer ID Application signature is required")
    for name in ("LICENSE", "AUTHORS", "NOTICE.md", "boot.ternobj", "boot-3cc.ternobj",
                 "VISION-NOTICE.md", "vision.ternobj", "vision-digits.bin", "vision-model.json", "vision-weights.bin", "vision-int8-weights.bin", "explorer.ternobj", "matvec.metal"):
        if not (app / "Contents" / "Resources" / name).is_file():
            raise ValueError("Required app resource is missing: " + name)
    if notarized:
        run("xcrun", "stapler", "validate", str(app))
        run("spctl", "--assess", "--type", "execute", "--verbose=2", str(app))
    return signature


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--developer-id", action="store_true")
    parser.add_argument("--notarized", action="store_true")
    args = parser.parse_args()
    try:
        verify(args.app, args.developer_id, args.notarized)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, "FAIL: " + str(error) + "\n")
    print("PASS signature, App Sandbox, minimal entitlements, hardened runtime, and bundled notices" +
          ("; notarization and Gatekeeper accepted" if args.notarized else ""))
