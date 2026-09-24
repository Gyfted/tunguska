// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac fork debugger, 2026-09-24.
#import "DebuggerWindow.h"
#include "debugger.h"

namespace dbg = tunguska::debugger;
static NSString *String(const std::string& value) { return [NSString stringWithUTF8String:value.c_str()]; }
static NSButton *Control(NSString *title, id target, SEL action) {
    return [NSButton buttonWithTitle:title target:target action:action];
}
static NSTextField *Text(NSString *value, BOOL mono = NO) {
    NSTextField *view = [NSTextField labelWithString:value];
    view.font = mono ? [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular] : [NSFont systemFontOfSize:12];
    return view;
}
static NSStackView *Stack(NSArray<NSView *> *views, BOOL vertical = NO) {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = vertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing = 10;
    return stack;
}

@implementation DebuggerWindow {
    NSTableView *_code, *_memory;
    NSTextField *_address, *_registers, *_state, *_error;
    NSButton *_run, *_follow;
    NSPopUpButton *_breakpoints;
    std::vector<dbg::Instruction> _instructions;
    int _codeStart, _memoryStart;
    bool _hasSnapshot;
    uint64_t _renderedCycles;
    int _renderedPC, _renderedCodeStart, _renderedMemoryStart;
    std::optional<int> _renderedHit;
    std::set<int> _renderedBreakpoints;
}
- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1060, 730)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if (!(self = [super initWithWindow:window])) return nil;
    window.title = @"Tunguska — Debugger";
    window.minSize = NSMakeSize(1000, 620);
    window.releasedWhenClosed = NO;
    [window center];

    _run = Control(@"Pause", self, @selector(toggleRun:));
    _state = Text(@"", YES);
    NSStackView *controls = Stack(@[_run, Control(@"Step", self, @selector(step:)), _state]);
    _registers = Text(@"", YES);
    _registers.selectable = YES;
    _registers.maximumNumberOfLines = 0;
    _address = [NSTextField textFieldWithString:@"000:000"];
    _address.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _address.placeholderString = @"000:000 or decimal";
    _address.accessibilityLabel = @"Memory address";
    _address.target = self; _address.action = @selector(go:);
    [_address.widthAnchor constraintEqualToConstant:145].active = YES;
    _follow = [NSButton checkboxWithTitle:@"Follow PC" target:self action:@selector(follow:)];
    _follow.state = NSControlStateValueOn;
    NSStackView *navigation = Stack(@[Text(@"Address"), _address, Control(@"Go", self, @selector(go:)),
        Control(@"Go to PC", self, @selector(goToPC:)), _follow,
        Control(@"Toggle Breakpoint at Address", self, @selector(toggleAddressBreakpoint:))]);
    _error = Text(@"Decimal: −265720…265720 · Nonary: DDD:DDD…444:444 (A=−1, B=−2, C=−3, D=−4)");
    _error.textColor = NSColor.secondaryLabelColor;

    _code = [self table:@[@[@"breakpoint", @"●", @28], @[@"pc", @"PC", @28], @[@"address", @"Address", @90],
        @[@"bytes", @"Trytes", @120], @[@"instruction", @"Instruction", @190]] label:@"Disassembly"];
    _code.target = self; _code.doubleAction = @selector(toggleSelectedBreakpoint:);
    _memory = [self table:@[@[@"address", @"Address", @90], @[@"decimal", @"Decimal", @75],
        @[@"nonary", @"Nonary", @65], @[@"ternary", @"Trits", @85]] label:@"Read-only memory"];
    NSScrollView *codeScroll = [self scroll:_code], *memoryScroll = [self scroll:_memory];
    NSStackView *codePane = Stack(@[Text(@"DISASSEMBLY · double-click a row to toggle its breakpoint"), codeScroll], YES);
    NSStackView *memoryPane = Stack(@[Text(@"MEMORY · read only · trits shown most significant first"), memoryScroll], YES);
    for (NSScrollView *scroll in @[codeScroll, memoryScroll]) {
        [scroll.widthAnchor constraintEqualToAnchor:scroll.superview.widthAnchor].active = YES;
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    }
    NSStackView *panes = Stack(@[codePane, memoryPane]);
    panes.alignment = NSLayoutAttributeTop;
    [codePane.widthAnchor constraintEqualToAnchor:memoryPane.widthAnchor multiplier:1.5].active = YES;
    [codePane.heightAnchor constraintEqualToAnchor:memoryPane.heightAnchor].active = YES;

    _breakpoints = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _breakpoints.accessibilityLabel = @"Active breakpoints";
    _breakpoints.target = self; _breakpoints.action = @selector(showBreakpoint:);
    [_breakpoints.widthAnchor constraintEqualToConstant:160].active = YES;
    NSStackView *breakpointControls = Stack(@[Control(@"Toggle Selected Breakpoint", self, @selector(toggleSelectedBreakpoint:)),
        _breakpoints, Control(@"Remove", self, @selector(removeBreakpoint:)), Control(@"Clear All", self, @selector(clearBreakpoints:))]);
    NSTextField *hint = Text(@"Stops before execution, including interrupt handlers. Continue passes the current breakpoint once. Reset clears breakpoints.");
    hint.textColor = NSColor.secondaryLabelColor;

    NSStackView *root = Stack(@[controls, _registers, navigation, _error, panes, breakpointControls, hint], YES);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [window.contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:20],
        [root.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:20],
        [root.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-20],
        [root.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor constant:-20],
        [panes.widthAnchor constraintEqualToAnchor:root.widthAnchor]
    ]];
    return self;
}
- (NSTableView *)table:(NSArray<NSArray *> *)columns label:(NSString *)label {
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.usesAlternatingRowBackgroundColors = YES;
    table.rowHeight = 24;
    table.allowsMultipleSelection = NO;
    table.accessibilityLabel = label;
    for (NSArray *entry in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:entry[0]];
        column.title = entry[1]; column.width = [entry[2] doubleValue];
        column.minWidth = column.width;
        [table addTableColumn:column];
    }
    table.dataSource = self; table.delegate = self;
    return table;
}
- (NSScrollView *)scroll:(NSView *)view {
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.documentView = view;
    return scroll;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table {
    return table == _code ? (NSInteger)_instructions.size() : 81;
}
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSTextField *cell = [table makeViewWithIdentifier:column.identifier owner:self];
    if (!cell) { cell = Text(@"", YES); cell.identifier = column.identifier; }
    if (!self.runtime) { cell.stringValue = @""; return cell; }
    NSString *key = column.identifier;
    NSString *value = @"";
    BOOL isPC = NO;
    if (table == _code && row >= 0 && (size_t)row < _instructions.size()) {
        const auto& instruction = _instructions[row];
        isPC = instruction.address == self.runtime->programCounter();
        if ([key isEqual:@"breakpoint"]) value = self.runtime->breakpoints().count(instruction.address) ? @"●" : @"";
        else if ([key isEqual:@"pc"]) value = isPC ? @"→" : @"";
        else if ([key isEqual:@"address"]) value = String(dbg::formatAddress(instruction.address));
        else if ([key isEqual:@"bytes"]) value = String(instruction.bytes);
        else value = String(instruction.text);
    } else if (table == _memory) {
        const int address = dbg::wrapAddress(_memoryStart + (int)row);
        const auto& memory = static_cast<const tunguska::Runtime&>(*self.runtime).cpu().memref(address);
        if ([key isEqual:@"address"]) value = String(dbg::formatAddress(address));
        else if ([key isEqual:@"decimal"]) value = [NSString stringWithFormat:@"%d", memory.to_int()];
        else if ([key isEqual:@"nonary"]) value = String(dbg::nonary(memory));
        else value = String(dbg::ternary(memory));
    }
    cell.stringValue = value;
    cell.textColor = [key isEqual:@"breakpoint"] ? NSColor.systemOrangeColor : isPC ? NSColor.systemGreenColor : NSColor.labelColor;
    return cell;
}
- (void)refresh {
    if (!self.runtime || !self.window.visible) return;
    auto& cpu = self.runtime->cpu();
    const int pc = self.runtime->programCounter();
    _run.title = self.runtime->running() ? @"Pause" : @"Continue";
    const auto hit = self.runtime->stoppedAtBreakpoint();
    _state.stringValue = hit ? [@"Breakpoint at " stringByAppendingString:String(dbg::formatAddress(*hit))]
        : self.runtime->running() ? @"Running · pause to inspect a stable state" : @"Paused";
    _registers.stringValue = [NSString stringWithFormat:@"PC %@ (%d)   A %d   X %d   Y %d   S %d   SP %d   CL %d   Executed %llu\nFlags   C %+d   G %+d   I %+d   B %+d   V %+d   PR %+d",
        String(dbg::formatAddress(pc)), pc, cpu.A.to_int(), cpu.X.to_int(), cpu.Y.to_int(), cpu.S.to_int(), cpu.SP.to_int(), cpu.CL.to_int(),
        (unsigned long long)self.runtime->cycles(), cpu.P[machine::C].to_int(), cpu.P[machine::G].to_int(), cpu.P[machine::I].to_int(),
        cpu.P[machine::B].to_int(), cpu.P[machine::V].to_int(), cpu.P[machine::PR].to_int()];
    if (_follow.state == NSControlStateValueOn) _codeStart = pc;
    const bool breakpointsChanged = !_hasSnapshot || _renderedBreakpoints != self.runtime->breakpoints();
    if (_hasSnapshot && _renderedCycles == self.runtime->cycles() && _renderedPC == pc &&
        _renderedCodeStart == _codeStart && _renderedMemoryStart == _memoryStart && _renderedHit == hit && !breakpointsChanged) return;
    // Keep stable rows while paused so selection, accessibility focus, and open
    // breakpoint menus survive the host app's periodic status refreshes.
    _hasSnapshot = true;
    _renderedCycles = self.runtime->cycles(); _renderedPC = pc;
    _renderedCodeStart = _codeStart; _renderedMemoryStart = _memoryStart;
    _renderedHit = hit; _renderedBreakpoints = self.runtime->breakpoints();
    const NSInteger selected = _code.selectedRow;
    const std::optional<int> selectedAddress = selected >= 0 && (size_t)selected < _instructions.size()
        ? std::optional<int>(_instructions[selected].address) : std::nullopt;
    _instructions.clear();
    int address = _codeStart;
    for (int i = 0; i < 81; ++i) {
        _instructions.push_back(dbg::disassemble(cpu, address));
        address = dbg::wrapAddress(address + _instructions.back().length);
    }
    [_code reloadData]; [_memory reloadData];
    [_code deselectAll:nil];
    for (size_t i = 0; i < _instructions.size(); ++i)
        if (selectedAddress == _instructions[i].address)
            [_code selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
    if (breakpointsChanged) {
        NSNumber *selectedBreakpoint = _breakpoints.selectedItem.representedObject;
        [_breakpoints removeAllItems];
        [_breakpoints addItemWithTitle:[NSString stringWithFormat:@"%zu breakpoints", self.runtime->breakpoints().size()]];
        for (int bp : self.runtime->breakpoints()) {
            [_breakpoints addItemWithTitle:String(dbg::formatAddress(bp))];
            _breakpoints.lastItem.representedObject = @(bp);
            if ([selectedBreakpoint isEqual:@(bp)]) [_breakpoints selectItem:_breakpoints.lastItem];
        }
    }
}
- (void)changed {
    if (self.didChange) self.didChange();
    [self refresh];
}
- (void)imageDidChange {
    _hasSnapshot = false;
    _codeStart = _memoryStart = self.runtime ? self.runtime->programCounter() : 0;
    _address.stringValue = String(dbg::formatAddress(_memoryStart));
    _follow.state = NSControlStateValueOn;
    _error.stringValue = @"Image loaded. Breakpoints cleared.";
    [self refresh];
}
- (void)toggleRun:(id)sender {
    if (self.runtime) { self.runtime->setRunning(!self.runtime->running()); [self changed]; }
}
- (void)step:(id)sender { if (self.runtime) { self.runtime->step(); [self changed]; } }
- (std::optional<int>)enteredAddress {
    auto address = dbg::parseAddress(_address.stringValue.UTF8String ?: "");
    _error.stringValue = address ? @"Nonary digits: 0…4 and A=−1, B=−2, C=−3, D=−4. Memory inspection is read only."
        : @"Invalid address. Enter a decimal integer from −265720 to 265720, or six nonary digits such as 000:000.";
    _error.textColor = address ? NSColor.secondaryLabelColor : NSColor.systemOrangeColor;
    return address;
}
- (void)go:(id)sender {
    const auto address = [self enteredAddress];
    if (!address) return;
    _codeStart = _memoryStart = *address;
    _follow.state = NSControlStateValueOff;
    [_code deselectAll:nil];
    [_code scrollRowToVisible:0]; [_memory scrollRowToVisible:0];
    [self refresh];
}
- (void)goToPC:(id)sender {
    if (!self.runtime) return;
    _address.stringValue = String(dbg::formatAddress(self.runtime->programCounter()));
    [self go:sender];
    _follow.state = NSControlStateValueOn;
}
- (void)follow:(id)sender { [self refresh]; }
- (void)toggleAddressBreakpoint:(id)sender {
    const auto address = [self enteredAddress];
    if (address && self.runtime) { self.runtime->toggleBreakpoint(*address); [self changed]; }
}
- (void)toggleSelectedBreakpoint:(id)sender {
    const NSInteger row = _code.selectedRow;
    if (!self.runtime || row < 0 || (size_t)row >= _instructions.size()) {
        _error.stringValue = @"Select an instruction row first, or enter an address above.";
        return;
    }
    self.runtime->toggleBreakpoint(_instructions[row].address);
    [self changed];
}
- (void)showBreakpoint:(id)sender {
    NSNumber *address = _breakpoints.selectedItem.representedObject;
    if (!address) return;
    _address.stringValue = String(dbg::formatAddress(address.intValue));
    [self go:sender];
}
- (void)removeBreakpoint:(id)sender {
    NSNumber *address = _breakpoints.selectedItem.representedObject;
    if (address && self.runtime && self.runtime->breakpoints().count(address.intValue)) {
        self.runtime->toggleBreakpoint(address.intValue); [self changed];
    }
}
- (void)clearBreakpoints:(id)sender { if (self.runtime) { self.runtime->clearBreakpoints(); [self changed]; } }
@end
