#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Independent Mac fork, 2026-09-24.
"""Preprocess 3CC sources, compile assembly, and optionally assemble a guest image."""
import argparse
import os
from pathlib import Path
import resource
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def child_limits():
    # These bound individual build steps; they are not a filesystem sandbox.
    resource.setrlimit(resource.RLIMIT_CPU, (30, 30))
    resource.setrlimit(resource.RLIMIT_FSIZE, (64 * 1024 * 1024, 64 * 1024 * 1024))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run(command):
    subprocess.run([str(x) for x in command], check=True, timeout=60, preexec_fn=child_limits)


def compile_sources(sources, output, *, origin="0", assembly=False, includes=(), backend=None):
    sources = [Path(source).resolve() for source in sources]
    output = Path(os.path.abspath(output))  # Keep the final symlink visible to lstat.
    for source in sources:
        if not source.is_file() or source.stat().st_size > 4 * 1024 * 1024:
            raise ValueError(f"Input must be a regular file no larger than 4 MiB: {source}")
        if output.resolve() == source:
            raise ValueError("Output must not overwrite an input source")
    mode = 0o600
    if output.exists() or output.is_symlink():
        info = output.lstat()
        if not stat.S_ISREG(info.st_mode):
            raise ValueError("Output must be a regular file, not a symlink or device")
        mode = stat.S_IMODE(info.st_mode)
    with tempfile.TemporaryDirectory(prefix="tunguska-3cc-") as work:
        work = Path(work)
        preprocessed = []
        for index, source in enumerate(sources):
            pp = work / f"{index}.ppc"
            command = ["xcrun", "clang", "-E", "-x", "c", "-undef", "-nostdinc", "-Werror"]
            command += ["-I" + str(Path(path).resolve()) for path in includes]
            run([*command, source, "-o", pp])
            preprocessed.append(pp)
        generated = work / "program.asm"
        run([backend or ROOT / "build/3cc", "-O", origin, "-o", generated, *preprocessed])
        result = generated
        if not assembly:
            result = work / "program.ternobj"
            run([ROOT / "build/tg_assembler", "-o", result, generated])
        fd, temporary = tempfile.mkstemp(prefix="." + output.name + ".", dir=output.parent)
        try:
            with os.fdopen(fd, "wb") as destination, result.open("rb") as source:
                shutil.copyfileobj(source, destination)
                os.fchmod(destination.fileno(), mode)
                destination.flush()
                os.fsync(destination.fileno())
            os.replace(temporary, output)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", nargs="+", type=Path)
    parser.add_argument("-o", "--output", required=True, type=Path)
    parser.add_argument("-S", "--assembly", action="store_true", help="write assembly instead of a memory image")
    parser.add_argument("-O", "--origin", default="0", help="signed decimal, 0n balanced nonary, or 0t ternary")
    parser.add_argument("-I", "--include", action="append", default=[], help="guest header search directory")
    args = parser.parse_args()
    try:
        output = compile_sources(args.sources, args.output, origin=args.origin,
                                 assembly=args.assembly, includes=args.include)
        print(f"Built {output}")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"3cc: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
