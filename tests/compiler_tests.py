#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compile, assemble and execute 3CC fixtures; reject malformed inputs transactionally."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from compile_3cc import compile_sources


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sanitized', action='store_true')
    args = parser.parse_args()
    backend = ROOT / ('build/3cc-sanitized' if args.sanitized else 'build/3cc')
    runner = ROOT / 'build/compiler-runner'
    with tempfile.TemporaryDirectory(prefix='tunguska-compiler-tests-') as folder:
        work = Path(folder)
        def execute(name, declarations, body, expressions, expected):
            source = work / (name + '.3c')
            stores = '\n'.join(f'*(int*){100010+2*i} = {e};' for i, e in enumerate(expressions))
            source.write_text('asm("SEI", "JSR main", "stop: JMP stop");\n' + declarations +
                              '\nvoid main() {\n' + body + '\n' + stores + '\n*(char*)100000 = 99;\n}\n')
            image = work / (name + '.ternobj')
            compile_sources([source], image, backend=backend)
            result = subprocess.run([str(runner), str(image), *map(str, expected)],
                                    text=True, capture_output=True, timeout=30)
            assert result.returncode == 0, f'{name}: {result.stderr}\n{result.stdout}'
            print(f'PASS 3CC {name}', flush=True)

        execute('arithmetic', '', 'int a = 1000; int b = 27; char c = 13; char d = 5;',
                ['a+b', 'a-b', 'a*b', 'a/b', 'a%b', '13%5', '-13%5', 'c+d', 'c*d',
                 'c/d', 'c%d', '0nD04', '0tP0N'], [1027,973,27000,37,1,3,-3,18,65,2,3,-320,8])
        execute('calls', '''int add(int a, char b) { return a+b; }
char select(char a, int b) { return a + b; }
int fib(int n) { if (n <= 1) return n; return fib(n-1)+fib(n-2); }
int array_arg(int a, char values[]) { return a + values[1]; }
''', 'char values[] = {2, 7, 11};', ['add(1000,7)', 'select(3,1000)', 'fib(8)', 'array_arg(900,values)'],
                [1007,274,21,907])
        execute('control', '', '''int i = 0; int total = 0;
for (i=0; i<10; i++) { int local = i; if(local==3) continue; if(i==8) break; total += i; }
while (i>0) { i--; }
''', ['total', 'i'], [25,0])
        execute('arrays_structs', 'struct Pair { int x; char y; };', '''int grid[2][3] = {{1,2,3},{4,5,6}};
struct Pair pair = {1000,7}; char values[] = {3,9,27};
pair.x += values[1];
grid[1][2] = 42;
''', ['grid[0][2]', 'grid[1][2]', 'pair.x', 'pair.y', 'sizeof(grid)'], [3,42,1009,7,12])
        execute('compound_logic', '', '''char a = 3; char b = 3; char c = 3;
a ^= 1; b |= 1; c &= 1;
''', ['a-(3^1)', 'b-(3|1)', 'c-(3&1)'], [0,0,0])
        execute('ternary_logic', '', 'int a = 729; int b = -729; int c = 0;',
                ['a&&a', 'a&&b', 'b||a', 'b||b', 'c&&a', 'c||b'], [1,-1,1,-1,0,0])
        execute('strings_comments', '', '''/* multiline
comment */ char* text = "A\\n" "B\\tC"; // a line comment
''', ['text[0]', 'text[1]', 'text[2]', 'text[3]', 'text[4]', 'text[5]'], [10,2,11,3,12,0])

        # Each rejection must be a normal diagnostic, never a crash or partial output.
        bad = {
            'syntax': 'void main( {',
            'unknown_token': 'void main() { @; }',
            'decimal_overflow': 'int value = 999999999999999999999;',
            'nonary_overflow': 'int value = 0n444444444444444444;',
            'constant_overflow': 'int value = 200000 * 200000;',
            'divide_zero': 'int value = 9/0;',
            'remainder_zero': 'int value = 9%0;',
            'array_zero': 'char value[0];',
            'array_overflow': 'int value[265720][265720];',
            'initializer_overflow': 'char value[1] = {1,2};',
            'unterminated_comment': '/* never closed',
            'unterminated_string': 'char* value = "not closed;',
            'bad_escape': 'char* value = "A\\q";',
            'unknown_symbol': 'void main() { missing = 1; }',
            'unknown_function': 'void main() { missing(); }',
            'large_frame': 'void main() { char values[365]; }',
            'unknown_struct': 'struct Missing value;',
            'bad_field': 'void main() { int* p = (int*)1000; p->nope = 1; }',
            'break_outside_loop': 'void main() { break; }',
            'arity': 'int f(int a) { return a; } void main() { f(); }',
            'duplicate_long_name': 'int '+('a'*10000)+';\nint '+('a'*10000)+';',
        }
        for name, text in bad.items():
            source = work / (name + '.ppc'); source.write_text(text)
            output = work / (name + '.asm'); output.write_bytes(b'previous good output\n')
            result = subprocess.run([str(backend), '-o', str(output), str(source)],
                                    capture_output=True, text=True, timeout=10)
            assert result.returncode == 1 and 'error:' in result.stderr, f'{name}: exit {result.returncode}\n{result.stderr}'
            assert 'Sanitizer' not in result.stderr and 'runtime error:' not in result.stderr, result.stderr
            assert output.read_bytes() == b'previous good output\n', name
        print(f'PASS 3CC {len(bad)} malformed-input and output-preservation checks', flush=True)
        result = subprocess.run([str(backend), '-o', str(work/'missing.asm'), str(work/'missing.ppc')],
                                capture_output=True, text=True, timeout=10)
        assert result.returncode == 1 and not (work/'missing.asm').exists()
        for origin in ['junk', '265721', '0n', '-999999999999999999999']:
            result = subprocess.run([str(backend), '-O', origin, str(source)], capture_output=True, timeout=10)
            assert result.returncode == 1
        # The public driver preserves images when preprocessing fails, and does not follow output symlinks.
        invalid = work/'invalid.3c'; invalid.write_text('#include "missing.3h"\n')
        image = work/'existing.ternobj'; image.write_bytes(b'existing image')
        try:
            compile_sources([invalid], image, backend=backend)
            raise AssertionError('Missing include was accepted')
        except subprocess.CalledProcessError:
            assert image.read_bytes() == b'existing image'
        link = work/'linked.ternobj'; link.symlink_to(image)
        try:
            compile_sources([invalid], link, backend=backend)
            raise AssertionError('Output symlink was accepted')
        except ValueError:
            assert image.read_bytes() == b'existing image'
        # End-to-end original guest system: compiler -> assembler -> original CPU -> keyboard.
        names = ['string', 'stdio', 'math', 'main', 'system', 'graphics', 'demos']
        guest = work/'guest.ternobj'
        compile_sources([ROOT/'resources/memory_image_3cc'/f'{name}.c' for name in names], guest,
                        origin='0n400000', backend=backend)
        result = subprocess.run([str(ROOT/'build/tunguska-cli'), str(guest), 'HELP'],
                                capture_output=True, text=True, timeout=30, check=True)
        assert 'Welcome to the 3CC memory image!' in result.stdout and 'available commands' in result.stdout
        print('PASS original 3CC guest boot and HELP', flush=True)
        hello = work/'hello.ternobj'
        compile_sources([ROOT/'examples/hello.3c'], hello, backend=backend)
        result = subprocess.run([str(ROOT/'build/tunguska-cli'), str(hello)], capture_output=True,
                                text=True, timeout=30, check=True)
        assert 'HELLO FROM 3CC!' in result.stdout
        print('PASS 3CC hello example', flush=True)
    print('PASS compiler integration' + (' with ASan/UBSan' if args.sanitized else ''), flush=True)


if __name__ == '__main__':
    main()
