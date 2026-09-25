# Ternary versus binary: measurements on this Mac

Measured September 25, 2026 on an **Apple M5 Max**, ARM64, macOS 27.0
(26A428), using optimized native builds. The installed game was paused during
measurement and resumed afterward. These benchmarks do not alter the game.

The game benefits from native execution; large AI weight calculations benefit
from compact ternary storage. Those are different findings. This Mac is binary
hardware in both experiments, so neither measures a physical ternary processor.

## Game ray casting: emulated guest versus native code

Each job casts the same 54 integer wall rays using Breach's map, precomputed
directions, divisions and traversal limit. The guest harness includes the actual
game source and calls its `cast()` function compiled by 3CC. The native baseline
is a C++ translation compiled by Clang with `-O2`, using ordinary 32-bit integers.

| Repeat | Ternary interpreter, 54 rays | Native binary, 54 rays | Native speed advantage |
| --- | ---: | ---: | ---: |
| 1 | 3.533 ms | 0.233 µs | 15,133× |
| 2 | 3.540 ms | 0.235 µs | 15,081× |

These are medians of nine round means. A measured round contains 360 scenes:
36 headings at ten displaced positions selected across the map. Native rounds
repeat that sequence 128 times to resolve the short execution time. Both paths
are warmed, and their measurement order alternates. A compiler barrier forces
the native outputs to be materialized and prevents work from being hoisted out
of the repeated loop. The guest executes a median **52,096 emulated instructions**
per job, including its harness and polling granularity.

Before timing, **3,060 scenes / 495,720 output values** must agree exactly:
distance, wall side and hit cell for every ray. This covers all 75 walkable tile
centers in every heading plus the displaced measurement scenes. Every timed
guest result is checked too. The correctness sweep also passed ASan/UBSan.

Timing excludes startup, input preparation, verification, graphics, game logic,
audio and UI presentation. Guest timing includes instruction interpretation,
cooperative peripheral servicing and command-completion polling in 64-instruction
batches, without sleeps or the UI time cap. Native timing includes its batch loop
and output barrier. The ratio includes compiler quality, execution model and
memory representation; it does **not** isolate the effect of number base.

This is **not a 15,000× game-FPS comparison**. There is no complete native game
in this benchmark. Separately, the existing full guest-frame benchmark measured
**15.59 ms median / 22.28 ms p95** across 210 frames, with estimated 60 Hz scheduling
latency of 33.3 / 50 ms. Those estimates exclude timer sleeps and actual screen
presentation; they are not measured input-to-screen latency.

## AI weights: packed ternary versus FP16 on the same GPU

The existing Weight Race engine calculates `y = W x` using identical numerical
weights from −1, 0 and +1. It compares two-bit ternary storage with a matched FP16
Metal kernel and Apple's FP16 MPS matrix-vector library. Each speed ratio below
uses the faster FP16 baseline for that metric. Both paths still execute on the
same binary Metal GPU.

Two sweeps used seeds 729 and 730, with nine warm-ups and **51 measured samples
per path and size**. Kernel order rotates, and three input vectors are exercised.
All **10,690,560 checked output values** matched the independent integer reference
exactly. The ranges below show the two sweeps' median ratios, not confidence
intervals.

| Matrix size | FP16 weights → ternary weights | GPU speed ratio | Submission-through-completion speed ratio |
| --- | ---: | ---: | ---: |
| 1,024² | 2 MiB → 0.25 MiB | 0.90–0.98× | 0.93–1.00× |
| 4,096² | 32 MiB → 4 MiB | 1.37–1.86× | 0.92–1.07× |
| 8,192² | 128 MiB → 16 MiB | 2.54–2.56× | 1.63–1.64× |
| 16,384² | 512 MiB → 64 MiB | 2.78–2.81× | 2.20–2.29× |

A ratio above one favors packed ternary. The largest case took **0.334–0.338 ms**
of GPU time with ternary weights, versus **0.940 ms** for the faster FP16 baseline.
Including command encoding, submission and waiting, ternary took **0.477–0.501 ms**
versus **1.091–1.102 ms**. Both large-layer sweeps show a practical gain. Small-layer
timings varied more; the 4,096² GPU gain did not consistently survive submission
overhead.

The memory reduction is exactly **8× for the weight buffers**, not whole-process
memory. Timing includes unpacking but excludes weight generation/packing, model
loading, reference checks and UI. This is a warmed matrix-vector workload with
already-ternary weights, not an entire AI model. It does not measure accuracy
after quantizing a trained model, token generation, power consumption or every
possible optimized low-bit baseline. See [Weight Race](WEIGHT-RACE.md) for the
algorithm and detailed measurement limits.

## Reproduce and inspect

```sh
make -j4 build/breach-rays build/breach-rays.ternobj build/weight-sweep
make breach-ray-benchmark
make breach-ray-sanitize
make weight-sweep
make breach-benchmark
```

`weight-sweep` requires access to the real Metal GPU; an enclosing command sandbox
may deny it. Native CPU timing uses optimized builds; sanitizer timing is never
used as a performance result. These targets build standalone benchmark programs
and do not rebuild or replace the installed app.

Raw timings, correctness logs, compiler/OS metadata, source/image hashes and both
CPU repeats are in [the measurement directory](benchmarks/ternary-vs-binary-m5-max/).
In particular, [provenance.json](benchmarks/ternary-vs-binary-m5-max/provenance.json)
identifies the exact game release and benchmark inputs, while
[weights.json](benchmarks/ternary-vs-binary-m5-max/weights.json) retains every GPU
and wall-time sample, including outliers.

The practical direction is to use native code for the game and other general
computation, while testing ternary packing for large, memory-heavy AI operations.
The interpreted guest remains useful for exploring ternary computing; this
benchmark provides no speed justification for moving ordinary Mac software into it.
