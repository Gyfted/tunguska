#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Prepare a reproducible-source Mac preview, then sign and notarize it.

Credentials stay in Keychain. This script never creates a GitHub release or
publishes an unnotarized binary. See docs/RELEASING.md.
"""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import tarfile
from pathlib import Path

from verify_app import EXPECTED_ENTITLEMENTS, verify

ROOT = Path(__file__).resolve().parents[1]


def capture(*args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.sha256(stream.read()).hexdigest()


def bundle_hashes(app):
    return {str(path.relative_to(app)): sha256(path) for path in sorted(app.rglob("*")) if path.is_file()}


def save_manifest(folder, manifest):
    temporary = folder / "manifest.json.new"
    temporary.write_text(json.dumps(manifest, indent=2) + "\n")
    temporary.replace(folder / "manifest.json")


def verify_inputs(folder, manifest):
    archive = folder / manifest["source_archive"]
    if archive.parent != folder or not archive.is_file() or sha256(archive) != manifest["source_sha256"]:
        raise ValueError("Matching source archive is missing or changed; prepare a fresh release")
    if bundle_hashes(folder / "Tunguska.app") != manifest["bundle_hashes"]:
        raise ValueError("App bundle changed after preparation; prepare a fresh release")
    if manifest.get("status") == "notarized":
        name = manifest.get("binary_archive", "")
        archive = folder / name
        if (not name or archive.parent != folder or archive.is_symlink() or not archive.is_file()
                or sha256(archive) != manifest.get("binary_sha256")):
            raise ValueError("Final binary archive is missing or changed; prepare a fresh release")
        sums = folder / "SHA256SUMS"
        if not sums.is_file() or sums.read_text() != distribution_checksums(manifest):
            raise ValueError("Distribution SHA256SUMS is missing or changed; prepare a fresh release")


def distribution_checksums(manifest):
    return (manifest["binary_sha256"] + "  " + manifest["binary_archive"] + "\n" +
            manifest["source_sha256"] + "  " + manifest["source_archive"] + "\n")


def prepare(args):
    if capture("git", "status", "--porcelain", cwd=ROOT):
        raise ValueError("Commit the work first: release preparation requires a clean checkout")
    commit = capture("git", "rev-parse", "--verify", args.ref + "^{commit}", cwd=ROOT)
    info = plistlib.loads(subprocess.check_output(["git", "show", commit + ":src/macos/Info.plist"], cwd=ROOT))
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", version):
        raise ValueError("Unexpected release version")
    folder = ROOT / "build" / "releases" / (version + "-" + commit[:12])
    folder.mkdir(parents=True, exist_ok=False)
    source_name = "Tunguska-" + version + "-source-" + commit[:12]
    archive = folder / (source_name + ".tar.gz")
    subprocess.run(["git", "archive", "--format=tar.gz", "--prefix=" + source_name + "/",
                    "--output=" + str(archive), commit], cwd=ROOT, check=True)
    # Extract only regular source files/directories beneath the known prefix.
    with tarfile.open(archive) as source_tar:
        for member in source_tar.getmembers():
            parts = Path(member.name).parts
            if not parts or parts[0] != source_name or ".." in parts or not (member.isfile() or member.isdir()):
                raise ValueError("Unsafe or unsupported source archive member: " + member.name)
        source_tar.extractall(folder)
    source = folder / source_name
    architecture = "universal2" if args.archs == ["arm64", "x86_64"] else args.archs[0]
    print("Building and testing exact source commit " + commit, flush=True)
    with (folder / "build-and-tests.log").open("w") as log:
        subprocess.run(["make", "-j4", "ARCHS=" + " ".join(args.archs), "all", "test", "sanitize", "security-check", "assembler-check", "assembler-sanitize", "image-fuzz-check", "compiler-check", "compiler-sanitize", "vision-check", "vision-sanitize", "explorer-check", "explorer-sanitize", "breach-check", "breach-sanitize", "weight-check", "weight-sanitize", "weight-gpu-validation", "search-check", "search-sanitize", "rendering-check", "rendering-sanitize", "verify-app", "release-check"],
                       cwd=source, check=True, stdout=log, stderr=subprocess.STDOUT)
        # Run on the build host. Cross-built slices are verified below, not claimed runtime-tested.
        subprocess.run(["make", "ARCHS=" + " ".join(args.archs), "sandbox-check"], cwd=source,
                       check=True, stdout=log, stderr=subprocess.STDOUT)
    app = folder / "Tunguska.app"
    shutil.copytree(source / "build" / "Tunguska.app", app)
    verify(app)
    slices = capture("lipo", "-archs", str(app / "Contents" / "MacOS" / "Tunguska")).split()
    if sorted(slices) != sorted(args.archs):
        raise ValueError("Built architectures do not match the requested release")
    preview = folder / ("Tunguska-" + version + "-" + architecture + "-LOCAL-PREVIEW.zip")
    subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(preview)], check=True)
    manifest = {
        "status": "local-preview-not-notarized", "version": version, "build": info["CFBundleVersion"],
        "commit": commit, "architectures": slices, "runtime_tested_architecture": capture("uname", "-m"),
        "macOS": capture("sw_vers", "-productVersion"), "compiler": capture("clang++", "--version"),
        "source_archive": archive.name, "source_sha256": sha256(archive), "source_directory": source_name,
        "bundle_hashes": bundle_hashes(app), "preview_archive": preview.name, "preview_sha256": sha256(preview),
        "notarization_id": None,
    }
    save_manifest(folder, manifest)
    (folder / "READ-ME-FIRST.txt").write_text(
        "LOCAL PREVIEW — AD-HOC SIGNED, NOT NOTARIZED\n\n"
        "App Sandbox and hardened runtime are enabled. This is not a Gatekeeper-approved public release.\n"
        "Do not disable Gatekeeper to distribute it. Use the notarize command after Developer ID setup.\n"
        "The corresponding source archive, license notices and build record accompany this app.\n"
        "Original Tunguska: Viktor Lofgren. Independent fork: Vinny Lingham. GPL-2.0-or-later.\n"
        "Only the build host architecture was executed by the automated tests.\n")
    print("Prepared " + str(folder), flush=True)
    print("Public signing/notarization is still pending; no binary was uploaded or published.")


def choose_identity(requested):
    identities = capture("security", "find-identity", "-v", "-p", "codesigning")
    # Keychain searches can report the same certificate more than once. Only
    # distinct certificates should make an exact identity selection ambiguous.
    choices = set(re.findall(r'([0-9A-Fa-f]{40}) "(Developer ID Application:[^"]+)"', identities))
    matches = [(fingerprint, name) for fingerprint, name in choices if requested in (fingerprint, name)]
    if len(matches) != 1:
        raise ValueError("Install a valid Developer ID Application certificate with its private key, then supply its exact name or fingerprint")
    return matches[0]


def write_distribution_notes(folder, manifest):
    (folder / "READ-ME-FIRST.txt").write_text(
        "DEVELOPER ID SIGNED — NOTARIZED — GATEKEEPER ACCEPTED\n\n"
        "Tunguska " + manifest["version"] + " (build " + manifest["build"] + ")\n"
        "Binary: " + manifest["binary_archive"] + "\n"
        "Matching source: " + manifest["source_archive"] + "\n"
        "Source commit: " + manifest["commit"] + "\n\n"
        "Distribute the binary, matching complete source archive, and SHA256SUMS together.\n"
        "Unzip the binary and move Tunguska.app to Applications. The app includes its notarization ticket.\n"
        "App Sandbox and hardened runtime are enabled. No Gatekeeper bypass is needed.\n"
        "Any LOCAL-PREVIEW.zip and notarization-upload.zip here are earlier artifacts; use the binary named above.\n\n"
        "Original Tunguska: Viktor Lofgren. Independent fork: Vinny Lingham. GPL-2.0-or-later.\n"
        "License, attribution and warranty notices accompany the app and complete source.\n"
        "Built architectures: " + ", ".join(manifest["architectures"]) + ".\n"
        "Runtime-tested architecture: " + manifest["runtime_tested_architecture"] + ".\n"
        "Apple notarization does not replace an independent security audit.\n")


def notarize(args):
    folder = args.folder.resolve()
    manifest = json.loads((folder / "manifest.json").read_text())
    verify_inputs(folder, manifest)
    fingerprint, identity = choose_identity(args.identity)  # Fail before network/upload if not configured.
    app = folder / "Tunguska.app"
    if manifest["status"] == "notarized":
        verify(app, notarized=True)
        write_distribution_notes(folder, manifest)
        print("Already notarized; matching app, source, final ZIP and checksums verified.")
        return
    if not manifest.get("notarization_id"):
        entitlements = folder / "release.entitlements"
        entitlements.write_bytes(plistlib.dumps(EXPECTED_ENTITLEMENTS))
        subprocess.run(["codesign", "--force", "--sign", fingerprint, "--timestamp", "--options", "runtime",
                        "--entitlements", str(entitlements), str(app)], check=True)
        verify(app, developer_id=True)
        manifest.update(status="signed-awaiting-notarization", signing_identity=identity, bundle_hashes=bundle_hashes(app))
        save_manifest(folder, manifest)
        upload = folder / "notarization-upload.zip"
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(upload)], check=True)
        submission = subprocess.run(["xcrun", "notarytool", "submit", str(upload), "--keychain-profile", args.profile,
                                     "--no-wait", "--output-format", "json"], capture_output=True, text=True)
        (folder / "notarization-submit.json").write_text(submission.stdout)
        submission.check_returncode()
        response = json.loads(submission.stdout)
        manifest.update(status="submitted", notarization_id=response["id"])
        save_manifest(folder, manifest)
    submission_id = manifest["notarization_id"]
    print("Waiting for Apple submission " + submission_id + "; rerun the same command to resume if interrupted.", flush=True)
    result = subprocess.run(["xcrun", "notarytool", "wait", submission_id, "--keychain-profile", args.profile,
                             "--timeout", "10m", "--output-format", "json"], capture_output=True, text=True)
    (folder / "notarization-result.json").write_text(result.stdout)
    result.check_returncode()
    response = json.loads(result.stdout)
    if response.get("status") != "Accepted":
        subprocess.run(["xcrun", "notarytool", "log", submission_id, "--keychain-profile", args.profile,
                        str(folder / "notarization-log.json")], check=True)
        raise ValueError("Apple did not accept the submission; inspect notarization-log.json")
    subprocess.run(["xcrun", "stapler", "staple", str(app)], check=True)
    # Stapling changes the bundle. Preserve its new hashes before Gatekeeper's
    # online assessment, so a transient assessment failure can be retried.
    manifest.update(status="stapled-awaiting-verification", bundle_hashes=bundle_hashes(app))
    save_manifest(folder, manifest)
    verify(app, notarized=True)
    architecture = "universal2" if len(manifest["architectures"]) == 2 else manifest["architectures"][0]
    binary = folder / ("Tunguska-" + manifest["version"] + "-" + architecture + ".zip")
    subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(binary)], check=True)
    manifest.update(status="notarized", bundle_hashes=bundle_hashes(app), binary_archive=binary.name, binary_sha256=sha256(binary))
    (folder / "SHA256SUMS").write_text(distribution_checksums(manifest))
    save_manifest(folder, manifest)
    verify_inputs(folder, manifest)
    write_distribution_notes(folder, manifest)
    print("Notarized and Gatekeeper-accepted. Publish the binary, matching source archive, and SHA256SUMS together.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser("prepare", help="Build/test a clean commit and package its exact source")
    prep.add_argument("--ref", default="HEAD")
    prep.add_argument("--archs", nargs="+", choices=["arm64", "x86_64"], default=["arm64", "x86_64"])
    signing = commands.add_parser("notarize", help="Sign with Developer ID, submit, staple, and verify")
    signing.add_argument("folder", type=Path)
    signing.add_argument("--identity", required=True)
    signing.add_argument("--profile", required=True, help="Name of a notarytool credential profile already stored in Keychain")
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            if len(set(args.archs)) != len(args.archs):
                raise ValueError("Duplicate architectures")
            args.archs.sort(key=lambda arch: arch != "arm64")
            prepare(args)
        else:
            notarize(args)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, "Release stopped: " + str(error) + "\nNo unverified binary is approved for publication.\n")


if __name__ == "__main__":
    main()
