# Source and binary release procedure

This fork currently publishes source only. The universal 0.14.1 Ternary Breach candidate
(source commit `45e3b9aceb37a8fae34581538e98b6ab77deeb28`) was Developer ID signed,
accepted by Apple notarization, stapled and accepted by Gatekeeper on 2026-09-25.
Publication is a separate step. Do not claim upstream endorsement.

Ordinary `make app` builds and newly prepared candidates remain ad-hoc signed
development previews. Both previews and notarized distributions enable App
Sandbox and hardened runtime; use the manifest and verification commands below
to distinguish their signing status.

## Prepare a local candidate and matching source

Commit all intended changes, then run from a normal macOS terminal:

```sh
python3 scripts/release.py prepare
```

This exports `HEAD` to a clean source directory, builds an arm64/x86_64 universal
app, runs core, sanitizer, security, assembler, compiler, image-mutation, Vision,
Explorer, Breach, audio, GPU, search, AppKit, sandbox and release-gate tests, checks the actual
signature/entitlements and architecture slices, and packages the app. Use
`--ref <tag-or-commit>` for a different committed source or `--archs arm64` for
a native-only candidate. Existing candidate directories are never overwritten.
Changing `ARCHS` in an existing Make build directory requires a fresh build;
the release script always starts from a clean export.

The audio gates check the synthesized waveforms and guest event bounds under
ASan/UBSan, then exercise the real AVAudioEngine callback silently. The latter
requires a working macOS output device and access to Core Audio. Run release
preparation outside a command sandbox that denies audio components; the app's
own App Sandbox permits output without extra entitlements.

Artifacts are under `build/releases/<version>-<commit>/`:

- `Tunguska.app`: the candidate, initially ad-hoc signed and updated in place by
  notarization. Consult the manifest for its current status.
- `*-LOCAL-PREVIEW.zip`: the original ad-hoc signed local build. It remains a
  preview even after the separate app is notarized.
- `*-source-<commit>.tar.gz`: complete corresponding source exported from the
  exact build commit, including original source copies, notices and build scripts.
- `manifest.json`: source commit, source/app hashes, architectures, compiler and
  OS versions, and signing/notarization state.
- `build-and-tests.log`: build and automated verification results.
- `READ-ME-FIRST.txt`: current release status, attribution and distribution instructions.

Tests execute the host's architecture, even for universal builds. Verify the
other slice on suitable hardware before claiming runtime support there.
Sandbox checks use a temporary, disposable file under the current user's home
directory; an enclosing execution sandbox can prevent this or app-container
initialization. Run those checks without an enclosing sandbox, leaving the
test app's own production App Sandbox entitlements enabled.

## One-time Apple setup

1. The owner enrolls in the [Apple Developer Program](https://developer.apple.com/programs/enroll/)
   and completes Apple's agreement, identity and payment steps themselves.
2. Create and install a [Developer ID Application certificate](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
   with its private key on the signing Mac. This is an Application certificate,
   not a Developer ID Installer or App Store certificate. Keep private keys
   out of the repository, release archive and chat.
3. Confirm the identity exists with `security find-identity -v -p codesigning`.
4. Store notarization credentials in Keychain using Apple's secure interactive
   prompt. Replace the public account/team placeholders below; do not put an
   app-specific password in the command or repository:

   ```sh
   xcrun notarytool store-credentials tunguska-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
   ```

Use an existing credential profile if one is already configured. Enrollment,
certificate creation and storing credentials are owner setup steps, not actions
performed by the build script.

## Sign, notarize and verify

Once the identity and Keychain profile exist, run:

```sh
python3 scripts/release.py notarize build/releases/VERSION-COMMIT \
  --identity 'Developer ID Application: YOUR NAME (TEAM_ID)' \
  --profile tunguska-notary
```

The command verifies the source and bundle hashes, requires an exact available
Developer ID identity, signs with a secure timestamp and hardened runtime, and
submits the app archive to Apple. It records the submission ID before waiting.
An interrupted wait can be resumed by rerunning the same command, without
submitting a duplicate. After acceptance it staples the ticket, verifies it,
and runs Gatekeeper assessment. It produces the final ZIP and `SHA256SUMS` only
after those checks pass, and updates `READ-ME-FIRST.txt` to identify the final
binary and its matching source. Re-verifying a notarized candidate also checks the
final ZIP and exact SHA256SUMS contents. A changed source archive/bundle/ZIP, missing identity,
extra entitlement, rejected submission or failed verification stops the process.

The signing machine needs network access; the app itself has no network
entitlements. Do not disable Gatekeeper, remove quarantine, weaken the sandbox,
or add hardened-runtime exceptions to bypass a failed release check. The
script never creates a GitHub release or uploads a public binary automatically.

For independent inspection:

```sh
python3 scripts/verify_app.py build/releases/VERSION-COMMIT/Tunguska.app --notarized
```

Follow [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
when diagnosing a service failure. Logs and the submission ID remain in the
candidate directory. If submission fails before an ID is recorded, check Apple's
submission history before retrying an uncertain upload.

## Publish with the original author's rights preserved

Before publishing a binary release:

1. Review any newly incorporated code, libraries, artwork or documentation for
   compatible licensing. Preserve their original copyright and license notices.
2. Add dated notices to modified original files. Keep AUTHORS, NOTICE.md and
   source provenance accurate; distinguish original work from fork changes.
3. Run `python3 scripts/release.py prepare` to build the app from a clean source
   export and execute every required release gate, including normal and sanitized
   guest-game, search and AppKit checks. Record the commit, architecture, compiler
   and macOS versions used.
4. Tag the exact source commit used to build the binary. Publish a complete
   corresponding source archive from that tag, including all required source,
   interface files, resources, license notices and build/installation scripts.
   Any dependencies needed beyond system components must be available under
   their applicable terms. Do not rely on an unrelated or moving main branch.
5. Provide the binary and matching source download together on the same release
   page. Include LICENSE, AUTHORS, NOTICE.md and VISION-NOTICE.md with the app/distribution, and
   make the GPL and warranty information accessible in the app.
6. Check signing, sandboxing and notarization requirements separately. They do
   not replace GPL compliance. Update the documented security limitations.

Publish the final notarized ZIP, its matching complete source archive and
`SHA256SUMS` together. Use the manifest's exact commit for the release tag;
never substitute the current branch if it has advanced. Keep preview ZIPs,
temporary upload archives, private keys and credentials out of public release
assets. Users can unzip the accepted app and drag it to Applications; no
privileged installer is required.

This procedure uses accompanying source rather than a written source offer.
A written-offer route has additional obligations, including duration, and
should not be substituted casually. Preserve source for every distributed
binary release and keep recipients' redistribution and modification rights.

References:

- GNU GPLv2, especially sections 1–3 and 6:
  https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
- GNU licensing FAQ: https://www.gnu.org/licenses/gpl-faq.en.html
