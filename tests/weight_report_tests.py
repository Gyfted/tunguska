#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the published experiment's raw evidence and reported summaries."""
import hashlib
import json
import math
import statistics
from pathlib import Path

root = Path(__file__).resolve().parents[1]
report = json.loads((root / 'docs/benchmarks/weight-race-m5-max.json').read_text())
assert report['format'] == 'tunguska-weight-race-v1'
assert report['completed_requested_run']
shader_hash = hashlib.sha256((root / 'resources/benchmark/matvec.metal').read_bytes()).hexdigest()
assert [r['rows'] for r in report['results']] == [1024, 4096, 8192, 16384]
for result in report['results']:
    n = result['rows']
    assert result['columns'] == n
    assert result['shader_sha256'] == shader_hash
    assert result['weight_count'] == n * n
    assert result['fp16_weight_bytes'] == n * n * 2
    assert result['packed_weight_bytes'] == n * n // 4
    assert result['combined_gpu_buffer_bytes'] == n * n * 2 + n * n // 4 + n * 18
    assert result['max_absolute_error'] == 0
    assert result['checked_values'] == n * 3 * (result['rounds'] + result['warmups_per_path'])
    assert len(result['paths']) == 3
    for path in result['paths']:
        for clock in ('gpu', 'wall'):
            samples = path[clock + '_ms']
            assert len(samples) == result['rounds']
            assert all(math.isfinite(v) and v > 0 for v in samples)
            assert math.isclose(statistics.median(samples), path[clock + '_median_ms'], abs_tol=1e-12)
        values = sorted(path['gpu_ms'])
        for key, fraction in (('gpu_p10_ms', .1), ('gpu_p90_ms', .9)):
            index = fraction * (len(values) - 1)
            lo, hi = math.floor(index), math.ceil(index)
            expected = values[lo] + (values[hi] - values[lo]) * (index - lo)
            assert math.isclose(expected, path[key], abs_tol=1e-12)
print('PASS recorded Weight Race shader hash, memory, raw samples, summaries and correctness counts')
