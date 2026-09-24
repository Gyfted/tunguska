# Tunguska for Mac

A native Mac revival of [Viktor Lofgren’s Tunguska](https://tunguska.sourceforge.net/): a computer whose digits are **−1, 0, +1**. This first working port retains the original processor, assembler, and operating system, with a new AppKit interface and a C++17 build.

**Original creator:** [Viktor Lofgren](https://github.com/vlofgren). **This fork's maintainer:** [Vinny Lingham](https://github.com/Gyfted).

This is an independently maintained fork of [vlofgren/tunguska](https://github.com/vlofgren/tunguska), not an official transfer of the original project. No endorsement by the original author is claimed. The Mac port began from the official 0.5 source release; the original GitHub history and source are also preserved. See [AUTHORS](AUTHORS), [NOTICE.md](NOTICE.md), and [source provenance](docs/PORTING.md).

This README was adapted for the Mac fork on 2026-09-24; the original GitHub README is preserved in `upstream/github/README.md`.

## Run

Open `build/Tunguska.app`, or rebuild from this directory:

```sh
make -j4
open build/Tunguska.app
```

Requires Apple’s Xcode Command Line Tools (`xcode-select --install`). No Homebrew packages, SDL, or other downloads are required to build. The local build is native **arm64**, tested on Apple Silicon with macOS 27. The deployment target is macOS 12; older systems and Intel Macs have not been tested. The app is locally ad-hoc signed, not notarized for distribution. This repository publishes source; it does not yet offer an official binary release.

Click the display and type `HELP`, then Return. Commands are uppercase. The sidebar also launches the original demos. A demo button boots a fresh bundled system before entering its command; Reset reloads the current image and clears the virtual disk.

| Control | Action |
| --- | --- |
| Run / Pause, ⌘P | Start or stop the processor |
| Step, ⌘. | Execute one instruction, leaving the machine paused |
| Reset, ⌘R | Reload the selected memory image |
| Open Image, ⌘O | Boot a complete `.ternobj` memory image |
| ⌘B | Return to the bundled original operating system |
| Escape | Send the guest Break interrupt |
| ⌘V / ⌘C | Paste guest text / copy the displayed text |
| Mount Disk, ⌘M | Attach a virtual floppy image |
| Save Disk As, ⌘S | Export the current virtual floppy |

The guest’s `LOAD` command no longer opens host paths. Use **Mount Disk**, then `FDSTAT` or `RUN` in the guest. Guest disk writes stay in memory; use **Save Disk As** to persist them. Disk images and memory images contain the same complete 531,441-tryte storage format, but are loaded into different devices.

## Build a program

```sh
build/tg_assembler -o build/hello.ternobj examples/hello.asm
```

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
```

Tests cover every pair of tryte values for addition and multiplication, all 531,441 word conversions, 2,125,764 ADD/CMP instruction cases, memory boundaries, bounded interrupts, image roundtrips and rejection of malformed images, original OS boot and keyboard commands, pause/step/reset, and the original text/vector/raster demos. `sanitize` runs the same suite with AddressSanitizer and UndefinedBehaviorSanitizer.

The Mac UI was also exercised directly: boot, typed `HELP`, pause, single step, reset, vector rendering, and mouse input in the 729-color drawing program.

A [targeted security review](docs/SECURITY-REVIEW.md) added malformed-image, guest file-access, floating-point boundary and randomized instruction checks. It found and fixed three additional arithmetic issues. This preview is not yet OS-sandboxed or independently audited; use trusted images.

## Layout and next work

- `src/core/` — adapted original CPU, balanced ternary math, memory, interrupts, disk and coprocessor.
- `src/runtime.*` — window-independent execution, input, and display snapshots.
- `src/macos/` — native AppKit window, keyboard/mouse input, graphics and file dialogs.
- `src/assembler/` — original two-pass assembler, built with Apple’s flex/bison.
- `resources/memory_image_asm/` — original guest OS assembly.
- `upstream/tunguska-0.5/` — untouched source release, including its manual and experimental 3CC compiler.
- `upstream/github/` — unchanged files from the original GitHub repository, whose commit history remains the ancestry of this fork.

This is a working port, not a complete rewrite. The next useful additions are a disassembler and memory inspector, breakpoint debugging, a modernized 3CC compiler, and a signed universal release. The old 3CC compiler is preserved but is not part of this build. The original guest software and instruction set have not been exhaustively validated beyond the tests above.

See [provenance and port notes](docs/PORTING.md) for the changes to the original implementation.

## License

The Tunguska software and this derivative port are distributed under GNU GPL version 2 or later (`GPL-2.0-or-later`), as specified in the original source headers. Original emulator, assembler, operating system, assets, and documentation by **Viktor Lofgren**. Existing copyright and warranty notices are preserved. Third-party build-support files retain their own notices and terms. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

This software is provided without warranty, including implied warranties of merchantability or fitness for a particular purpose. You may redistribute and modify it under the applicable GPL terms. Future binary releases must include matching complete source and build scripts; see [the release procedure](docs/RELEASING.md).
