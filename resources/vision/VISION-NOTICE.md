Ternary Vision Lab — dataset and model attribution
================================================

Dataset: Optical Recognition of Handwritten Digits (1998)
Creators: E. Alpaydin and C. Kaynak
Repository: UCI Machine Learning Repository
DOI: https://doi.org/10.24432/C50P49
Source: https://archive.ics.uci.edu/dataset/80/optical+recognition+of+handwritten+digits
License: Creative Commons Attribution 4.0 International (CC BY 4.0)
License text: https://creativecommons.org/licenses/by/4.0/legalcode
License summary: https://creativecommons.org/licenses/by/4.0/

UCI identifies this dataset as CC BY 4.0. You may share and adapt the dataset,
including commercially, subject to that license. Retain appropriate credit,
a license link and a statement of changes. No endorsement by the creators,
UCI or Creative Commons is implied. These data assets are independently
licensed; Tunguska's GPL notice does not replace their CC BY 4.0 terms.

Changes in this independent Tunguska fork, 2026-09-24, Vinny Lingham:
- The 1,797 official test records were converted from comma-separated integers
  to an 8-byte magic string, little-endian count and 65 bytes per record.
  Pixel values, labels and record order were retained without changes.
- Two 64 → 54 → 10 neural networks were trained using the official training
  file only: 3,323 fitting records and 500 checkpoint-validation records.
  Fitting examples include synthetic shifts, rotations, scale and stroke
  variations. Validation uses clean and jittered views of the same 500 records.
  No test records were used in training, checkpoint or uncertainty selection.
- One network uses ternary weights and integer activations; the other uses
  float32 parameters. An 8-bit weight-only baseline is derived from the float32
  network. None of these models is supplied or endorsed by UCI.
- The 3,996 ternary weights are encoded as five balanced trits per byte.

The dataset-derived numerical parameters in model.h, vision-weights.bin,
vision-int8-weights.bin, vision-model.json and the converted vision-digits.bin are provided under
CC BY 4.0 with the above attribution. Their generation and inference code,
native interface and tests are GPL-2.0-or-later, as marked in those files.

Model results are for this small historical digit dataset, not general image
recognition. User drawings can differ substantially from its distribution.
Training is reproducible from a pinned archive; see docs/VISION-LAB.md and
scripts/train_vision.py. All app inference is offline.

Original Tunguska emulator and operating system: Viktor Lofgren.
The Vision Lab is a new addition by the independent Mac fork, not original
upstream functionality. Original notices and upstream snapshots are retained.
