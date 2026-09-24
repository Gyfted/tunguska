# Ternary Vision Lab

Open **Ternary Vision Lab** in the sidebar or **Machine → Ternary Vision Lab**
(⌘L). This is an offline handwritten-digit classifier running inside Tunguska,
with an independently calculated float32 baseline on the Mac. The lab pauses
the original OS and uses its own machine, leaving the original guest intact.

## Try it

1. Choose **Run inference** on the first held-out digit. Its 54 hidden
   activations and ten integer scores are calculated by the guest CPU.
2. Choose **Next sample**, or **Clear** and draw a large, centered digit.
   Drag to paint; right-drag to erase. The 32×32 ink surface reduces to 8×8
   counts from 0 to 16. There is no automatic centering or rotation correction.
3. Click a hidden neuron's weight map or choose it from the neuron selector.
   Green weights add, orange weights subtract, and dark weights skip inputs.
   The detail view shows its bias, reference arithmetic, guest activation and
   memory address. Labels under the maps are `neuron:activation`.
4. Choose **Debug guest** to restart a finished prediction paused, or pause an
   active one. Step through real compiled 3CC instructions, inspect memory,
   add breakpoints and Continue. Resume also works from the lab. A new
   inference resets the machine and clears its breakpoints.
5. **Benchmark** runs the first 100 official test records, or all 1,797, through
   both models. It remains responsive and supports Pause/Resume and Cancel.
   A full UI run may take several minutes. Partial results are retained.
6. **Export report…** saves JSON containing model provenance, current input,
   hidden activations and scores, and the last benchmark's per-sample results,
   timings, instruction counts and confusion matrix (true labels as rows).
   Saving uses a native file panel and an atomic, coordinated write.

Inputs changed while the guest runs cancel that prediction. Scores are raw
integer ranking values, **not calibrated probabilities**. A blank canvas still
produces a classification; the model has no “unknown” or rejection class.
User drawings are not necessarily distributed like the historical test set.

## What executes where

`resources/vision/inference.3c` is compiled by the restored 3CC compiler and
assembled during a normal build. A separate Runtime loads that image. The host
copies 64 pixels, learned ternary weights and integer biases into guest memory.
The guest computes every matrix product with **add, subtract or skip**. It then
normalizes hidden activations with integer division by eight and clips to 0…81.
It does not call the host model or read precomputed classifications.

The network has 64 inputs, 54 hidden neurons and ten output scores:

```
h[j] = clamp(max(0, bias1[j] + sum(weight1[j,i] * pixel[i])) / 8, 0, 81)
s[k] = bias2[k] + sum(weight2[k,j] * h[j])
prediction = index of largest score (lowest index wins ties)
```

Division follows integer truncation after the nonnegative clamp. The host's
integer reference independently evaluates the same function; all 54 guest
activations and all ten scores must match before the result is accepted. The
float32 baseline is a separately trained network of the same size, using ReLU
and float32 multiply/add arithmetic. It is not used to complete guest inference.

The guest has a ten-million-instruction limit. UI execution yields after about
5 ms or 100,000 instructions per timer tick, whichever is reached first; the
existing runtime checks time every 1,024 instructions. Debugger execution uses
the same session and limit. Closing the lab cancels execution.

## Memory map

Addresses below are decimal tryte addresses; words store their high tryte first.
They do not overlap the program, system registers or 3CC stack.

| Address | Length | Contents |
| --- | ---: | --- |
| 0 | — | Entry instruction (`SEI`) |
| 100000 | 1 tryte | Status: 0 before start, 1 computing, 2 complete |
| 100001 | 1 tryte | Completed neurons, 0…64 |
| 100010 | 64 trytes | Pixels, 0…16 |
| 100100 | 54 trytes | Hidden activations, 0…81 |
| 100200 | 20 trytes | Ten signed, two-tryte scores |
| 110000 | 3,996 trytes | Hidden weights followed by output weights, row-major |
| 114000 | 128 trytes | 54 hidden and ten output biases, each a two-tryte word |

The host expands packed weights into one full tryte each to make guest memory
inspection straightforward. This is not a compact emulator memory layout.

## Model and fair comparison

The [UCI Optical Recognition of Handwritten Digits dataset](https://doi.org/10.24432/C50P49)
by **E. Alpaydin and C. Kaynak (1998)** supplies 3,823 official training records
and 1,797 official test records from different writers. The test records retain
their original order. From training only, a seeded split uses 3,323 records for
fitting and 500 for validation/checkpoint selection. Each model trains for 180
epochs; its lowest validation-cross-entropy checkpoint is exported. No test
records influence weights or checkpoint selection. This is one fixed training
run, not a multi-seed estimate or a state-of-the-art accuracy claim.

The quantized model uses straight-through gradients for rounded/clipped weights,
integer biases and hidden activations. Training uses NumPy on the host;
optimization uses floating point. Only exported inference uses ternary weights.
See the complete algorithm in `scripts/train_vision.py` and recorded settings,
software version and hashes in `resources/vision/vision-model.json`.

| Measurement | Ternary network | Float32 baseline |
| --- | ---: | ---: |
| Correct on all 1,797 held-out digits | 1,711 (95.21%) | 1,724 (95.94%) |
| Weights | 3,996 | 3,996 |
| Encoded weight payload | 800 bytes | 15,984 bytes |
| Bias payload, 64 × 32 bits | 256 bytes | 256 bytes |
| Matrix arithmetic per prediction | 2,483 adds/subtracts; 1,513 skips | 3,996 multiply/add pairs |

`vision-weights.bin` really is 800 bytes: five weights per byte, each mapped from
−1/0/+1 to 0/1/2 and stored least-significant-trit first. The last byte has one
used weight; its unused positions are zero. The same packed values are compiled
into the app. The float32 weight payload comparison is 3,996 × 4 bytes. This is
about **20× smaller for weights**, or **15.4× including the stated biases**.
These are payload sizes, not total app, executable, guest RAM or process RSS.
The app additionally contains the baseline, dataset, metadata, emulator and UI.

The operation count excludes address calculation, loops, bias loads, normalization
and other instructions. The current 3CC guest executes roughly 455,000 machine
instructions per prediction. A packed ternary model can also run on an ordinary
binary processor; this project does not demonstrate a hardware advantage.

Timing measures the guest runtime's active execution calls and the native scalar
C++ baseline separately. Setup, model copying and UI waits are excluded from
active guest time and included in the benchmark's displayed elapsed time.
Native single-sample timings include timer overhead and are noisy; no speedup
ratio is claimed. Timing after manual debugger stepping is omitted from the
single-prediction display. The Mac's native baseline is much faster than emulation.
The 100-sample subset can have different accuracy from the full held-out corpus.

## Reproduce training

Normal builds are offline and require no Python packages. The checked-in assets
and compiled guest are sufficient. Retraining is optional and needs NumPy
(the recorded run uses 2.3.5) and the official UCI archive:

```
https://archive.ics.uci.edu/static/public/80/optical%2Brecognition%2Bof%2Bhandwritten%2Bdigits.zip
```

The trainer checks this archive's SHA-256 before reading either CSV:

```
0d7b054fea010270e9b3f06411c654c5e59547732ad626381980baffe0a23fb0
```

```sh
python3 scripts/train_vision.py /path/to/optdigits.zip
make -j4 app
make vision-check vision-sanitize
```

Seed, split, epochs and architecture are fixed in the script. Exact numerical
reproduction may depend on NumPy/BLAS and the platform. `--output /path/to/folder`
lets you compare newly trained assets without replacing the checked-in model.
The trainer only reads named members of the pinned archive and never downloads,
executes archive contents, or extracts arbitrary archive paths.

`vision-check` verifies the actual packed file and data/model hashes, checks
all 1,797 test records against both models, and executes **every test record on
the guest with exact activation/score parity**. It also covers zero/full/checkerboard
and seeded random inputs, corrupt datasets, invalid pixels, tie handling,
breakpoints, pause/step, cancellation/restart, intentional reference mismatch and
an infinite guest's instruction limit. `vision-sanitize` runs these controls and
30 guest test records under ASan/UBSan, while checking full-corpus host accuracy.
The release preparation pipeline includes both targets.

The dataset and learned numerical assets retain **CC BY 4.0** terms and full
attribution in [VISION-NOTICE.md](../resources/vision/VISION-NOTICE.md), bundled
in the app's **License and Credits** window. Code remains GPL-2.0-or-later.
This lab is an independent addition to Viktor Lofgren's original Tunguska.
