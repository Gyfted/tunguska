// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac frontend, 2026-09-24. Original project: Viktor Lofgren.
#import <Cocoa/Cocoa.h>
#import "DebuggerWindow.h"
#include "runtime.h"
#include <deque>

static NSColor *RGB(unsigned rgb) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255)/255.0 green:((rgb >> 8) & 255)/255.0 blue:(rgb & 255)/255.0 alpha:1];
}
static NSTextField *Label(NSString *text, CGFloat size, NSColor *color, BOOL mono = NO) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = mono ? [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular] : [NSFont systemFontOfSize:size];
    label.textColor = color;
    return label;
}
static NSButton *Button(NSString *title, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

@interface ScreenView : NSView
@property(nonatomic, assign) tunguska::Runtime *runtime;
@property(nonatomic, copy) void (^input)(NSString *);
@end

@implementation ScreenView
- (instancetype)initWithFrame:(NSRect)rect {
    if ((self = [super initWithFrame:rect])) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = RGB(0x09120F).CGColor;
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = 1;
        self.layer.borderColor = RGB(0x2D4238).CGColor;
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityTextAreaRole;
        self.accessibilityLabel = @"Tunguska display";
        self.accessibilityHelp = @"Type commands here. Command-V pastes text. Escape sends the guest break key.";
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    if (_runtime) _runtime->mouseButton(true);
}
- (void)mouseUp:(NSEvent *)event { if (_runtime) _runtime->mouseButton(false); }
- (void)mouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)mouseMoved:(NSEvent *)event {
    if (_runtime && _runtime->frame().mode != 0)
        _runtime->mouse((int)event.deltaX, (int)event.deltaY);
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)keyDown:(NSEvent *)event {
    if (!_runtime) return;
    if (event.keyCode == 53) { _runtime->breakKey(); return; }
    if ((event.modifierFlags & NSEventModifierFlagCommand) == 0 && self.input) self.input(event.characters ?: @"");
}
- (void)paste:(id)sender {
    NSString *text = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    if (text && self.input) self.input(text);
}
- (void)copy:(id)sender {
    if (!_runtime) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:[NSString stringWithUTF8String:_runtime->text().c_str()] forType:NSPasteboardTypeString];
}
- (void)drawRect:(NSRect)dirty {
    if (!_runtime) return;
    const auto& frame = _runtime->frame();
    NSRect area = NSInsetRect(self.bounds, 24, 24);
    if (frame.mode == 0) {
        const CGFloat cellWidth = MIN(area.size.width / tunguska::columns, area.size.height / (tunguska::rows * 1.7));
        const CGFloat cellHeight = cellWidth * 1.7;
        const CGFloat x0 = NSMidX(area) - cellWidth * tunguska::columns/2;
        const CGFloat y0 = NSMidY(area) - cellHeight * tunguska::rows/2;
        NSFont *font = [NSFont monospacedSystemFontOfSize:cellWidth / 0.60 weight:NSFontWeightMedium];
        NSDictionary *attributes = @{NSFontAttributeName:font, NSForegroundColorAttributeName:RGB(0xB4EAD0)};
        NSArray *extra = @[@"▘", @"▌", @"▚", @"▛", @"▀", @"▐", @"▞", @"▟", @"▄", @"█"];
        for (int y = 0; y < tunguska::rows; ++y) for (int x = 0; x < tunguska::columns; ++x) {
            const int code = frame.text[y*tunguska::columns+x];
            NSString *glyph = @"";
            const char c = ternarytoascii(code);
            if (c >= 32) glyph = [NSString stringWithFormat:@"%c", c];
            else if (code >= 76 && code <= 85) glyph = extra[code-76];
            else if (code == 2) glyph = @"↓";
            else if (code == 3) glyph = @"→";
            else if (code == 4) glyph = @"←";
            else if (code == 93) glyph = @"≤";
            else if (code == 94) glyph = @"≥";
            [glyph drawAtPoint:NSMakePoint(x0+x*cellWidth, y0+y*cellHeight) withAttributes:attributes];
        }
    } else {
        const CGFloat aspect = frame.mode == -1 ? 4.0/3.0 : 432.0/270.0;
        NSRect viewport = area;
        if (viewport.size.width / viewport.size.height > aspect) viewport.size.width = viewport.size.height * aspect;
        else viewport.size.height = viewport.size.width / aspect;
        viewport.origin.x = NSMidX(area) - viewport.size.width/2;
        viewport.origin.y = NSMidY(area) - viewport.size.height/2;
        [NSColor.blackColor setFill]; NSRectFill(viewport);
        if (frame.mode == -1) {
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:tunguska::width pixelsHigh:tunguska::height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:tunguska::width*4 bitsPerPixel:32];
            memcpy(bitmap.bitmapData, frame.pixels.data(), frame.pixels.size());
            NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(tunguska::width, tunguska::height)];
            [image addRepresentation:bitmap];
            NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationNone;
            [image drawInRect:viewport fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES hints:nil];
        } else {
            [NSGraphicsContext saveGraphicsState];
            NSRectClip(viewport);
            NSPoint previous = NSMakePoint(NSMidX(viewport), NSMidY(viewport));
            for (const auto& v : frame.vertices) {
                const NSPoint point = NSMakePoint(viewport.origin.x + v.x*viewport.size.width, viewport.origin.y + v.y*viewport.size.height);
                if (v.color != 0 && v.color != -364) {
                    auto c = tunguska::Runtime::color(v.color);
                    [[NSColor colorWithSRGBRed:c[0]/255.0 green:c[1]/255.0 blue:c[2]/255.0 alpha:1] setStroke];
                    NSBezierPath *line = [NSBezierPath bezierPath];
                    [line moveToPoint:previous]; [line lineToPoint:point]; line.lineWidth = 1.5; [line stroke];
                }
                previous = point;
            }
            [NSGraphicsContext restoreGraphicsState];
        }
    }
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
    std::unique_ptr<tunguska::Runtime> _runtime;
    std::deque<char> _input;
    NSTimeInterval _lastStats;
    uint64_t _lastCycles, _revision, _nextInputCycle;
}
@property(strong) NSWindow *window;
@property(strong) NSWindow *licenseWindow;
@property(strong) DebuggerWindow *debugger;
@property(strong) ScreenView *screen;
@property(strong) NSButton *runButton;
@property(strong) NSTextField *registers;
@property(strong) NSTextField *status;
@property(strong) NSTextField *metrics;
@property(strong) NSTextField *mode;
@property(strong) NSTextField *imageLabel;
@property(strong) NSTextField *diskLabel;
@property(strong) NSTimer *timer;
@property(copy) NSString *imagePath;
@end

@implementation AppDelegate
- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Tunguska couldn’t complete that action";
    alert.informativeText = message;
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1140, 750) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Tunguska — Ternary Computer";
    self.window.minSize = NSMakeSize(920, 660);
    self.window.backgroundColor = RGB(0x131C18);
    self.window.delegate = self;
    self.window.acceptsMouseMovedEvents = YES;
    [self.window center];

    NSView *root = self.window.contentView;
    NSStackView *header = [NSStackView stackViewWithViews:@[]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.spacing = 10;
    NSTextField *title = Label(@"TUNGUSKA", 19, RGB(0xD8EEE2), YES);
    title.font = [NSFont monospacedSystemFontOfSize:19 weight:NSFontWeightSemibold];
    [header addArrangedSubview:title];
    NSView *spacer = [[NSView alloc] init]; [header addArrangedSubview:spacer];
    self.runButton = Button(@"Pause", self, @selector(toggleRun:));
    [header addArrangedSubview:self.runButton];
    [header addArrangedSubview:Button(@"Step", self, @selector(step:))];
    [header addArrangedSubview:Button(@"Reset", self, @selector(reset:))];
    [header addArrangedSubview:Button(@"Debugger", self, @selector(showDebugger:))];
    [header addArrangedSubview:Button(@"Open Image…", self, @selector(openImage:))];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *sidebar = [NSStackView stackViewWithViews:@[]];
    sidebar.orientation = NSUserInterfaceLayoutOrientationVertical;
    sidebar.alignment = NSLayoutAttributeLeading;
    sidebar.spacing = 14;
    [sidebar addArrangedSubview:Label(@"A computer in base three.", 14, RGB(0xA1B6A9))];
    [sidebar addArrangedSubview:Label(@"MACHINE", 10, RGB(0x789686), YES)];
    self.status = Label(@"●  Running", 14, RGB(0x8CDBAE));
    [sidebar addArrangedSubview:self.status];
    self.mode = Label(@"54 × 27 · Text mode", 12, RGB(0xA1B6A9));
    [sidebar addArrangedSubview:self.mode];
    [sidebar addArrangedSubview:Label(@"REGISTERS", 10, RGB(0x789686), YES)];
    self.registers = Label(@"", 13, RGB(0xC6D7CD), YES);
    self.registers.maximumNumberOfLines = 0;
    [sidebar addArrangedSubview:self.registers];
    [sidebar addArrangedSubview:Label(@"TRY A PROGRAM", 10, RGB(0x789686), YES)];
    for (NSArray *entry in @[@[@"Command reference", @"HELP"], @[@"Character map", @"CHARMAP"], @[@"Vector random walk", @"BROWN"], @[@"Draw in 729 colors", @"RASTERDEMO729"]]) {
        NSButton *button = Button(entry[0], self, @selector(example:));
        button.identifier = entry[1];
        button.toolTip = [NSString stringWithFormat:@"Boot the bundled system and run %@", entry[1]];
        [sidebar addArrangedSubview:button];
    }
    [sidebar addArrangedSubview:Label(@"IMAGE", 10, RGB(0x789686), YES)];
    self.imageLabel = Label(@"Original Tunguska OS", 12, RGB(0xA1B6A9));
    self.imageLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [sidebar addArrangedSubview:self.imageLabel];
    [sidebar addArrangedSubview:Button(@"Mount Disk…", self, @selector(mountDisk:))];
    self.diskLabel = Label(@"No disk mounted", 11, RGB(0x789686));
    self.diskLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [sidebar addArrangedSubview:self.diskLabel];

    self.screen = [[ScreenView alloc] initWithFrame:NSZeroRect];
    __weak AppDelegate *weakSelf = self;
    self.screen.input = ^(NSString *text) { [weakSelf enqueue:text]; };
    self.metrics = Label(@"Starting…", 11, RGB(0x789686), YES);
    NSTextField *hint = Label(@"Click the display to type  ·  HELP lists commands  ·  Esc sends Break  ·  ⌘V pastes", 11, RGB(0x8FA999));
    for (NSView *view in @[header, sidebar, self.screen, self.metrics, hint]) {
        view.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:root.topAnchor constant:20],
        [header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],
        [header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],
        [header.heightAnchor constraintEqualToConstant:34],
        [sidebar.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:24],
        [sidebar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],
        [sidebar.widthAnchor constraintEqualToConstant:220],
        [sidebar.bottomAnchor constraintLessThanOrEqualToAnchor:self.metrics.topAnchor constant:-12],
        [self.screen.topAnchor constraintEqualToAnchor:sidebar.topAnchor],
        [self.screen.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:24],
        [self.screen.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],
        [self.screen.bottomAnchor constraintEqualToAnchor:hint.topAnchor constant:-14],
        [hint.leadingAnchor constraintEqualToAnchor:self.screen.leadingAnchor constant:4],
        [hint.bottomAnchor constraintEqualToAnchor:self.metrics.topAnchor constant:-12],
        [self.metrics.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],
        [self.metrics.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-16],
        [self.imageLabel.widthAnchor constraintLessThanOrEqualToConstant:215],
        [self.diskLabel.widthAnchor constraintLessThanOrEqualToConstant:215]
    ]];
    [self setupMenu];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self loadImage:[NSBundle.mainBundle pathForResource:@"boot" ofType:@"ternobj"]];
    self.timer = [NSTimer timerWithTimeInterval:1.0/60 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    self.timer.tolerance = 0.002;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)setupMenu {
    NSMenu *bar = [[NSMenu alloc] init];
    NSMenuItem *app = [[NSMenuItem alloc] init]; [bar addItem:app];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Tunguska"]; app.submenu = appMenu;
    [appMenu addItemWithTitle:@"About Tunguska" action:@selector(about:) keyEquivalent:@""];
    [appMenu addItemWithTitle:@"License and Credits…" action:@selector(showLicense:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Quit Tunguska" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem *file = [[NSMenuItem alloc] init]; [bar addItem:file];
    file.submenu = [[NSMenu alloc] initWithTitle:@"File"];
    [file.submenu addItemWithTitle:@"Open Memory Image…" action:@selector(openImage:) keyEquivalent:@"o"];
    [file.submenu addItemWithTitle:@"Mount Disk…" action:@selector(mountDisk:) keyEquivalent:@"m"];
    [file.submenu addItemWithTitle:@"Save Disk As…" action:@selector(saveDisk:) keyEquivalent:@"s"];
    [file.submenu addItemWithTitle:@"Eject Disk" action:@selector(ejectDisk:) keyEquivalent:@""];
    NSMenuItem *edit = [[NSMenuItem alloc] init]; [bar addItem:edit];
    edit.submenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit.submenu addItemWithTitle:@"Copy Display" action:@selector(copy:) keyEquivalent:@"c"];
    [edit.submenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    NSMenuItem *machine = [[NSMenuItem alloc] init]; [bar addItem:machine];
    machine.submenu = [[NSMenu alloc] initWithTitle:@"Machine"];
    [machine.submenu addItemWithTitle:@"Run / Pause" action:@selector(toggleRun:) keyEquivalent:@"p"];
    [machine.submenu addItemWithTitle:@"Step Instruction" action:@selector(step:) keyEquivalent:@"."];
    [machine.submenu addItemWithTitle:@"Show Debugger" action:@selector(showDebugger:) keyEquivalent:@"d"];
    [machine.submenu addItemWithTitle:@"Reset Image" action:@selector(reset:) keyEquivalent:@"r"];
    [machine.submenu addItemWithTitle:@"Boot Original System" action:@selector(bootOriginal:) keyEquivalent:@"b"];
    [machine.submenu addItemWithTitle:@"Send Break" action:@selector(sendBreak:) keyEquivalent:@""];
    NSApp.mainMenu = bar;
}
- (void)loadImage:(NSString *)path {
    if (!path) { [self showError:@"The bundled boot image is missing. Run make app again."]; return; }
    try {
        if (_runtime) _runtime->reset(path.fileSystemRepresentation);
        else _runtime = std::make_unique<tunguska::Runtime>(path.fileSystemRepresentation);
        self.imagePath = path;
        self.screen.runtime = _runtime.get();
        self.debugger.runtime = _runtime.get();
        [self.debugger imageDidChange];
        _input.clear(); _nextInputCycle = 0; _lastCycles = 0; _revision = 0;
        _lastStats = NSDate.timeIntervalSinceReferenceDate;
        self.imageLabel.stringValue = [path.lastPathComponent isEqual:@"boot.ternobj"] ? @"Original Tunguska OS" : path.lastPathComponent;
        self.diskLabel.stringValue = @"No disk mounted";
        [self.window makeFirstResponder:self.screen];
        [self updateStats];
        self.screen.needsDisplay = YES;
    } catch (const std::exception& e) { [self showError:[NSString stringWithUTF8String:e.what()]]; }
}
- (void)enqueue:(NSString *)text {
    // The guest has a small keyboard buffer: feed pasted text gradually.
    for (NSUInteger i = 0; i < text.length && _input.size() < 8192; ++i) {
        unichar c = [text characterAtIndex:i];
        if (c < 128 && (asciitoternary((char)c) || c == '\r' || c == 127)) _input.push_back((char)c);
    }
}
- (void)tick:(NSTimer *)timer {
    if (!_runtime) return;
    if (_runtime->running() && !_input.empty() && _runtime->cycles() >= _nextInputCycle) {
        _runtime->key(_input.front()); _input.pop_front();
        _nextInputCycle = _runtime->cycles() + 5000;
    }
    _runtime->run(18000, 7);
    if (_revision != _runtime->frame().revision) {
        _revision = _runtime->frame().revision;
        self.screen.needsDisplay = YES;
        self.screen.accessibilityValue = [NSString stringWithUTF8String:_runtime->text().c_str()];
    }
    if (NSDate.timeIntervalSinceReferenceDate - _lastStats > 0.20) [self updateStats];
}
- (void)updateStats {
    if (!_runtime) return;
    auto& c = _runtime->cpu();
    const double elapsed = MAX(0.001, NSDate.timeIntervalSinceReferenceDate - _lastStats);
    const double rate = (_runtime->cycles() - _lastCycles)/elapsed;
    _lastCycles = _runtime->cycles(); _lastStats = NSDate.timeIntervalSinceReferenceDate;
    self.status.stringValue = _runtime->stoppedAtBreakpoint() ? @"◉  Breakpoint" : _runtime->running() ? @"●  Running" : @"◉  Paused";
    self.runButton.title = _runtime->running() ? @"Pause" : @"Run";
    self.mode.stringValue = _runtime->frame().mode == 0 ? @"54 × 27 · Text mode" : _runtime->frame().mode == 1 ? @"Vector graphics" : _runtime->frame().auxiliary == 1 ? @"324 × 243 · 3 colors" : @"324 × 243 · 729 colors";
    self.registers.stringValue = [NSString stringWithFormat:@"PC   %03X:%03X\nA    %4d   X  %4d\nY    %4d   S  %4d\nP    %4d   CL %4d", c.PCH.nonaryhex(), c.PCL.nonaryhex(), c.A.to_int(), c.X.to_int(), c.Y.to_int(), c.S.to_int(), c.P.to_int(), c.CL.to_int()];
    self.metrics.stringValue = [NSString stringWithFormat:@"6 TRITS / TRYTE    ·    531,441 TRYTE MEMORY    ·    %.0f K INSTRUCTIONS/S    ·    %llu EXECUTED", rate/1000, (unsigned long long)_runtime->cycles()];
    [self.debugger refresh];
}
- (void)showDebugger:(id)sender {
    if (!_runtime) return;
    _runtime->setRunning(false);
    if (!self.debugger) {
        self.debugger = [[DebuggerWindow alloc] init];
        self.debugger.runtime = _runtime.get();
        __weak AppDelegate *weakSelf = self;
        self.debugger.didChange = ^{ [weakSelf updateStats]; weakSelf.screen.needsDisplay = YES; };
        [self.debugger imageDidChange];
    }
    [self.debugger showWindow:sender];
    [self updateStats];
}
- (void)toggleRun:(id)sender { if (_runtime) { _runtime->setRunning(!_runtime->running()); [self updateStats]; [self.window makeFirstResponder:self.screen]; } }
- (void)step:(id)sender { if (_runtime) { _runtime->step(); [self updateStats]; self.screen.needsDisplay = YES; } }
- (void)reset:(id)sender { if (self.imagePath) [self loadImage:self.imagePath]; }
- (void)bootOriginal:(id)sender { [self loadImage:[NSBundle.mainBundle pathForResource:@"boot" ofType:@"ternobj"]]; }
- (void)sendBreak:(id)sender { if (_runtime) _runtime->breakKey(); }
- (void)example:(NSButton *)sender {
    [self bootOriginal:sender];
    if (!_runtime) return;
    _nextInputCycle = 100000;
    [self enqueue:[sender.identifier stringByAppendingString:@"\n"]];
}
- (void)openImage:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseDirectories = NO;
    panel.message = @"Choose a complete Tunguska memory image (.ternobj).";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) [self loadImage:panel.URL.path];
    }];
}
- (void)mountDisk:(id)sender {
    if (!_runtime) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseDirectories = NO;
    panel.message = @"Mount a virtual floppy. Changes stay in memory until you choose Save Disk As.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        try { self->_runtime->mount(panel.URL.fileSystemRepresentation); self.diskLabel.stringValue = panel.URL.lastPathComponent; }
        catch (const std::exception& e) { [self showError:[NSString stringWithUTF8String:e.what()]]; }
    }];
}
- (void)saveDisk:(id)sender {
    if (!_runtime) return;
    NSSavePanel *panel = [NSSavePanel savePanel]; panel.nameFieldStringValue = @"disk.ternobj";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        try { self->_runtime->saveDisk(panel.URL.fileSystemRepresentation); }
        catch (const std::exception& e) { [self showError:[NSString stringWithUTF8String:e.what()]]; }
    }];
}
- (void)ejectDisk:(id)sender { if (_runtime) { _runtime->eject(); self.diskLabel.stringValue = @"No disk mounted"; } }
- (void)about:(id)sender {
    [NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionApplicationName:@"Tunguska for Mac", NSAboutPanelOptionApplicationVersion:@"0.6 · Mac preview", NSAboutPanelOptionCredits:[[NSAttributedString alloc] initWithString:@"Originally created by Viktor Lofgren.\nOriginal emulator and operating system © 2007–2008 Viktor Lofgren.\nIndependent Mac fork maintained by Vinny Lingham.\nNo upstream endorsement is claimed.\n\nYou may modify and redistribute this software under GNU GPL v2 or later. Provided without warranty.\nChoose Tunguska → License and Credits for full terms and attribution."]}];
}
- (void)showLicense:(id)sender {
    if (!self.licenseWindow) {
        NSMutableString *contents = [NSMutableString string];
        for (NSString *name in @[@"AUTHORS", @"NOTICE.md", @"LICENSE"]) {
            NSString *path = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:name];
            NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            if (!text) { [self showError:@"A bundled license or attribution file is missing. Please rebuild the app."]; return; }
            [contents appendFormat:@"%@\n\n%@\n\n", name, text];
        }
        self.licenseWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 740, 600) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        self.licenseWindow.title = @"Tunguska — License and Credits";
        self.licenseWindow.releasedWhenClosed = NO;
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:self.licenseWindow.contentView.bounds];
        scroll.hasVerticalScroller = YES;
        scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        NSTextView *textView = [[NSTextView alloc] initWithFrame:scroll.bounds];
        textView.editable = NO; textView.selectable = YES;
        textView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        textView.textContainerInset = NSMakeSize(20, 20);
        textView.autoresizingMask = NSViewWidthSizable;
        textView.verticallyResizable = YES;
        textView.textContainer.widthTracksTextView = YES;
        textView.string = contents;
        scroll.documentView = textView;
        self.licenseWindow.contentView = scroll;
        [self.licenseWindow center];
    }
    [self.licenseWindow makeKeyAndOrderFront:nil];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
