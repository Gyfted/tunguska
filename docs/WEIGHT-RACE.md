# Weight Race

Open **Weight Race** from the sidebar or **Machine → Weight Race** (⌘G).
This native Metal experiment measures the effect of storing the same numerical
weights in different formats. It uses the Mac's GPU directly; the emulated
ternary CPU is not part of the timed calculation.

## Try it

1. Press **Compare all sizes**. Four square layers range from 1,024 to 16,384
   rows/columns. The default 8,192-square layer contains 67,108,864 weights.
2. Compare the memory bars and median GPU times. The table retains all completed
   sizes. The selected layer controls **Run comparison**, not the size sweep.
3. Use **51 rounds** to collect more samples. **New weights** advances the
   deterministic seed; existing results keep their original seed until the next run.
4. **Cancel** stops preparation or waits for the current GPU command to finish.
   An interrupted size has no result; already completed sizes can still be exported.
   Closing the window also requests cancellation.
5. **Export results…** writes JSON through the sandboxed Save panel. It includes
   every timing sample, the shader SHA-256, device/OS, matrix sizes, seed, memory,
   exact-output check count, warm-ups, and whether the requested run completed.

All three execution paths use one input vector per invocation (batch size 1):

| Path | Weight representation | Execution |
| --- | --- | --- |
| FP16 matched Metal | IEEE binary16 values −1, 0, +1 | Our vectorized GPU matrix-vector kernel |
| Packed ternary Metal | Four two-bit values per byte | Matching GPU kernel, with vector decoding in registers |
| FP16 Apple MPS | The same FP16 buffer | Apple's MPSMatrixVectorMultiplication library |

The second baseline prevents a comparison against only our own floating-point
implementation. It does not establish a win over every possible optimized kernel
or newer hardware-specific matrix API. Both custom kernels use the same row
assignment, vector width, input format and SIMD reduction. The packed kernel
still performs ordinary floating-point arithmetic after decoding; it is not a
claim of multiplication-free hardware.

## What is being calculated?

Each output is the dot product of one matrix row and the input vector, `y = W x`.
Weights are reproducibly generated as −1, 0, +1. Three independent input vectors
contain values from −7/8 to +7/8 in steps of 1/8. Inputs are FP16 and outputs FP32;
the custom kernels accumulate in FP32. There are no biases, nonlinearities,
learned parameters, attention, group scales or training in this experiment.
The weights have unit scale and are already exactly ternary.

Before timing, every packed weight is checked against the FP16 representation.
During generation, an independent CPU integer accumulator computes every expected
output for all three inputs; division by eight gives the exact reference result.
The bounded dyadic data keep these products and sums exactly representable in
FP32. Every output row from every warm-up and timed invocation must match that
reference exactly, including the Apple MPS outputs. NaNs, unwritten rows and any
difference reject the result. Two GPU implementations agreeing with each other
is insufficient: a deliberately corrupted shader is tested against the oracle.

The packing is row-major. Each byte contains four codes, starting in its low bits:
`00 = 0`, `01 = +1`, `10 = −1`; `11` is reserved and rejected by host decoding.
Trailing slots are zero. FP16 rows are padded to a 16-byte boundary, needed for
reliable MPS matrix layout on small irregular shapes. The custom FP16 kernel uses
that same stride. Displayed weight-buffer bytes include this padding.

For the power-of-two sizes in the UI, FP16 uses 16 bits per weight and packed
ternary uses exactly two. The weight-buffer ratio is therefore exactly 8:1:

| Layer | Weight count | FP16 | Packed ternary |
| --- | ---: | ---: | ---: |
| 1,024² | 1,048,576 | 2 MiB | 0.25 MiB |
| 4,096² | 16,777,216 | 32 MiB | 4 MiB |
| 8,192² | 67,108,864 | 128 MiB | 16 MiB |
| 16,384² | 268,435,456 | 512 MiB | 64 MiB |

These are actual weight-buffer lengths, not whole-process memory. Both formats
coexist during comparison, alongside three inputs and three output buffers. The
report gives their combined size. It does not include driver allocations,
compiled pipelines, MPS scratch memory, CPU reference vectors, or the rest of the app.

## Timing and interpretation

Each path gets nine warm-up invocations. The measured phase uses 9, 21 or 51 rounds,
with all three paths run once per round. Path order rotates each round, and the
same input is used for all three paths in a round. Input patterns cycle across the
three prepared vectors. No CPU reference work, packing, buffer allocation, shader
compilation or output verification is counted as GPU time.

GPU time is `GPUEndTime - GPUStartTime` from a completed Metal command buffer and
includes packed decoding and command work. Separate wall samples include encoding,
submission and waiting. The timing fields must be finite and positive; failures
stop the run. GPU kernels execute sequentially, not as a simultaneous race. The
CPU worker keeps the app responsive. The reported setup time covers buffer/data
preparation and reference generation after the Metal pipelines have been created. Timing-phase UI updates are limited to the
start/end to avoid continuously redrawing the charts during measurement.

The UI shows median and 10th–90th percentile times. Its ratio uses the faster
median of the two FP16 baselines. A clear win/loss label requires non-overlapping
middle-80% ranges against that baseline; otherwise it says that timing ranges
overlap. This is a descriptive noise check, not a statistical significance test.
Exports retain all samples, including slow ones. Repeat before generalizing.

This is a warmed, repeated-weight workload. It does not flush caches or measure
physical DRAM traffic. Small layers can be dominated by dispatch, computation or
cache behavior. Larger layers can benefit more from the compact representation,
but the benchmark does not identify the hardware bottleneck with performance
counters. Other GPU activity, power state and temperature affect the result.

A faster packed result demonstrates an advantage for this computation, format,
kernel, size and device. It does not prove that a ternary processor is faster,
that an arbitrary trained model can be compressed without losing accuracy, or
that an LLM will receive the same speedup. No energy measurement is performed.
Bonsai-style grouped scaling, real model quality and full application latency
would be separate experiments.

## Build and reproduce

```sh
make -j4 app
make weight-check weight-sanitize weight-gpu-validation
build/weight-benchmark-tests resources/benchmark/matvec.metal --measure
```

The last command runs correctness checks, then prints a 51-round size sweep.
It needs access to a real Metal GPU. A restricted command environment without
GPU access fails explicitly instead of silently using CPU timings. Supported
Intel/Apple Silicon builds use the GPU's reported SIMD width; runtime verification
on the development machine is Apple Silicon only. A GPU without the required
Metal/MPS support produces an error in the lab while other Tunguska features remain
available.

`weight-sanitize` instruments the host code with ASan/UBSan. Metal shader/API
validation is a separate target because CPU sanitizers do not instrument GPU code.
Tests include tiny/odd shapes, partial vectors and SIMD groups, packing, dimension
bounds, sample statistics, exact outputs, corrupted-result rejection, and early/
late cancellation. GPU timing results collected under validation are not performance
measurements. Release preparation runs all three checks.

The benchmark adds no networking or entitlements and accepts no user-supplied
shader/model files in the app. Dimensions are capped at 16,384 and rounds at 99 in
the engine (51 in the UI); allocations are checked against device limits and half
its recommended working-set budget. Cancellation is cooperative and cannot abort
an already submitted GPU command. See [the security review](SECURITY-REVIEW.md).

This is an independent GPL-2.0-or-later addition by Vinny Lingham's Mac fork.
Original Tunguska remains credited to Viktor Lofgren; original source/history and
license notices are preserved. No Bonsai code or model weights are bundled.

## Recorded local result — September 25, 2026

The [full JSON measurement](benchmarks/weight-race-m5-max.json) was exported from
the sandboxed app on an Apple M5 Max, seed 730, 51 measured rounds per path after
nine warm-ups. Its shader hash matches the bundled source. All 5,345,280 output
values matched the independent reference exactly. GPU medians in milliseconds:

| Layer | FP16 matched | FP16 Apple MPS | Packed ternary | Speed relative to faster FP16 |
| --- | ---: | ---: | ---: | ---: |
| 1,024² | 0.017 | 0.020 | 0.019 | 0.91× (slower) |
| 4,096² | 0.063 | 0.055 | 0.053 | 1.04× (ranges overlap) |
| 8,192² | 0.259 | 0.256 | 0.093 | 2.74× |
| 16,384² | 0.976 | 1.020 | 0.337 | 2.89× |

The larger two layers had non-overlapping middle-80% ranges against the faster
FP16 baseline. A separate 51-round command-line sweep with seed 729 measured
2.54× and 2.81× at those sizes, again with zero output error. Both sweeps show the
same pattern: a substantial benefit on these large layers, little or none on
small ones, and 8× smaller weight buffers at every size. These local measurements
are evidence for this implementation and Mac, not a universal speedup claim.
