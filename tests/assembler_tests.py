# SPDX-License-Identifier: GPL-2.0-or-later
"""Assembler input regressions: fail safely and preserve previous output."""
import argparse
import gzip
import os
from pathlib import Path
import struct
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--sanitized", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
assembler = root / "build" / ("tg_assembler-sanitized" if args.sanitized else "tg_assembler")
env = dict(os.environ, UBSAN_OPTIONS="halt_on_error=1", ASAN_OPTIONS="abort_on_error=1")
rejected = [
    "@DT 1/0\n", "@DT 2147483647+1\n", "@DT {-2147483647-1}/-1\n",
    "@DT -{-2147483647-1}\n", "@DT 50000*50000\n", "@DT -2147483647-2\n",
    "@DT 99999999999999999999999999999999999999999\n", "@DT 1!\n",
    "@DT 1\\\n", "@DW 1.2.3f\n", "@DW " + "9"*60 + "f\n",
    "@REST 2147483647\n", "@REST -1\n", "@REST 531441\n@DT 1\n",
    "@ORG 2147483647\n@DT 1\n", "@ORG -265721\n", "@INC 'loop.asm'\n",
]
with tempfile.TemporaryDirectory(prefix="tunguska-assembler-") as directory:
    folder = Path(directory)
    source, output = folder / "input.asm", folder / "output.ternobj"
    (folder / "loop.asm").write_text("@INC 'loop.asm'\n")
    def run():
        result = subprocess.run([str(assembler), "-o", str(output), str(source)],
                                cwd=folder, env=env, capture_output=True, timeout=10)
        diagnostics = result.stdout + result.stderr
        assert result.returncode >= 0, diagnostics.decode(errors="replace")
        assert b"runtime error:" not in diagnostics and b"AddressSanitizer" not in diagnostics, diagnostics
        return result
    for index, text in enumerate(rejected):
        source.write_text(text)
        output.write_bytes(b"previous output")
        result = run()
        assert result.returncode != 0, (index, text, result.stdout)
        assert output.read_bytes() == b"previous output", index
    # Regular-file validation also rejects devices/FIFOs before opening them.
    source.unlink()
    os.mkfifo(source)
    assert run().returncode != 0
    source.unlink()
    source.write_bytes(b"x" * (4*1024*1024+1))
    assert run().returncode != 0
    # Large host integers wrap deliberately, and floats retain all their digits.
    source.write_text("@ORG 0\r\n@DT 2147483647,-2147483647-1\r\n@DW 1.5f,-1.5f\r\n"
                      "@DT 12/divisor\n@EQU divisor 3\n@ORG 265720\n@DW 729\n")
    result = run()
    assert result.returncode == 0, result.stdout
    values = struct.unpack("<531441h", gzip.decompress(output.read_bytes()))
    wrap = lambda n: (n+364)%729-364
    assert values[265720:265727] == (wrap(2147483647), wrap(-2147483648), 81, 364, -81, -364, 4)
    assert values[-1] == 1 and values[0] == 0, "word emission must wrap safely across memory end"
print(f"PASS assembler: {len(rejected)+2} malformed inputs, preserved output, valid floats/forward labels/boundary emission")
