# Ternary Explorer

Open **Ternary Explorer** from the main sidebar or **Machine → Ternary Explorer**
(⌘E). The original OS pauses; this lab uses a separate Tunguska machine. It is
an offline robot simulation with no camera, network or physical-device access.

## Explore a world

1. Keep **Switchback**, **Reach goal**, **Reliable scans** and **360 energy**,
   then press **Run**. The robot starts at B and seeks G. R marks its position.
2. Compare the actual world on the left with the robot's map on the right.
   The robot begins knowing only its own cell. Orange is **−1 blocked**, question
   marks are **0 unknown**, and green is **+1 observed clear**. The destination
   coordinate is given to the robot, but its cell remains unknown until observed.
3. Gold lines show the last accepted route; dots show travel history. Outlines
   on the knowledge map identify cells read by the latest scan. The dashboard
   explains the decision and shows battery, coverage and real guest instructions.
4. **Pause** stops automatic turns and any running guest. **Step turn** finishes
   one scan/decision; **Run/Resume** continues automatically. A scan costs one
   energy unit and a successful move costs one.
5. With **Toggle wall**, click cells in the left map to edit them. Arrow keys
   select a cell and Space applies the selected tool. Robot, base and goal cells
   are protected from walls. Moving the base or goal restarts the mission.
6. An edit during execution cancels the pending plan and triggers a fresh scan.
   The robot learns the change only if a reading reaches it. **Restart / recharge**
   preserves the edited world, restores the selected battery and clears knowledge
   and history. Changing mission options also restarts; changing presets replaces
   the world. **New maze** advances the seed for the seeded preset.
7. **Intermittent scans** deterministically drop some readings. Missing data leave
   old knowledge unchanged; they never imply clear ground. The robot may wait and
   scan again. Sensor dropouts are not false-positive or noisy range measurements.
8. **80 energy** demonstrates the return reserve. **Explore first** prefers nearby
   unexplored edges before taking a known route to the goal. Compare its coverage
   and extra movement with **Reach goal** on the same world and sensor setting.
9. **Export mission…** writes JSON through a sandboxed native Save panel. It includes
   the current world/knowledge, options, battery, moves and bounded decision history.
   Maps are snapshots at export time; this is not a complete replay of edits and
   cancelled scans. UI coordinates are one-based; exported cell IDs are zero-based,
   row-major (`cell = row * 15 + column`).

A cancelled plan may already have consumed its scan's energy. It never applies a
movement afterwards. A completed/stopped mission requires Restart before running
again. Restart does not undo maze edits; reselect the preset to restore its layout.

## The guest makes the decisions

`resources/explorer/navigator.3c` is compiled by the restored 3CC compiler and
assembled into `explorer.ternobj` on every relevant rebuild. The Mac simulates the
world, observations, battery and motion. It supplies the guest only the knowledge
map, robot/base/goal coordinates, energy, selected priority and return flag.
Neither hidden walls nor a precomputed route are copied into guest memory.

The guest runs a breadth-first search from the robot over **exactly +1** cells.
It records shortest distances and parents, then applies these deterministic rules:

1. If at the goal, stop successfully. If at most one energy unit remains, stop.
2. If already returning, or remaining energy is at most `2 × known distance to
   base + 6`, select the base. Stop when docked or if the return route is lost.
   Return mode remains set once selected. The factor of two budgets a scan and
   a move per remaining step; six units provide a small reserve.
3. **Reach goal** takes a known goal route as soon as one exists. **Explore first**
   does so when at least 192/225 cells are known (about 85%), or when no reachable
   frontier remains. Either mode finishes immediately on physically reaching G.
4. Otherwise, find reachable clear cells adjacent to at least one unknown cell.
   These are exploration frontiers. Reach-goal priority minimizes
   `4 × path distance + Manhattan distance to goal`; explore-first minimizes
   `4 × path distance − 6 × unknown neighbors`. Lowest cell ID wins score ties.
5. At a frontier already under the robot, request another scan. Otherwise,
   reconstruct a route and move just one cell. With neither a reachable goal nor
   a frontier, stop instead of treating unknown cells as traversable.

BFS considers neighbors north, east, south, west. The independent C++ reference
uses its own queue and parent arrays and evaluates the same policy. The entire
returned route, action, target, direction, reason and reachable-cell count must
match before the simulator accepts a decision. The host reference checks results;
it does not complete the guest's route calculation.

Three actions also use −1/0/+1: **stop / scan in place / move**. Movement components
`dx` and `dy` are −1, 0 or +1, with cardinal motion only. Map cells are logically
one trit each, but currently occupy a full six-trit tryte in emulator memory.
This is a clear representation of uncertainty, not a memory or speed benchmark
against optimized binary implementations.

## Sensors and changing obstacles

Each scan looks up to two cells in each cardinal direction, stopping at the map
edge, a wall, or a missing reading. There is no seeing through an unobserved wall.
Reliable scans report the world accurately. In intermittent mode, a reading is
missing when `(scan number + cell ID + seed) % 3 == 0`; this is reproducible and
never persists forever for a stationary robot. The current cell is known clear.

Clear means **last observed clear**, not a guarantee against later edits. The
simulator checks the next physical cell again before moving. If a wall changed
and its sensor reading was missed, it blocks the move, marks the obstacle and
requires replanning. This physical collision guard has privileged world access;
the navigation guest does not. A successful move costs one energy; a rejected move
costs none beyond the scan already performed.

The return reserve is a heuristic, not a guarantee under arbitrary edits or lost
routes. Removed walls outside sensor range do not magically erase old blocked
knowledge. The robot can stop with an outdated/incomplete map; restart or edit
near its observed region to explore that situation. This is not SLAM, probabilistic
mapping, a global optimal exploration policy, or a controller suitable for hardware.

## Debug the brain

**Debug brain** pauses the next guest decision and opens the existing disassembler,
registers, breakpoints and read-only memory inspector. Step executes one instruction;
Continue finishes the decision and then applies its single action. Automatic
exploration stays paused. Debug timing is omitted because manual steps are excluded
from the runtime's active timing calls. Each new decision reloads the guest image
and clears breakpoints. Closing the lab cancels pending work.

The shared `src/explorer_protocol.h` defines the memory contract. All addresses
below are decimal trytes; the energy word stores its high tryte first.

| Address | Length | Meaning |
| --- | ---: | --- |
| 0 | — | Entry `SEI`, then call the 3CC `main` |
| 100000 | 1 | Status: 0 ready, 1 planning, 2 complete |
| 100001…100003 | 3 | Robot, base and goal cell IDs |
| 100004 | 2 | Energy, 0…999 |
| 100006…100007 | 2 | Priority (0 goal/1 explore) and return flag |
| 100100 | 225 | Observed map, −1/0/+1 |
| 100330…100336 | 7 | Action, reason, target, dx, dy, route length, reachable count |
| 100400 | Up to 224 | Route cell IDs, excluding the starting cell |
| 110000 | 225 | BFS distances (−1 means unreachable) |
| 110300 | 225 | BFS parent cell IDs |
| 110600 | 225 | BFS work queue |

The program, buffers and stack are separate. Inputs are range-checked before a
session is replaced; corrupt or mismatched outputs cancel it. Each plan is limited
to ten million guest instructions. UI batches yield after roughly 4 ms or 50,000
instructions, with the runtime's cooperative time checks. Missions are limited to
4,096 scans, which also bounds accepted history and travel storage. No world-file
import, arbitrary native code loading or new entitlements are introduced.

## Build and validate

```sh
make -j4 app
make explorer-check explorer-sanitize
```

The normal suite compares random/boundary observations and complete guest routes,
then runs closed-loop missions across the three presets, both priorities and both
sensor modes. It tests shortest known paths, exclusion of unknown/blocked cells,
low-battery return, no-route stops, a wall appearing during a missed reading,
editing without leaking knowledge, reset, malformed inputs, corrupt results,
bounded execution, single instruction stepping, breakpoints and cancellation.
The sanitizer target uses a smaller guest sample plus the complete host missions
under ASan/UBSan. Release preparation runs both suites with the existing regressions.

The native app is additionally checked for real mission completion, editing,
stepping, debugger use, options and sandboxed JSON export. These are focused checks,
not comprehensive fuzzing or a safety certification. See [the security review](SECURITY-REVIEW.md).

Explorer code and generated guest software are GPL-2.0-or-later additions by this
independent Mac fork. The original emulator and compiler remain attributed to
**Viktor Lofgren**, and upstream history/snapshots and license notices are preserved.
