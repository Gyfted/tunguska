#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Reproduce local search measurements using the Mac's own manual text.

No network access or dataset distribution. Installed manuals retain their
respective copyrights. The local copies live only in the chosen build folder.
"""
import argparse
import hashlib
import json
import platform
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QUERIES = [
    'file permissions', 'network connection', 'process memory', 'certificate signing',
    'search regular expression', 'display window', 'disk device', 'compression archive',
    'password authentication', 'socket address', 'thread signal', 'directory symbolic link',
    'unicode character encoding', 'time date timezone', 'print document', 'audio video',
    'error status', 'backup restore', 'encryption key', 'resource limit',
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build' / 'search-benchmark')
    parser.add_argument('--meaning', action='store_true', help='Include Apple embeddings and benchmark ternary shortlist vs exhaustive FP32')
    parser.add_argument('--max-files', type=int, default=10000, help='Use a smaller corpus for slower meaning indexing')
    args = parser.parse_args()
    if not 1 <= args.max_files <= 10000:
        parser.error('--max-files must be 1..10000')
    args.output.mkdir(parents=True, exist_ok=True)
    corpus = args.output / 'corpus'
    corpus.mkdir(exist_ok=False)  # Refuse to reuse a possibly stale corpus.
    manifest = []
    for path in sorted(Path('/usr/share/man').rglob('*')):
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 1024 * 1024:
            continue
        data = path.read_bytes()
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError:
            continue
        if len(text) < 200 or '\x00' in text:
            continue
        name = path.relative_to('/usr/share/man').as_posix().replace('/', '__') + '.txt'
        (corpus / name).write_bytes(data)
        manifest.append(dict(source=str(path), sha256=hashlib.sha256(data).hexdigest(), bytes=len(data)))
        if len(manifest) >= args.max_files:
            break
    if not manifest:
        raise RuntimeError('No suitable installed manual text found')
    (args.output / 'source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    queries = args.output / 'queries.txt'
    queries.write_text('\n'.join(QUERIES) + '\n')
    subprocess.run(['make', 'build/search-cli'], cwd=ROOT, check=True)
    command = [str(ROOT / 'build/search-cli'), str(corpus), 'unused', '--benchmark', str(queries)]
    command += ['--meaning'] if args.meaning else ['--keywords-only']
    result = json.loads(subprocess.check_output(command, cwd=ROOT, text=True))
    tracked = ['src/search.h', 'src/search.cc', 'src/search_cli.mm', 'src/macos/SearchService.h', 'src/macos/SearchService.mm', 'Makefile']
    result['source_file_sha256'] = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in tracked}
    result['host_platform'] = platform.platform()
    result['queries'] = QUERIES  # These are the public test queries, not private UI queries.
    result['corpus_description'] = 'UTF-8 installed macOS manual source text, <=1 MiB/file, >=200 characters. No symlinks or NUL bytes.'
    result['source_manifest_sha256'] = hashlib.sha256((args.output / 'source-manifest.json').read_bytes()).hexdigest()
    output = args.output / 'report.json'
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({k: result[k] for k in ['documents', 'passages', 'native_median_ms', 'reference_median_ms', 'speedup', 'recall_at_20', 'min_query_recall_at_20', 'two_times_target_met']}, indent=2))
    print(output)


if __name__ == '__main__':
    main()
