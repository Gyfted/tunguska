# Ternary Vision Lab

Open **Ternary Vision Lab** in the sidebar or **Machine → Ternary Vision Lab**
(⌘L). Draw a digit, inspect the network, compare three numerical models, and
explore their mistakes. Everything runs offline. The lab pauses the original OS
and uses its own machine, leaving the original guest intact.

## Try it

1. Choose **Run inference** on the first historical test digit. **Ternary CPU**
   computes its 54 hidden activations and ten integer scores on the guest.
   **Fast on Mac** runs the same ternary model directly on the Mac's binary CPU.
2. Choose **Next sample**, or **Clear** and draw one digit. Drag to paint;
   right-drag to erase. **Center and resize drawings** fits the ink into a
   centered square while preserving aspect ratio. The small preview shows the
   exact 8×8 input shared by all three models. Turn the checkbox off to compare
   the original drawing. Dataset samples always retain their original pixels.
3. Blank, tiny and almost-solid drawings prompt you to try again without making
   a prediction. When the top two ternary scores are too close, the lab says
   **Not sure** and shows both choices. Scores are ranking values, not probabilities.
4. Click a hidden neuron's weight map or choose it from the selector. Green
   weights add, orange weights subtract, and dark weights skip inputs. The detail
   shows its bias, reference arithmetic, activation and guest memory address.
5. **Show mistakes…** lists raw top-choice errors on the historical test set.
   Filter by true digit or include any model's mistakes. The right-hand heat map
   erases one input cell at a time and measures its effect on the original
   predicted-class score. Green means erasing lowers that score; orange means
   erasing raises it. This sensitivity experiment is not a causal explanation.
   **Open this sample in the lab** loads the selected input for inference/debugging.
6. **Debug guest** starts or pauses the real guest even in Fast mode. Step through
   ordinary Tunguska instructions, inspect memory, add breakpoints and Continue.
   A new debug run resets the machine and clears breakpoints.
7. **Benchmark** runs the first 100 records or all 1,797 through all three models.
   The selected execution mode determines how ternary results are produced.
   Pause/Resume and Cancel retain partial results. Raw accuracy, the percentage
   answered, and accuracy among answers are reported separately.
8. **Export report…** saves JSON with provenance, raw and prepared input,
   activations/scores, execution mode, uncertainty, per-sample benchmark results,
   timings, instruction counts and the raw ternary confusion matrix (true labels
   as rows). Saving uses a native file panel and an atomic, coordinated write.

Changing the input or mode cancels an active prediction. Drawing preparation uses
32×32 ink, an ink bounding box fitted inside 28×28, bilinear interpolation and
4×4 reduction to 8×8 counts from 0 to 16. It centers and rescales; it does not
straighten handwriting. Rejection heuristics detect obvious input problems, not
arbitrary unknown objects. A non-digit can still receive a confident answer.

## What executes where

The network has 64 inputs, 54 hidden neurons and ten output scores:

```
h[j] = clamp(max(0, bias1[j] + sum(weight1[j,i] * pixel[i])) / 8, 0, 81)
s[k] = bias2[k] + sum(weight2[k,j] * h[j])
prediction = index of largest score (lowest index wins ties)
```

Division truncates after the nonnegative clamp. Every ternary weight is −1, 0 or
+1. The host's dense integer reference independently evaluates this function;
all 54 activations and ten scores must match before accepting either the sparse
native result or the guest result.

At build time, `scripts/build_vision_guest.py` specializes the packed weights into
ordinary Tunguska assembly: add for +1, subtract for −1, and emit no matrix work
for zero. This removes repeated loops, address arithmetic and weight branches.
No new ISA or host callback completes the guest's inference. Biases and inputs
are still read from guest memory. The preserved readable
`resources/vision/inference.3c` builds a separate reference guest for testing.

The native ternary path builds sparse lists once and evaluates the same add/subtract
network. The float32 baseline is a separately trained network of the same size,
using float ReLU and multiply/add arithmetic. The 8-bit baseline quantizes that
float network's weights symmetrically to −127…127 using one scale per layer.
Its hidden activations and biases remain float32; it is **weight-only 8-bit
quantization**, not a fully integer inference engine. These baselines make
independent predictions and never complete ternary inference.

A cleanly completed guest can reuse its loaded machine on the next prediction.
Inputs, outputs, progress, biases and weight-inspection memory are reinitialized.
Cancelled, paused/debugged or breakpoint-bearing sessions take a full reset.
The guest has a ten-million-instruction limit; UI execution yields after about
5 ms or 100,000 instructions per timer tick, whichever is reached first. The
runtime checks time every 1,024 instructions. Closing the lab cancels execution.

## Memory map

Addresses are decimal tryte addresses; words store their high tryte first.
They do not overlap the program, system registers or stack.

| Address | Length | Contents |
| --- | ---: | --- |
| 0 | — | Entry instruction (`SEI`) |
| 100000 | 1 tryte | Status: 0 before start, 1 computing, 2 complete |
| 100001 | 1 tryte | Completed neurons, 0…64 |
| 100010 | 64 trytes | Pixels, 0…16 |
| 100100 | 54 trytes | Hidden activations, 0…81 |
| 100200 | 20 trytes | Ten signed, two-tryte scores |
| 110000 | 3,996 trytes | Expanded weights for inspection, hidden then output, row-major |
| 114000 | 128 trytes | 54 hidden and ten output biases, each a two-tryte word |

The optimized program embeds weight choices in its instructions; editing the
inspection copy does not change that program. Rebuild after changing weights.
The 3CC reference reads the expanded weights directly. Neither layout is compact
emulator memory storage.

## Model and comparison

The [UCI Optical Recognition of Handwritten Digits dataset](https://doi.org/10.24432/C50P49)
by **E. Alpaydin and C. Kaynak (1998)** supplies 3,823 official training records
and 1,797 official test records from different writers, retained in original order.
A seeded training-only split uses 3,323 records for fitting and 500 for validation.
Half of each fitting batch receives small random rotations (±10°), translations
(±0.45 cell), scale changes (0.9…1.1) and stroke changes (±12%).

Both models train for 180 epochs. Checkpoints use the lowest mean cross entropy
across 500 clean validation inputs and 500 deterministically jittered views of
those same inputs: **500 independent records, not 1,000**. The ternary model
uses straight-through gradients for rounded/clipped weights, integer biases and
activations. Training/optimization uses host floating point.

The uncertainty threshold is selected only from those validation views: choose
the smallest score gap meeting at least 98% selective accuracy and 50% coverage.
The selected gap is **9** (a gap below 9 abstains). It answered 965/1,000 validation
views with 946 correct. This is an empirical rule, not calibrated confidence or
a guarantee of 98% accuracy on other inputs.

| Historical test measurement | Ternary | Float32 | 8-bit weights |
| --- | ---: | ---: | ---: |
| Correct out of all 1,797, before abstention | 1,727 (96.10%) | 1,750 (97.38%) | 1,750 (97.38%) |
| Weight count | 3,996 | 3,996 | 3,996 |
| Encoded weight payload | 800 B | 15,984 B | 3,996 B |
| Bias payload | 256 B | 256 B | 256 B |
| Additional scales | — | — | 8 B |

With abstention, ternary answers **1,740/1,797 (96.83%)**, including **1,702 correct
(97.82% of answers)**; 57 inputs receive “Not sure.” Raw accuracy always includes
all inputs. The confusion matrix and mistake browser use raw choices, including
those withheld by the uncertainty rule.

Version 0.8 scored 95.21% ternary and 95.94% float32 on this same test set. These
results are historical benchmarks: earlier errors informed the decision to add
augmentation. Test inputs were not used for gradient training, checkpoint or
threshold selection, but this is **not a fresh independent generalization study**.
One fixed training run was exported. New user drawings may differ substantially;
collect a new, consented evaluation set before making broader claims.

`vision-weights.bin` really is 800 bytes: five weights per byte, mapped from
−1/0/+1 to 0/1/2, least-significant trit first. The last byte uses one weight;
unused positions are zero. This is about 20× smaller than float32 weights and
5× smaller than 8-bit weights. Including stated biases, the float32 ratio is
15.4×. These are numerical payload sizes, **not total executable size, guest RAM
or process RSS**. Generated guest code embeds the sparse structure; native mode
also stores expanded indices/weights. The app includes all baselines and data.

The new model has 2,579 nonzero weights and 1,417 zeros. Matrix products perform
2,579 additions/subtractions; addressing, bias loads, normalization and other
instructions are extra. Across the first 30 test records, optimized code executes
328,119 instructions versus 13,757,644 for the same model's 3CC reference: about
**42× fewer guest instructions**, roughly 10,937 per prediction. This is a software
optimization, not evidence of ternary hardware superiority.

Guest timing measures active runtime calls, excluding setup/model copying/UI
waits. Elapsed benchmark time includes those costs and repeated native timing.
Each native path is warmed once, then averaged over 64 scalar C++ calls. Timings
are noisy and are not optimized CPU/GPU-library or energy benchmarks. Benchmark
native totals sum those per-input averages, not the time spent on all repetitions.
Guest timings after manual debugger stepping are omitted from the single-result
display. Fast mode avoids emulation; the Mac still uses binary hardware.

## Reproduce training and tests

Normal builds are offline and require no Python packages. Retraining is optional
and needs NumPy (the recorded run uses 2.3.5) and the official UCI archive:

```
https://archive.ics.uci.edu/static/public/80/optical%2Brecognition%2Bof%2Bhandwritten%2Bdigits.zip
```

The trainer checks the archive SHA-256 before reading named CSV members:

```
0d7b054fea010270e9b3f06411c654c5e59547732ad626381980baffe0a23fb0
```

```sh
OPENBLAS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 python3 scripts/train_vision.py /path/to/optdigits.zip --augment
make -j4 app
make vision-check vision-sanitize
```

The seed, split, epochs and architecture are fixed. `--output /path/to/folder`
compares new assets without replacing the bundled model. Exact reproduction may
depend on NumPy/BLAS and platform; repeated training on this host reproduced all
five generated assets byte for byte. The trainer never downloads, executes archive
contents or extracts arbitrary paths. Full settings and hashes are recorded in
`resources/vision/vision-model.json`.

`vision-check` checks asset hashes/encoding and all three models' full-corpus
accuracy. Every one of the 1,797 inputs executes on the optimized guest with exact
activation/score parity against the independent host reference and native sparse
kernel. Thirty also execute on the preserved 3CC reference. Tests cover drawing
normalization/rejection, uncertainty boundaries/ties, sensitivity, malformed
inputs, pause/step/breakpoints, reuse/reset, cancellation, intentional reference
mismatch and an infinite guest's instruction limit. `vision-sanitize` checks the
same controls and 30 real guest inputs under ASan/UBSan, plus full host accuracy.
Both targets are included in release preparation.

The data and learned numerical assets retain **CC BY 4.0** terms and full
attribution in [VISION-NOTICE.md](../resources/vision/VISION-NOTICE.md), bundled
in **License and Credits**. Code remains GPL-2.0-or-later. This lab is an independent
addition to Viktor Lofgren's original Tunguska.
