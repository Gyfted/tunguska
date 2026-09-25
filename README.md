# Tunguska for Mac

A native Mac revival of [Viktor Lofgren’s Tunguska](https://tunguska.sourceforge.net/): a computer whose digits are **−1, 0, +1**. The port retains the original processor, assembler, 3CC compiler, and operating systems, with a new AppKit interface and a C++17 build.

**Original creator:** [Viktor Lofgren](https://github.com/vlofgren). **This fork's maintainer:** [Vinny Lingham](https://github.com/Gyfted).

This is an independently maintained fork of [vlofgren/tunguska](https://github.com/vlofgren/tunguska), not an official transfer of the original project. No endorsement by the original author is claimed. The Mac port began from the official 0.5 source release; the original GitHub history and source are also preserved. See [AUTHORS](AUTHORS), [NOTICE.md](NOTICE.md), and [source provenance](docs/PORTING.md).

This README was adapted for the Mac fork on 2026-09-24; the original GitHub README is preserved in `upstream/github/README.md`.

## Run

Open `build/Tunguska.app`, or rebuild from this directory:

```sh
make -j4
open build/Tunguska.app
```

Requires Apple’s Xcode Command Line Tools (`xcode-select --install`). No Homebrew packages, SDL, or other downloads are required to build. The local build is native **arm64**, tested on Apple Silicon with macOS 27. The deployment target is macOS 12; older systems and Intel Macs have not been runtime-tested. The release script also builds a universal app with arm64 and x86_64 slices. The app enables **App Sandbox and hardened runtime**, but is locally ad-hoc signed and not notarized for distribution. This repository publishes source; it does not yet offer an official binary release.

Click the display and type `HELP`, then Return. Commands are uppercase. The sidebar separates the computer, three experiments, and original demos. Use **View → Appearance** for System, Light, or Dark mode. Lab pages scroll to keep controls reachable in smaller windows; window sizes and your appearance choice are remembered. A demo button boots a fresh bundled system before entering its command; Reset reloads the current image and clears the virtual disk.

| Control | Action |
| --- | --- |
| Local Search, ⌘F | Search a selected folder of text, Markdown and PDFs offline |
| Ternary Breach, ⌘5 | Play an original first-person game on the ternary CPU |
| Computer, ⌘1 | Return to the original machine without resetting it |
| Vision Lab / Explorer / Weight Race, ⌘2 / ⌘3 / ⌘4 | Switch experiments; the existing ⌘L / ⌘E / ⌘G shortcuts also work |
| Run / Pause, ⌘P | Start or stop the processor |
| Step, ⌘. | Execute one instruction, leaving the machine paused |
| Debugger, ⌘D | Pause and open disassembly, breakpoints, registers and memory |
| Ternary Vision Lab, ⌘L | Draw digits, run ternary neural inference, inspect neurons and benchmark |
| Ternary Explorer, ⌘E | Edit a maze and watch a ternary guest navigate with incomplete knowledge |
| Weight Race, ⌘G | Compare packed ternary and FP16 weights using the native Mac GPU |
| Reset, ⌘R | Reload the selected memory image |
| Open Image, ⌘O | Boot a complete `.ternobj` memory image |
| ⌘B | Return to the bundled original operating system |
| Escape | Send the guest Break interrupt |
| ⌘V / ⌘C | Paste guest text / copy the displayed text |
| Mount Disk, ⌘M | Attach a virtual floppy image |
| Save Disk As, ⌘S | Export the current virtual floppy |

Opening a lab pauses the original machine. Use the **Computer** button or ⌘1 to return, then **Run** to resume. Machine and file commands apply to the active computer window; debugger Run/Step commands target that debugger. See [the interface guide](docs/INTERFACE.md) for navigation and shortcuts.

The guest’s `LOAD` command no longer opens host paths. Use **Mount Disk**, then `FDSTAT` or `RUN` in the guest. Guest disk writes stay in memory; use **Save Disk As** to persist them. The app uses macOS-coordinated replacement files for atomic saves without requesting access to the enclosing folder. Symbolic-link destinations are rejected. Disk images and memory images contain the same complete 531,441-tryte storage format, but are loaded into different devices.

The app requests only App Sandbox and user-selected file read/write access. There are no network, camera, microphone, broad-folder, JIT or hardened-runtime-exception entitlements. Open and Save dialogs authorize individual files or the folder explicitly selected for Local Search; the current memory image's URL is retained so Reset can reopen it. No persistent file bookmarks are stored. The developer CLI, assembler and 3CC compiler are separate, unsandboxed tools and are not included in the distributed app.

## Ternary Breach

Choose **Ternary Breach** in the sidebar or press **⌘5**. Recover three reactor
cells, evade or disable four sentinels, and find the exit. **W/S** move, **A/D**
turn, **Q/E** strafe, **Space** fires, **M** shows the map and **R** restarts.
The original one-level game is compiled with 3CC: ray casting, sprites, collision,
combat and HUD drawing all run on the ternary guest. It uses the existing
324 × 243 three-color display and original graphics peripheral. This is a small
Doom-style experiment with new assets, not original Doom or a performance claim.
See [the game guide](docs/BREACH.md) for controls, architecture and tests.

## Local Search

Open **Local Search** (⌘F), choose a folder, and search text, Markdown and PDFs
with selectable text. Results include excerpts and PDF page numbers. Optional
English meaning search finds related ideas using an installed Apple sentence
model, ternary candidate scoring and original-vector reranking. The index stays
in memory; Refresh picks up edits and Forget folder clears it.

The built-in comparison measures query preparation, ranking and excerpts against
SQLite FTS5 or an Accelerate FP32 semantic baseline, checks result agreement, and
exports every sample. It reports a 2× target only when the measurements pass.
Keyword gains come from the native inverted index; a ternary semantic speedup is
not assumed. The recorded M5 Max run achieved 12.00× for keyword search and
0.98× for meaning search; these exclude indexing and screen drawing. See [the search guide](docs/SEARCH.md) for measurements, input limits,
privacy and the distinction between pipeline latency and visible UI latency.

## Inspect and debug

Open **Debugger** (⌘D) to pause execution. Inspect instructions and registers, use **Step** to execute one instruction, or **Continue** to run. Double-click an instruction to toggle its breakpoint, or enter an address and choose **Toggle breakpoint**. Continue passes the breakpoint you just hit once, so loops stop again on the next visit. Breakpoints also catch interrupt handlers before their first instruction.

The memory inspector shows decimal, balanced nonary, and all six trits. Enter a decimal address such as `198697`, or a nonary address such as `333:D04`, then **Go**. **Follow PC** follows execution in the disassembly while the memory view stays at your chosen address. Reset or loading another image clears breakpoints. See [the debugger guide](docs/DEBUGGING.md) for a walkthrough and limitations.

## Ternary Vision Lab

Open **Ternary Vision Lab** from the sidebar. Draw a digit or browse 1,797 historical
test examples. Drawings automatically center and resize; blank inputs are rejected
and close calls say **Not sure**. Run the same ternary network on the guest CPU
or directly in **Fast on Mac** mode. Inspect neurons, debug the guest, explore a
mistake browser with pixel-erasure sensitivity, and export detailed JSON reports.

On the existing benchmark, raw ternary accuracy is **96.10%** (previously 95.21%);
float32 and weight-only 8-bit baselines each reach **97.38%**. With uncertainty
handling, ternary answers 96.83% of inputs with 97.82% accuracy among those answers.
The 3,996 ternary weights occupy **800 packed bytes**, versus 15,984 float32 bytes
or 3,996 8-bit bytes (biases add 256 bytes each; 8-bit adds 8 bytes of scales).

Generated guest code uses about **42× fewer instructions** than the preserved
3CC reference for the same model. Executable/working memory is additional to
weight payloads; this does not establish a ternary hardware advantage. Everything
runs offline. See [the lab guide](docs/VISION-LAB.md) for controls, reproducible
training, licensing, and the limits of this historical benchmark.

## Ternary Explorer

Open **Ternary Explorer** in the sidebar (⌘E) and click **Run**. The left map is
the real maze; the right is the robot's knowledge: **−1 blocked, 0 unknown,
+1 observed clear**. A compiled 3CC guest searches that observed map and chooses
each route. The simulator supplies sensor readings and enforces physical walls;
it never gives the guest the hidden world.

Edit walls while it runs, step one turn, or **Debug brain** to step actual ternary
instructions. Try **Explore first**, intermittent sensor readings, or a smaller
battery to see the robot change its decisions or return to base. Three presets
include a reproducible seeded maze. Restart preserves your edits, recharges and
clears the robot's knowledge. Export the current maps and decision history as JSON.

This is an offline simulation and an example of explicit three-state reasoning,
not evidence of faster ternary hardware or a physical robot controller.
See [the Explorer guide](docs/EXPLORER.md) for controls, planning rules, memory
addresses, validation and limits.

## Weight Race

Open **Weight Race** (⌘G) and press **Compare all sizes**. It runs the same
matrix-vector calculation with FP16 weights, packed two-bit ternary weights,
and Apple's MPS matrix library as an additional FP16 baseline. Every output is
checked against an independent exact reference. Weight-memory bars, GPU timings,
sample ranges and JSON exports separate the guaranteed 8× smaller weight buffers
from any measured speed benefit. Select a completed layer in the results table or the selector above the charts to revisit it. Small layers may see no benefit.

This is native Metal execution on binary hardware, separate from the guest CPU.
It tests a synthetic layer with already-ternary weights, not trained-model
accuracy or energy efficiency. See [the benchmark guide](docs/WEIGHT-RACE.md)
for measurement details, reproducibility and limitations.

## Build a program

```sh
build/tg_assembler -o build/hello.ternobj examples/hello.asm
```

To compile a 3CC program instead:

```sh
python3 scripts/compile_3cc.py examples/hello.3c -o build/hello-3cc.ternobj
```

The new driver preprocesses guest headers, compiles and assembles an image, and
preserves existing output if a build stage fails. Choose **Machine → Boot
Experimental 3CC System** to run the original alternative OS, rebuilt with the
modern compiler; type `HELP` for its commands. See [the compiler guide](docs/COMPILER.md)
for language differences, examples and limitations.

Open `build/hello.ternobj` in the app. To rebuild the original OS, edit the assembly under `resources/memory_image_asm/` and run `make`.

For a quick run without a window:

```sh
build/tunguska-cli build/boot.ternobj HELP
```

## Verify

```sh
make test
make sanitize
make security-check
make assembler-check assembler-sanitize image-fuzz-check
make sandbox-check verify-app release-check
make compiler-check compiler-sanitize
make vision-check vision-sanitize
make explorer-check explorer-sanitize
make weight-check weight-sanitize weight-gpu-validation
make rendering-check rendering-sanitize
make search-check search-sanitize
```

Tests cover every pair of tryte values for addition and multiplication, all 531,441 word conversions, 2,125,764 ADD/CMP instruction cases, memory boundaries, bounded interrupts, image roundtrips and rejection of malformed images, original OS boot and keyboard commands, pause/step/reset, and the original text/vector/raster demos. `sanitize` runs the same suite with AddressSanitizer and UndefinedBehaviorSanitizer.

Debugger tests additionally roundtrip every memory address, decode all 729 instruction encodings, check every addressing mode at the memory boundary, and verify breakpoint/continue/step behavior in loops and interrupt handlers. Save tests force a compressed-write failure using a child process's file-size limit, verify the original file is unchanged and temporary output removed, and check successful replacement, permissions, and symbolic-link rejection.

Compiler integration tests execute arithmetic, mixed-size function calls, recursion, array parameters, nested-scope loop control, arrays, structs, tritwise and three-valued logic, and string fixtures. They reject malformed inputs while preserving existing output. The compiler suite also runs under ASan/UBSan, boots the original 3CC OS and checks `HELP` and the new greeting example. See [compiler validation](docs/COMPILER.md#validation).

Vision tests run all 1,797 held-out digits on the actual guest, requiring exact
hidden activation and score parity with an independent integer reference. They
also verify native ternary parity, float32/8-bit accuracy, 30 independent 3CC
reference runs, drawing preparation, uncertainty, model/data hashes, malformed inputs,
breakpoints, cancellation, failure rejection and instruction limits. A subset
runs under ASan/UBSan.

Explorer tests compare complete guest decisions/routes with an independent native
reference, exercise closed-loop missions across priorities and sensor modes, and
check unknown-cell exclusion, battery return, stale readings after wall edits,
corrupt outputs, instruction limits, pause/step/breakpoints and cancellation.
A bounded subset also runs under ASan/UBSan.

AppKit rendering tests draw Explorer's real-world and knowledge maps offscreen
in light and dark appearances, across all three worlds and multiple turns. They
also simulate an unavailable monospaced font: the old drawing code raised an
`NSInvalidArgumentException`, while the shared text attributes now use a fallback
font and omit unavailable values. This guards the map-label dictionary failure
reported in 0.12.0; the crash report did not identify the original missing value.
The rendering test is required by release preparation.

The Mac UI was also exercised directly: boot, typed `HELP`, pause, single step, reset, vector rendering, and mouse input in the 729-color drawing program.

The Vision Lab was exercised with blank and off-center drawings, normalization
on/off, uncertainty and mistake browsing, complete 1,797-input guest/native benchmarks,
guest stepping, pause/resume and validated sandboxed JSON exports.

The debugger was exercised in the native UI: pause on opening, breakpoint stops and re-entry, one-instruction stepping, address validation, boundary navigation, row breakpoint toggles, and breakpoint-list selection/removal.

A [targeted security review](docs/SECURITY-REVIEW.md) added malformed-image, guest file-access, floating-point boundary and randomized instruction checks. It found and fixed three additional arithmetic issues. The new signed sandbox test app verifies denied access to an unselected private file and denied outbound network access, plus successful boot and coordinated saves inside its container. Run `sandbox-check` from a normal macOS terminal; an enclosing sandbox may prevent macOS from creating the test app's container. Its disposable private-file fixture is removed afterward. This preview is not independently audited; use trusted images.

## Prepare a Mac release

From a clean, committed checkout, run `python3 scripts/release.py prepare`. It builds a universal app from an exported exact source commit, runs the test suites, and packages both a clearly marked local preview and the matching complete GPL source archive under `build/releases/`. It records architecture, compiler, checksums and source commit in a manifest.

Developer ID signing and Apple notarization require Apple Developer Program membership, an installed signing identity and a Keychain credential profile. The separate `notarize` command checks those prerequisites and never treats an ad-hoc preview as an approved release. See [the release procedure](docs/RELEASING.md) for setup and publication steps.

## Layout and next work

- `src/core/` — adapted original CPU, balanced ternary math, memory, interrupts, disk and coprocessor.
- `src/runtime.*` — window-independent execution, input, and display snapshots.
- `src/weight_benchmark.*`, `src/macos/WeightBenchmark.mm` and `resources/benchmark/` — native GPU weight-format comparison.
- `src/explorer.*` and `resources/explorer/` — ternary robot simulation, reference planner and 3CC navigation guest.
- `src/vision.*` and `resources/vision/` — offline ternary vision engine, trained assets and guest.
- `src/debugger.*` — read-only disassembly, address validation and number formatting.
- `src/macos/` — native AppKit window, keyboard/mouse input, graphics and file dialogs.
- `src/3cc/` — adapted original 3CC compiler, built as C++17.
- `scripts/compile_3cc.py` — preprocessing, compilation and assembly driver.
- `resources/memory_image_3cc/` — original alternative 3CC guest OS and headers.
- `src/assembler/` — original two-pass assembler, built with Apple’s flex/bison.
- `resources/memory_image_asm/` — original guest OS assembly.
- `upstream/tunguska-0.5/` — untouched source release, including its manual and experimental 3CC compiler.
- `upstream/github/` — unchanged files from the original GitHub repository, whose commit history remains the ancestry of this fork.

The debugger, memory inspector, breakpoints and modernized 3CC build are implemented. The universal 0.12.2 security-fix release candidate has passed Developer ID signing, Apple notarization and Gatekeeper assessment; see [the release procedure](docs/RELEASING.md). Ordinary local builds remain ad-hoc signed previews. Version 0.12.2 fixes the issues documented in the [security review](docs/SECURITY-REVIEW.md). Next priorities are stronger process isolation, broader instruction-set and compiler conformance tests, and source labels in the debugger. The original guest software, experimental 3CC language and instruction set have not been exhaustively validated beyond the tests above.

See [provenance and port notes](docs/PORTING.md) for the changes to the original implementation.

## License

The Tunguska software and this derivative port are distributed under GNU GPL version 2 or later (`GPL-2.0-or-later`), as specified in the original source headers. Original emulator, assembler, operating system, assets, and documentation by **Viktor Lofgren**. Existing copyright and warranty notices are preserved. The Vision Lab dataset and learned numerical assets use CC BY 4.0 with separate [attribution](resources/vision/VISION-NOTICE.md). Third-party build-support files retain their own notices and terms. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

This software is provided without warranty, including implied warranties of merchantability or fitness for a particular purpose. You may redistribute and modify it under the applicable GPL terms. Future binary releases must include matching complete source and build scripts; see [the release procedure](docs/RELEASING.md).
