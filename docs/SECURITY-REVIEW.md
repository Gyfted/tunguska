# Targeted security review — September 24, 2026

This is a focused local review of the native Mac preview, not a certification or an independent audit. The relevant attacker-controlled inputs are memory/floppy images, guest instructions and peripheral commands, and pasted keyboard input. The CLI assembler is a separate developer tool and is not loaded into the app.

## Verified controls

- Image loading limits decompression output to the exact image length plus one byte; truncated, oversized, out-of-range and corrupt images are rejected before memory changes.
- Test inputs include an image expanding to 16 MiB, truncated gzip data, a bad gzip CRC, and missing/invalid files.
- Guest disk LOAD does not resolve host filenames. Guest SYNC does not write the original mounted host file. Tests verify both behaviors. Saving requires a native file-panel action.
- Core image saves use a uniquely created temporary sibling file, check compression completion and `fsync`, and atomically rename only after success. A forced write-failure test verifies the old file remains byte-for-byte intact and partial temporary output is removed. The native app additionally uses `NSFileCoordinator` and an `NSItemReplacementDirectory` to safely replace a selected destination without requesting parent-folder access. Saves reject symbolic-link and other non-regular destinations. Native replacements use Foundation's metadata-preservation behavior; new staged images start with mode 0600.
- The native app now enables App Sandbox and hardened-runtime signing with only the user-selected-file read/write entitlement. No network, broad-folder, hardware, JIT, unsigned-code or debugger-attachment exceptions are granted. CLI tools remain unsandboxed and are not packaged inside the app.
- A separately signed test app with the production entitlements verifies that macOS denies reads/writes of a disposable, unselected private-home fixture and denies an outbound loopback connection. It also verifies bundled OS boot, native save/replacement roundtrips and symbolic-link rejection in its own container. System resources and installed apps remain readable where macOS's standard sandbox permits them.
- Native UI checks cover opening a private user-selected image, Reset using the same URL, mounting a selected disk, creating a saved image and replacing it. The saved image's complete decompressed contents were compared with the mounted fixture.
- Interrupt queues are bounded and clock requests coalesced. The native paste queue is capped at 8,192 ASCII characters.
- Source review found no network API, subprocess launch, shell execution, or dynamically loaded plugin functionality in the app.
- The original release's SHA-256 was checked against its published SourceForge metadata. Only system libraries are linked into the Mac app.

## Findings fixed in this review

1. **Invalid trits from negative remainders.** The original permutation/shift operators could produce −2, outside the legal −1/0/+1 domain. Corrected modular normalization and saturating addition. Exhaustive single-trit closure checks now pass.
2. **Undefined floating-point conversions.** Converting zero attempted to cast negative infinity from `log(0)` to an integer; extreme coprocessor results could also exceed integer ranges. Sanitizer reproduction confirmed the issue. Zero and underflow now have explicit encodings, finite overflow saturates to the representable ternary float, non-finite results raise a guest arithmetic interrupt, and float-to-word conversion rejects out-of-range values before casting. Coprocessor errors acknowledge the request and preserve operand storage.
3. **Signed overflow in word multiplication.** Two 12-trit values can produce a product beyond a 32-bit host integer. Sanitizer reproduction confirmed the issue. Multiplication now uses a 64-bit intermediate and wraps explicitly into the ternary word range.

The security regression suite additionally executes all 729 opcode/address-mode encodings against 32 reproducible randomized register/operand/stack states each (23,328 cases), under AddressSanitizer, UndefinedBehaviorSanitizer and float-cast-overflow instrumentation. This is bounded randomized testing, not comprehensive coverage-guided fuzzing.

## Reproduce

```sh
make test sanitize security-check
make sandbox-check verify-app release-check
```

The existing suite covers normal guest boot and demos as well as arithmetic. Security output is in `build/security-tests.log`; sanitizer diagnostics fail the target. A Clang static analyzer pass was also run on the core and runtime sources. It identified that the host interrupt API could accept a null pointer; that input is now rejected and regression-tested. This path is not directly guest-accessible. The local analyzer report is in `build/security-analysis/report.txt`.

## Remaining limitations

- The `.app` now has App Sandbox and hardened runtime, but is still ad-hoc signed and not notarized. Developer ID signing and Apple's service require credentials unavailable on the initial build host. Notarization submission, ticket stapling and final Gatekeeper acceptance remain unverified until those credentials exist. The release tooling rejects unexpected entitlements and missing Developer ID signatures before submission.
- The native GUI, assembler/parser, bundled old 3CC compiler, and all instruction semantics have not undergone comprehensive fuzzing or independent review. In particular, the assembler supports host-file includes and should be used only on trusted source. It is not a security boundary.
- Guest execution is in the UI process. Expensive guest block operations or excessive debug output can still affect responsiveness and resource consumption. The batch time budget is not a hard per-instruction resource limit.
- No current CVE/database audit of Apple’s system zlib or OS libraries was performed; their security updates come from macOS.
- Not all file-panel/error paths or host filesystem races have been audited. Native saves coordinate with cooperating file presenters; they do not control processes that bypass coordination. Atomic replacement does not guarantee directory-metadata durability across power loss. A process crash may leave a temporary replacement file.

Use the bundled programs and trusted images for this preview. App Sandbox limits host access but does not make the emulator memory-safe or impose hard guest CPU limits. Stronger process/resource isolation, sustained fuzzing and review of the assembler remain work for running arbitrary third-party programs.
