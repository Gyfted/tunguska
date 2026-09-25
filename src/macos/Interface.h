// SPDX-License-Identifier: GPL-2.0-or-later
// Shared presentation for the independent Mac frontend.
#import <Cocoa/Cocoa.h>

NSTextField *TGText(NSString *text, CGFloat size = 13, BOOL mono = NO);
NSTextField *TGHeading(NSString *text, CGFloat size = 13);
NSStackView *TGStack(NSArray<NSView *> *views, BOOL vertical = NO, CGFloat spacing = 12);
NSButton *TGButton(NSString *title, NSString *symbol, id target, SEL action);
void TGPrimary(NSButton *button);
NSView *TGSpacer();
NSView *TGCard(NSView *content, CGFloat inset = 16);
NSView *TGSection(NSString *title, NSView *content);
NSButton *TGNavigation(NSString *title, NSString *subtitle, NSString *symbol, id target, SEL action);
void TGConfigureWindow(NSWindow *window, NSString *frameName, NSSize minimum);
void TGInstallPage(NSWindow *window, NSString *title, NSString *subtitle, NSString *symbol,
                   NSView *content, CGFloat minimumContentWidth);
