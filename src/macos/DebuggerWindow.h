// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac fork debugger, 2026-09-24.
#import <Cocoa/Cocoa.h>
#include "runtime.h"

@interface DebuggerWindow : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, assign) tunguska::Runtime *runtime;
@property(nonatomic, copy) void (^didChange)(void);
- (void)refresh;
- (void)imageDidChange;
@end
