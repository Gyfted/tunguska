# The Mac interface

The 0.12 interface update belongs to the independent Mac fork maintained by
Vinny Lingham. Original Tunguska remains credited to Viktor Lofgren. All existing
licenses and data attribution remain in the repository and app.

## Find your way around

The Computer window has a sidebar with three experiments and four original
programs. Short descriptions explain what each experiment does. Run, Step and
Debugger sit beside the display; the current system image and virtual disk have
their own panel below it. CPU registers live in the debugger.

- **⌘1:** return to Computer without resetting its memory or disk.
- **⌘2 / ⌘L:** Vision Lab.
- **⌘3 / ⌘E:** Explorer.
- **⌘4 / ⌘G:** Weight Race.
- **⌘W:** close the active window. The Window menu lists open windows.
- **View → Appearance:** follow the system, or choose Light or Dark.

Opening an experiment pauses the original computer. Returning to Computer
preserves that pause; choose Run when ready. Reset and original-program buttons
still start fresh state and eject the virtual disk; their tooltips explain this.
Machine/file commands cannot silently operate the original computer from another
lab. In a debugger, ⌘P and ⌘. run/pause and step that debugger's runtime.
⌘D opens the relevant guest debugger from Vision Lab or Explorer.

Every lab and debugger has a Computer button in its header. Pages scroll
vertically; at narrow widths the fixed scientific panels can also scroll
horizontally. Window frames and appearance are stored locally in the app's
sandbox. No experiment results, drawings or virtual-machine state are persisted
by these interface preferences.

## Read the experiments

Vision Lab is organized as **input → neurons → prediction**, followed by model
accuracy comparisons. The mistake browser uses the same page structure. The
canvas, model inputs, score meanings and uncertainty behavior are unchanged.

Explorer groups mission settings with both maps and the robot's status, with
recent decisions underneath. Map symbols still distinguish blocked, unknown,
clear, base, goal and robot; the interface does not rely on color alone.

Weight Race groups setup, measured results and completed comparisons. Use the
**View completed layer** selector beside the chart title, or select a table row
with the mouse/arrow keys, to revisit that layer's charts, exact-match counts,
seed, rounds, timing ranges and verdict. New runs replace the current result set;
export first if you want to keep it. Cancel retains fully completed layers.
Selecting a result does not run the GPU again or change exported measurements.

The debugger separates processor state from address navigation, disassembly,
read-only memory and breakpoint controls. Double-click an instruction to toggle
its breakpoint. The address field also accepts Return. The instruction set,
address formats, breakpoint semantics and memory protections are unchanged.

## Presentation and access

The shared AppKit interface uses semantic system colors, native buttons, SF
Symbols, selectable text, consistent spacing and rounded content panels. The
terminal and data grids retain their intentional dark plotting surfaces. Light
and dark appearance changes apply to open windows. Controls expose labels and
help to accessibility clients; all lab navigation is available in the menu bar.

Build with `make app`. The interface adds no downloaded fonts, runtime libraries,
network access or new entitlements. Apple signing and notarization remain a
separate release step.
