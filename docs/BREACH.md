# Ternary Breach

An original, small first-person game compiled with Viktor Lofgren's 3CC and
executed on Tunguska's emulated ternary CPU. Introduced in 0.14.0 (build 12).
This is a Doom-style experiment, not a port of Doom or its engine.

## Play

Choose **Ternary Breach** in the sidebar or **Machine → Play Ternary Breach (⌘5)**.
Starting a game replaces the current guest memory and ejects its virtual disk,
just like the existing demo launchers. Click the display if it lacks keyboard focus.

Recover the three reactor cells, then enter the exit in the northeast corner.
Four stationary sentinels guard the corridors. Shoot them or avoid their range.
A supply cache in the southwest restores health and adds ammunition. **M** shows
the map: gray walls, white objectives and player, patterned sentinel markers.

| Key | Action |
| --- | --- |
| W / S | Move forward / backward |
| A / D | Turn left / right |
| Q / E | Strafe left / right |
| Space | Fire the pulse tool |
| M | Toggle the map |
| R | Restart after winning, losing, or at any time |
| ⌘P | Pause / resume the machine |
| ⌘D | Inspect the running guest in the debugger |
| ⌘B | Return to the original Tunguska OS |

Movement is step-based. Since 0.14.1, holding movement/turn keys repeats every
75 milliseconds when the guest is ready, without macOS's typing delay. Holding
Space repeats at 180 milliseconds; map and restart remain single-press actions.
Releasing keys, changing focus or pausing clears held-key state; slow frames do
not accumulate a backlog of repeats. Combat advances on player actions;
sentinels can damage a nearby, visible player every fourth action. Waiting does
not cause damage. A shot consumes one round; a hit disables one sentinel.
Walls block both shots and sentinel attacks. The exit requires all three cells,
but disabling every sentinel is optional. This first version is one level, with
no sound, saved games, mouse aiming, or original Doom asset compatibility.

## What really runs on the ternary machine?

The `.3c` source implements integer DDA ray casting, sprite projection and wall
occlusion, collision checks, combat, pickups, the map and the bitmap HUD. It uses
81 coordinate units per tile and a 36-direction integer lookup table. All of this
compiles to ordinary Tunguska instructions. The image contains no native game code.

The display is the existing 324 × 243 three-color framebuffer: every pixel is a
trit (black, gray or white). Wall columns are six pixels wide. A small guest
assembly loop fills vertical spans six rows at a time, and the original AGDP block-set peripheral
clears horizontal regions. The existing Mac frontend converts the guest framebuffer
to display pixels. There are no new CPU instructions, host ray caster, or GPU game
renderer. Python generates only static map/font/trigonometric data at build time.

The game uses a bounded 26-event guest keyboard queue, consuming at most four
events before drawing another frame. Overflow drops newly arriving events. The
Mac frontend permits up to 100,000 guest instructions per timer tick when input
arrives or a game frame is being built, retaining the existing seven-millisecond execution budget.
It returns to the normal 18,000-instruction quota when the guest is idle. This is
an emulation scheduling choice, not a ternary speedup claim. A captured game frame
yields back to AppKit immediately. Static HUD text is retained; only changing
numbers and messages are redrawn. Font copies use short guest assembly sequences.
The CPU still interprets every instruction; it now splits instruction codes using
their numeric value instead of constructing and shifting temporary trit arrays.
All 729 encodings are checked against the original decoding operations.

The guest memory layout is in `src/breach_protocol.h`. Useful debugger addresses:

| Address | Contents |
| --- | --- |
| 80000 | Status: 1 busy, 2 ready, 3 won, −1 lost |
| 80002–80005 | Health, ammo, disabled sentinels, collected cells (trytes) |
| 80010 / 80012 | Player X / Y (two-tryte words) |
| 80014 / 80016 | Angle / completed-frame count (words) |
| 81000 | 12 × 12 map |
| 82000 | Four sentinel alive flags |
| 83000 | 54 wall distances (words) |
| 84000 | 27-slot keyboard ring (one slot kept empty) |

## Build and validation

```sh
make app breach-check breach-sanitize
```

The build generates `build/breach_assets.3h` and compiles
`resources/breach/breach.3c` into `build/breach.ternobj`. You can also open that
image using **File → Open Memory Image**, including in a compatible older build;
older frontends retain their lower instruction quota. For disassembly output:

```sh
python3 scripts/compile_3cc.py -S -I build resources/breach/breach.3c -o build/breach.asm
```

The integration tests execute the compiled game on the real guest interpreter.
They cover boot/display colors, movement, wall collision, turning, strafing,
map toggling, shooting and wall occlusion, empty ammo, sentinel damage/death,
restart, rapid input, supplies, and collection of all three cells followed by
escape. An independent BFS supplies the route for the navigation test; it uses
guest movement commands with sentinels disabled and sets cardinal headings to
isolate navigation from the separately tested combat and turning. It is not a
claim that an autonomous player completed combat. Each tested frame must finish
within 350,000 guest instructions. The sanitizer target also compiles the
game with the instrumented 3CC and executes it under ASan/UBSan.

`make breach-benchmark` reports guest frame CPU time, executed instructions and
a 60 Hz scheduling estimate over 210 frames. Set `BREACH_REFERENCE=/path/to/old.ternobj`
to compare pixels and game state against an earlier image, including every viewing
direction from five positions, map toggles, movement, firing and restart. Both
images then use the current CPU implementation; the reference uses the old
instruction quotas and does not yield after capture. To measure the old CPU too,
compile `tests/breach_performance.cc` with `-DTUNGUSKA_BASELINE_RUNTIME`, the old
release's `src` include path and its runtime/core object files. The harness uses
the same seven-millisecond cap but omits timer sleeps and AppKit drawing; its
tick estimates are not measured keyboard-to-screen latency or a guarantee of FPS.

On this Apple M5 Max, the original 0.14.0 CPU/runtime and guest took **36.87 ms
median / 43.89 ms p95** of CPU time per benchmark frame. The 0.14.1 candidate took
**13.52 ms median / 19.03 ms p95**, a **2.73× median reduction in CPU time**. The
60 Hz scheduling estimate fell from 100 ms to 33.3 ms median. The paired image
comparison passed all 210 pixel/state comparisons. These measurements cover the
fixed benchmark scene set, not full application latency or all machines; held-key
input improvements are separate. See `docs/benchmarks/breach-m5-max.txt` for the
measurement context and raw summaries.

## Release verification — September 25, 2026

Version **0.14.0 (build 12)** was built from
`6dcc9f898677ea5d88adbe84ef13013217b98b67`. The clean universal build passed core,
assembler, compiler, image-mutation, Vision, Explorer, Breach, GPU, search,
AppKit, sanitizer, release-integrity and real App Sandbox gates. The game boot
frame took 381,184 guest instructions; the largest frame in the integration suite
took 451,840. These are instruction counts, not an end-to-end speed comparison.
Native UI checks verified launching, movement, firing, map toggling and debugger
single-stepping. Launching, movement and a successful shot were repeated in the
final notarized app.

Apple accepted notarization submission
`0b31b1d3-18a5-4f02-956f-fb1ed911cb4a`. The final ZIP was extracted and checked
for matching bundle hashes, timestamped Developer ID signing, exact minimal
entitlements, hardened runtime, stapled notarization, Gatekeeper acceptance and
both `arm64` and `x86_64` slices. Matching source, ZIP and distribution checksums
were also verified. Runtime tests ran on ARM64; Intel and older macOS runtime
validation remain outstanding.

Local distribution files are under `build/releases/0.14.0-6dcc9f898677/`:
`Tunguska-0.14.0-universal2.zip`,
`Tunguska-0.14.0-source-6dcc9f898677.tar.gz`, and `SHA256SUMS`.
Distribute all three together with the included notices. No public GitHub binary
release was published by this work.

### 0.14.1 responsiveness update

Version **0.14.1 (build 13)** was built from
`45e3b9aceb37a8fae34581538e98b6ab77deeb28`. The full clean universal release gates
passed, including the new input, instruction-decoding and frame-yield regressions,
and normal/sanitized game runs. The integration suite's largest frame was 269,312
instructions. Apple accepted submission
`88289bff-b2d9-4315-8007-74b6dae23015`.

The final ZIP was extracted and its bundle hashes, Developer ID signature,
minimal entitlements, hardened runtime, notarization ticket, Gatekeeper acceptance
and both architecture slices were independently verified. Source/ZIP/checksums
matched the manifest. The exact signed app was installed at `build/Tunguska.app`
and launched; movement and turning were verified there. Earlier native smoke
checks also covered shooting, map, pause/resume and ordinary OS `HELP` typing.
Only ARM64 was runtime-tested.

Distribution files are in `build/releases/0.14.1-45e3b9aceb37/`:
`Tunguska-0.14.1-universal2.zip`,
`Tunguska-0.14.1-source-45e3b9aceb37.tar.gz`, and `SHA256SUMS`.
Distribute these together. No public binary release was uploaded.

## Authorship and rights

The game source, map, simple pixel font and sprite designs are new work in Vinny
Lingham's independent Mac fork, released under GPL-2.0-or-later. Original Tunguska,
its instruction set, 3CC and guest peripherals remain credited to Viktor Lofgren.
No Doom code, levels, names of characters, graphics, music or sound files are
bundled. No endorsement by id Software or the original Tunguska author is claimed.
