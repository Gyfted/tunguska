// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac frontend, 2026-09-24. Original project: Viktor Lofgren.
#import <Cocoa/Cocoa.h>
#import "DebuggerWindow.h"
#import "VisionLab.h"
#import "ExplorerLab.h"
#import "WeightLab.h"
#import "FileAccess.h"
#import "Interface.h"
#include "runtime.h"
#include <deque>

static NSColor *RGB(unsigned rgb) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255)/255.0 green:((rgb >> 8) & 255)/255.0 blue:(rgb & 255)/255.0 alpha:1];
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
    if (NSIsEmptyRect(area)) return;
    if (frame.mode == 0) {
        const CGFloat cellWidth = MIN(area.size.width / tunguska::columns, area.size.height / (tunguska::rows * 1.7));
        const CGFloat cellHeight = cellWidth * 1.7;
        const CGFloat x0 = NSMidX(area) - cellWidth * tunguska::columns/2;
        const CGFloat y0 = NSMidY(area) - cellHeight * tunguska::rows/2;
        NSDictionary *attributes = TGDrawingAttributes(cellWidth / 0.60, YES, NSFontWeightMedium, RGB(0xB4EAD0));
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
    std::unique_ptr<tunguska::macos::ScopedURL> _imageAccess;
    std::deque<char> _input;
    NSTimeInterval _lastStats;
    uint64_t _lastCycles, _revision, _nextInputCycle;
}
@property(strong) NSWindow *window;
@property(strong) NSWindow *licenseWindow;
@property(strong) DebuggerWindow *debugger;
@property(strong) VisionLab *visionLab;
@property(strong) ExplorerLab *explorerLab;
@property(strong) WeightLab *weightLab;
@property(strong) ScreenView *screen;
@property(strong) NSButton *runButton;
@property(strong) NSButton *stepButton;
@property(strong) NSMenu *appearanceMenu;
@property(strong) NSTextField *status;
@property(strong) NSTextField *metrics;
@property(strong) NSTextField *mode;
@property(strong) NSTextField *imageLabel;
@property(strong) NSTextField *diskLabel;
@property(strong) NSTimer *timer;
@property(strong) NSURL *imageURL;
@end

@implementation AppDelegate
- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Tunguska couldn’t complete that action";
    alert.informativeText = message;
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self applyAppearance];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1160, 770) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Tunguska — Computer";
    TGConfigureWindow(self.window, @"Computer", NSMakeSize(1000, 700));
    self.window.delegate = self;
    self.window.acceptsMouseMovedEvents = YES;
    NSView *root = self.window.contentView;

    NSVisualEffectView *rail = [[NSVisualEffectView alloc] init];
    rail.material = NSVisualEffectMaterialSidebar;
    rail.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    NSStackView *sidebar = TGStack(@[], YES, 8);
    NSTextField *tagline = TGText(@"Explore computing in base three.", 11);
    tagline.textColor = NSColor.secondaryLabelColor;
    [sidebar addArrangedSubview:TGHeading(@"Tunguska", 25)];
    [sidebar addArrangedSubview:tagline];
    [sidebar setCustomSpacing:24 afterView:tagline];
    NSButton *computer = TGNavigation(@"Computer", @"The original ternary machine", @"desktopcomputer", self, @selector(showComputer:));
    computer.state = NSControlStateValueOn;
    [sidebar addArrangedSubview:computer];
    [sidebar setCustomSpacing:20 afterView:computer];
    [sidebar addArrangedSubview:TGHeading(@"Experiments", 11)];
    [sidebar addArrangedSubview:TGNavigation(@"Vision Lab", @"Draw a digit. Inspect a network.", @"eye", self, @selector(showVisionLab:))];
    [sidebar addArrangedSubview:TGNavigation(@"Explorer", @"Navigate an unknown world.", @"map", self, @selector(showExplorer:))];
    NSButton *weights = TGNavigation(@"Weight Race", @"Memory and GPU speed.", @"chart.bar.xaxis", self, @selector(showWeightRace:));
    [sidebar addArrangedSubview:weights]; [sidebar setCustomSpacing:20 afterView:weights];
    [sidebar addArrangedSubview:TGHeading(@"Original programs", 11)];
    for (NSArray *entry in @[@[@"Command reference", @"HELP"], @[@"Character map", @"CHARMAP"], @[@"Vector random walk", @"BROWN"], @[@"Draw in 729 colors", @"RASTERDEMO729"]]) {
        NSButton *button = TGButton(entry[0], @"play", self, @selector(example:));
        button.identifier = entry[1]; button.alignment = NSTextAlignmentLeft;
        button.toolTip = [NSString stringWithFormat:@"Starts a fresh system and runs %@. This resets memory and ejects the disk.", entry[1]];
        [sidebar addArrangedSubview:button];
    }
    NSTextField *credit = TGText(@"Created by Viktor Lofgren\nMac revival by Vinny Lingham", 10);
    credit.textColor = NSColor.secondaryLabelColor;
    NSButton *license = TGButton(@"License & credits", nil, self, @selector(showLicense:));
    license.bordered = NO; license.alignment = NSTextAlignmentLeft; license.font = [NSFont systemFontOfSize:11];
    NSStackView *credits = TGStack(@[credit, license], YES, 4);
    for (NSView *view in sidebar.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:sidebar.widthAnchor].active = YES;

    self.status = TGHeading(@"Running", 13);
    self.mode = TGText(@"54 × 27 · Text mode", 12); self.mode.textColor = NSColor.secondaryLabelColor;
    NSStackView *machineTitle = TGStack(@[TGHeading(@"Ternary computer", 24), self.mode], YES, 4);
    [machineTitle setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.runButton = TGButton(@"Pause", @"pause.fill", self, @selector(toggleRun:));
    TGPrimary(self.runButton);
    self.runButton.toolTip = @"Run or pause the computer (⌘P).";
    self.stepButton = TGButton(@"Step", @"forward.frame", self, @selector(step:));
    self.stepButton.toolTip = @"Execute one instruction and pause (⌘.).";
    NSButton *debug = TGButton(@"Debugger", @"ant", self, @selector(showDebugger:));
    debug.toolTip = @"Inspect instructions, memory and breakpoints (⌘D).";
    NSStackView *header = TGStack(@[machineTitle, TGSpacer(), self.runButton, self.stepButton, debug], NO, 10);
    NSButton *reset = TGButton(@"Reset", @"arrow.counterclockwise", self, @selector(reset:));
    reset.toolTip = @"Reload the current image, reset memory and eject the disk (⌘R).";
    NSStackView *state = TGStack(@[self.status, TGText(@"−1   0   +1", 12, YES)]);
    self.screen = [[ScreenView alloc] initWithFrame:NSZeroRect];
    __weak AppDelegate *weakSelf = self;
    self.screen.input = ^(NSString *text) { [weakSelf enqueue:text]; };
    NSTextField *hint = TGText(@"Click the display to type · HELP lists commands · Esc sends Break · ⌘V pastes", 11);
    hint.textColor = NSColor.secondaryLabelColor;
    self.imageLabel = TGText(@"Original Tunguska OS", 12);
    self.diskLabel = TGText(@"No disk mounted", 12);
    for (NSTextField *label in @[self.imageLabel, self.diskLabel]) {
        label.maximumNumberOfLines = 1; label.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [label setContentCompressionResistancePriority:500 forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    NSStackView *image = TGStack(@[TGHeading(@"System", 11), self.imageLabel], YES, 4);
    NSStackView *disk = TGStack(@[TGHeading(@"Virtual disk", 11), self.diskLabel], YES, 4);
    NSStackView *storage = TGStack(@[image, TGButton(@"Open…", @"folder", self, @selector(openImage:)), reset,
        disk, TGButton(@"Mount…", @"externaldrive", self, @selector(mountDisk:))], NO, 16);
    [image.widthAnchor constraintEqualToAnchor:disk.widthAnchor].active = YES;
    NSView *storageCard = TGCard(storage, 14);
    self.metrics = TGText(@"Starting…", 10, YES); self.metrics.textColor = NSColor.secondaryLabelColor;
    self.metrics.maximumNumberOfLines = 1; self.metrics.lineBreakMode = NSLineBreakByTruncatingTail;
    for (NSView *view in @[rail, header, state, self.screen, hint, storageCard, self.metrics]) {
        view.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:view];
    }
    for (NSView *view in @[sidebar, credits]) { view.translatesAutoresizingMaskIntoConstraints = NO; [rail addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [rail.leadingAnchor constraintEqualToAnchor:root.leadingAnchor], [rail.topAnchor constraintEqualToAnchor:root.topAnchor],
        [rail.bottomAnchor constraintEqualToAnchor:root.bottomAnchor], [rail.widthAnchor constraintEqualToConstant:258],
        [sidebar.leadingAnchor constraintEqualToAnchor:rail.leadingAnchor constant:16], [sidebar.trailingAnchor constraintEqualToAnchor:rail.trailingAnchor constant:-16],
        [sidebar.topAnchor constraintEqualToAnchor:rail.topAnchor constant:20],
        [credits.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:8], [credits.bottomAnchor constraintEqualToAnchor:rail.bottomAnchor constant:-16],
        [credits.topAnchor constraintGreaterThanOrEqualToAnchor:sidebar.bottomAnchor constant:16],
        [header.leadingAnchor constraintEqualToAnchor:rail.trailingAnchor constant:24], [header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],
        [header.topAnchor constraintEqualToAnchor:root.topAnchor constant:20],
        [state.leadingAnchor constraintEqualToAnchor:header.leadingAnchor], [state.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:20],
        [self.screen.leadingAnchor constraintEqualToAnchor:header.leadingAnchor], [self.screen.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [self.screen.topAnchor constraintEqualToAnchor:state.bottomAnchor constant:12], [self.screen.bottomAnchor constraintEqualToAnchor:hint.topAnchor constant:-12],
        [hint.leadingAnchor constraintEqualToAnchor:header.leadingAnchor], [hint.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [hint.bottomAnchor constraintEqualToAnchor:storageCard.topAnchor constant:-16],
        [storageCard.leadingAnchor constraintEqualToAnchor:header.leadingAnchor], [storageCard.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [storageCard.bottomAnchor constraintEqualToAnchor:self.metrics.topAnchor constant:-14],
        [self.metrics.leadingAnchor constraintEqualToAnchor:header.leadingAnchor], [self.metrics.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [self.metrics.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-16]
    ]];
    [self setupMenu];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self loadImage:[NSBundle.mainBundle URLForResource:@"boot" withExtension:@"ternobj"]];
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
    [file.submenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
    [file.submenu addItemWithTitle:@"Open Memory Image…" action:@selector(openImage:) keyEquivalent:@"o"];
    [file.submenu addItemWithTitle:@"Mount Disk…" action:@selector(mountDisk:) keyEquivalent:@"m"];
    [file.submenu addItemWithTitle:@"Save Disk As…" action:@selector(saveDisk:) keyEquivalent:@"s"];
    [file.submenu addItemWithTitle:@"Eject Disk" action:@selector(ejectDisk:) keyEquivalent:@""];
    NSMenuItem *edit = [[NSMenuItem alloc] init]; [bar addItem:edit];
    edit.submenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit.submenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit.submenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    NSMenuItem *machine = [[NSMenuItem alloc] init]; [bar addItem:machine];
    machine.submenu = [[NSMenu alloc] initWithTitle:@"Machine"];
    [machine.submenu addItemWithTitle:@"Run / Pause" action:@selector(toggleRun:) keyEquivalent:@"p"];
    [machine.submenu addItemWithTitle:@"Step Instruction" action:@selector(step:) keyEquivalent:@"."];
    [machine.submenu addItemWithTitle:@"Show Debugger" action:@selector(showDebugger:) keyEquivalent:@"d"];
    [machine.submenu addItemWithTitle:@"Reset Image" action:@selector(reset:) keyEquivalent:@"r"];
    [machine.submenu addItemWithTitle:@"Boot Original System" action:@selector(bootOriginal:) keyEquivalent:@"b"];
    [machine.submenu addItemWithTitle:@"Boot Experimental 3CC System" action:@selector(boot3CC:) keyEquivalent:@""];
    [machine.submenu addItemWithTitle:@"Send Break" action:@selector(sendBreak:) keyEquivalent:@""];
    [machine.submenu addItemWithTitle:@"Ternary Vision Lab" action:@selector(showVisionLab:) keyEquivalent:@"l"];
    [machine.submenu addItemWithTitle:@"Ternary Explorer" action:@selector(showExplorer:) keyEquivalent:@"e"];
    [machine.submenu addItemWithTitle:@"Weight Race" action:@selector(showWeightRace:) keyEquivalent:@"g"];
    NSMenuItem *view = [[NSMenuItem alloc] init]; [bar addItem:view];
    view.submenu = [[NSMenu alloc] initWithTitle:@"View"];
    [view.submenu addItemWithTitle:@"Computer" action:@selector(showComputer:) keyEquivalent:@"1"];
    [view.submenu addItemWithTitle:@"Vision Lab" action:@selector(showVisionLab:) keyEquivalent:@"2"];
    [view.submenu addItemWithTitle:@"Explorer" action:@selector(showExplorer:) keyEquivalent:@"3"];
    [view.submenu addItemWithTitle:@"Weight Race" action:@selector(showWeightRace:) keyEquivalent:@"4"];
    [view.submenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *appearance = [view.submenu addItemWithTitle:@"Appearance" action:nil keyEquivalent:@""];
    self.appearanceMenu = [[NSMenu alloc] initWithTitle:@"Appearance"]; appearance.submenu = self.appearanceMenu;
    for (NSString *name in @[@"System", @"Light", @"Dark"]) {
        NSMenuItem *item = [self.appearanceMenu addItemWithTitle:name action:@selector(changeAppearance:) keyEquivalent:@""];
        item.representedObject = name;
    }
    [self applyAppearance];
    NSMenuItem *windows = [[NSMenuItem alloc] init]; [bar addItem:windows];
    windows.submenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windows.submenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@""];
    [windows.submenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windows.submenu addItem:NSMenuItem.separatorItem];
    [windows.submenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    NSApp.windowsMenu = windows.submenu;
    NSApp.mainMenu = bar;
}
- (void)applyAppearance {
    NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:@"InterfaceAppearance"] ?: @"System";
    NSApp.appearance = [name isEqual:@"Dark"] ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]
        : [name isEqual:@"Light"] ? [NSAppearance appearanceNamed:NSAppearanceNameAqua] : nil;
    for (NSMenuItem *item in self.appearanceMenu.itemArray) item.state = [item.representedObject isEqual:name] ? NSControlStateValueOn : NSControlStateValueOff;
}
- (void)changeAppearance:(NSMenuItem *)sender {
    [NSUserDefaults.standardUserDefaults setObject:sender.representedObject forKey:@"InterfaceAppearance"];
    [self applyAppearance];
}
- (void)showComputer:(id)sender { [self.window makeKeyAndOrderFront:sender]; [self.window makeFirstResponder:self.screen]; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible { [self showComputer:nil]; return YES; }
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (action == @selector(toggleRun:) || action == @selector(step:) || action == @selector(reset:) ||
        action == @selector(sendBreak:) || action == @selector(showDebugger:) || action == @selector(openImage:) || action == @selector(mountDisk:) ||
        action == @selector(saveDisk:) || action == @selector(ejectDisk:) || action == @selector(bootOriginal:) || action == @selector(boot3CC:))
        return NSApp.keyWindow == self.window;
    return YES;
}
- (void)loadImage:(NSURL *)url {
    if (!url) { [self showError:@"The bundled operating system is missing. Reinstall Tunguska or open a valid memory image."]; return; }
    try {
        auto access = std::make_unique<tunguska::macos::ScopedURL>(url);
        if (_runtime) _runtime->reset(url.fileSystemRepresentation);
        else _runtime = std::make_unique<tunguska::Runtime>(url.fileSystemRepresentation);
        _imageAccess = std::move(access);
        self.imageURL = url;
        self.screen.runtime = _runtime.get();
        self.debugger.runtime = _runtime.get();
        [self.debugger imageDidChange];
        _input.clear(); _nextInputCycle = 0; _lastCycles = 0; _revision = 0;
        _lastStats = NSDate.timeIntervalSinceReferenceDate;
        self.imageLabel.stringValue = [url.lastPathComponent isEqual:@"boot.ternobj"] ? @"Original Tunguska OS" : url.lastPathComponent;
        if ([url.lastPathComponent isEqual:@"boot-3cc.ternobj"]) self.imageLabel.stringValue = @"Experimental 3CC System";
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
    const double elapsed = MAX(0.001, NSDate.timeIntervalSinceReferenceDate - _lastStats);
    const double rate = (_runtime->cycles() - _lastCycles)/elapsed;
    _lastCycles = _runtime->cycles(); _lastStats = NSDate.timeIntervalSinceReferenceDate;
    self.status.stringValue = _runtime->stoppedAtBreakpoint() ? @"◉  Breakpoint" : _runtime->running() ? @"●  Running" : @"◉  Paused";
    self.runButton.title = _runtime->running() ? @"Pause" : @"Run";
    self.runButton.image = [NSImage imageWithSystemSymbolName:_runtime->running() ? @"pause.fill" : @"play.fill" accessibilityDescription:nil];
    self.runButton.accessibilityLabel = self.runButton.title;
    self.status.textColor = _runtime->running() ? TGSuccessTextColor() : NSColor.secondaryLabelColor;
    self.mode.stringValue = _runtime->frame().mode == 0 ? @"54 × 27 · Text mode" : _runtime->frame().mode == 1 ? @"Vector graphics" : _runtime->frame().auxiliary == 1 ? @"324 × 243 · 3 colors" : @"324 × 243 · 729 colors";
    self.metrics.stringValue = [NSString stringWithFormat:@"531,441 trytes · 6 trits per tryte · %.0f K instructions/s · %llu executed", rate/1000, (unsigned long long)_runtime->cycles()];
    [self.debugger refresh];
}
- (void)showVisionLab:(id)sender {
    if (_runtime) _runtime->setRunning(false);
    if (!self.visionLab) self.visionLab = [[VisionLab alloc] init];
    [self.visionLab showWindow:sender];
    [self updateStats];
}
- (void)showWeightRace:(id)sender {
    if (_runtime) _runtime->setRunning(false);
    if (!self.weightLab) self.weightLab = [[WeightLab alloc] init];
    [self.weightLab showWindow:sender];
    [self updateStats];
}
- (void)showExplorer:(id)sender {
    if (_runtime) _runtime->setRunning(false);
    if (!self.explorerLab) self.explorerLab = [[ExplorerLab alloc] init];
    [self.explorerLab showWindow:sender];
    [self updateStats];
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
- (void)reset:(id)sender { if (self.imageURL) [self loadImage:self.imageURL]; }
- (void)bootOriginal:(id)sender { [self loadImage:[NSBundle.mainBundle URLForResource:@"boot" withExtension:@"ternobj"]]; }
- (void)boot3CC:(id)sender { [self loadImage:[NSBundle.mainBundle URLForResource:@"boot-3cc" withExtension:@"ternobj"]]; }
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
        if (response == NSModalResponseOK) [self loadImage:panel.URL];
    }];
}
- (void)mountDisk:(id)sender {
    if (!_runtime) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseDirectories = NO;
    panel.message = @"Mount a virtual floppy. Changes stay in memory until you choose Save Disk As.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        try {
            tunguska::macos::ScopedURL access(panel.URL);
            self->_runtime->mount(panel.URL.fileSystemRepresentation);
            self.diskLabel.stringValue = panel.URL.lastPathComponent;
        }
        catch (const std::exception& e) { [self showError:[NSString stringWithUTF8String:e.what()]]; }
    }];
}
- (void)saveDisk:(id)sender {
    if (!_runtime) return;
    NSSavePanel *panel = [NSSavePanel savePanel]; panel.nameFieldStringValue = @"disk.ternobj";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        try { tunguska::macos::saveDiskImage(*self->_runtime, panel.URL); }
        catch (const std::exception& e) { [self showError:[NSString stringWithUTF8String:e.what()]]; }
    }];
}
- (void)ejectDisk:(id)sender { if (_runtime) { _runtime->eject(); self.diskLabel.stringValue = @"No disk mounted"; } }
- (void)about:(id)sender {
    [NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionApplicationName:@"Tunguska for Mac", NSAboutPanelOptionApplicationVersion:[NSString stringWithFormat:@"%@ · Mac preview", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]], NSAboutPanelOptionCredits:[[NSAttributedString alloc] initWithString:@"Originally created by Viktor Lofgren.\nOriginal emulator and operating system © 2007–2008 Viktor Lofgren.\nIndependent Mac fork maintained by Vinny Lingham.\nNo upstream endorsement is claimed.\n\nYou may modify and redistribute this software under GNU GPL v2 or later. Provided without warranty.\nChoose Tunguska → License and Credits for full terms and attribution."]}];
}
- (void)showLicense:(id)sender {
    if (!self.licenseWindow) {
        NSMutableString *contents = [NSMutableString string];
        for (NSString *name in @[@"AUTHORS", @"NOTICE.md", @"VISION-NOTICE.md", @"LICENSE"]) {
            NSString *path = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:name];
            NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            if (!text) { [self showError:@"A bundled license or attribution file is missing. Please reinstall Tunguska to restore it."]; return; }
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
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)sender { return YES; }
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
