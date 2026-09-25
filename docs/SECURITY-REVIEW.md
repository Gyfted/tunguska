# Security review — September 25, 2026 (0.12.2)

A targeted local code review of baseline `a17d9330ff81375d6db24b5584e8fd06d62419ae`
covered the emulator, image loading/saving, native UI and labs, assembler, 3CC
compiler/driver, and release verification. This is maintainer-led review, not an
independent audit or a guarantee against vulnerabilities. Confirmed problems
were fixed in 0.12.2; the historical reviews below retain their original scope.

## Findings and fixes

| Finding | Impact and evidence | Fix |
| --- | --- | --- |
| Assembler arithmetic and host integer conversion (medium) | `@DT 1/0`, `@DT 2147483647+1` and `@DT 2147483647` triggered sanitizer failures: division by zero and signed overflow, including normalization before the tryte lookup. No code-execution exploit was established. | Checked decimal/expression arithmetic, widened host conversion/addition/address arithmetic, validated nonary strings and shifts. Tests include INT_MIN/INT_MAX and previous-output preservation. |
| Unbounded image input and blocking file types (medium) | The old loader blocked opening a FIFO until the reproduction timed out. Bounding decompressed output did not bound compressed input/header scanning. | Open nonblocking, validate the opened descriptor as a regular file, cap encoded input at 8 MiB even if it grows, bound decompression, and reject extra gzip members/trailing bytes. Validation completes before memory changes. |
| Guest batch budget checked too infrequently (medium) | A guest loop requesting large block operations executed 1,024 instructions in 408.967 ms against a requested 1 ms budget. | Check elapsed time after each instruction/peripheral cycle. The same optimized probe yielded after 3 instructions in 1.600 ms on this host. This remains cooperative: a single operation and final display capture can overshoot. |
| Unbounded guest diagnostics and excess motion processing (low) | Guest DEBUG and invalid peripheral operations could repeatedly print; huge host motion deltas kept allocating/discarding interrupts after the queue filled. | Share a 64-event diagnostic budget per machine lifetime; retain explicit host tracing separately. Stop motion processing at the 4,096-event capacity; clamp finite native event deltas before conversion. |
| Final distribution ZIP skipped on re-verification (medium, local release integrity) | An already-notarized candidate checked app/source but never checked its final ZIP or SHA256SUMS. A replacement ZIP could therefore evade that check. | Require the final archive name/path/hash and exact distribution checksum file. Tampered/missing ZIP and checksum regressions pass. The local manifest remains trusted; this does not authenticate a maliciously rewritten manifest. |
| Assembler silent input corruption/resource exposure (low) | `@DT 1!` succeeded with an ignored character; `1.5f` was lexed starting two characters late. Very large reservations/emission and origins lacked bounds. | Reject unknown tokens and invalid floats, retain full float text, bound source file size, origins and total emission/reservations, wrap the guest PC safely, release include streams, and correct the lexer return signature. |

The assembler and 3CC are separate command-line developer tools, not native app
components. Source includes are intentional host-file access and remain trusted
inputs. Their size checks are not a filesystem sandbox or a hard process-wide
resource limit. The assembler now limits each regular source file to 4 MiB,
include depth to the existing 100-file bound, and total emitted trytes per pass
to one guest address space. Repeated overlapping emissions also consume that
budget. This can reject formerly accepted oversized assembly.

Valid raw little-endian images and single-member gzip images remain supported,
including both original guest OS builds. Concatenated gzip members and trailing
junk are now intentionally rejected. These are format restrictions, not a claim
that every historically accepted file is still accepted.

## Verification and reproduction

```sh
make test sanitize security-check
make assembler-check assembler-sanitize image-fuzz-check
make compiler-check compiler-sanitize
make vision-check vision-sanitize explorer-check explorer-sanitize
make weight-check weight-sanitize weight-gpu-validation rendering-check
make sandbox-check verify-app release-check
```

The native ARM64 checks passed on Apple M5 Max. They include exhaustive tryte and
word tests, 2,125,764 ADD/CMP cases, 23,328 randomized opcode/state cases, original
boot/HELP and demos, 19 malformed assembler inputs, compiler execution/rejection
fixtures, 1,797 Vision guest/reference comparisons, 622 Explorer plan comparisons,
GPU reference and Metal validation, and 288 offscreen drawing cases. Smaller
sanitized Vision/Explorer suites run separately. Existing atomic-save,
sandbox-denial and user-selected-file checks remain part of release gates.

`image-fuzz-check` is **bounded, seeded mutation testing**, not coverage-guided
fuzzing. Its 4,096 mutations cover compressed bytes, raw payloads, truncations,
trailing bytes and recompressed payloads with valid CRCs. This run accepted 142
valid mutations and rejected 3,954, with no ASan/UBSan/float-cast-overflow failure.
The stock toolchain lacks the libFuzzer runtime; sustained coverage-guided
fuzzing is still future work. Fixed regressions additionally cover FIFO input,
compressed expansion, corrupt CRCs, invalid final trytes, oversized input,
concatenated gzip members, extreme arithmetic/shifts, diagnostic flooding and
expensive guest operations.

Clang static analysis covered 30 translation units. No diagnostics were reported
for the app/core/runtime/lab sources. Re-analysis of all changed C++/Objective-C++
translation units, including the assembler, also reported none. The legacy 3CC
compiler still has 11 analyzer warnings: allocation/stream lifetime and possible
null-object paths. These have not all been established as reachable source-input
bugs or eliminated; they are not a clean compiler security sign-off. Parser/token
and AST ownership modernization remains unfinished.

Local evidence is in `build/security-review-20260925/`: baseline sanitizer logs,
FIFO and budget reproductions, analyzer summaries, `full-checks.log` and
`sandbox.log`. Every new clean release build reruns the regression gates,
including assembler sanitizers and image mutations. Build artifacts/logs stay
outside the source repository; tests and this report are included in source.

## Remaining security boundaries

- Guest execution and rendering still share the UI process. Limits are cooperative;
  there is no hard per-operation CPU/memory limit or separate guest worker sandbox.
- The compiler and assembler are trusted-source developer tools. Includes can read
  host files, and historical parser/AST allocations can persist until process exit.
  3CC's public driver has CPU/wall/output limits but no hard memory cap.
- Randomized tests, static analysis and Apple notarization do not establish memory
  safety, full ISA/compiler correctness, or protection against every malformed input.
- System zlib, AppKit, Metal and macOS are supplied by Apple. This review did not
  audit their internals or query a current CVE database. Intel slices and older
  supported macOS versions still need runtime testing on those systems.
- Filesystem coordination and atomic rename do not exclude uncooperative local
  processes or guarantee directory-metadata durability after power loss. Regular
  files on slow/network filesystems can still stall synchronous reads.

App Sandbox, hardened runtime and the two minimal file-access entitlements remain
required. The universal 0.12.2 candidate from commit
`763b4d5d1c7dfa1f3200df8828675ec4d95191bd` passed all clean-build release gates,
Developer ID signing, Apple notarization, stapling and Gatekeeper assessment on
September 25, 2026. The app extracted from the final ZIP passed the same security
configuration/notarization checks; final ZIP/source hashes and SHA256SUMS were
re-verified. Apple submission `4b63b948-e9c4-476b-9541-82639bec4ad8` was Accepted
with no reported issues. Artifacts, complete matching source and logs are in
`build/releases/0.12.2-763b4d5d1c7d/`. The ARM64 slice was executed; the Intel slice
was built and inspected, not runtime-tested. No GitHub binary release was published.

---

# Historical targeted security review — September 24, 2026

This is a focused local review of the native Mac preview, not a certification or an independent audit. The relevant attacker-controlled inputs are memory/floppy images, guest instructions and peripheral commands, and pasted keyboard input. The CLI assembler and 3CC compiler are separate developer tools and are not loaded into the app.

## Verified controls

- Image loading limits decompression output to the exact image length plus one byte; truncated, oversized, out-of-range and corrupt images are rejected before memory changes.
- Test inputs include an image expanding to 16 MiB, truncated gzip data, a bad gzip CRC, and missing/invalid files.
- Guest disk LOAD does not resolve host filenames. Guest SYNC does not write the original mounted host file. Tests verify both behaviors. Saving requires a native file-panel action.
- Core image saves use a uniquely created temporary sibling file, check compression completion and `fsync`, and atomically rename only after success. A forced write-failure test verifies the old file remains byte-for-byte intact and partial temporary output is removed. The native app additionally uses `NSFileCoordinator` and an `NSItemReplacementDirectory` to safely replace a selected destination without requesting parent-folder access. Saves reject symbolic-link and other non-regular destinations. Native replacements use Foundation's metadata-preservation behavior; new staged images start with mode 0600.
- The native app now enables App Sandbox and hardened-runtime signing with only the user-selected-file read/write entitlement. No network, broad-folder, hardware, JIT, unsigned-code or debugger-attachment exceptions are granted. CLI tools remain unsandboxed and are not packaged inside the app.
- A separately signed test app with the production entitlements verifies that macOS denies reads/writes of a disposable, unselected private-home fixture and denies an outbound loopback connection. It also verifies bundled OS boot, native save/replacement roundtrips and symbolic-link rejection in its own container. System resources and installed apps remain readable where macOS's standard sandbox permits them.
- Native UI checks cover opening a private user-selected image, Reset using the same URL, mounting a selected disk, creating a saved image and replacing it. The saved image's complete decompressed contents were compared with the mounted fixture.
- Interrupt queues are bounded and clock requests coalesced. The native paste queue is capped at 8,192 ASCII characters.
- Source review found no network API, subprocess launch, shell execution, or dynamically loaded plugin functionality in the app.
- The original release's SHA-256 was checked against its published SourceForge metadata. Only system libraries are linked into the Mac app.

## Findings fixed in this review

1. **Invalid trits from negative remainders.** The original permutation/shift operators could produce −2, outside the legal −1/0/+1 domain. Corrected modular normalization and saturating addition. Exhaustive single-trit closure checks now pass.
2. **Undefined floating-point conversions.** Converting zero attempted to cast negative infinity from `log(0)` to an integer; extreme coprocessor results could also exceed integer ranges. Sanitizer reproduction confirmed the issue. Zero and underflow now have explicit encodings, finite overflow saturates to the representable ternary float, non-finite results raise a guest arithmetic interrupt, and float-to-word conversion rejects out-of-range values before casting. Coprocessor errors acknowledge the request and preserve operand storage.
3. **Signed overflow in word multiplication.** Two 12-trit values can produce a product beyond a 32-bit host integer. Sanitizer reproduction confirmed the issue. Multiplication now uses a 64-bit intermediate and wraps explicitly into the ternary word range.

The security regression suite additionally executes all 729 opcode/address-mode encodings against 32 reproducible randomized register/operand/stack states each (23,328 cases), under AddressSanitizer, UndefinedBehaviorSanitizer and float-cast-overflow instrumentation. This is bounded randomized testing, not comprehensive coverage-guided fuzzing.

## Reproduce

```sh
make test sanitize security-check compiler-check compiler-sanitize
make sandbox-check verify-app release-check
```

The existing suite covers normal guest boot and demos as well as arithmetic. Security output is in `build/security-tests.log`; sanitizer diagnostics fail the target. A Clang static analyzer pass was also run on the core and runtime sources. It identified that the host interrupt API could accept a null pointer; that input is now rejected and regression-tested. This path is not directly guest-accessible. The local analyzer report is in `build/security-analysis/report.txt`.

## Remaining limitations

- The `.app` now has App Sandbox and hardened runtime, but is still ad-hoc signed and not notarized. Developer ID signing and Apple's service require credentials unavailable on the initial build host. Notarization submission, ticket stapling and final Gatekeeper acceptance remain unverified until those credentials exist. The release tooling rejects unexpected entitlements and missing Developer ID signatures before submission.
- The native GUI, assembler/parser, modernized 3CC compiler, and all instruction semantics have not undergone comprehensive fuzzing or independent review. In particular, the assembler supports host-file includes and should be used only on trusted source. It is not a security boundary.
- Guest execution is in the UI process. Expensive guest block operations or excessive debug output can still affect responsiveness and resource consumption. The batch time budget is not a hard per-instruction resource limit.
- No current CVE/database audit of Apple’s system zlib or OS libraries was performed; their security updates come from macOS.
- Not all file-panel/error paths or host filesystem races have been audited. Native saves coordinate with cooperating file presenters; they do not control processes that bypass coordination. Atomic replacement does not guarantee directory-metadata durability across power loss. A process crash may leave a temporary replacement file.

Use the bundled programs and trusted images for this preview. App Sandbox limits host access but does not make the emulator memory-safe or impose hard guest CPU limits. Stronger process/resource isolation, sustained fuzzing and review of the assembler remain work for running arbitrary third-party programs.

## Compiler checks added on September 24, 2026

3CC now builds as a separate C++17 command. Focused hardening covers initialized
state, non-truncating arm64 dimension handling, checked literal and constant
arithmetic, bounded array/function-frame sizes, unknown tokens and unterminated
comments/strings, long duplicate identifiers, bad argument counts and invalid field
access. A sanitizer test exposed signed overflow in constant type selection; range
comparisons replace the old squaring operation. Expression deletion now removes
stale allocation-list entries. String data is emitted as numeric guest trytes.

Both the backend and public driver stage output. Failed parsing/preprocessing
preserves earlier output; the driver rejects symlink/device destinations and
source/output aliases. `compiler-check` and `compiler-sanitize` run the same
compile/assemble/guest-execution fixtures and malformed-input regressions.

The historical AST/type graph still retains allocations until process exit; this
is not a memory-leak-free compiler. The driver limits per-process CPU/wall time and
file output, but has no hard memory cap and is not a filesystem sandbox. Guest
source and assembler includes remain trusted inputs. Compiler tests, boot/HELP and
selected guest programs do not establish exhaustive correctness of the language,
guest OS or ISA. See [the compiler guide](COMPILER.md).

A targeted Clang analyzer pass on the adapted compiler still reported allocation-lifetime and possible null-object paths in the historical expression/initializer graph. Null inputs to array conversion now produce errors, but the remaining reports are not all proven unreachable. This compiler has not received a clean static-analysis or independent-security sign-off.

## Vision Lab checks added on September 24, 2026

The lab uses only bundled, fixed-size numerical parameters and data, with no
networking, model downloads, native-code loading or added entitlements. Dataset
loading checks the exact length/header, count, pixel ranges and labels before
accepting it. Invalid inputs cannot replace a completed session. Guest inference
is bounded at ten million instructions and its full result is rejected if any
activation or score differs from the independently computed integer reference.
Cancel, pause, breakpoint, restart, reference-failure and infinite-loop paths are
regression-tested; ASan/UBSan run boundary, random and selected real inputs.

The native canvas only supplies values 0…16. Reports are bounded by the 1,797
bundled test records and written atomically through a coordinated user-selected
URL. User drawings leave the app only if the user exports a report. No telemetry
or persistent training history is collected. Training is an optional standalone
NumPy script using a pinned official archive, not a runtime app capability.

This targeted work does not change the remaining emulator/compiler limitations
or constitute an independent security audit. The lab shares the existing UI
process; the guest instruction/time budgets are cooperative limits.

A targeted Clang analyzer pass on `src/vision.cc` and `src/macos/VisionLab.mm`
reported no diagnostics. Native UI verification covered drawing, a completed
100-sample benchmark, single-instruction guest debugging, memory navigation,
benchmark pause/cancel, and a successfully parsed partial JSON export through
the sandboxed Save panel. These are focused checks, not exhaustive GUI coverage.

## Vision Lab 0.9 follow-up

Drawing preparation validates all 1,024 ink values for finiteness and range before
bounded resampling; the model paths validate all 64 pixels. Regression checks
include NaN, infinity, out-of-range ink, blank/dense/tiny input, translation
normalization, native sparse/reference agreement, uncertainty ties/boundaries,
and reset after debugging. The optimized guest uses ordinary existing instructions;
there is no JIT or additional entitlement. All 1,797 historical test inputs match
the dense reference exactly, and 30 additionally match the preserved 3CC guest.
ASan/UBSan cover the new controls and selected real guest inputs.

The optional generator reads a fixed-size packed model. Training still reads
only the pinned UCI archive. Native baselines and the mistake browser add no
external loading, networking or persistence. Reports now distinguish native and
guest execution, raw/prepared pixels, raw predictions and abstentions. Obvious
input rejection and a validation-selected score threshold are usability/model
quality measures, not a general detector for unknown or adversarial inputs.

The 0.9 native UI checks cover blank rejection, an off-center drawn digit with
normalization on/off, uncertain output, mistake selection/filtering, guest stepping
from Fast mode, complete 1,797-input guest/native benchmarks, native pause/resume, and
sandboxed JSON exports. Exported aggregates, all 1,797 records and drawing
preparation fields were independently checked. Targeted Clang analysis of the
vision engine and native lab reported no diagnostics. These checks leave the
existing emulator/compiler and independent-review limitations unchanged.

## Ternary Explorer 0.10 checks

Explorer is a fixed-size, offline robot simulation. Its bundled 3CC program runs
through the existing interpreter, with no network, device access, external world
import, native code loading, or new entitlements. The guest receives only the
observed map and mission inputs. Hidden-world access stays in the simulator's
sensor and collision checks. Unknown cells never count as traversable ground.

Inputs validate all cell values, indices, policy and battery bounds before
replacing a session. Every guest action, reason, route, target, direction and
reachable-cell count must match an independent C++ planner before movement.
Invalid lengths, corrupt results and instruction-limit failures cancel the plan.
An edited physical wall can block a previously clear route even when its reading
is missed; the simulator rejects that move and updates the observation. Cancelling
a plan cannot apply a later move, and depleted batteries cannot take free scans.

Normal checks passed 622 guest/reference decisions across boundary/random inputs
and closed-loop missions. Missions exercise all three presets, both priorities
and both sensor modes; seeded-maze missions use guest samples followed by the
native reference, while the other presets use the guest throughout. The smaller
ASan/UBSan suite passed 46 guest/reference decisions plus the host missions.
Regression cases include low-battery return, stale readings after edits, malformed
inputs, tampered outputs, infinite-loop limits, debugger stepping and breakpoints.

Maps have 225 cells. Missions are bounded by 4,096 scans; guest plans have a ten
million instruction limit and cooperative UI execution batches. JSON exports use
the existing coordinated, atomic write through a user-selected Save panel. They
contain export-time maps and bounded decision history, not a complete replay of
world edits or cancelled scans. Native UI checks covered goal completion, live
edits, pause/step/debug, preset/seed/base/goal/options changes, low-battery return
and a parsed JSON export whose routes, counters, energy and reference matches
were independently checked. Targeted Clang analysis of the Explorer engine and
native lab reported no diagnostics.

These are focused checks, not an independent audit or hardware safety validation.
The return reserve is a heuristic and can fail under arbitrary world changes or
lost routes. Guest execution remains in the UI process, and all existing emulator
and compiler limitations above still apply. Developer ID signing and notarization
remain deferred at the maintainer's request.

## Weight Race 0.11 checks — September 25, 2026

Weight Race adds a native Metal/MPS synthetic matrix-vector comparison. The app
loads a fixed bundled shader and generated numerical data; it does not accept
external models, shader files, downloads or network input. Shader compilation
uses the system Metal API. Existing App Sandbox, hardened runtime and minimal
file-panel entitlements remain unchanged. The exported report includes the
shader's SHA-256 and bounded numerical measurements, with no telemetry.

The engine bounds dimensions, rounds and buffer sizes before allocation, checks
device memory limits, and rejects missing GPU support, pipeline/command failures,
invalid timestamps and nonfinite or incorrect output. Every stored weight and
all GPU outputs are verified. Independent integer reference calculations catch
GPU bugs even if both custom kernels agree with each other. A negative test
modifies both kernels to return an incorrect result and verifies rejection.

Host ASan/UBSan and separate Metal API/shader-validation suites passed on Apple
M5 Max. The cases cover one-cell and odd-sized matrices, padded FP16 rows, partial
vectors/SIMD groups, exact FP16/packed/MPS agreement, bounded configuration,
sample summaries, and cancellation during preparation and after warm-up.
Targeted Clang analysis of the host helper, GPU runner and native lab reported
no diagnostics. These checks do not instrument or audit Apple's driver code.

Native UI verification covered a completed four-size sweep, 51-round selection,
new weights, cancellation, and sandboxed JSON export. Exported raw samples,
medians/percentiles, buffer lengths, shader hash and exact-check counts were
independently verified. Performance results are documented in
[the Weight Race guide](WEIGHT-RACE.md), separately from correctness checks.

GPU work runs from a background worker with cooperative cancellation between
bounded commands. An already submitted GPU command cannot be forcibly cancelled
by the app. The app adds no hard process-wide CPU/memory limit, comprehensive GPU
fuzzing, independent security audit or hardware power measurement. Existing
emulator/compiler limitations remain; Apple signing/notarization stays deferred.

## Local Search addition (0.13.0)

Selected-folder text and Markdown reads use bounded regular-file descriptors,
`openat` and `O_NOFOLLOW` for each component. Symlinks, hidden entries, package
contents, FIFOs and devices are excluded. Queries have byte/term limits and
canonical terms are bound into a prepared SQLite statement. The index is
session-only; no network or additional entitlement. SearchService's denial of an
unselected private-home folder and successful in-container lexical/semantic
search are exercised in the real production sandbox test app.

Search tests check exact packed ternary arithmetic, Accelerate against an
independent double-precision cosine reference, seeded approximate recall, native
BM25/SQLite score and result parity, Unicode, PDF page extraction, malformed PDFs,
FIFO/link rejection, cancellation and quality gates under ASan/UBSan. Native UI
checks cover folder selection, paraphrases, excerpts and coordinated JSON export.

PDFKit and NaturalLanguage are Apple frameworks, not bundled third-party
dependencies. PDF parsing remains in-process; file/page/text limits do not bound
internal parser allocations or time. The search addition has not had an external
security audit, PDF fuzz campaign, or Intel/older-macOS runtime validation. See
[SEARCH.md](SEARCH.md) for concrete limits and incomplete capabilities.

Final search UI smoke testing exposed a weak `NSTableCellView.textField` lifetime
error in the newly added result layout. Labels are now retained as subviews
before assignment. The required AppKit regression checks label lifetimes after
autorelease, row bounds and multiline PDF excerpts; it fails on the earlier
implementation with the same nil-array exception and passes after the fix.
The earlier local preview was rejected and never notarized or published.

A second UI test found a dangling C++ callback closure captured by a queued
Objective-C progress block. Search and the matching Weight Race callback now
copy their weak window reference and cancellation token into block-owned locals.
An asynchronous regression deliberately lets indexing finish before draining
the main queue; AddressSanitizer rejects the old callback and passes the fixed
version. `rendering-sanitize` is now a required clean-release gate.

## Ternary Breach addition (0.14.0)

The bundled game adds guest code and static, original map/font/sprite data. It
does not add a native game engine, downloaded content, new CPU instructions,
network access or additional entitlements. Input uses a 27-slot guest ring with
26 usable entries, dropping new events on overflow and processing at most four
before rendering. The native frontend retains its seven-millisecond cooperative
execution budget while allowing larger instruction batches during game rendering.

The required Breach checks execute the actual compiled image, including rapid
input, collision, occlusion, combat, death/restart, pickups and the exit condition.
Instrumented 3CC compilation and ASan/UBSan runtime checks passed, as did the full
clean universal release gates. Native UI checks covered gameplay and actual guest
debugger stepping. The signed and notarized ZIP was extracted and independently
verified; see [BREACH.md](BREACH.md) for its exact source and submission IDs.

This does not add a process boundary around guest execution or a general
execution limit for arbitrary memory images. The one-million-instruction frame
limit belongs to the integration test, not an application-wide watchdog. Existing
emulator, compiler and in-process PDF-parser limitations remain. This is focused
testing, not an independent security audit; Intel runtime testing is outstanding.
