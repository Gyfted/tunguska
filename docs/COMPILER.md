# 3CC on modern Macs

The build now includes an adapted C++17 version of Viktor Lofgren's experimental
**3CC**, derived from `upstream/github/tunguska_3cc/`. The archived originals are
unchanged. This is a continuation of his compiler and ternary language, not an
ISO C implementation. It builds with Apple's Command Line Tools and Python 3;
no additional packages are required.

## Compile a program

From the repository root:

```sh
make -j4
python3 scripts/compile_3cc.py examples/hello.3c -o build/hello-3cc.ternobj
```

Open the resulting image with **File → Open Memory Image**. It displays
`HELLO FROM 3CC!`. Use **⌘D** to inspect the compiled instructions, memory,
registers and breakpoints. A standalone image starts execution at address zero;
the example supplies a small assembly entry stub that calls `main`.

The driver preprocesses headers/macros with Apple Clang, compiles to Tunguska
assembly, and runs `tg_assembler`. `-I path` adds a guest-header directory,
`-O 0n400000` changes the code origin, and `-S` writes assembly for inspection:

```sh
python3 scripts/compile_3cc.py -S examples/hello.3c -o build/hello-3cc.asm
```

Multiple source files are accepted in command-line order. Supply prototypes
before use; the driver combines the generated assembly into one memory image.
Source filenames and line numbers are retained in preprocessing diagnostics.
The lower-level `build/3cc` command accepts already-preprocessed source and
produces assembly, not a `.ternobj` image.

## Original 3CC system

Choose **Machine → Boot Experimental 3CC System**, then type `HELP` and Return.
The app bundles a freshly compiled copy of the original alternative guest OS.
**Machine → Boot Original System** (⌘B) returns to the assembly-based OS. Demo
buttons in the sidebar still boot the assembly-based OS before running a demo.
Both image changes clear the current disk and breakpoints, just like Reset.

Build the 3CC image separately with `make guest-3cc`; the result is
`build/boot-3cc.ternobj`. Its original source and headers are in
`resources/memory_image_3cc/`, copied unchanged from the archived GitHub version.

## Language and implementation limits

- `char` is a signed six-trit tryte (−364…364); `int` and pointers use twelve
  trits (−265720…265720). Guest character codes differ from ASCII.
- The language has ternary logic. Conditions take the positive branch for
  values greater than zero; zero and negative values take the other branch.
  `~` obtains the sign. Logical operators use −1/0/+1 and retain the original
  three-valued semantics. Do not assume ordinary C boolean behavior or precedence.
- Functions, recursion, loops, pointers, arrays, structs, static locals, inline
  assembly and guest headers are supported. Floating-point C types, the host C
  library, and full modern C syntax are not supported.
- Host-side constant arithmetic is checked and rejects values outside the
  twelve-trit range, including division by zero. Runtime arithmetic still follows
  the original guest CPU's wrapping and interrupt behavior.
- A single function frame must fit 364 trytes. Recursion and calls share the
  finite original guest stacks; there is no runtime stack-overflow protection.
- The compiler's historical shared AST/type graph still has process-lifetime
  allocations. It runs as a separate command, not a persistent compiler service.
  A full ownership/type-system redesign remains future work.

Only compile trusted source. The compiler and assembler are unsandboxed developer
tools outside the app. Preprocessing and assembly include directives can read
host files; inline assembly can contain assembler directives. CPU time (30 seconds),
wall time (60 seconds) and individual output-file size (64 MiB) are bounded per
driver subprocess, and source/preprocessed inputs are limited to 4 MiB per file.
These limits are not a memory limit or a security sandbox.

Compilation happens in temporary files. The driver replaces the requested output
only after all stages succeed, retains existing permission bits, and rejects
symlink/device outputs and source/output aliases. The backend also stages its
assembly until parsing succeeds. Errors include a source location where available.

## Validation

```sh
make compiler-check compiler-sanitize
```

The integration suite compiles, assembles and executes programs with checked
guest-memory results for arithmetic, signed remainders, mixed-size arguments,
recursion, array parameters, nested-scope loop control, arrays, structs, compound
tritwise operators, three-valued logic, strings and comments. It also checks
malformed inputs, preservation of previous outputs, preprocessing errors and
symlink rejection. The same fixtures run with ASan and UBSan in the compiler. Native UI checks also
verified switching to the 3CC OS, keyboard `HELP`, a breakpoint stop and a
one-instruction step.
The original 3CC guest must boot and answer `HELP`; the example must render its
greeting. The release preparation command runs these checks too.

This is a tested experimental compiler, not exhaustive language or instruction-set
conformance. Intel slices are built but have not been exercised on Intel hardware.

Original 3CC and guest software © Viktor Lofgren. Independent Mac fork changes
dated 2026-09-24, maintained by Vinny Lingham, under GPL-2.0-or-later.
