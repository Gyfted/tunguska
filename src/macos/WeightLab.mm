// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac fork addition, 2026-09-25. Original emulator: Viktor Lofgren.
#import "WeightLab.h"
#import "FileAccess.h"
#include "weight_benchmark.h"
#include <algorithm>
#include <cmath>
namespace wb=tunguska::weights;
static NSString *String(const std::string& s){return [NSString stringWithUTF8String:s.c_str()];}
static NSColor *Color(unsigned rgb){return [NSColor colorWithSRGBRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];}
static NSTextField *Label(NSString *text,CGFloat size,BOOL mono=NO){NSTextField *f=[NSTextField wrappingLabelWithString:text];f.selectable=YES;f.font=mono?[NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular]:[NSFont systemFontOfSize:size];return f;}
static NSStackView *Stack(NSArray<NSView*> *views,BOOL vertical=NO){NSStackView *s=[NSStackView stackViewWithViews:views];s.orientation=vertical?NSUserInterfaceLayoutOrientationVertical:NSUserInterfaceLayoutOrientationHorizontal;s.alignment=vertical?NSLayoutAttributeLeading:NSLayoutAttributeCenterY;s.spacing=12;return s;}
static void Draw(NSString *text,NSRect rect,CGFloat size,NSColor *color){[text drawInRect:rect withAttributes:@{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular],NSForegroundColorAttributeName:color}];}
@interface WeightBars : NSView
@property(copy) NSArray<NSNumber*> *values;
@property(copy) NSArray<NSString*> *names;
@property(copy) NSString *unit;
@end
@implementation WeightBars
- (instancetype)init{if((self=[super initWithFrame:NSZeroRect])){self.accessibilityElement=YES;self.accessibilityRole=NSAccessibilityImageRole;[self.widthAnchor constraintEqualToConstant:480].active=YES;[self.heightAnchor constraintEqualToConstant:190].active=YES;}return self;}
- (BOOL)isFlipped{return YES;}
- (void)drawRect:(NSRect)dirty {
    [Color(0x152020) setFill];[[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8] fill];
    if(!_values.count){Draw(@"Run a comparison to see measured results.",NSMakeRect(14,76,455,30),12,Color(0xA3B8AD));return;}
    double largest=0;for(NSNumber *v in _values)largest=std::max(largest,v.doubleValue);
    for(NSUInteger i=0;i<_values.count;++i){CGFloat y=12+i*58;double value=_values[i].doubleValue;
        Draw([NSString stringWithFormat:@"%@   %.3f %@",_names[i],value,_unit],NSMakeRect(14,y,455,20),12,Color(0xDFE9E2));
        [Color(0x293B36) setFill];NSRectFill(NSMakeRect(14,y+24,450,14));
        [Color(i==_values.count-1?0x8BDEAE:0x89ACCD) setFill];NSRectFill(NSMakeRect(14,y+24,largest?450*value/largest:0,14));
    }
}
@end
@implementation WeightLab {
    NSPopUpButton *_size,*_rounds;
    NSButton *_run,*_sweep,*_cancelButton,*_export,*_newSeed;
    NSTextField *_status,*_device,*_verdict,*_detail,*_history,*_seedLabel;
    NSProgressIndicator *_progress;
    WeightBars *_memory,*_time;
    std::vector<wb::Result> _results;
    std::shared_ptr<std::atomic<bool>> _cancel;
    uint32_t _seed;
    BOOL _busy,_complete;
}
- (instancetype)init {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1070,820) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if(!(self=[super initWithWindow:window]))return nil;
    window.title=@"Tunguska — Weight Race";window.minSize=NSMakeSize(1060,800);window.delegate=self;window.releasedWhenClosed=NO;[window center];_seed=729;
    _size=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[_size addItemsWithTitles:@[@"1,024 × 1,024",@"4,096 × 4,096",@"8,192 × 8,192",@"16,384 × 16,384"]];[_size selectItemAtIndex:2];_size.accessibilityLabel=@"Layer size";
    _rounds=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[_rounds addItemsWithTitles:@[@"9 rounds",@"21 rounds",@"51 rounds"]];[_rounds selectItemAtIndex:1];_rounds.accessibilityLabel=@"Timing rounds";
    _run=[NSButton buttonWithTitle:@"Run comparison" target:self action:@selector(run:)];_sweep=[NSButton buttonWithTitle:@"Compare all sizes" target:self action:@selector(sweep:)];
    _cancelButton=[NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];_cancelButton.enabled=NO;
    _export=[NSButton buttonWithTitle:@"Export results…" target:self action:@selector(export:)];_export.enabled=NO;
    _newSeed=[NSButton buttonWithTitle:@"New weights" target:self action:@selector(newSeed:)];_seedLabel=Label(@"Seed 729",12,YES);
    _status=Label(@"Ready. Same weights and inputs; two representations; one GPU.",13);[_status.widthAnchor constraintEqualToConstant:990].active=YES;
    _device=Label(@"Native Metal experiment · GPU name appears after the first run",12);
    _progress=[[NSProgressIndicator alloc] init];_progress.indeterminate=NO;_progress.minValue=0;_progress.maxValue=1;[_progress.widthAnchor constraintEqualToConstant:990].active=YES;
    _memory=[[WeightBars alloc] init];_time=[[WeightBars alloc] init];_memory.unit=@"MiB";_time.unit=@"ms";
    _memory.accessibilityLabel=@"Weight memory comparison";_time.accessibilityLabel=@"Median GPU execution time comparison";
    NSStackView *charts=Stack(@[Stack(@[Label(@"WEIGHT MEMORY · LOWER IS BETTER",12,YES),_memory],YES),Stack(@[Label(@"GPU TIME · LOWER IS BETTER",12,YES),_time],YES)]);charts.spacing=30;
    _verdict=Label(@"Does smaller also mean faster? Measure it.",21);[_verdict.widthAnchor constraintEqualToConstant:990].active=YES;
    _detail=Label(@"FP16 stores each weight in 16 bits. Packed ternary stores it in 2 bits.\nBoth use the same −1, 0, +1 values. The Apple MPS library provides an additional FP16 baseline.",12);[_detail.widthAnchor constraintEqualToConstant:990].active=YES;[_detail.heightAnchor constraintEqualToConstant:88].active=YES;
    _history=Label(@"Completed layer sizes will appear here.",11,YES);[_history.widthAnchor constraintEqualToConstant:990].active=YES;[_history.heightAnchor constraintEqualToConstant:104].active=YES;
    NSTextField *notes=Label(@"Timing includes GPU unpacking. Setup and reference checks are excluded; export includes submit-to-completion timings and every sample. Repeated weights may stay in cache. This synthetic layer tests storage and execution, not trained-model accuracy, power use, or a ternary processor.",12);[notes.widthAnchor constraintEqualToConstant:990].active=YES;
    NSStackView *content=Stack(@[Label(@"WEIGHT RACE",24,YES),Label(@"Same calculation. Less memory. Test whether compact ternary weights make a neural layer faster.",13),Stack(@[_size,_rounds,_run,_sweep,_cancelButton,_export]),Stack(@[_newSeed,_seedLabel]),_device,_status,_progress,charts,_verdict,_detail,_history,notes,Label(@"Original Tunguska: Viktor Lofgren · Independent experiment: Vinny Lingham · GPL v2 or later",10)],YES);
    content.spacing=13;content.translatesAutoresizingMaskIntoConstraints=NO;[window.contentView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[[content.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:28],[content.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:22],[content.trailingAnchor constraintLessThanOrEqualToAnchor:window.contentView.trailingAnchor constant:-24],[content.bottomAnchor constraintLessThanOrEqualToAnchor:window.contentView.bottomAnchor constant:-16]]];return self;
}
- (void)showWindow:(id)sender{[super showWindow:sender];[self.window makeKeyAndOrderFront:sender];}
- (void)windowWillClose:(NSNotification*)notification{[self cancel:nil];}
- (void)setBusy:(BOOL)busy {
    _busy=busy;_size.enabled=_rounds.enabled=_run.enabled=_sweep.enabled=_newSeed.enabled=!busy;_cancelButton.enabled=busy;_export.enabled=!busy&&!_results.empty();
}
- (void)newSeed:(id)sender{++_seed;_seedLabel.stringValue=[NSString stringWithFormat:@"Seed %u",_seed];_status.stringValue=@"New seed selected. Run to compare these weights; existing results retain their original seed.";}
- (void)cancel:(id)sender{if(_busy){_cancel->store(true);_cancelButton.enabled=NO;_status.stringValue=@"Cancelling after the current bounded GPU command…";}}
- (void)run:(id)sender{[self start:NO];}
- (void)sweep:(id)sender{[self start:YES];}
- (void)start:(BOOL)all {
    if(_busy)return;
    NSString *shader=[NSBundle.mainBundle pathForResource:@"matvec" ofType:@"metal"];
    if(!shader){_status.stringValue=@"The bundled Metal shader is missing.";return;}
    const uint32_t dimensions[]={1024,4096,8192,16384};const int rounds[]={9,21,51};
    std::vector<uint32_t> sizes;if(all)sizes={1024,4096,8192,16384};else sizes={dimensions[_size.indexOfSelectedItem]};
    int count=rounds[_rounds.indexOfSelectedItem];uint32_t seed=_seed;
    _results.clear();_complete=NO;_memory.values=_time.values=@[];_memory.accessibilityValue=_time.accessibilityValue=@"No completed results";
    _memory.needsDisplay=_time.needsDisplay=YES;_history.stringValue=@"Waiting for the first validated result.";_verdict.stringValue=@"Checking the calculation before claiming a speedup.";
    _detail.stringValue=@"Three input vectors, an independent integer reference, and identical weights in both formats. Every measured output must match exactly.";
    _progress.doubleValue=0;_status.stringValue=@"Preparing the Metal pipelines…";
    _cancel=std::make_shared<std::atomic<bool>>(false);auto cancellation=_cancel;[self setBusy:YES];
    std::string path=shader.fileSystemRepresentation;__weak WeightLab *weak=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
        try {
            wb::Runner runner(path);NSString *device=String(runner.deviceName());
            dispatch_async(dispatch_get_main_queue(),^{WeightLab *self=weak;if(self)self->_device.stringValue=[NSString stringWithFormat:@"%@ · Native Metal · FP16 inputs / FP32 outputs · Batch size 1",device];});
            for(size_t i=0;i<sizes.size();++i) {
                int lastPercent=-1;
                auto progress=[&](const std::string& message,double fraction){int percent=int(fraction*100);if(percent==lastPercent)return;lastPercent=percent;
                    NSString *status=[NSString stringWithFormat:@"%u × %u · %@",sizes[i],sizes[i],String(message)];double overall=(i+fraction)/sizes.size();
                    dispatch_async(dispatch_get_main_queue(),^{WeightLab *self=weak;if(self&&!cancellation->load()){self->_status.stringValue=status;self->_progress.doubleValue=overall;}});};
                wb::Result result=runner.run({sizes[i],sizes[i],seed,count},*cancellation,progress);
                dispatch_async(dispatch_get_main_queue(),^{WeightLab *self=weak;if(self){self->_results.push_back(result);[self showResult];}});
            }
            dispatch_async(dispatch_get_main_queue(),^{WeightLab *self=weak;if(self){self->_complete=YES;self->_progress.doubleValue=1;self->_status.stringValue=@"Complete. Every GPU output matched the independent reference exactly.";[self setBusy:NO];}});
        } catch(const wb::Cancelled&) {
            dispatch_async(dispatch_get_main_queue(),^{WeightLab *self=weak;if(self){self->_status.stringValue=@"Cancelled. Completed sizes remain available; the interrupted size has no result.";[self setBusy:NO];}});
        } catch(const std::exception& error) {
            NSString *message=String(error.what());dispatch_async(dispatch_get_main_queue(),^{WeightLab *self=weak;if(self){self->_status.stringValue=[@"Benchmark stopped: " stringByAppendingString:message];[self setBusy:NO];}});
        }
    }});
}
- (void)showResult {
    if(_results.empty())return;const auto& r=_results.back();double half=r.paths[0].gpu.median,packed=r.paths[1].gpu.median,mps=r.paths[2].gpu.median;
    _memory.names=@[@"FP16 weights",@"Packed ternary weights"];_memory.values=@[@(r.sizes.halfBytes/1048576.0),@(r.sizes.packedBytes/1048576.0)];
    _time.names=@[@"FP16 matched kernel",@"FP16 Apple MPS",@"Packed ternary kernel"];_time.values=@[@(half),@(mps),@(packed)];
    double best=std::min(half,mps),ratio=best/packed;const auto& baseline=r.paths[half<=mps?0:2];
    bool clearWin=r.paths[1].gpu.p90<baseline.gpu.p10,clearLoss=r.paths[1].gpu.p10>baseline.gpu.p90;
    _verdict.stringValue=clearWin?[NSString stringWithFormat:@"Packed ternary was %.2f× faster than the faster FP16 baseline.",ratio]:clearLoss?[NSString stringWithFormat:@"The faster FP16 baseline won by %.2f×. Packing still saved memory.",1/ratio]:@"Timing ranges overlap. Repeat before claiming a speed win.";
    _detail.stringValue=[NSString stringWithFormat:@"Answers match exactly · %llu checked values · %.1f× smaller weight buffers\nGPU median: FP16 %.3f ms · Apple MPS %.3f ms · Packed %.3f ms\nPacked middle 80%%: %.3f–%.3f ms · Best FP16: %.3f–%.3f ms\nSetup %.2f s · Combined GPU buffers %.1f MiB · Seed %u · %d rounds per path",(unsigned long long)r.checkedValues,double(r.sizes.halfBytes)/r.sizes.packedBytes,half,mps,packed,r.paths[1].gpu.p10,r.paths[1].gpu.p90,baseline.gpu.p10,baseline.gpu.p90,r.setupMs/1000,r.workingBufferBytes/1048576.0,r.config.seed,r.config.rounds];
    NSMutableString *table=[NSMutableString stringWithString:@"LAYER        WEIGHTS       FP16 MiB  PACKED MiB    FP16 ms    MPS ms   PACKED ms  vs best FP16\n"];
    for(const auto& row:_results)[table appendFormat:@"%5u²    %8.2f M    %8.1f    %8.2f    %7.3f   %7.3f    %7.3f      %.2f×\n",row.config.rows,row.sizes.count/1e6,row.sizes.halfBytes/1048576.0,row.sizes.packedBytes/1048576.0,row.paths[0].gpu.median,row.paths[2].gpu.median,row.paths[1].gpu.median,std::min(row.paths[0].gpu.median,row.paths[2].gpu.median)/row.paths[1].gpu.median];
    _history.stringValue=table;_memory.accessibilityValue=[NSString stringWithFormat:@"FP16 %.3f MiB; packed ternary %.3f MiB",r.sizes.halfBytes/1048576.0,r.sizes.packedBytes/1048576.0];
    _time.accessibilityValue=[NSString stringWithFormat:@"FP16 %.4f milliseconds; Apple MPS %.4f milliseconds; packed ternary %.4f milliseconds",half,mps,packed];_memory.needsDisplay=_time.needsDisplay=YES;
}
static NSArray *Numbers(const std::vector<double>& values){NSMutableArray *a=[NSMutableArray array];for(double v:values)[a addObject:@(v)];return a;}
- (void)export:(id)sender {
    NSMutableArray *results=[NSMutableArray array];for(const auto& r:_results){NSMutableArray *paths=[NSMutableArray array];
        for(const auto& p:r.paths)[paths addObject:@{@"name":String(p.name),@"gpu_ms":Numbers(p.gpuMs),@"wall_ms":Numbers(p.wallMs),@"gpu_median_ms":@(p.gpu.median),@"gpu_p10_ms":@(p.gpu.p10),@"gpu_p90_ms":@(p.gpu.p90),@"wall_median_ms":@(p.wall.median)}];
        [results addObject:@{@"rows":@(r.config.rows),@"columns":@(r.config.columns),@"seed":@(r.config.seed),@"rounds":@(r.config.rounds),@"device":String(r.device),@"os":String(r.os),@"weight_count":@(r.sizes.count),@"fp16_weight_bytes":@(r.sizes.halfBytes),@"packed_weight_bytes":@(r.sizes.packedBytes),@"combined_gpu_buffer_bytes":@(r.workingBufferBytes),@"shader_sha256":String(r.shaderHash),@"warmups_per_path":@(wb::warmupRounds),@"setup_ms":@(r.setupMs),@"checked_values":@(r.checkedValues),@"max_absolute_error":@(r.maxError),@"paths":paths}];}
    NSDictionary *report=@{@"format":@"tunguska-weight-race-v1",@"app_version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],@"completed_requested_run":@(_complete),@"results":results,@"method":@"Synthetic batch-1 matrix-vector product. Identical -1/0/+1 weights and three dyadic input vectors. 9 warmups per path. Round order rotates across FP16 matched, packed ternary, and Apple MPS; input pattern rotates independently of path. Every row checked exactly against CPU integer accumulation. GPU time includes unpacking and command work; wall time includes encoding, submission and wait. Setup/reference/output checks excluded. FP16 and packed weight buffers coexist. Warm-cache repeated workload; no forced eviction, power measurement or trained-model accuracy claim.",@"packing":@"Row-major; four 2-bit codes per byte, low bits first. 00=zero, 01=+1, 10=-1; 11 reserved. Trailing row slots zero. No per-group scales needed: weights are exactly ternary, unit scale."};
    NSError *error=nil;NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];if(!data){_status.stringValue=error.localizedDescription;return;}
    NSSavePanel *panel=[NSSavePanel savePanel];panel.nameFieldStringValue=@"tunguska-weight-race.json";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response!=NSModalResponseOK)return;tunguska::macos::ScopedURL scope(panel.URL);
        NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];__block NSError *writeError=nil;NSError *coordError=nil;
        [coordinator coordinateWritingItemAtURL:panel.URL options:NSFileCoordinatorWritingForReplacing error:&coordError byAccessor:^(NSURL *url){[data writeToURL:url options:NSDataWritingAtomic error:&writeError];}];
        if(coordError||writeError)self->_status.stringValue=(coordError?:writeError).localizedDescription;}];
}
@end
