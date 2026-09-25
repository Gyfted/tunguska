// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac frontend, 2026-09-25. Original Tunguska: Viktor Lofgren.
#import "Interface.h"

NSTextField *TGText(NSString *text, CGFloat size, BOOL mono) {
    NSTextField *field = [NSTextField wrappingLabelWithString:text];
    field.font = mono ? [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular]
                      : [NSFont systemFontOfSize:size];
    field.textColor = NSColor.labelColor;
    field.selectable = YES;
    return field;
}
NSTextField *TGHeading(NSString *text, CGFloat size) {
    NSTextField *field = TGText(text, size);
    field.font = [NSFont systemFontOfSize:size weight:NSFontWeightSemibold];
    return field;
}
NSStackView *TGStack(NSArray<NSView *> *views, BOOL vertical, CGFloat spacing) {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = vertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    return stack;
}
NSButton *TGButton(NSString *title, NSString *symbol, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle = NSBezelStyleRounded;
    if (symbol.length) {
        button.accessibilityLabel = title;
        button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
        button.imagePosition = NSImageLeading;
        button.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightMedium];
    }
    return button;
}
void TGPrimary(NSButton *button) { button.bezelColor = NSColor.controlAccentColor; }
NSView *TGSpacer() {
    NSView *view = [[NSView alloc] init];
    [view setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [view setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return view;
}

@interface TGCardView : NSView
@end
@implementation TGCardView
- (void)drawRect:(NSRect)dirty {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, .5, .5) xRadius:12 yRadius:12];
    [NSColor.controlBackgroundColor setFill]; [path fill];
    [NSColor.separatorColor setStroke]; [path stroke];
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end
NSView *TGCard(NSView *content, CGFloat inset) {
    NSView *card = [[TGCardView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset]
    ]];
    return card;
}
NSView *TGSection(NSString *title, NSView *content) {
    NSStackView *stack = TGStack(@[TGHeading(title), content], YES);
    NSLayoutConstraint *width = [content.widthAnchor constraintEqualToAnchor:stack.widthAnchor];
    width.priority = 749; width.active = YES;
    return TGCard(stack);
}

// A standard NSButton retains keyboard and accessibility behavior; only its
// presentation is custom so destinations can include a useful description.
@interface TGNavigationButton : NSButton
@property(copy) NSString *subtitle;
@property BOOL hovered;
@end
@implementation TGNavigationButton
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; self.needsDisplay = YES; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)dirty {
    BOOL active = self.highlighted || self.state == NSControlStateValueOn;
    if (active || self.hovered) {
        [(active ? [NSColor.controlAccentColor colorWithAlphaComponent:.16] : NSColor.quaternaryLabelColor) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:8 yRadius:8] fill];
    }
    NSImage *icon = [self.image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.labelColor]]];
    [icon drawInRect:NSMakeRect(12, 17, 22, 22) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    [self.title drawInRect:NSMakeRect(46, 9, self.bounds.size.width-54, 20) withAttributes:@{
        NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSForegroundColorAttributeName:NSColor.labelColor}];
    [self.subtitle drawInRect:NSMakeRect(46, 30, self.bounds.size.width-54, 17) withAttributes:@{
        NSFontAttributeName:[NSFont systemFontOfSize:11], NSForegroundColorAttributeName:NSColor.secondaryLabelColor}];
}
@end
NSButton *TGNavigation(NSString *title, NSString *subtitle, NSString *symbol, id target, SEL action) {
    TGNavigationButton *button = [[TGNavigationButton alloc] init];
    button.title = title; button.subtitle = subtitle; button.target = target; button.action = action;
    button.bordered = NO; button.focusRingType = NSFocusRingTypeExterior;
    button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    button.accessibilityLabel = title; button.accessibilityHelp = subtitle;
    button.toolTip = subtitle;
    [button.heightAnchor constraintEqualToConstant:56].active = YES;
    return button;
}
@interface TGFlippedView : NSView
@end
@implementation TGFlippedView
- (BOOL)isFlipped { return YES; }
@end
void TGConfigureWindow(NSWindow *window, NSString *frameName, NSSize minimum) {
    window.minSize = minimum;
    window.releasedWhenClosed = NO;
    window.backgroundColor = NSColor.windowBackgroundColor;
    window.titlebarAppearsTransparent = YES;
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    [window center];
    [window setFrameAutosaveName:frameName];
}
void TGInstallPage(NSWindow *window, NSString *title, NSString *subtitle, NSString *symbol,
                   NSView *content, CGFloat minimumContentWidth) {
    NSTextField *description = TGText(subtitle, 12);
    description.textColor = NSColor.secondaryLabelColor;
    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]];
    icon.accessibilityElement = NO;
    icon.contentTintColor = NSColor.controlAccentColor;
    icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:26 weight:NSFontWeightMedium];
    [icon.widthAnchor constraintEqualToConstant:32].active = YES;
    [icon.heightAnchor constraintEqualToConstant:32].active = YES;
    NSStackView *titles = TGStack(@[TGHeading(title, 24), description], YES, 4);
    [titles setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *home = TGButton(@"Computer", @"desktopcomputer", nil, NSSelectorFromString(@"showComputer:"));
    home.toolTip = @"Return to the ternary computer (⌘1). Its current state is preserved.";
    NSStackView *header = TGStack(@[icon, titles, TGSpacer(), home], NO, 16);
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES; scroll.hasHorizontalScroller = YES;
    scroll.autohidesScrollers = YES; scroll.drawsBackground = NO;
    NSView *document = [[TGFlippedView alloc] init];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:content]; scroll.documentView = document;
    NSBox *divider = [[NSBox alloc] init]; divider.boxType = NSBoxSeparator;
    NSView *root = window.contentView;
    for (NSView *view in @[header, divider, scroll]) { view.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:view]; }
    NSLayoutConstraint *fit = [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor]; fit.priority = 749;
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],
        [header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],
        [header.topAnchor constraintEqualToAnchor:root.topAnchor constant:18],
        [divider.leadingAnchor constraintEqualToAnchor:root.leadingAnchor], [divider.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [divider.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:18],
        [scroll.topAnchor constraintEqualToAnchor:divider.bottomAnchor], [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [content.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:24],
        [content.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-24],
        [content.topAnchor constraintEqualToAnchor:document.topAnchor constant:20],
        [content.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-24],
        [content.widthAnchor constraintGreaterThanOrEqualToConstant:minimumContentWidth],
        [document.widthAnchor constraintGreaterThanOrEqualToAnchor:scroll.contentView.widthAnchor], fit
    ]];
}
