# Source and port notes

## Provenance

The baseline is the official Tunguska 0.5 release, published November 29, 2008:

- Project: https://tunguska.sourceforge.net/
- Archive: https://downloads.sourceforge.net/project/tunguska/tunguska/0.5/tunguska-0.5.tar.bz2
- SHA-256: `86b45d19c8fbba04597dff30fb8b90b6c082f5c23e3eef5e2f092f59033372d7`
- Author’s later repository: https://github.com/vlofgren/tunguska

The archive checksum was verified against SourceForge’s release metadata before extraction. `upstream/tunguska-0.5/` is unmodified. The active sources in `src/core/` and `src/assembler/` were copied from that release. The guest assembly was extracted from its `share/memory_image_asm.tar.gz` without modification.

## GitHub ancestry and independent maintenance

This fork retains all seven commits in the original GitHub history through
`eeb639b37acdb1f0949a9ea59e6e62f7356c4677` (the upstream `master` checked on
2026-09-24). Original author identities, commit dates and messages are preserved.
The original GitHub working-tree files were moved, without content changes, to
`upstream/github/` so they remain available alongside the 0.5 release baseline.
The native Mac port is a later commit on that history, not a replacement or
rewrite of the original authorship.

The GitHub source includes development beyond release 0.5. Our active Mac core
is derived from 0.5, so this fork does not claim to have integrated every later
GitHub change. Future work should compare those sources explicitly.

Vinny Lingham maintains this independent fork. The original project remains
attributed to Viktor Lofgren; no transfer of ownership, appointment by the author,
or endorsement is claimed. Modified original files carry 2026-09-24 notices.
Unmodified originals retain their existing notices and bytes.

## Architecture

The original machine and its program/image formats remain central. The processor is independent of AppKit. `Runtime` owns the CPU, disk, and auxiliary processor and implements the former SDL main-loop behavior. Its frame snapshots cover 54×27 text, vectors, and 324×243 raster graphics in both color modes.

The UI and machine run on one thread. A 60 Hz timer requests bounded execution batches, with a 7 ms time budget checked every 1,024 instructions. Display handshakes are serviced within batches. This removes the original concurrent unsynchronized display access and keeps UI input responsive. The timer is instruction-budgeted, not cycle-accurate or synchronized to a historical physical CPU.

The text renderer uses scalable native monospace fonts. It maps the original display codes, approximating the old bitmap block glyphs with Unicode. Raster and vector output retain the original ternary color mapping. The mouse keeps relative-motion semantics. These are modern renderers rather than a pixel-perfect recreation of the old SDL window.

## Core changes

- Removed the processor header’s dependency on the SDL display header.
- Removed obsolete `register` keywords and dynamic exception specifications for C++17.
- Fixed const correctness in nonary string conversion and used macOS’s native `strndup`.
- Expanded the opcode label table from 80 to 81 entries; opcode +40 was out of bounds.
- Corrected the character lookup bound: code 100 indexed beyond a 100-element table.
- Fixed CMP’s pointer/integer comparison and defined its overflow from the integer difference.
- Fixed ADD overflow: ternary comparison results −1 and +1 had both been treated as C++ `true`.
- Made image loading transactional and validated complete lengths, zlib errors, and tryte ranges. Images use explicit little-endian signed 16-bit values and are compatible with historical little-endian images. Memory snapshots contain memory only, not CPU state.
- Replaced the memory-size macro with a constant and made address wrapping work for the full signed integer domain.
- Prevented accidental copying of memory owners; released processor states, queued interrupts, and mounted disk filenames on destruction/reset.
- Coalesced pending clock interrupts and bounded the input interrupt queue at 4,096 entries.
- Made guest disk loading a host-UI operation and disk persistence explicit through Save Disk As. Invalid replacement disk images preserve the previous mount. Guest changes are lost on reset/eject unless saved.
- Made core image saves atomic: compress into a uniquely created sibling file, verify gzip completion, flush it, then rename it over the destination. Existing Unix permission bits are retained; new files start private. Partial temporary files are removed on reported failures. Symbolic-link and non-regular destinations are rejected. The sandboxed native UI wraps staging in Foundation-coordinated replacement; see below. This does not claim power-loss durability for directory metadata.

## App Sandbox and release preparation — 2026-09-24

The native app's two entitlements are App Sandbox and user-selected file
read/write access. Hardened runtime is enabled with no exceptions, including
no JIT or debugger-attachment exception. The interpreted ternary CPU does not
require executable memory. File dialogs authorize selected URLs. A scoped URL
owner keeps the current image available to Reset; no bookmark survives app exit.

`src/macos/FileAccess.*` handles native saves through `NSFileCoordinator`, a
same-volume `NSItemReplacementDirectory`, and Foundation replacement/move APIs.
The existing checked gzip writer prepares the image there. The app does not need
a blanket grant to the destination directory. The command-line tools retain
their existing core save implementation and are not inside the app bundle.

`scripts/release.py` exports an exact Git commit, builds/tests in that clean
source directory, and keeps complete matching source alongside the app. Universal
builds contain arm64 and x86_64 slices, with runtime tests on the build host only.
Developer ID signing and notarization form a separate, credential-gated step;
local preview packages are explicitly not marked as public releases.

## Debugger additions — 2026-09-24

The new AppKit debugger provides read-only disassembly and memory inspection,
register/flag display, and host-managed execution breakpoints. The active core's
instruction API now accepts an optional stop predicate and reports whether an
instruction actually executed. The predicate runs after interrupt dispatch,
before fetching/executing the instruction. A pending-instruction flag and a
runtime device-preparation flag keep resume/step from repeating interrupt or
peripheral work. Breakpoints do not modify guest instructions.

Disassembly and validated address/number conversions live in `src/debugger.*`;
the window lives in `src/macos/DebuggerWindow.*`. These additions are independent
fork work under the existing GPL-2.0-or-later terms. The archived upstream copies
remain unchanged. See [the debugger guide](DEBUGGING.md) for behavior and limits.

## Validation environment

Apple Silicon (`arm64`), macOS 27.0, Apple Command Line Tools. Build uses C++17, AppKit and system zlib with flex/bison for assembler generation. Minimum deployment target is 12.0; there is no verified Intel or older-macOS release yet.

`make test` exercises the processor and original guest system. `make sanitize` compiles the suite separately with AddressSanitizer and UndefinedBehaviorSanitizer and stops on undefined behavior. These tests establish a baseline, not full instruction-set conformance; the remaining instruction families and full 3CC semantics still need broader coverage before deeper architectural rewrites. The added compiler integration/sanitizer suite is described below.

## 3CC revival — 2026-09-24

The active compiler in `src/3cc/` derives from the later archived GitHub version,
not the 0.5 compiler. Original copyright headers are retained and modified copies
carry dated notices. All original archives remain byte-for-byte unchanged.
`resources/memory_image_3cc/` contains unchanged copies of the GitHub guest sources.
The app bundles both the original assembly OS and the freshly compiled 3CC OS.

Changes include C++17/arm64 portability, initialized compiler state, exceptions
by value, checked literals/array sizes/constant arithmetic, staged output, proper
comments and string encoding, and actionable diagnostics. Regression tests drove
fixes for mixed-width call arguments, array arguments, constant remainder, swapped
compound OR/XOR, high-word tritwise operands, logical operand normalization, and
stack restoration when continuing from a nested scope. The original code generator
and ternary language remain recognizable; this is not an ISO C frontend replacement.
See [COMPILER.md](COMPILER.md) for commands and explicit limitations.

## Ternary Vision Lab addition — 2026-09-24

Version 0.8 adds an independent AppKit vision laboratory and a new 3CC guest
network, with packed ternary parameters and a separately trained float32 baseline.
Original CPU, compiler and archive provenance is unchanged. New code is GPL-2.0-or-later;
UCI digit data and learned numerical assets carry separate CC BY 4.0 attribution.
The app builds offline and gains no entitlements or external ML dependencies.
See [VISION-LAB.md](VISION-LAB.md) for training provenance, validation and limits.
