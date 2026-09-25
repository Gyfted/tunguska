// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen tests of the production AppKit drawing code.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "macos/Interface.h"
#import "macos/SearchWindow.h"
#include "explorer.h"
#include <cmath>
#include <iostream>

namespace ex = tunguska::explorer;
@interface SearchWindow (RegressionTesting)
- (void)indexFolder:(NSURL *)url;
@end
@protocol ExplorerMapRendering
@property(assign) const ex::Simulation *simulation;
@property(assign) const ex::Decision *decision;
@property BOOL belief;
@end

static void Check(bool ok, const char *message) {
    if (!ok) throw std::runtime_error(message);
}
static unsigned missingFontCalls;
static NSFont *MissingFont(id, SEL, CGFloat, NSFontWeight) {
    ++missingFontCalls;
    return nil;
}
static NSFont *MissingPlainFont(id, SEL, CGFloat) { return nil; }
// Scoped to this test process; production has no fault-injection switch.
class ReplaceFontMethod {
    Method method_;
    IMP original_;
public:
    ReplaceFontMethod(SEL selector, IMP replacement) {
        method_ = class_getClassMethod(NSFont.class, selector);
        Check(method_ != nullptr, "font method exists");
        original_ = method_setImplementation(method_, replacement);
    }
    ~ReplaceFontMethod() { method_setImplementation(method_, original_); }
    ReplaceFontMethod(const ReplaceFontMethod&) = delete;
    ReplaceFontMethod& operator=(const ReplaceFontMethod&) = delete;
};

static void CheckAttributes() {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    NSColor *color = NSColor.redColor;
    NSDictionary *attributes = TGDrawingAttributes(14, YES, NSFontWeightSemibold, color, paragraph);
    Check([attributes[NSFontAttributeName] pointSize] == 14, "requested font size preserved");
    Check(attributes[NSForegroundColorAttributeName] == color, "requested color preserved");
    Check([attributes[NSParagraphStyleAttributeName] alignment] == NSTextAlignmentCenter, "alignment preserved");
    for (CGFloat size : {CGFloat(0), CGFloat(-1), CGFloat(INFINITY), CGFloat(NAN)}) {
        attributes = TGDrawingAttributes(size, YES, NSFontWeightRegular, nil);
        Check([attributes[NSFontAttributeName] pointSize] == 13, "invalid font size uses readable default");
        Check(attributes[NSForegroundColorAttributeName] != nil, "missing color uses default");
        Check(attributes[NSParagraphStyleAttributeName] == nil, "optional paragraph omitted");
    }
}

static unsigned RenderMaps() {
    Class mapClass = NSClassFromString(@"ExplorerMap");
    Check(mapClass != Nil, "production ExplorerMap is linked");
    NSView<ExplorerMapRendering> *map = [[mapClass alloc] init];
    map.frame = NSMakeRect(0, 0, 360, 360);
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr
        pixelsWide:360 pixelsHigh:360 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    Check(context != nil, "offscreen drawing context exists");
    __block unsigned renders = 0;
    [NSGraphicsContext saveGraphicsState];
    @try {
        NSGraphicsContext.currentContext = context;
        for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            NSAppearance *appearance = [NSAppearance appearanceNamed:name];
            Check(appearance != nil, "test appearance exists");
            [appearance performAsCurrentDrawingAppearance:^{
                for (int preset = 0; preset < 3; ++preset) {
                    ex::Simulation simulation;
                    simulation.reset(ex::scenario(preset), {});
                    ex::Decision decision;
                    map.simulation = &simulation;
                    map.decision = &decision;
                    for (int turn = 0; turn < 12 && !simulation.finished(); ++turn) {
                        if (turn) decision = ex::reference(simulation.prepare());
                        for (BOOL belief : {NO, YES}) {
                            map.belief = belief;
                            [map drawRect:map.bounds];
                            ++renders;
                        }
                        if (turn) simulation.apply(decision);
                    }
                    map.simulation = nullptr;
                    map.decision = nullptr;
                }
            }];
        }
        Check([bitmap colorAtX:1 y:1].alphaComponent > 0, "map paints into bitmap");
    } @finally {
        [NSGraphicsContext restoreGraphicsState];
    }
    return renders;
}

static void CheckSearchRows() {
    SearchWindow *window=[[SearchWindow alloc] init];
    [window setValue:@[@{@"title":@"Manual.pdf",@"path":@"/test/Manual.pdf",@"page":@19,
        @"snippet":@"First line\nSecond line\r\nThird line\nA long PDF excerpt with enough text to wrap if the row does not truncate it correctly."}] forKey:@"hits"];
    NSTableView *table=[window valueForKey:@"table"];
    NSTableCellView *cell;__weak NSTextField *title;
    @autoreleasepool {
        cell=(NSTableCellView *)[window tableView:table viewForTableColumn:table.tableColumns[0] row:0];
        title=cell.textField;
    }
    Check(title!=nil&&[title.stringValue isEqual:@"Manual.pdf · page 19"],"search title survives its autorelease pool");
    Check(cell.subviews.count==2,"search row retains title and excerpt");
    cell.frame=NSMakeRect(0,0,400,55);
    [window.window.contentView addSubview:cell];
    [window.window.contentView layoutSubtreeIfNeeded];
    for(NSTextField *field in cell.subviews){
        Check(NSContainsRect(cell.bounds,field.frame),"PDF labels fit inside their result row");
        Check([field.stringValue rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location==NSNotFound,"PDF line breaks do not overflow result rows");
    }
    [window close];
}

static void CheckSearchProgressLifetime() {
    NSURL *directory=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    Check([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil],"create UI index fixture");
    Check([@"A receipt for office furniture." writeToURL:[directory URLByAppendingPathComponent:@"receipt.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil],"write UI index fixture");
    SearchWindow *window=[[SearchWindow alloc] init];
    [window indexFolder:directory];
    dispatch_queue_t worker=[window valueForKey:@"worker"];
    // Keep the main queue blocked until the indexing callback's C++ closure dies.
    dispatch_sync(worker,^{});
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,.05,false);
    Check([window valueForKey:@"service"]!=nil,"queued progress/completion survives the indexing callback");
    Check(![[window valueForKey:@"busy"] boolValue],"indexing finishes on the main queue");
    [window close];
    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
}

int main() {
    @autoreleasepool {
        @try {
            try {
                [NSApplication sharedApplication];
                CheckAttributes();
                CheckSearchRows();
                CheckSearchProgressLifetime();
                Check(RenderMaps() == 144, "normal maps render in both appearances");
                {
                    ReplaceFontMethod unavailable(@selector(monospacedSystemFontOfSize:weight:), reinterpret_cast<IMP>(MissingFont));
                    CheckAttributes();
                    Check(RenderMaps() == 144, "maps render with an unavailable monospaced font");
                    ReplaceFontMethod weighted(@selector(systemFontOfSize:weight:), reinterpret_cast<IMP>(MissingFont));
                    Check(TGDrawingAttributes(13, YES, NSFontWeightRegular, nil)[NSFontAttributeName] != nil,
                          "plain system font is a second fallback");
                    ReplaceFontMethod plain(@selector(systemFontOfSize:), reinterpret_cast<IMP>(MissingPlainFont));
                    Check(TGDrawingAttributes(13, YES, NSFontWeightRegular, nil)[NSFontAttributeName] == nil,
                          "all fonts unavailable: attribute is safely omitted");
                }
                Check(missingFontCalls > 0, "font-failure path was exercised");
                Check([NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular] != nil,
                      "font implementation restored");
                std::cout << "PASS AppKit: search row lifetimes and PDF layout; 288 map renders, light/dark, three worlds, routes; missing fonts/colors and invalid font sizes\n";
                return 0;
            } catch (const std::exception& error) {
                std::cerr << "FAIL: " << error.what() << '\n';
            }
        } @catch (NSException *error) {
            std::cerr << "FAIL: " << error.name.UTF8String << ": " << error.reason.UTF8String << '\n';
        }
        return 1;
    }
}
