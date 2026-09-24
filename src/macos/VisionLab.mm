// SPDX-License-Identifier: GPL-2.0-or-later
// Independent offline ternary vision laboratory, 2026-09-24.
#import "VisionLab.h"
#import "DebuggerWindow.h"
#import "FileAccess.h"
#include "vision.h"
#include "../../resources/vision/model.h"
#include <algorithm>
#include <chrono>
#include <cmath>

namespace v = tunguska::vision;
static NSColor *Green() { return [NSColor colorWithSRGBRed:.43 green:.85 blue:.65 alpha:1]; }
static NSColor *Orange() { return [NSColor colorWithSRGBRed:1 green:.58 blue:.34 alpha:1]; }
static NSTextField *Text(NSString *s, CGFloat size = 12, BOOL mono = NO) {
    NSTextField *t = [NSTextField wrappingLabelWithString:s];
    t.font = mono ? [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular] : [NSFont systemFontOfSize:size];
    t.selectable = YES;
    return t;
}
static NSButton *Button(NSString *s, id target, SEL action) {
    return [NSButton buttonWithTitle:s target:target action:action];
}
static NSStackView *Stack(NSArray<NSView *> *views, BOOL vertical = NO) {
    NSStackView *s = [NSStackView stackViewWithViews:views];
    s.orientation = vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    s.alignment = vertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    s.spacing = 10;
    return s;
}
static void DrawText(NSString *s, NSPoint point, CGFloat size, NSColor *color, BOOL mono = NO) {
    [s drawAtPoint:point withAttributes:@{NSFontAttributeName:mono ? [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular] : [NSFont systemFontOfSize:size], NSForegroundColorAttributeName:color}];
}

@interface DigitCanvas : NSView {
    std::array<float,1024> _ink;
    NSPoint _last;
}
@property(copy) void (^changed)(void);
- (v::Pixels)pixels;
- (void)setPixels:(const v::Pixels&)pixels;
@end
@implementation DigitCanvas
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityImageRole;
        self.accessibilityLabel = @"Digit drawing canvas";
        self.accessibilityHelp = @"Draw a large centered digit with the mouse; right-drag erases. Next sample provides a keyboard-accessible alternative.";
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (v::Pixels)pixels {
    v::Pixels p{};
    for(int y=0;y<8;++y) for(int x=0;x<8;++x) {
        float sum=0;
        for(int j=0;j<4;++j) for(int i=0;i<4;++i) sum += _ink[(y*4+j)*32+x*4+i];
        p[y*8+x] = std::clamp(int(std::lround(sum)),0,16);
    }
    return p;
}
- (void)setPixels:(const v::Pixels&)p {
    for(int y=0;y<32;++y) for(int x=0;x<32;++x) _ink[y*32+x] = p[(y/4)*8+x/4]/16.0f;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)rect {
    [[NSColor colorWithWhite:.055 alpha:1] setFill]; NSRectFill(self.bounds);
    auto pixels = [self pixels];
    CGFloat cell = self.bounds.size.width/8;
    for(int y=0;y<8;++y) for(int x=0;x<8;++x) {
        CGFloat ink=pixels[y*8+x]/16.0;
        [[NSColor colorWithSRGBRed:.055+ink*.55 green:.055+ink*.84 blue:.055+ink*.68 alpha:1] setFill];
        NSRectFill(NSMakeRect(x*cell+1,y*cell+1,cell-2,cell-2));
    }
    self.accessibilityValue = @"8 by 8 grayscale digit, 17 intensity levels";
}
- (NSPoint)point:(NSEvent*)event {
    NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];
    return NSMakePoint(p.x*32/self.bounds.size.width,p.y*32/self.bounds.size.height);
}
- (void)paint:(NSEvent*)event from:(NSPoint)previous {
    NSPoint p=[self point:event];
    int steps=std::max(1,int(std::ceil(std::hypot(p.x-previous.x,p.y-previous.y)*2)));
    for(int step=1;step<=steps;++step) {
        double cx=previous.x+(p.x-previous.x)*step/steps,cy=previous.y+(p.y-previous.y)*step/steps;
        for(int y=std::max(0,int(cy)-3);y<std::min(32,int(cy)+4);++y)
            for(int x=std::max(0,int(cx)-3);x<std::min(32,int(cx)+4);++x) {
                float coverage=std::clamp(2.5-std::hypot(x+.5-cx,y+.5-cy),0.0,1.0);
                if(event.type==NSEventTypeRightMouseDown || event.type==NSEventTypeRightMouseDragged)
                    _ink[y*32+x] *= 1-coverage;
                else _ink[y*32+x] = std::max(_ink[y*32+x],coverage);
            }
    }
    _last=p; self.needsDisplay=YES;
    if(self.changed) self.changed();
}
- (void)mouseDown:(NSEvent*)e { [self paint:e from:[self point:e]]; }
- (void)mouseDragged:(NSEvent*)e { [self paint:e from:_last]; }
- (void)rightMouseDown:(NSEvent*)e { [self mouseDown:e]; }
- (void)rightMouseDragged:(NSEvent*)e { [self mouseDragged:e]; }
@end

@interface WeightMap : NSView
@property(assign) const v::Model *model;
@property(assign) v::Session *session;
@property int selected;
@property(copy) void (^selectedNeuron)(int);
@end
@implementation WeightMap
- (instancetype)initWithFrame:(NSRect)rect {
    if((self=[super initWithFrame:rect])) {
        self.accessibilityElement=YES; self.accessibilityRole=NSAccessibilityImageRole;
        self.accessibilityLabel=@"54 hidden neurons, each with an 8 by 8 ternary weight map";
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    if(!_model) return;
    for(int row=0;row<v::neurons;++row) {
        CGFloat x=(row%9)*52+2,y=(row/9)*58+2;
        if(row==_selected) { [NSColor.labelColor setStroke]; NSFrameRect(NSMakeRect(x-2,y-2,49,56)); }
        for(int i=0;i<64;++i) {
            int weight=_model->weights()[row*64+i];
            [(weight>0 ? Green() : weight<0 ? Orange() : [NSColor colorWithWhite:.16 alpha:1]) setFill];
            NSRectFill(NSMakeRect(x+(i%8)*5.5,y+(i/8)*5.5,5,5));
        }
        int activation=_session && (_session->active() || _session->complete()) ? _session->runtime().cpu().memref(v::hiddenAddress+row).to_int() : 0;
        DrawText([NSString stringWithFormat:@"%02d:%02d",row,activation],NSMakePoint(x,y+44),9,NSColor.secondaryLabelColor,YES);
    }
}
- (void)mouseDown:(NSEvent*)event {
    NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];
    int x=int(p.x)/52,y=int(p.y)/58;
    if(x<0||x>=9||y<0||y>=6) return;
    self.selected=y*9+x; self.needsDisplay=YES;
    if(self.selectedNeuron) self.selectedNeuron(self.selected);
}
@end

@interface ScoreChart : NSView
@property(assign) const v::Result *result;
@end
@implementation ScoreChart
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    if(!_result) { DrawText(@"Run inference to see guest scores.",NSMakePoint(0,10),12,NSColor.secondaryLabelColor); return; }
    int low=*std::min_element(_result->scores.begin(),_result->scores.end());
    int high=*std::max_element(_result->scores.begin(),_result->scores.end());
    for(int i=0;i<10;++i) {
        CGFloat y=i*26;
        NSColor *color=i==_result->prediction()?Green():NSColor.secondaryLabelColor;
        DrawText([NSString stringWithFormat:@"%d",i],NSMakePoint(0,y+1),13,color,YES);
        [color setFill];
        CGFloat width=std::max(2.0,135.0*(_result->scores[i]-low)/std::max(1,high-low));
        NSRectFill(NSMakeRect(23,y+5,width,12));
        DrawText([NSString stringWithFormat:@"%d",_result->scores[i]],NSMakePoint(166,y+1),12,color,YES);
    }
}
@end

@implementation VisionLab {
    v::Model _model;
    std::vector<v::Sample> _samples;
    std::unique_ptr<v::Session> _session;
    v::Result _lastResult;
    v::Baseline _lastBaseline;
    v::Pixels _runPixels;
    DigitCanvas *_canvas;
    WeightMap *_map;
    ScoreChart *_scores;
    NSTextField *_sampleLabel,*_prediction,*_baselineLabel,*_runStatus,*_neuron,*_benchmarkStatus,*_comparison;
    NSButton *_run,*_pause,*_cancel,*_export;
    NSPopUpButton *_count,*_neuronSelector;
    NSProgressIndicator *_progress;
    NSTimer *_timer;
    DebuggerWindow *_debugger;
    NSInteger _index;
    BOOL _custom,_benchmark,_manualDebug,_hasResult,_hasReport;
    int _batchTotal,_batchDone,_ternaryCorrect,_floatCorrect,_parityCount;
    std::array<std::array<int,10>,10> _confusion;
    double _batchGuestMs,_batchFloatMs,_lastFloatMs;
    uint64_t _batchCycles;
    NSTimeInterval _batchStarted;
    NSMutableArray *_records;
}
- (instancetype)init {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1160,830)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if(!(self=[super initWithWindow:window])) return nil;
    window.title=@"Tunguska — Ternary Vision Lab"; window.minSize=NSMakeSize(1140,820);
    window.releasedWhenClosed=NO; window.delegate=self; [window center];
    NSString *resource=NSBundle.mainBundle.resourcePath;
    try {
        _samples=v::loadSamples([[resource stringByAppendingPathComponent:@"vision-digits.bin"] fileSystemRepresentation]);
        _session=std::make_unique<v::Session>([[resource stringByAppendingPathComponent:@"vision.ternobj"] fileSystemRepresentation],_model);
    } catch(const std::exception& e) {
        NSAlert *alert=[[NSAlert alloc] init]; alert.messageText=@"Vision Lab could not load";
        alert.informativeText=[NSString stringWithUTF8String:e.what()]; [alert runModal]; return nil;
    }
    NSTextField *title=Text(@"TERNARY VISION LAB",22,YES);
    NSTextField *subtitle=Text(@"Draw a digit. Follow 54 neurons. Watch a real ternary CPU recognize it.",13);
    subtitle.textColor=NSColor.secondaryLabelColor;
    _run=Button(@"Run inference",self,@selector(run:)); _run.keyEquivalent=@"\r";
    _pause=Button(@"Pause",self,@selector(pause:));
    _cancel=Button(@"Cancel",self,@selector(cancel:));
    _export=Button(@"Export report…",self,@selector(exportReport:));
    NSStackView *toolbar=Stack(@[_run,_pause,_cancel,Button(@"Debug guest",self,@selector(debug:)),_export]);

    _canvas=[[DigitCanvas alloc] initWithFrame:NSZeroRect];
    [_canvas.widthAnchor constraintEqualToConstant:256].active=YES;
    [_canvas.heightAnchor constraintEqualToConstant:256].active=YES;
    _sampleLabel=Text(@"",12,YES);
    NSStackView *samples=Stack(@[Button(@"Previous",self,@selector(previous:)),Button(@"Next sample",self,@selector(next:)),Button(@"Clear",self,@selector(clear:))]);
    NSTextField *drawing=Text(@"Draw large and centered. Drag to paint; right-drag to erase. Each cell measures ink from 0 to 16.",12);
    _baselineLabel=Text(@"",13);
    NSStackView *left=Stack(@[Text(@"INPUT · 8 × 8",12,YES),_canvas,samples,_sampleLabel,drawing,_baselineLabel],YES);
    [left.widthAnchor constraintEqualToConstant:266].active=YES;
    [drawing.widthAnchor constraintEqualToConstant:256].active=YES;
    [_sampleLabel.widthAnchor constraintEqualToConstant:256].active=YES;
    [_baselineLabel.widthAnchor constraintEqualToConstant:256].active=YES;

    _map=[[WeightMap alloc] initWithFrame:NSZeroRect]; _map.model=&_model; _map.session=_session.get();
    [_map.widthAnchor constraintEqualToConstant:468].active=YES;
    [_map.heightAnchor constraintEqualToConstant:348].active=YES;
    _neuronSelector=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for(int i=0;i<54;++i) [_neuronSelector addItemWithTitle:[NSString stringWithFormat:@"Neuron %02d",i]];
    _neuronSelector.target=self; _neuronSelector.action=@selector(selectNeuron:);
    _neuronSelector.accessibilityLabel=@"Inspect hidden neuron";
    _neuron=Text(@"",11,YES); [_neuron.widthAnchor constraintEqualToConstant:468].active=YES;
    NSStackView *middle=Stack(@[Text(@"HIDDEN LAYER · 54 WEIGHT MAPS",12,YES),_map,
        Stack(@[_neuronSelector,Text(@"Green +1   Orange −1   Dark 0",11)]),_neuron],YES);
    [middle.widthAnchor constraintEqualToConstant:468].active=YES;

    _prediction=Text(@"Ready",32,YES);
    _scores=[[ScoreChart alloc] initWithFrame:NSZeroRect];
    [_scores.widthAnchor constraintEqualToConstant:228].active=YES; [_scores.heightAnchor constraintEqualToConstant:260].active=YES;
    _scores.accessibilityElement=YES; _scores.accessibilityRole=NSAccessibilityImageRole; _scores.accessibilityLabel=@"Guest output scores";
    _runStatus=Text(@"",11,YES); [_runStatus.widthAnchor constraintEqualToConstant:228].active=YES;
    NSStackView *right=Stack(@[Text(@"GUEST PREDICTION",12,YES),_prediction,_scores,
        Text(@"Scores are relative, not probabilities.",11),_runStatus],YES);
    [right.widthAnchor constraintEqualToConstant:228].active=YES;
    NSStackView *body=Stack(@[left,middle,right]); body.spacing=24; body.alignment=NSLayoutAttributeTop;
    [body.heightAnchor constraintEqualToConstant:482].active=YES;

    _count=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_count addItemsWithTitles:@[@"First 100 held-out samples",@"All 1,797 held-out samples"]];
    _count.accessibilityLabel=@"Benchmark sample count";
    _progress=[[NSProgressIndicator alloc] init]; _progress.indeterminate=NO; _progress.minValue=0; _progress.maxValue=100;
    [_progress.widthAnchor constraintEqualToConstant:160].active=YES;
    _progress.accessibilityLabel=@"Guest benchmark progress";
    _benchmarkStatus=Text(@"Run the same samples through both models. Every guest activation and score is checked.",12);
    _comparison=Text([NSString stringWithFormat:@"Held-out accuracy: ternary %.2f%% · float32 %.2f%% (1,797 digits, integer reference / native baseline).\nWeight payload: 800 B packed ternary vs 15,984 B float32; biases add 256 B to each. Emulation is slower than native Mac inference.",
        100.0*v::model::ternaryCorrect/v::model::testCount,100.0*v::model::floatCorrect/v::model::testCount],12);
    NSStackView *benchmarkControls=Stack(@[Text(@"COMPARE",12,YES),_count,Button(@"Benchmark",self,@selector(benchmark:)),_progress]);
    NSTextField *credit=Text(@"UCI Optical Recognition of Handwritten Digits · E. Alpaydin & C. Kaynak · CC BY 4.0 · Full attribution in License and Credits",10);
    credit.textColor=NSColor.secondaryLabelColor;
    NSStackView *content=Stack(@[title,subtitle,toolbar,body,benchmarkControls,_benchmarkStatus,_comparison,credit],YES);
    content.spacing=12; content.translatesAutoresizingMaskIntoConstraints=NO;
    [window.contentView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:24],
        [content.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:20],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:window.contentView.trailingAnchor constant:-24],
        [content.bottomAnchor constraintLessThanOrEqualToAnchor:window.contentView.bottomAnchor constant:-16],
        [_benchmarkStatus.widthAnchor constraintEqualToConstant:1060],[_comparison.widthAnchor constraintEqualToConstant:1060]
    ]];
    __weak VisionLab *weak=self;
    _canvas.changed=^{ [weak inputChanged]; };
    _map.selectedNeuron=^(int i){ [weak selectNeuronIndex:i]; };
    [self loadSample:0]; [self refresh];
    return self;
}
- (void)showWindow:(id)sender {
    [super showWindow:sender]; [self.window makeKeyAndOrderFront:sender];
    if(!_timer) {
        _timer=[NSTimer timerWithTimeInterval:1.0/60 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    }
}
- (void)windowWillClose:(NSNotification*)notification {
    [self cancel:nil]; [_timer invalidate]; _timer=nil; [_debugger close];
}
- (void)error:(const std::exception&)e {
    [self cancel:nil]; _runStatus.stringValue=[NSString stringWithUTF8String:e.what()];
    _prediction.stringValue=@"Error";
}
- (void)invalidateResult {
    _hasResult=NO; _scores.result=nullptr; _scores.needsDisplay=YES;
    _scores.accessibilityValue=@"No inference result for this input";
    _prediction.stringValue=@"Ready"; _baselineLabel.stringValue=@"Float32 baseline runs on the Mac alongside the guest.";
    _runStatus.stringValue=@"64 inputs → 54 neurons → 10 scores\nWeights: −1, 0, +1\nMatrix products use add/subtract/skip.";
}
- (void)inputChanged {
    [self cancel:nil]; _custom=YES; _sampleLabel.stringValue=@"Your drawing · no ground-truth label";
    _session->cancel();
    [self invalidateResult]; [self refresh];
}
- (void)loadSample:(NSInteger)index {
    [self cancel:nil]; _index=(index+_samples.size())%_samples.size(); _custom=NO;
    _session->cancel();
    [_canvas setPixels:_samples[_index].pixels];
    _sampleLabel.stringValue=[NSString stringWithFormat:@"Held-out sample %ld / %lu\nTrue digit: %d",(long)_index+1,(unsigned long)_samples.size(),_samples[_index].label];
    [self invalidateResult]; [self refresh];
}
- (void)previous:(id)sender { [self loadSample:_index-1]; }
- (void)next:(id)sender { [self loadSample:_index+1]; }
- (void)clear:(id)sender { v::Pixels blank{}; [_canvas setPixels:blank]; [self inputChanged]; }
- (void)selectNeuronIndex:(int)i { _map.selected=i; [_neuronSelector selectItemAtIndex:i]; [self refreshNeuron]; }
- (void)selectNeuron:(id)sender { [self selectNeuronIndex:int(_neuronSelector.indexOfSelectedItem)]; }
- (void)refreshNeuron {
    int row=_map.selected,sum=v::model::bias1[row],adds=0,subs=0;
    auto pixels=_session->active()||_hasResult ? _runPixels : [_canvas pixels];
    for(int i=0;i<64;++i) {
        int w=_model.weights()[row*64+i]; sum+=w*pixels[i]; adds+=w>0; subs+=w<0;
    }
    int reference=std::clamp(std::max(0,sum)/8,0,81);
    NSString *guest=(_session->active()||_hasResult) && _session->progress()>row ?
        [NSString stringWithFormat:@"%d",_session->runtime().cpu().memref(v::hiddenAddress+row).to_int()] : @"pending";
    _neuron.stringValue=[NSString stringWithFormat:@"Bias %d · %d adds · %d subtracts · %d skips\nReference: clamp(max(0, %d) / 8) = %d · Guest: %@\nGuest activation address: %d",v::model::bias1[row],adds,subs,64-adds-subs,sum,reference,guest,v::hiddenAddress+row];
    _map.needsDisplay=YES;
}
- (void)startPaused:(BOOL)paused {
    _runPixels=[_canvas pixels];
    auto start=std::chrono::steady_clock::now();
    _lastBaseline=_model.baseline(_runPixels);
    _lastFloatMs=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    _session->start(_runPixels,paused); _manualDebug=paused; _hasResult=NO;
    _scores.result=nullptr; _scores.needsDisplay=YES;
    _scores.accessibilityValue=@"Guest inference has not finished";
    _prediction.stringValue=paused?@"Paused":@"Running…";
    _baselineLabel.stringValue=[NSString stringWithFormat:@"Native float32 predicts %d.\nGuest result is calculated independently.",_lastBaseline.prediction()];
    [_debugger imageDidChange]; [self refresh];
}
- (void)run:(id)sender {
    [self cancel:nil];
    try { [self startPaused:NO]; } catch(const std::exception& e) { [self error:e]; }
}
- (void)pause:(id)sender {
    if(_session->active()) _session->runtime().setRunning(!_session->runtime().running());
    [self refresh];
}
- (void)cancel:(id)sender {
    if(_benchmark) _benchmarkStatus.stringValue=[NSString stringWithFormat:@"Cancelled after %d / %d samples. Partial results can be exported.",_batchDone,_batchTotal];
    _benchmark=NO;
    if(_session && _session->active()) {
        _session->cancel(); _prediction.stringValue=@"Cancelled";
        _runStatus.stringValue=@"Run cancelled. Start a new inference to continue.";
    }
    [self refresh];
}
- (void)debug:(id)sender {
    if(_benchmark) [self cancel:nil];
    try {
        if(!_session->active()) [self startPaused:YES];
        else _session->runtime().setRunning(false);
        _manualDebug=YES;
        if(!_debugger) {
            _debugger=[[DebuggerWindow alloc] init]; _debugger.runtime=&_session->runtime();
            _debugger.window.title=@"Tunguska — Vision Guest Debugger";
            __weak VisionLab *weak=self; _debugger.didChange=^{ [weak refresh]; };
        }
        [_debugger imageDidChange]; [_debugger showWindow:sender]; [self refresh];
    } catch(const std::exception& e) { [self error:e]; }
}
- (void)benchmark:(id)sender {
    [self cancel:nil];
    _batchTotal=_count.indexOfSelectedItem==0?100:int(_samples.size()); _batchDone=0;
    _ternaryCorrect=0; _floatCorrect=0; _parityCount=0; _confusion={};
    _batchGuestMs=0; _batchFloatMs=0; _batchCycles=0; _records=[NSMutableArray array];
    _hasReport=YES; _batchStarted=NSDate.timeIntervalSinceReferenceDate;
    _progress.maxValue=_batchTotal; _progress.doubleValue=0;
    [self loadSample:0]; _benchmark=YES;
    try { [self startPaused:NO]; } catch(const std::exception& e) { [self error:e]; }
}
- (void)recordResult {
    int predicted=_lastResult.prediction(),truth=_samples[_index].label;
    ++_batchDone; _ternaryCorrect+=predicted==truth; _floatCorrect+=_lastBaseline.prediction()==truth;
    _parityCount+=_session->matchesReference(); ++_confusion[truth][predicted];
    _batchGuestMs+=_session->computeMilliseconds(); _batchFloatMs+=_lastFloatMs; _batchCycles+=_session->runtime().cycles();
    [_records addObject:@{@"sample_index":@(_index),@"label":@(truth),@"ternary_prediction":@(predicted),
        @"float32_prediction":@(_lastBaseline.prediction()),@"guest_instructions":@(_session->runtime().cycles()),
        @"guest_active_ms":@(_session->computeMilliseconds()),@"float32_native_ms":@(_lastFloatMs),@"reference_match":@YES}];
    _progress.doubleValue=_batchDone;
    _benchmarkStatus.stringValue=[NSString stringWithFormat:@"%@ %d / %d · Ternary %.2f%% · Float32 %.2f%% · %d exact guest/reference matches\nCompute totals: guest %.1f ms · native float32 %.3f ms · elapsed %.1f s (includes setup and UI scheduling).",
        _batchDone==_batchTotal?@"Complete":@"Testing",_batchDone,_batchTotal,100.0*_ternaryCorrect/_batchDone,100.0*_floatCorrect/_batchDone,
        _parityCount,_batchGuestMs,_batchFloatMs,NSDate.timeIntervalSinceReferenceDate-_batchStarted];
}
- (void)tick:(NSTimer*)timer {
    if(!_session->active()) return;
    try {
        _session->pump(100000,5);
        if(_session->complete()) {
            _lastResult=_session->result(); _hasResult=YES;
            _scores.result=&_lastResult; _scores.needsDisplay=YES;
            _prediction.stringValue=[NSString stringWithFormat:@"Digit %d",_lastResult.prediction()];
            _scores.accessibilityValue=[NSString stringWithFormat:@"Predicted digit %d. Integer scores: %d, %d, %d, %d, %d, %d, %d, %d, %d, %d",_lastResult.prediction(),_lastResult.scores[0],_lastResult.scores[1],_lastResult.scores[2],_lastResult.scores[3],_lastResult.scores[4],_lastResult.scores[5],_lastResult.scores[6],_lastResult.scores[7],_lastResult.scores[8],_lastResult.scores[9]];
            _runStatus.stringValue=[NSString stringWithFormat:@"%llu guest instructions\n%@\nExact reference match ✓",(unsigned long long)_session->runtime().cycles(),
                _manualDebug?@"Timing omitted after debugging":[NSString stringWithFormat:@"%.2f ms active guest compute",_session->computeMilliseconds()]];
            if(_benchmark) {
                [self recordResult];
                if(_batchDone<_batchTotal) {
                    NSInteger next=_batchDone;
                    // Load the next sample without cancelling this benchmark.
                    _index=next; _custom=NO; [_canvas setPixels:_samples[next].pixels];
                    _sampleLabel.stringValue=[NSString stringWithFormat:@"Held-out sample %ld / %lu\nTrue digit: %d",(long)next+1,(unsigned long)_samples.size(),_samples[next].label];
                    [self startPaused:NO];
                } else _benchmark=NO;
            }
        }
        [self refresh];
    } catch(const std::exception& e) { [self error:e]; }
}
- (void)refresh {
    if(!_session) return;
    _pause.enabled=_session->active(); _pause.title=_session->runtime().running()?@"Pause":@"Resume";
    _cancel.enabled=_session->active()||_benchmark; _export.enabled=_hasResult||_hasReport;
    if(_session->active()) {
        _prediction.stringValue=_session->runtime().running()?@"Running…":@"Paused";
        _runStatus.stringValue=[NSString stringWithFormat:@"%d / 64 neurons complete\n%llu guest instructions\n%@",_session->progress(),(unsigned long long)_session->runtime().cycles(),
            _session->runtime().stoppedAtBreakpoint()?@"Stopped at breakpoint":@"Inference executes inside Tunguska"];
    }
    [self refreshNeuron]; [_debugger refresh];
}
- (void)exportReport:(id)sender {
    NSMutableDictionary *report=[@{@"format":@"tunguska-vision-report-v1",@"architecture":@[@64,@54,@10],
        @"dataset":@"UCI Optical Recognition of Handwritten Digits",@"dataset_doi":@"10.24432/C50P49",
        @"dataset_license":@"CC-BY-4.0",@"packed_weight_bytes":@800,@"float32_weight_bytes":@15984,@"bias_bytes_each":@256,
        @"timing_note":@"Guest active compute excludes setup, UI waits and manual steps. Native float32 is unoptimized scalar C++; per-sample timings include timer overhead. This is an emulator demonstration, not a hardware efficiency benchmark."} mutableCopy];
    if(_hasResult) {
        NSMutableArray *pixels=[NSMutableArray array],*scores=[NSMutableArray array],*hidden=[NSMutableArray array];
        for(int p:_runPixels) [pixels addObject:@(p)]; for(int s:_lastResult.scores) [scores addObject:@(s)];
        for(int h:_lastResult.hidden) [hidden addObject:@(h)];
        report[@"current_inference"]=@{@"pixels":pixels,@"scores":scores,@"hidden":hidden,@"ternary_prediction":@(_lastResult.prediction()),
            @"sample_index":_custom?(id)NSNull.null:@(_index),@"true_label":_custom?(id)NSNull.null:@(_samples[_index].label),
            @"float32_prediction":@(_lastBaseline.prediction()),@"manually_debugged":@(_manualDebug),@"reference_match":@(_session->matchesReference())};
    }
    if(_hasReport) {
        NSMutableArray *matrix=[NSMutableArray array];
        for(const auto& row:_confusion) { NSMutableArray *values=[NSMutableArray array]; for(int n:row) [values addObject:@(n)]; [matrix addObject:values]; }
        report[@"benchmark"]=@{@"selection":@"First N records in official held-out test file",@"requested":@(_batchTotal),@"completed":@(_batchDone),
            @"ternary_correct":@(_ternaryCorrect),@"float32_correct":@(_floatCorrect),@"guest_reference_matches":@(_parityCount),
            @"guest_active_ms":@(_batchGuestMs),@"float32_native_ms":@(_batchFloatMs),@"guest_instructions":@(_batchCycles),
            @"confusion_rows_true_columns_predicted":matrix,@"records":_records?:@[]};
    }
    NSData *modelData=[NSData dataWithContentsOfFile:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"vision-model.json"]];
    if(modelData) report[@"model_provenance"]=[NSJSONSerialization JSONObjectWithData:modelData options:0 error:nil];
    report[@"app_version"]=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSError *error=nil; NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    if(!data) return;
    NSSavePanel *panel=[NSSavePanel savePanel]; panel.nameFieldStringValue=@"tunguska-vision-report.json";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if(response!=NSModalResponseOK) return;
        tunguska::macos::ScopedURL scope(panel.URL);
        NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block NSError *writeError=nil; NSError *coordinateError=nil;
        [coordinator coordinateWritingItemAtURL:panel.URL options:NSFileCoordinatorWritingForReplacing error:&coordinateError byAccessor:^(NSURL *url){
            [data writeToURL:url options:NSDataWritingAtomic error:&writeError];
        }];
        NSError *failure=coordinateError?:writeError;
        if(failure) { NSAlert *alert=[[NSAlert alloc] init]; alert.messageText=@"Report could not be saved"; alert.informativeText=failure.localizedDescription; [alert beginSheetModalForWindow:self.window completionHandler:nil]; }
    }];
}
@end
