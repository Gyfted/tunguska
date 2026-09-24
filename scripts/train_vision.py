#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Reproduce Vision Lab models. Requires NumPy; never runs during a normal build.

Supply the pinned official UCI archive. No network access is performed.
Only the 3,823 official training records influence weights/checkpoint selection.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import zipfile
import numpy as np

ARCHIVE_SHA256 = '0d7b054fea010270e9b3f06411c654c5e59547732ad626381980baffe0a23fb0'
HIDDEN = 54
SEED = 729
EPOCHS = 180


def quantized(p, x):
    a1, a2 = (max(float(np.abs(p[i]).mean()), 1e-6) for i in (0, 2))
    t1, t2 = (np.clip(np.rint(p[i] / a), -1, 1) for i, a in ((0, a1), (2, a2)))
    b1 = np.rint(p[1] * 16 / a1)
    b2 = np.rint(p[3] * 2 / (a1 * a2))
    pre = (x * 16 @ t1 + b1) / 8
    h = np.clip(np.floor(pre), 0, 81)
    logits = (h @ t2 + b2) * (a1 * a2 / 2)
    return logits, (a1, a2, t1, t2, pre, h, b1, b2)


def forward(p, x, ternary):
    if ternary:
        return quantized(p, x)[0]
    return np.maximum(x @ p[0] + p[1], 0) @ p[2] + p[3]


def train(x, y, ternary):
    rng = np.random.default_rng(SEED)
    order = rng.permutation(len(x))
    valid, fit = order[:500], order[500:]
    p = [rng.normal(0, .2, (64, HIDDEN)), np.zeros(HIDDEN),
         rng.normal(0, .15, (HIDDEN, 10)), np.zeros(10)]
    m, v = [np.zeros_like(a) for a in p], [np.zeros_like(a) for a in p]
    best, best_loss, step = None, float('inf'), 0
    for epoch in range(EPOCHS):
        for rows in np.array_split(rng.permutation(fit), 26):
            a = x[rows]
            if ternary:
                z, (s1, s2, t1, t2, pre, hq, _, _) = quantized(p, a)
                h = hq * s1 / 2
                w2 = t2 * s2
                gate = (pre > 0) & (pre < 81)
            else:
                pre = a @ p[0] + p[1]
                h = np.maximum(pre, 0)
                w2 = p[2]
                gate = pre > 0
                z = h @ w2 + p[3]
            z -= z.max(axis=1, keepdims=True)
            dz = np.exp(z); dz /= dz.sum(axis=1, keepdims=True)
            dz[np.arange(len(rows)), y[rows]] -= 1
            dz /= len(rows)
            dh = (dz @ w2.T) * gate
            gradients = [a.T @ dh + .0001 * p[0], dh.sum(axis=0),
                         h.T @ dz + .0001 * p[2], dz.sum(axis=0)]
            step += 1
            rate = .003 * (1 - .8 * epoch / EPOCHS)
            for i, g in enumerate(gradients):
                m[i] = .9 * m[i] + .1 * g
                v[i] = .999 * v[i] + .001 * g * g
                p[i] -= rate * (m[i] / (1 - .9 ** step)) / (np.sqrt(v[i] / (1 - .999 ** step)) + 1e-8)
        z = forward(p, x[valid], ternary)
        z -= z.max(axis=1, keepdims=True)
        loss = float(np.mean(np.log(np.exp(z).sum(axis=1)) - z[np.arange(len(valid)), y[valid]]))
        if loss < best_loss:
            best_loss, best = loss, [a.copy() for a in p]
        if epoch % 30 == 0 or epoch == EPOCHS - 1:
            print(('ternary' if ternary else 'float32'), epoch, 'validation accuracy',
                  round(float(np.mean(z.argmax(axis=1) == y[valid])), 4), flush=True)
    return best, best_loss


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--output', type=Path, default=Path('resources/vision'))
    args = parser.parse_args()
    raw = args.archive.read_bytes()
    if hashlib.sha256(raw).hexdigest() != ARCHIVE_SHA256:
        raise ValueError('Archive does not match the pinned UCI dataset')
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        train_data = np.loadtxt(io.BytesIO(z.read('optdigits.tra')), delimiter=',', dtype=np.int32)
        test_data = np.loadtxt(io.BytesIO(z.read('optdigits.tes')), delimiter=',', dtype=np.int32)
    assert train_data.shape == (3823, 65) and test_data.shape == (1797, 65)
    for data in (train_data, test_data):
        assert ((data[:, :64] >= 0) & (data[:, :64] <= 16)).all()
        assert ((data[:, 64] >= 0) & (data[:, 64] <= 9)).all()
    x, y = train_data[:, :64] / 16, train_data[:, 64]
    fp, fl = train(x, y, False)
    qp, ql = train(x, y, True)
    _, (_, _, w1, w2, _, _, b1, b2) = quantized(qp, x[:1])
    # Runtime float baseline uses float32 parameters and arithmetic.
    fp = [a.astype(np.float32) for a in fp]
    tx, ty = test_data[:, :64] / 16, test_data[:, 64]
    h = np.clip(np.floor((test_data[:, :64] @ w1 + b1) / 8), 0, 81)
    qcorrect = int(np.sum((h @ w2 + b2).argmax(axis=1) == ty))
    fcorrect = int(np.sum(forward(fp, tx.astype(np.float32), False).argmax(axis=1) == ty))
    assert max(abs(b1)) <= 2048 and max(abs(b2)) <= 8192
    target = args.output; target.mkdir(parents=True, exist_ok=True)
    weights = np.concatenate((w1.T.flatten(), w2.T.flatten())).astype(int)
    packed = np.array([sum((int(v)+1)*3**j for j, v in enumerate(weights[i:i+5]))
                       for i in range(0, len(weights), 5)], dtype=np.uint8)
    (target / 'vision-weights.bin').write_bytes(packed.tobytes())
    arrays = [('packedWeights', 'uint8_t', packed), ('bias1', 'int32_t', b1),
              ('bias2', 'int32_t', b2),
              ('floatWeights1', 'float', fp[0].T), ('floatBias1', 'float', fp[1]),
              ('floatWeights2', 'float', fp[2].T), ('floatBias2', 'float', fp[3])]
    header = '// SPDX-License-Identifier: CC-BY-4.0\n// Generated by scripts/train_vision.py. See VISION-NOTICE.md for data attribution.\n#pragma once\n#include <cstdint>\nnamespace tunguska::vision::model {\n'
    for name, ctype, values in arrays:
        flat = values.flatten()
        encoded = [(format(float(a), '.9e') + 'f') if ctype == 'float' else str(int(a)) for a in flat]
        header += f'inline constexpr {ctype} {name}[{len(flat)}] = {{\n'
        header += '\n'.join(','.join(encoded[i:i+16]) + ',' for i in range(0, len(flat), 16)) + '\n};\n'
    header += f'inline constexpr int testCount = 1797, ternaryCorrect = {qcorrect}, floatCorrect = {fcorrect};\n}}\n'
    (target / 'model.h').write_text(header)
    (target / 'vision-digits.bin').write_bytes(b'TVDIGIT1' + struct.pack('<I', len(test_data)) + test_data.astype(np.uint8).tobytes())
    meta = dict(dataset='UCI Optical Recognition of Handwritten Digits', doi='10.24432/C50P49',
                license='CC-BY-4.0', archive_sha256=ARCHIVE_SHA256, seed=SEED, numpy=np.__version__,
                architecture=[64, HIDDEN, 10], epochs=EPOCHS, fit_samples=3323, validation_samples=500,
                test_samples=1797, checkpoint_selection='lowest training-split validation cross entropy',
                ternary_validation_loss=ql, float_validation_loss=fl,
                ternary_correct=qcorrect, float32_correct=fcorrect,
                nonzero_weights=int(np.count_nonzero(w1) + np.count_nonzero(w2)),
                hidden_rule='clamp(floor((dot(input, ternary_weights) + integer_bias) / 8), 0, 81)',
                output_rule='dot(hidden, ternary_weights) + integer_bias; lowest index wins ties',
                model_sha256=hashlib.sha256((target/'model.h').read_bytes()).hexdigest(),
                test_data_sha256=hashlib.sha256((target/'vision-digits.bin').read_bytes()).hexdigest())
    (target / 'vision-model.json').write_text(json.dumps(meta, indent=2) + '\n')
    print(json.dumps(meta, indent=2))


if __name__ == '__main__':
    main()
