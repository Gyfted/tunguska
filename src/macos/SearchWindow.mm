// SPDX-License-Identifier: GPL-2.0-or-later
#import "SearchWindow.h"
#import "SearchService.h"
#import "Interface.h"
#import "FileAccess.h"
#include <memory>
#include <chrono>

@interface TGSearchResultCell : NSTableCellView
@property(strong) NSTextField *excerpt;
@end
@implementation TGSearchResultCell
- (void)setBackgroundStyle:(NSBackgroundStyle)style {
    [super setBackgroundStyle:style];
    self.textField.textColor=NSColor.labelColor;
    self.excerpt.textColor=style==NSBackgroundStyleEmphasized?NSColor.labelColor:NSColor.secondaryLabelColor;
}
@end

@implementation SearchWindow {
    SearchService *_service;
    NSURL *_folder;
    std::shared_ptr<tunguska::macos::ScopedURL> _access;
    dispatch_queue_t _worker;
    std::shared_ptr<std::atomic<bool>> _cancel;
    NSSearchField *_query;
    NSSegmentedControl *_mode;
    NSButton *_choose,*_refresh,*_forget,*_cancelButton,*_reveal,*_compare,*_export,*_includeMeaning;
    NSTextField *_folderLabel,*_status,*_stats,*_preview,*_benchmarkLabel;
    NSTableView *_table;
    NSProgressIndicator *_progress;
    NSArray<NSDictionary *> *_hits;
    NSDictionary *_report;
    NSUInteger _generation;
    BOOL _busy;
}
- (instancetype)init {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1080,800) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if(!(self=[super initWithWindow:window]))return nil;
    window.title=@"Tunguska — Local Search";window.delegate=self;TGConfigureWindow(window,@"LocalSearch",NSMakeSize(920,700));
    _worker=dispatch_queue_create("org.tunguska.search",DISPATCH_QUEUE_SERIAL);_hits=@[];
    _choose=TGButton(@"Choose folder…",@"folder",self,@selector(choose:));TGPrimary(_choose);
    _refresh=TGButton(@"Refresh",@"arrow.clockwise",self,@selector(refresh:));_refresh.enabled=NO;
    _forget=TGButton(@"Forget folder",nil,self,@selector(forget:));_forget.enabled=NO;
    _cancelButton=TGButton(@"Cancel",nil,self,@selector(cancel:));_cancelButton.enabled=NO;
    _includeMeaning=[NSButton checkboxWithTitle:@"Include meaning search" target:nil action:nil];
    _includeMeaning.toolTip=@"Build English sentence embeddings when choosing or refreshing a folder. This takes longer than keyword indexing.";
    _folderLabel=TGText(@"Choose the folder you want to search.",14);
    _stats=TGText(@"Text, Markdown and PDFs with selectable text. Hidden files and links are skipped.",12);_stats.textColor=NSColor.secondaryLabelColor;
    _status=TGText(@"Your files stay on this Mac. The index clears when you quit.",12);
    _progress=[[NSProgressIndicator alloc] init];_progress.style=NSProgressIndicatorStyleSpinning;_progress.controlSize=NSControlSizeSmall;_progress.displayedWhenStopped=NO;
    _query=[[NSSearchField alloc] initWithFrame:NSZeroRect];_query.placeholderString=@"Find a name, an idea, or a passage…";_query.delegate=self;_query.target=self;_query.action=@selector(search:);_query.enabled=NO;_query.accessibilityLabel=@"Search your folder";
    [_query.widthAnchor constraintEqualToConstant:630].active=YES;
    _mode=[NSSegmentedControl segmentedControlWithLabels:@[@"Keywords",@"Meaning · English"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(search:)];_mode.selectedSegment=0;_mode.enabled=NO;
    _table=[[NSTableView alloc] init];_table.dataSource=self;_table.delegate=self;_table.style=NSTableViewStyleFullWidth;_table.rowHeight=55;_table.allowsMultipleSelection=NO;_table.accessibilityLabel=@"Search results";
    NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"result"];column.title=@"Matching passages";column.width=900;[_table addTableColumn:column];_table.headerView=nil;
    NSScrollView *scroll=[[NSScrollView alloc] init];scroll.documentView=_table;scroll.hasVerticalScroller=YES;
    [scroll.widthAnchor constraintEqualToConstant:920].active=YES;[scroll.heightAnchor constraintEqualToConstant:260].active=YES;
    _preview=TGText(@"Results will appear here. Select a passage to read its excerpt.",13);[_preview.widthAnchor constraintEqualToConstant:900].active=YES;[_preview.heightAnchor constraintGreaterThanOrEqualToConstant:80].active=YES;
    _reveal=TGButton(@"Show in Finder",@"arrow.up.forward.square",self,@selector(reveal:));_reveal.enabled=NO;
    _compare=TGButton(@"Measure this query",@"speedometer",self,@selector(compare:));_compare.enabled=NO;
    _export=TGButton(@"Export measurement…",nil,self,@selector(export:));_export.enabled=NO;
    _benchmarkLabel=TGText(@"Measure a real query to check speed and result agreement. No speedup is assumed.",12);[_benchmarkLabel.widthAnchor constraintEqualToConstant:900].active=YES;
    NSView *folder=TGCard(TGStack(@[TGStack(@[_choose,_refresh,_forget,_cancelButton,_progress,_includeMeaning]),_folderLabel,_stats,_status],YES,9));
    NSView *results=TGCard(TGStack(@[TGStack(@[_query,_mode]),scroll,_preview,_reveal],YES,12));
    NSView *benchmark=TGSection(@"Performance",TGStack(@[TGStack(@[_compare,_export]),_benchmarkLabel],YES,8));
    NSStackView *content=TGStack(@[folder,results,benchmark,TGText(@"Meaning search is experimental and can miss passages; check the source. Scanned PDFs need OCR before indexing. Refresh to pick up edits. Original Tunguska: Viktor Lofgren · Mac fork: Vinny Lingham · GPL v2 or later",11)],YES,18);
    for(NSView *card in @[folder,results,benchmark])[card.widthAnchor constraintEqualToAnchor:content.widthAnchor].active=YES;
    TGInstallPage(window,@"Local Search",@"Find something you remember, in the files you choose.",@"magnifyingglass",content,952);
    return self;
}
- (void)showWindow:(id)sender{[super showWindow:sender];[self.window makeKeyAndOrderFront:sender];if(_service)[self.window makeFirstResponder:_query];}
- (void)windowWillClose:(NSNotification *)note{[self cancel:nil];[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(search:) object:nil];++_generation;}
- (void)setBusy:(BOOL)busy {
    _busy=busy;_choose.enabled=_includeMeaning.enabled=!busy;_refresh.enabled=_forget.enabled=!busy&&_service;_query.enabled=_mode.enabled=!busy&&_service;
    _compare.enabled=!busy&&_service&&_query.stringValue.length>0;_export.enabled=!busy&&_report;_cancelButton.enabled=busy;
    if(busy)[_progress startAnimation:nil];else [_progress stopAnimation:nil];
}
- (void)choose:(id)sender {
    if(_busy)return;NSOpenPanel *panel=[NSOpenPanel openPanel];panel.canChooseFiles=NO;panel.canChooseDirectories=YES;panel.allowsMultipleSelection=NO;panel.prompt=@"Index folder";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response==NSModalResponseOK)[self indexFolder:panel.URL];}];
}
- (void)refresh:(id)sender{if(_folder&&!_busy)[self indexFolder:_folder];}
- (void)forget:(id)sender {
    if(_busy)return;++_generation;_service=nil;_folder=nil;_access.reset();_hits=@[];_report=nil;_query.stringValue=@"";[_table reloadData];_preview.stringValue=@"Choose a folder to start a new search.";_folderLabel.stringValue=@"No folder selected";_stats.stringValue=@"The previous index has been cleared.";_status.stringValue=@"Your files were not modified.";_reveal.enabled=NO;[self setBusy:NO];
    _benchmarkLabel.stringValue=@"Choose a folder and search to measure performance.";_stats.toolTip=nil;
}
- (void)cancel:(id)sender{if(_cancel)_cancel->store(true);if(_busy){_cancelButton.enabled=NO;_status.stringValue=@"Cancelling after the current document operation…";}}
- (void)indexFolder:(NSURL *)url {
    if(_busy)return;[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(search:) object:nil];++_generation;
    _cancel=std::make_shared<std::atomic<bool>>(false);auto cancelled=_cancel;auto access=std::make_shared<tunguska::macos::ScopedURL>(url);
    BOOL semantic=_includeMeaning.state==NSControlStateValueOn;
    _status.stringValue=@"Preparing the local index…";[self setBusy:YES];__weak SearchWindow *weak=self;
    dispatch_async(_worker,^{@autoreleasepool{
        try {
            auto last=std::chrono::steady_clock::now()-std::chrono::milliseconds(101);
            auto progress=[&](NSString *message){auto now=std::chrono::steady_clock::now();if(std::chrono::duration<double>(now-last).count()<.1)return;last=now;
                // Copy out of the C++ closure: a nested block must not retain its stack 'this'.
                __weak SearchWindow *target=weak;auto flag=cancelled;NSString *update=[message copy];
                dispatch_async(dispatch_get_main_queue(),^{SearchWindow *self=target;if(self&&!flag->load())self->_status.stringValue=update;});};
            SearchService *service=[SearchService indexFolder:url cancel:*cancelled progress:progress semantic:semantic];
            dispatch_async(dispatch_get_main_queue(),^{SearchWindow *self=weak;if(!self)return;if(cancelled->load()){self->_status.stringValue=@"Cancelled. Your previous index is still available.";[self setBusy:NO];return;}
                self->_service=service;self->_folder=url;self->_access=access;self->_hits=@[];self->_report=nil;[self->_table reloadData];self->_reveal.enabled=NO;
                self->_folderLabel.stringValue=url.path;
                self->_stats.stringValue=[NSString stringWithFormat:@"%lu files · %lu passages · %lu skipped · indexed in %.1f seconds",(unsigned long)service.fileCount,(unsigned long)service.passageCount,(unsigned long)service.skippedCount,service.buildMilliseconds/1000];
                self->_stats.toolTip=[service.warnings componentsJoinedByString:@"\n"];
                self->_status.stringValue=service.passageCount?(service.semanticCount?@"Ready. Search for words or switch to Meaning for related ideas.":@"Ready for keywords. To find related ideas, enable meaning search and Refresh."):@"No readable text found. Choose a folder containing text, Markdown, or searchable PDFs.";
                self->_mode.toolTip=semantic?service.modelDescription:@"Enable Include meaning search and Refresh to build English sentence embeddings.";
                self->_preview.stringValue=@"Select a result to read its excerpt.";[self setBusy:NO];[self->_mode setEnabled:service.semanticCount>0 forSegment:1];if(!service.semanticCount)self->_mode.selectedSegment=0;[self search:nil];[self.window makeFirstResponder:self->_query];
            });
        }catch(const std::exception& e){NSString *message=[NSString stringWithUTF8String:e.what()];dispatch_async(dispatch_get_main_queue(),^{SearchWindow *self=weak;if(self){self->_status.stringValue=message;[self setBusy:NO];}});}
    }});
}
- (void)controlTextDidChange:(NSNotification *)note {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(search:) object:nil];++_generation;
    [self performSelector:@selector(search:) withObject:nil afterDelay:.25];
}
- (void)search:(id)sender {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(search:) object:nil];if(!_service||_busy)return;
    NSString *query=[_query.stringValue copy];BOOL meaning=_mode.selectedSegment==1;NSUInteger generation=++_generation;SearchService *service=_service;__weak SearchWindow *weak=self;
    _compare.enabled=query.length>0;_report=nil;_export.enabled=NO;_benchmarkLabel.stringValue=@"Measure this query to compare speed and result agreement.";
    if(!query.length){_hits=@[];[_table reloadData];_reveal.enabled=NO;_preview.stringValue=@"Type a search to see matching passages.";return;}
    _status.stringValue=@"Searching…";
    dispatch_async(_worker,^{@autoreleasepool{try{NSDictionary *result=[service search:query meaning:meaning reference:NO];
        dispatch_async(dispatch_get_main_queue(),^{SearchWindow *self=weak;if(!self||self->_generation!=generation)return;self->_hits=result[@"hits"];[self->_table reloadData];self->_reveal.enabled=NO;
            self->_status.stringValue=[NSString stringWithFormat:@"%lu passages · %.2f ms",(unsigned long)self->_hits.count,[result[@"milliseconds"] doubleValue]];self->_preview.stringValue=self->_hits.count?@"Select a passage to read its excerpt.":@"No matching passages. Try fewer words or switch to Meaning.";
            if(self->_hits.count)[self->_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];});
    }catch(const std::exception& e){NSString *message=[NSString stringWithUTF8String:e.what()];dispatch_async(dispatch_get_main_queue(),^{SearchWindow *self=weak;if(self&&self->_generation==generation){self->_status.stringValue=message;self->_hits=@[];[self->_table reloadData];self->_reveal.enabled=NO;self->_preview.stringValue=@"Try a shorter query.";}});}}});
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table{return _hits.count;}
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    TGSearchResultCell *cell=[table makeViewWithIdentifier:@"result" owner:nil];
    if(!cell){
        cell=[[TGSearchResultCell alloc] init];cell.identifier=@"result";
        // NSTableCellView.textField is weak: retain labels as subviews before assigning it.
        NSTextField *titleField=[NSTextField labelWithString:@""];
        NSTextField *excerptField=[NSTextField labelWithString:@""];
        [cell addSubview:titleField];[cell addSubview:excerptField];
        cell.textField=titleField;cell.excerpt=excerptField;
        for(NSTextField *field in @[titleField,excerptField]){
            field.translatesAutoresizingMaskIntoConstraints=NO;field.font=[NSFont systemFontOfSize:13];
            field.maximumNumberOfLines=1;field.lineBreakMode=NSLineBreakByTruncatingTail;
            [field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4].active=YES;
            [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4].active=YES;
            [field.heightAnchor constraintEqualToConstant:18].active=YES;
        }
        [cell.textField.topAnchor constraintEqualToAnchor:cell.topAnchor constant:7].active=YES;
        [cell.excerpt.topAnchor constraintEqualToAnchor:cell.textField.bottomAnchor constant:3].active=YES;
        cell.excerpt.textColor=NSColor.secondaryLabelColor;
    }
    NSDictionary *hit=_hits[row];NSString *page=[hit[@"page"] integerValue]?[NSString stringWithFormat:@" · page %@",hit[@"page"]]:@"";
    NSString *title=[[hit[@"title"] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@" "];
    cell.textField.stringValue=[title stringByAppendingString:page];
    cell.excerpt.stringValue=[[hit[@"snippet"] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@" "];
    cell.toolTip=hit[@"path"];return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification *)note {
    NSInteger row=_table.selectedRow;_reveal.enabled=row>=0&&row<(NSInteger)_hits.count;
    if(_reveal.enabled){NSDictionary *hit=_hits[row];_preview.stringValue=[NSString stringWithFormat:@"%@\n%@",hit[@"path"],hit[@"snippet"]];}
}
- (void)reveal:(id)sender {
    NSInteger row=_table.selectedRow;if(row<0||row>=(NSInteger)_hits.count)return;NSString *path=_hits[row][@"path"];
    if(![_service canReveal:path]){_status.stringValue=@"This file moved or became a link. Refresh the folder before opening it.";return;}
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
}
- (void)compare:(id)sender {
    if(_busy||!_service||!_query.stringValue.length)return;
    _cancel=std::make_shared<std::atomic<bool>>(false);auto cancel=_cancel;SearchService *service=_service;NSString *query=[_query.stringValue copy];BOOL meaning=_mode.selectedSegment==1;__weak SearchWindow *weak=self;[self setBusy:YES];_status.stringValue=@"Measuring both paths and checking results…";
    dispatch_async(_worker,^{@autoreleasepool{try{NSDictionary *report=[service benchmark:@[query] meaning:meaning rounds:21 cancel:*cancel];dispatch_async(dispatch_get_main_queue(),^{SearchWindow *self=weak;if(!self)return;self->_report=report;
        self->_benchmarkLabel.stringValue=[NSString stringWithFormat:@"%.2f× vs %@ · %.3f ms vs %.3f ms · %.1f%% result overlap. %@\nQuery-to-result timing includes preparation, ranking, and snippets; excludes indexing and screen drawing. See the export for every sample.",[report[@"speedup"] doubleValue],report[@"reference"],[report[@"native_median_ms"] doubleValue],[report[@"reference_median_ms"] doubleValue],100*[report[@"recall_at_20"] doubleValue],[report[@"two_times_target_met"] boolValue]?@"2× target met for this query.":@"2× target not met for this query."];
        self->_status.stringValue=@"Measurement complete. The result applies to this query, folder, and Mac.";[self setBusy:NO];});
    }catch(const std::exception& e){NSString *message=[NSString stringWithUTF8String:e.what()];dispatch_async(dispatch_get_main_queue(),^{SearchWindow *self=weak;if(self){self->_status.stringValue=message;[self setBusy:NO];}});}}});
}
- (void)export:(id)sender {
    if(!_report)return;NSData *data=[NSJSONSerialization dataWithJSONObject:_report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];if(!data)return;
    NSSavePanel *panel=[NSSavePanel savePanel];panel.nameFieldStringValue=@"tunguska-search-measurement.json";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response!=NSModalResponseOK)return;tunguska::macos::ScopedURL scope(panel.URL);
        NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];__block NSError *writeError=nil;NSError *coordError=nil;
        [coordinator coordinateWritingItemAtURL:panel.URL options:NSFileCoordinatorWritingForReplacing error:&coordError byAccessor:^(NSURL *url){[data writeToURL:url options:NSDataWritingAtomic error:&writeError];}];
        self->_status.stringValue=(coordError||writeError)?(coordError?:writeError).localizedDescription:@"Measurement saved.";}];
}
@end
