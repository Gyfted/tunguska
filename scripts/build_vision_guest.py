#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Specialize the checked-in ternary model into ordinary Tunguska instructions.

This is static ahead-of-time code generation, never host execution or a new ISA.
Weights select addition/subtraction instructions; zero weights emit no work.
The preserved 3CC program is the readable independent guest reference.
"""
import argparse
from pathlib import Path


def generate(packed):
    if len(packed)!=800 or any(v>=243 for v in packed):
        raise ValueError('Expected 800 valid packed weight bytes')
    weights=[]
    for byte in packed:
        for _ in range(5):
            weights.append(byte%3-1);byte//=3
    lines=['; GPL-2.0-or-later generator; model data CC-BY-4.0, see VISION-NOTICE.md.',
           '@ORG 0','entry: SEI','LDA #0','STA 100001','LDA #1','STA 100000']
    for row in range(64):
        hidden=row<54
        size=64 if hidden else 54
        base=row*64 if hidden else 3456+(row-54)*54
        source=100010 if hidden else 100100
        bias=114000+row*2
        lines += [f'neuron{row}: LDX {bias}',f'LDY {bias+1}']
        for col in range(size):
            sign=weights[base+col]
            if not sign: continue
            lines += ['PSH #0']
            if sign>0: lines += [f'PSH {source+col}']
            else: lines += [f'LDA {source+col}','EOR #364','PSH A']
            lines += ['ADW X,Y']
        if hidden:
            lines += ['CAD 0',f'JGT positive{row}','LAD 0',f'positive{row}: PSH #0',
                      'PSH #8','DVW X,Y','CAD 81',f'JLT clipped{row}','LAD 81',f'clipped{row}: STY {100100+row}']
        else: lines += [f'STX {100200+2*(row-54)}',f'STY {100201+2*(row-54)}']
        lines += [f'LDA #{row+1}','STA 100001']
    lines += ['LDA #2','STA 100000','PAUSE','JMP entry']
    return '\n'.join(lines)+'\n'


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('weights',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args()
    args.output.write_text(generate(args.weights.read_bytes()))
