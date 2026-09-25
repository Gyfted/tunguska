# Native debugger

The Mac fork adds a debugger around Viktor Lofgren's original instruction set.
It uses the same balanced nonary notation as the original assembler and trace
output. All inspection is read only; breakpoints do not patch guest memory.

## First session

1. Start the bundled OS and click **Debugger**, or press **⌘D**. Opening the
   debugger pauses the processor. The green arrow marks the next instruction.
2. Click **Go to PC** to put the current address into the address field and
   align both views with it. Click **Toggle breakpoint**.
3. Click **Continue**. If no interrupt redirects execution first, the machine
   stops at that address before executing it, with no instruction-count change.
4. Click **Step**. Exactly one instruction runs, leaving the machine paused.
   Interrupt dispatch can redirect the instruction to an interrupt handler.
5. Click **Continue**. A loop revisiting the breakpoint stops there again.
   Continuing directly from a breakpoint bypasses that address once; it does
   not disable or remove the breakpoint.

Double-click an instruction row to toggle its breakpoint. The orange dot shows
an active breakpoint. The breakpoint menu navigates to a saved breakpoint;
**Remove** removes the selected menu entry, and **Clear All** removes all entries.
Reset and successful image replacement clear every breakpoint. Failed image
loads leave the machine and breakpoints intact. Closing the debugger leaves
the machine in its current run/pause state and keeps breakpoints active.

## Addresses and memory

The **Address** field accepts signed decimal from `-265720` to `265720` or a pair
of three-digit balanced nonary trytes such as `333:D04`. Nonary digits are
`0` through `4`, then `A = -1`, `B = -2`, `C = -3`, and `D = -4`. Lowercase is
accepted. `DDD:DDD` and `444:444` are the minimum and maximum addresses.
Invalid input displays an error and leaves the views at their previous address.

**Go** starts both views at the chosen address and turns off **Follow PC**.
Each view provides 81 rows; use the address field to inspect another region.
Addresses wrap from `444:444` to `DDD:DDD`, just like the processor's memory.
**Follow PC** tracks execution in the instruction view without moving the memory
view. **Go to PC** aligns both views and enables following again.

The memory table shows each tryte as decimal, balanced nonary, and six trits
written most significant first: `-`, `0`, `+`. The register line is decimal
except for the explicitly paired nonary program counter. The flag line shows
the processor's C, G, I, B, V, and PR trits.

## Scope

- Disassembly decodes consecutive instructions from the chosen address. It has
  no symbol table and cannot distinguish code from data. `???` marks the two
  undefined opcodes; accumulator/implicit mode has no printed operand.
- Breakpoints stop after interrupt dispatch but before instruction execution.
  The interrupt's stack/register changes are already visible at a handler
  breakpoint. Resuming does not repeat that dispatch or the device heartbeat.
- While running, the window samples state about five times a second. Pause for
  a stable view; this is not a trace of every executed instruction.
- Breakpoints exist for the current image/session only. Conditional breakpoints,
  memory watchpoints, step-over, source labels and reverse execution are future
  work. There is no memory or register editing in this version.

New Mac fork functionality, 2026-09-24. Original Tunguska by Viktor Lofgren;
independent maintenance by Vinny Lingham. GPL-2.0-or-later.
