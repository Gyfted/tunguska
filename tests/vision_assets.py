#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check model/data provenance and the actual exported weight payload."""
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1] / 'resources' / 'vision'
meta = json.loads((root / 'vision-model.json').read_text())
for name, key in [('model.h', 'model_sha256'), ('vision-digits.bin', 'test_data_sha256'), ('vision-int8-weights.bin', 'int8_weights_sha256')]:
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == meta[key], name + ' checksum mismatch'
header = (root / 'model.h').read_text()
match = re.search(r'packedWeights\[800\] = \{([^}]+)\}', header)
assert match, 'Packed weight declaration is missing'
packed = bytes(int(n) for n in re.findall(r'\d+', match.group(1)))
assert packed == (root / 'vision-weights.bin').read_bytes() and len(packed) == 800
weights = []
for b in packed:
    assert b < 243
    for i in range(5):
        weights.append(b % 3 - 1)
        b //= 3
assert sum(w != 0 for w in weights[:3996]) == meta['nonzero_weights']
int8_values = []
for name, count in [('int8Weights1',3456),('int8Weights2',540)]:
    match = re.search(rf'{name}\[{count}\] = \{{([^}}]+)\}}', header)
    values = [int(n) for n in re.findall(r'-?\d+', match.group(1))]
    assert len(values) == count and all(-127 <= n <= 127 for n in values)
    int8_values.extend(n % 256 for n in values)
assert bytes(int8_values) == (root/'vision-int8-weights.bin').read_bytes()
for constant, key in [('testCount','test_samples'),('ternaryCorrect','ternary_correct'),
                      ('floatCorrect','float32_correct'),('int8Correct','int8_correct'),
                      ('uncertaintyMargin','uncertainty_margin')]:
    assert int(re.search(rf'{constant} = (\d+)', header).group(1)) == meta[key]
assert meta['uncertainty_margin'] >= 0 and meta['augmented']
assert meta['validation_selective']['correct'] / meta['validation_selective']['accepted'] >= .98
assert meta['fit_samples'] + meta['validation_samples'] == 3823
assert meta['test_samples'] == 1797 and meta['architecture'] == [64, 54, 10]
assert 'CC BY 4.0' in (root / 'VISION-NOTICE.md').read_text()
print('PASS vision model/data hashes, 800-byte ternary payload, training split and attribution')
