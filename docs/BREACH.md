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
the map: blue walls, yellow objectives and player, red patterned sentinel markers.

| Key | Action |
| --- | --- |
| W / S | Move forward / backward |
| A / D | Turn left / right |
| Q / E | Strafe left / right |
| Space | Fire the pulse tool |
| M | Toggle the map |
| R | Restart after winning, losing, or at any time |
| ⌘P | Pause / resume the machine |
| ⌘U | Mute / unmute game sound (also available beside the display) |
| ⌘D | Inspect the running guest in the debugger |
| ⌘B | Return to the original Tunguska OS |

Movement is step-based. Since 0.14.1, holding movement/turn keys repeats every
75 milliseconds when the guest is ready, without macOS's typing delay. Holding
Space repeats at 180 milliseconds; map and restart remain single-press actions.
Releasing keys, changing focus or pausing clears held-key state; slow frames do
not accumulate a backlog of repeats. Since 0.15.1, combat advances only on
successful movement or firing. Turning to aim, map use, blocked movement, empty
weapon clicks and waiting cannot advance an enemy attack. A nearby sentinel
first shows **SENTINEL TARGETING YOU**; each eight exposed movement/firing actions
can then cost one health point, even if several sentinels are nearby. Moving out
of range or behind cover clears the buildup. This remains action-paced combat,
not a wall-clock cooldown. A shot consumes one round; a hit disables one sentinel.
Walls block both shots and sentinel attacks. The exit requires all three cells,
but disabling every sentinel is optional. The game remains one level, without
saved games, mouse aiming, or original Doom asset compatibility.

Version 0.15.0 adds teal corridors, red/orange sentinels, green reactor cells,
cyan supplies, a purple exit and yellow muzzle flashes. Ten original synthesized
effects cover shots, sentinel kills, cells, supplies, damage, victory, defeat,
an empty weapon, footsteps and startup. The mute setting persists across launches.
Pausing or moving focus away silences the game; missed sounds are discarded.
If an output device is unavailable, the game continues with sound disabled.

Hits add a red border, and health turns red at three points or less. At zero
health the screen says **YOU WERE DEFEATED — HEALTH DEPLETED BY SENTINELS** and
**PRESS R TO RESTART**. The earlier “SIGNAL LOST” wording meant defeat, not a
display, network or application failure.

## What really runs on the ternary machine?

The `.3c` source implements integer DDA ray casting, sprite projection and wall
occlusion, collision checks, combat, pickups, the map and the bitmap HUD. It uses
81 coordinate units per tile and a 36-direction integer lookup table. All of this
compiles to ordinary Tunguska instructions. The image contains no native game code.

The 324 × 243 display keeps six trit pixels packed in each tryte. The fork's new
palette raster mode adds one palette attribute per six-pixel group, selecting
three colors from a guest-controlled table. Breach uses twelve palettes. The
guest chooses every attribute. The initial color release preserved 0.14.1's
bitmap geometry; 0.15.1 adds damage indicators and clearer defeat text.
Wall columns are six pixels wide. A guest assembly loop fills spans six rows at
a time, and the original AGDP block-set peripheral clears horizontal regions.
The frontend converts the bitmap and attributes to display pixels. There are
no new CPU instructions, host ray caster, or GPU game renderer. Python generates
only static map, font, palette and integer ray-direction data at build time.

The extension is specified in `src/display_protocol.h`: raster mode −1 with
auxiliary −1 uses bitmap address −264262, attributes at −251140 and 729
three-color palettes at −238018. A signed attribute selects palette 0 through
728 after adding 364; each palette entry is an ordinary 729-color tryte.
Existing raster modes retain their behavior. This color guest requires 0.15.0
or later; it is not display-compatible with the unmodified original frontend.

Sound events also originate in guest code, through a separate 27-slot ring with
26 usable entries. The Mac sound device consumes at most 26 events per poll,
ignores unknown IDs and coalesces repeated IDs in that poll. It synthesizes the
ten effects at startup, then mixes at most eight voices in a 48 kHz audio callback
without allocation or locks. Native audio plays the guest's commands; the ternary
CPU still decides when shots, hits and other events occur. No recordings or
external sound assets are used, and no new app permissions are required.

The game uses a bounded 26-event guest keyboard queue, consuming at most four
events before drawing another frame. Overflow drops newly arriving events. The
Mac frontend permits up to 120,000 guest instructions with a nine-millisecond
cooperative execution budget per timer tick when input arrives or a frame is
being built. It returns to 18,000 instructions and seven milliseconds when idle. This is
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
| 80040 / 80041 | Sound queue read / write positions |
| 80025 | Exposed movement/firing actions toward the next attack (0–7) |
| 85000 | 27-slot sound ring (one slot kept empty) |

## Build and validation

```sh
make app breach-check breach-sanitize audio-check audio-sanitize audio-device-check
```

The build generates `build/breach_assets.3h` and compiles
`resources/breach/breach.3c` into `build/breach.ternobj`. You can also open that
image using **File → Open Memory Image** in version 0.15.0 or later. For disassembly output:

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
game with the instrumented 3CC and executes it under ASan/UBSan. Sound assertions
cover each gameplay event and a full queue; separate audio tests check queue
corruption, waveform bounds, mixing, voice limits and mute. Core tests exercise
all 729 palette indices. The native audio test silently exercises the real output
callback and its owned mixer lifetime, including under ASan/UBSan. It requires
access to a working Mac audio output device.

The 0.15.1 regressions reproduce the former death-by-turning problem and verify
safe aiming, blocked movement, empty firing, map/idle safety, warning grace,
retreat reset, a single damage point from overlapping sentinels, red hit feedback,
death and restored health/attack state after restart.

`make breach-benchmark` reports guest frame CPU time, executed instructions and
a 60 Hz scheduling estimate over 210 frames. Set `BREACH_REFERENCE=/path/to/old.ternobj`
to compare geometry and game state against an earlier image, including every viewing
direction from five positions, map toggles, movement, firing and restart. Both
images then use the current CPU implementation. The candidate uses 120,000
instructions / 9 ms for active rendering; the reference defaults to the 0.14.1
100,000 / 7 ms policy, with frame yielding. Add
`BREACH_REFERENCE_FLAGS=--legacy-schedule` for the original 0.14.0 reference
policy (18,000 instructions unless the guest reports busy, then 100,000; 7 ms
without frame yielding). RGB pixels are compared when the
modes match; the complete packed bitmap is compared across palette/monochrome
modes. To measure the old CPU too,
compile `tests/breach_performance.cc` with `-DTUNGUSKA_BASELINE_RUNTIME`, the old
release's `src` include path and its runtime/core object files. The harness uses
applicable execution caps but omits timer sleeps, AppKit drawing and actual audio
callback cost; its
tick estimates are not measured keyboard-to-screen latency or a guarantee of FPS.

On this Apple M5 Max, the original 0.14.0 CPU/runtime and guest took **36.87 ms
median / 43.89 ms p95** of CPU time per benchmark frame. The 0.14.1 candidate took
**13.52 ms median / 19.03 ms p95**, a **2.73× median reduction in CPU time**. The
60 Hz scheduling estimate fell from 100 ms to 33.3 ms median. The paired image
comparison passed all 210 pixel/state comparisons. These measurements cover the
fixed benchmark scene set, not full application latency or all machines; held-key
input improvements are separate. See `docs/benchmarks/breach-m5-max.txt` for the
measurement context and raw summaries.

The 0.15.0 color update measured **15.58 ms median / 22.23 ms p95** frame CPU
time versus **13.78 / 19.45 ms** for the monochrome 0.14.1 guest in the same run.
The scheduling estimate stayed at **33.3 ms median / 50 ms p95** for both, after
the bounded active-frame slice increase. All 210 geometry/state comparisons
passed. Color costs approximately 1.8 ms more median CPU time here; this does not
claim identical real-world input latency or include native audio rendering.
See `docs/benchmarks/breach-color-m5-max.txt`.

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

### 0.15.0 color and sound update

Version **0.15.0 (build 14)** was built from
`d0ad9503e82dce069f04f5bb764188c29fe20bef`. All clean universal release gates
passed, including normal/sanitized game and audio tests, the actual native audio
callback, exhaustive palette indices, and App Sandbox checks. Boot took 265,984
guest instructions; the largest integration-test frame took 308,224.
Apple accepted submission `7edfed81-790a-485d-bac6-fa983d01c18c`.

The final ZIP was extracted and verified against its manifest, including bundle
hashes, timestamped Developer ID signing, minimal entitlements, hardened runtime,
stapled notarization, Gatekeeper acceptance and both architecture slices. Matching
source and distribution checksums passed. The exact signed bundle was installed
at `build/Tunguska.app`; color, movement, a successful shot, the map and mute/unmute
were checked there. Sound output and waveform tests ran on ARM64; Intel and older
macOS runtime validation remain outstanding.

Distribution files are in `build/releases/0.15.0-d0ad9503e82d/`:
`Tunguska-0.15.0-universal2.zip`,
`Tunguska-0.15.0-source-d0ad9503e82d.tar.gz`, and `SHA256SUMS`.
Distribute all three together. No public binary release was uploaded.

### 0.15.1 combat feedback fix

Version **0.15.1 (build 15)** was built from
`84db05b665bf27a8d647a7735e343ad28e328289`. The old game failed the new regression:
three forward moves followed by 36 turns killed a healthy player. The fixed game
passes that case and the attack grace, retreat, overlapping-enemy, hit-feedback,
death/restart and existing gameplay checks. Normal and ASan/UBSan runs passed;
the largest tested frame took 325,120 instructions, within the unchanged 350,000
instruction regression limit. All clean universal release gates passed.

Apple accepted submission `35482d6e-c333-4e98-9211-84d37471a432`. The final ZIP,
matching source/checksums, bundle hashes, Developer ID signature, hardened runtime,
minimal entitlements, stapled ticket, Gatekeeper and both architecture slices
were verified. The exact signed app was installed at `build/Tunguska.app`.
A native UI check repeated the corridor/turn sequence: health remained nine and
the targeting warning stayed visible. The game was restarted for the user.
Runtime validation was on ARM64; Intel/older macOS remain untested.

Distribution files are under `build/releases/0.15.1-84db05b665bf/`:
`Tunguska-0.15.1-universal2.zip`,
`Tunguska-0.15.1-source-84db05b665bf.tar.gz`, and `SHA256SUMS`.
Distribute them together. No public binary release was uploaded.

## Authorship and rights

The game source, map, simple pixel font, sprite designs, color palettes and
synthesized sounds are new work in Vinny
Lingham's independent Mac fork, released under GPL-2.0-or-later. Original Tunguska,
its instruction set, 3CC and guest peripherals remain credited to Viktor Lofgren.
No Doom code, levels, names of characters, graphics, music or sound files are
bundled. No endorsement by id Software or the original Tunguska author is claimed.
