// SPDX-License-Identifier: GPL-2.0-or-later
// Independent offline ternary vision laboratory, 2026-09-24.
#import "VisionLab.h"
#import "Interface.h"
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
static NSTextField *Text(NSString *s, CGFloat size = 12, BOOL mono = NO) { return TGText(s,size,mono); }
static NSButton *Button(NSString *s, id target, SEL action) {
    return TGButton(s, nil, target, action);
}
static NSStackView *Stack(NSArray<NSView *> *views, BOOL vertical = NO) { return TGStack(views,vertical,10); }
static void DrawText(NSString *s, NSPoint point, CGFloat size, NSColor *color, BOOL mono = NO) {
    [s drawAtPoint:point withAttributes:@{NSFontAttributeName:mono ? [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular] : [NSFont systemFontOfSize:size], NSForegroundColorAttributeName:color}];
}

@interface DigitCanvas : NSView {
    std::array<float,1024> _ink;
    NSPoint _last;
}
@property(copy) void (^changed)(void);
- (v::Pixels)pixels;
- (v::Drawing)drawing:(BOOL)normalize;
- (void)setPixels:(const v::Pixels&)pixels;
@end
@implementation DigitCanvas
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityImageRole;
        self.accessibilityLabel = @"Digit drawing canvas";
        self.accessibilityHelp = @"Draw one digit with the mouse; right-drag erases. Next sample provides a keyboard-accessible alternative.";
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
- (v::Drawing)drawing:(BOOL)normalize { return v::prepareDrawing(_ink,normalize); }
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
@property(assign) const v::Result *result;
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
        int activation=_result ? _result->hidden[row] : _session && (_session->active() || _session->complete()) ? _session->runtime().cpu().memref(v::hiddenAddress+row).to_int() : 0;
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
    if(!_result) { DrawText(@"Run inference to see ternary scores.",NSMakePoint(0,10),12,NSColor.secondaryLabelColor); return; }
    int low=*std::min_element(_result->scores.begin(),_result->scores.end());
    int high=*std::max_element(_result->scores.begin(),_result->scores.end());
    for(int i=0;i<10;++i) {
        CGFloat y=i*26;
        NSColor *color=i==_result->prediction()?TGSuccessTextColor():NSColor.secondaryLabelColor;
        DrawText([NSString stringWithFormat:@"%d",i],NSMakePoint(0,y+1),13,color,YES);
        [color setFill];
        CGFloat width=std::max(2.0,135.0*(_result->scores[i]-low)/std::max(1,high-low));
        NSRectFill(NSMakeRect(23,y+5,width,12));
        DrawText([NSString stringWithFormat:@"%d",_result->scores[i]],NSMakePoint(166,y+1),12,color,YES);
    }
}
@end

// Small read-only previews share the same numerical input as inference.
@interface PixelPreview : NSView
@property v::Pixels pixels;
@property std::array<int,64> effect;
@property BOOL heat;
@end
@implementation PixelPreview
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    [[NSColor colorWithWhite:.055 alpha:1] setFill];NSRectFill(self.bounds);
    CGFloat cell=self.bounds.size.width/8;
    int largest=1;for(int v:_effect) largest=std::max(largest,std::abs(v));
    for(int i=0;i<64;++i) {
        double brightness=_heat?double(std::abs(_effect[i]))/largest:_pixels[i]/16.0;
        NSColor *base=_heat&&_effect[i]<0?Orange():Green();
        [[base colorWithAlphaComponent:brightness] setFill];
        NSRectFillUsingOperation(NSMakeRect((i%8)*cell+1,(i/8)*cell+1,cell-2,cell-2),NSCompositingOperationSourceOver);
    }
}
@end

@interface MistakeBrowser : NSWindowController <NSTableViewDataSource,NSTableViewDelegate>
- (instancetype)initWithModel:(const v::Model*)model samples:(const std::vector<v::Sample>*)samples;
@property(copy) void (^openSample)(int);
@end
@implementation MistakeBrowser {
    const v::Model *_model;
    const std::vector<v::Sample> *_samples;
    std::vector<v::Mistake> _all,_visible;
    NSTableView *_table;
    NSPopUpButton *_kind,*_digit;
    PixelPreview *_drawing,*_effect;
    NSTextField *_detail,*_summary,*_effectLabel;
    NSButton *_open;
}
- (instancetype)initWithModel:(const v::Model*)model samples:(const std::vector<v::Sample>*)samples {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,650)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if(!(self=[super initWithWindow:window])) return nil;
    _model=model;_samples=samples;_all=v::mistakes(*model,*samples);
    window.title=@"Tunguska — Mistake Browser";TGConfigureWindow(window,@"MistakeBrowser",NSMakeSize(850,540));
    _kind=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[_kind addItemsWithTitles:@[@"Ternary mistakes",@"Any model's mistakes"]];
    _digit=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[_digit addItemWithTitle:@"All true digits"];
    for(int i=0;i<10;++i) [_digit addItemWithTitle:[NSString stringWithFormat:@"True digit %d",i]];
    _kind.target=self;_kind.action=@selector(filter:);_digit.target=self;_digit.action=@selector(filter:);
    _kind.accessibilityLabel=@"Mistake filter";_digit.accessibilityLabel=@"True digit filter";
    _summary=Text(@"",12);
    NSStackView *filters=Stack(@[_kind,_digit,_summary]);
    _table=[[NSTableView alloc] init];_table.dataSource=self;_table.delegate=self;_table.rowHeight=26;
    _table.accessibilityLabel=@"Mistakes on the official held-out digits";
    _table.style=NSTableViewStylePlain;_table.intercellSpacing=NSMakeSize(3,2);
    _table.columnAutoresizingStyle=NSTableViewUniformColumnAutoresizingStyle;
    NSArray *names=@[@"Sample",@"True",@"Ternary",@"Float32",@"8-bit",@"Margin"];
    for(NSString *name in names){NSTableColumn *col=[[NSTableColumn alloc] initWithIdentifier:name];col.title=name;col.minWidth=70;col.maxWidth=90;col.width=80;[_table addTableColumn:col];}
    NSScrollView *scroll=[[NSScrollView alloc] init];scroll.documentView=_table;scroll.hasVerticalScroller=YES;
    [scroll.widthAnchor constraintEqualToConstant:530].active=YES;[scroll.heightAnchor constraintEqualToConstant:490].active=YES;
    _drawing=[[PixelPreview alloc] init];_effect=[[PixelPreview alloc] init];_effect.heat=YES;
    for(PixelPreview *view in @[_drawing,_effect]) {
        [view.widthAnchor constraintEqualToConstant:160].active=YES;[view.heightAnchor constraintEqualToConstant:160].active=YES;
        view.accessibilityElement=YES;view.accessibilityRole=NSAccessibilityImageRole;
    }
    _drawing.accessibilityLabel=@"Selected mistaken digit";_effect.accessibilityLabel=@"Effect of erasing each input cell";
    _detail=Text(@"",13,YES);[_detail.widthAnchor constraintEqualToConstant:350].active=YES;
    _effectLabel=Text(@"",12);[_effectLabel.widthAnchor constraintEqualToConstant:350].active=YES;
    _open=Button(@"Open this sample in the lab",self,@selector(open:));
    NSTextField *explanation=Text(@"Green: erasing lowers the score. Orange: erasing raises it.\nThis is a sensitivity experiment, not proof of why a digit is correct.",11);
    [explanation.widthAnchor constraintEqualToConstant:350].active=YES;
    NSStackView *detail=Stack(@[Stack(@[_drawing,_effect]),_detail,_effectLabel,explanation,_open],YES);
    NSStackView *body=Stack(@[scroll,detail]);body.alignment=NSLayoutAttributeTop;body.spacing=24;
    NSStackView *content=TGStack(@[filters,TGCard(body),
        Text(@"Raw top-choice errors before abstention. These historical test examples are diagnostic; do not use them to tune the model.",11)],YES,20);
    TGInstallPage(window,@"Mistake Browser",@"Compare missed digits and inspect how each pixel affects the score.",@"magnifyingglass",content,936);
    [self filter:nil];return self;
}
- (void)filter:(id)sender {
    _visible.clear();int digit=int(_digit.indexOfSelectedItem)-1;
    for(auto row:_all) if((digit<0||row.truth==digit)&&(_kind.indexOfSelectedItem==1||row.ternary!=row.truth)) _visible.push_back(row);
    [_table reloadData];_summary.stringValue=[NSString stringWithFormat:@"%lu matching samples",(unsigned long)_visible.size()];
    if(!_visible.empty()) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self updateSelection];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { return _visible.size(); }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    const auto& item=_visible.at(row);NSString *name=column.identifier;int value=item.margin;
    if([name isEqual:@"Sample"])value=item.sample+1;else if([name isEqual:@"True"])value=item.truth;
    else if([name isEqual:@"Ternary"])value=item.ternary;else if([name isEqual:@"Float32"])value=item.floating;else if([name isEqual:@"8-bit"])value=item.quantized;
    TGTableCell *cell=TGCell(table,column.identifier);
    cell.textField.stringValue=[NSString stringWithFormat:@"%d",value];
    cell.tone=NSColor.labelColor;
    if(([name isEqual:@"Ternary"]||[name isEqual:@"Float32"]||[name isEqual:@"8-bit"])&&value!=item.truth)cell.tone=TGWarningTextColor();
    return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    [self updateSelection];
}
- (void)updateSelection {
    NSInteger row=_table.selectedRow;_open.enabled=row>=0&&row<NSInteger(_visible.size());
    if(!_open.enabled){_detail.stringValue=@"No matching mistakes.";_drawing.pixels={};_effect.effect={};_effectLabel.stringValue=@"";}
    else {
        const auto& item=_visible[row];const auto& pixels=(*_samples)[item.sample].pixels;
        _drawing.pixels=pixels;_effect.effect=_model->sensitivity(pixels);
        _detail.stringValue=[NSString stringWithFormat:@"Sample %d · correct digit %d\nTernary %d · Float32 %d · 8-bit %d\nTernary score gap %d · %@",item.sample+1,item.truth,item.ternary,item.floating,item.quantized,item.margin,item.margin<v::model::uncertaintyMargin?@"would abstain":@"would answer"];
        _effectLabel.stringValue=[NSString stringWithFormat:@"Right: erase one cell at a time and measure the change in digit %d's score.",item.ternary];
        _drawing.accessibilityValue=[NSString stringWithFormat:@"True digit %d; ternary prediction %d",item.truth,item.ternary];
        _effect.accessibilityValue=_effectLabel.stringValue;
    }
    _drawing.needsDisplay=YES;_effect.needsDisplay=YES;
}
- (void)open:(id)sender {if(_open.enabled&&self.openSample)self.openSample(_visible[_table.selectedRow].sample);}
@end

@implementation VisionLab {
    v::Model _model;
    std::vector<v::Sample> _samples;
    std::unique_ptr<v::Session> _session;
    v::Result _lastResult;
    v::Baseline _lastBaseline;
    v::Comparison _native;
    v::Pixels _rawPixels;
    PixelPreview *_preview;
    NSButton *_normalize;
    NSPopUpButton *_execution;
    MistakeBrowser *_mistakes;
    BOOL _pendingNative,_nativePaused,_guestRun,_runNormalized,_batchNative;
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
    int _batchTotal,_batchDone,_ternaryCorrect,_floatCorrect,_int8Correct,_parityCount,_nativeParityCount,_answered,_answeredCorrect;
    std::array<std::array<int,10>,10> _confusion;
    double _batchGuestMs,_batchFloatMs,_batchTernaryMs,_batchInt8Ms,_lastFloatMs;
    uint64_t _batchCycles;
    NSTimeInterval _batchStarted;
    NSMutableArray *_records;
}
- (instancetype)init {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1180,780)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if(!(self=[super initWithWindow:window])) return nil;
    window.title=@"Tunguska — Vision Lab"; window.delegate=self;
    TGConfigureWindow(window, @"VisionLab", NSMakeSize(980,600));
    NSString *resource=NSBundle.mainBundle.resourcePath;
    try {
        _samples=v::loadSamples([[resource stringByAppendingPathComponent:@"vision-digits.bin"] fileSystemRepresentation]);
        _session=std::make_unique<v::Session>([[resource stringByAppendingPathComponent:@"vision.ternobj"] fileSystemRepresentation],_model);
    } catch(const std::exception& e) {
        NSAlert *alert=[[NSAlert alloc] init]; alert.messageText=@"Vision Lab could not load";
        alert.informativeText=[NSString stringWithUTF8String:e.what()]; [alert runModal]; return nil;
    }
    _run=Button(@"Run inference",self,@selector(run:)); _run.keyEquivalent=@"\r"; TGPrimary(_run);
    _run.toolTip=@"Recognize the current drawing or sample (Return).";
    _pause=Button(@"Pause",self,@selector(pause:));
    _cancel=Button(@"Cancel",self,@selector(cancel:));
    _export=Button(@"Export report…",self,@selector(exportReport:));
    _execution=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_execution addItemsWithTitles:@[@"Ternary CPU",@"Fast on Mac"]];_execution.accessibilityLabel=@"Inference execution mode";
    _execution.target=self;_execution.action=@selector(modeChanged:);
    NSStackView *toolbar=Stack(@[_execution,_run,_pause,_cancel,Button(@"Debug guest",self,@selector(debug:)),Button(@"Show mistakes…",self,@selector(showMistakes:)),_export]);

    _canvas=[[DigitCanvas alloc] initWithFrame:NSZeroRect];
    [_canvas.widthAnchor constraintEqualToConstant:224].active=YES;
    [_canvas.heightAnchor constraintEqualToConstant:224].active=YES;
    _sampleLabel=Text(@"",12,YES);
    NSStackView *samples=Stack(@[TGButton(@"",@"chevron.left",self,@selector(previous:)),Button(@"Next sample",self,@selector(next:)),Button(@"Clear",self,@selector(clear:))]);
    ((NSButton *)samples.arrangedSubviews[0]).accessibilityLabel=@"Previous sample";
    ((NSButton *)samples.arrangedSubviews[0]).toolTip=@"Previous sample";
    NSTextField *drawing=Text(@"Drag to paint; right-drag to erase. Preview shows the exact input sent to all three models.",11);
    _normalize=[NSButton checkboxWithTitle:@"Center and resize drawings" target:self action:@selector(normalizeChanged:)];_normalize.state=NSControlStateValueOn;
    _preview=[[PixelPreview alloc] init];[_preview.widthAnchor constraintEqualToConstant:64].active=YES;[_preview.heightAnchor constraintEqualToConstant:64].active=YES;
    _preview.accessibilityElement=YES;_preview.accessibilityRole=NSAccessibilityImageRole;_preview.accessibilityLabel=@"Prepared model input";
    NSStackView *preprocessing=Stack(@[_preview,Text(@"Model input\nSamples keep their original pixels.",11)]);
    _baselineLabel=Text(@"",13);
    NSStackView *left=Stack(@[TGHeading(@"1. Draw or choose a digit"),_canvas,samples,_normalize,preprocessing,_sampleLabel,drawing,_baselineLabel],YES);
    [left.widthAnchor constraintEqualToConstant:266].active=YES;
    [drawing.widthAnchor constraintEqualToConstant:224].active=YES;
    [_sampleLabel.widthAnchor constraintEqualToConstant:224].active=YES;
    [_baselineLabel.widthAnchor constraintEqualToConstant:224].active=YES;

    _map=[[WeightMap alloc] initWithFrame:NSZeroRect]; _map.model=&_model; _map.session=_session.get();
    [_map.widthAnchor constraintEqualToConstant:468].active=YES;
    [_map.heightAnchor constraintEqualToConstant:348].active=YES;
    _neuronSelector=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for(int i=0;i<54;++i) [_neuronSelector addItemWithTitle:[NSString stringWithFormat:@"Neuron %02d",i]];
    _neuronSelector.target=self; _neuronSelector.action=@selector(selectNeuron:);
    _neuronSelector.accessibilityLabel=@"Inspect hidden neuron";
    _neuron=Text(@"",11,YES); [_neuron.widthAnchor constraintEqualToConstant:468].active=YES;
    NSStackView *middle=Stack(@[TGHeading(@"2. Inspect the 54 neurons"),_map,
        Stack(@[_neuronSelector,Text(@"Green +1   Orange −1   Dark 0",11)]),_neuron],YES);
    [middle.widthAnchor constraintEqualToConstant:468].active=YES;

    _prediction=TGHeading(@"Ready",30);
    _scores=[[ScoreChart alloc] initWithFrame:NSZeroRect];
    [_scores.widthAnchor constraintEqualToConstant:228].active=YES; [_scores.heightAnchor constraintEqualToConstant:260].active=YES;
    _scores.accessibilityElement=YES; _scores.accessibilityRole=NSAccessibilityImageRole; _scores.accessibilityLabel=@"Ternary output scores";
    _runStatus=Text(@"",11,YES); [_runStatus.widthAnchor constraintEqualToConstant:228].active=YES;
    NSStackView *right=Stack(@[TGHeading(@"3. Read the prediction"),_prediction,_scores,
        Text(@"Scores are relative, not probabilities.",11),_runStatus],YES);
    [right.widthAnchor constraintEqualToConstant:228].active=YES;
    NSStackView *body=Stack(@[left,middle,right]); body.spacing=24; body.alignment=NSLayoutAttributeTop;
    [body.heightAnchor constraintGreaterThanOrEqualToConstant:510].active=YES;

    _count=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_count addItemsWithTitles:@[@"First 100 held-out samples",@"All 1,797 held-out samples"]];
    _count.accessibilityLabel=@"Benchmark sample count";
    _progress=[[NSProgressIndicator alloc] init]; _progress.indeterminate=NO; _progress.minValue=0; _progress.maxValue=100;
    [_progress.widthAnchor constraintEqualToConstant:160].active=YES;
    _progress.accessibilityLabel=@"Benchmark progress";
    _benchmarkStatus=Text(@"Same input for all three models. Raw accuracy and the rate of uncertain answers are reported separately.",12);
    _comparison=Text([NSString stringWithFormat:@"All 1,797 historical test digits: ternary %.2f%% · float32 %.2f%% · 8-bit weights %.2f%% (raw accuracy).\nWeight payloads: 800 B / 15,984 B / 3,996 B. Biases add 256 B each; 8-bit adds 8 B of scales. Native modes use your Mac's binary CPU.",
        100.0*v::model::ternaryCorrect/v::model::testCount,100.0*v::model::floatCorrect/v::model::testCount,100.0*v::model::int8Correct/v::model::testCount],11);
    NSStackView *benchmarkControls=Stack(@[Text(@"COMPARE",12,YES),_count,Button(@"Benchmark",self,@selector(benchmark:)),_progress]);
    NSTextField *credit=Text(@"UCI Optical Recognition of Handwritten Digits · E. Alpaydin & C. Kaynak · CC BY 4.0 · Full attribution in License and Credits",10);
    credit.textColor=NSColor.secondaryLabelColor;
    [_benchmarkStatus.widthAnchor constraintEqualToConstant:1060].active=YES;
    [_comparison.widthAnchor constraintEqualToConstant:1060].active=YES;
    NSView *inference = TGCard(body);
    NSView *benchmark = TGSection(@"Compare model accuracy", Stack(@[benchmarkControls,_benchmarkStatus,_comparison],YES));
    NSStackView *content=TGStack(@[toolbar,inference,benchmark,credit],YES,20);
    [inference.widthAnchor constraintEqualToAnchor:content.widthAnchor].active=YES;
    [benchmark.widthAnchor constraintEqualToAnchor:content.widthAnchor].active=YES;
    TGInstallPage(window,@"Vision Lab",@"Draw a digit. Follow the neurons. Compare three ways to recognize it.",@"eye",content,1092);
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
    [self cancel:nil]; [_timer invalidate]; _timer=nil; [_debugger close]; [_mistakes close];
}
- (void)error:(const std::exception&)e {
    [self cancel:nil]; _runStatus.stringValue=[NSString stringWithUTF8String:e.what()];
    _prediction.stringValue=@"Error";
}
- (void)invalidateResult {
    _hasResult=NO; _map.result=nullptr; _scores.result=nullptr; _scores.needsDisplay=YES;
    _scores.accessibilityValue=@"No inference result for this input";
    _prediction.stringValue=@"Ready"; _baselineLabel.stringValue=@"Float32 and 8-bit weights run natively for comparison.";
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
- (v::Pixels)preparedPixels {
    return _custom?[_canvas drawing:_normalize.state==NSControlStateValueOn].pixels:[_canvas pixels];
}
- (void)updatePreview {
    _preview.pixels=[self preparedPixels];_preview.needsDisplay=YES;
    _preview.accessibilityValue=_custom&&_normalize.state==NSControlStateValueOn?@"Centered and resized drawing":_custom?@"Original drawing pixels":@"Original sample pixels";
}
- (void)normalizeChanged:(id)sender { [self cancel:nil];_session->cancel();[self invalidateResult];[self refresh]; }
- (void)modeChanged:(id)sender { [self cancel:nil];_session->cancel();[self invalidateResult];[self refresh]; }
- (void)showMistakes:(id)sender {
    if(!_mistakes) {
        _mistakes=[[MistakeBrowser alloc] initWithModel:&_model samples:&_samples];
        __weak VisionLab *weak=self;
        _mistakes.openSample=^(int i){[weak loadSample:i];[weak showWindow:nil];[weak run:nil];};
    }
    [_mistakes showWindow:sender];[_mistakes.window makeKeyAndOrderFront:sender];
}
- (void)selectNeuronIndex:(int)i { _map.selected=i; [_neuronSelector selectItemAtIndex:i]; [self refreshNeuron]; }
- (void)selectNeuron:(id)sender { [self selectNeuronIndex:int(_neuronSelector.indexOfSelectedItem)]; }
- (void)refreshNeuron {
    int row=_map.selected,sum=v::model::bias1[row],adds=0,subs=0;
    auto pixels=_session->active()||_hasResult ? _runPixels : [self preparedPixels];
    for(int i=0;i<64;++i) {
        int w=_model.weights()[row*64+i]; sum+=w*pixels[i]; adds+=w>0; subs+=w<0;
    }
    int reference=std::clamp(std::max(0,sum)/8,0,81);
    NSString *guest=_hasResult ? [NSString stringWithFormat:@"%d",_lastResult.hidden[row]] : _session->active() && _session->progress()>row ?
        [NSString stringWithFormat:@"%d",_session->runtime().cpu().memref(v::hiddenAddress+row).to_int()] : @"pending";
    _neuron.stringValue=[NSString stringWithFormat:@"Bias %d · %d adds · %d subtracts · %d skips\nReference: clamp(max(0, %d) / 8) = %d · Result: %@\nGuest activation address: %d",v::model::bias1[row],adds,subs,64-adds-subs,sum,reference,guest,v::hiddenAddress+row];
    _map.needsDisplay=YES;
}
- (void)startPaused:(BOOL)paused {
    _rawPixels=[_canvas pixels];_runNormalized=_custom&&_normalize.state==NSControlStateValueOn;
    if(_custom) {
        auto drawing=[_canvas drawing:_normalize.state==NSControlStateValueOn];
        if(drawing.quality!=v::InputQuality::Ready) {
            _session->cancel();_pendingNative=NO;
            [self invalidateResult];
            _prediction.stringValue=drawing.quality==v::InputQuality::Empty?@"Draw a digit":@"Try again";
            _runStatus.stringValue=drawing.quality==v::InputQuality::TooSmall?@"Draw a larger, complete digit.":drawing.quality==v::InputQuality::TooDense?@"Clear the canvas and draw one digit.":@"The canvas is empty. No prediction was made.";
            _baselineLabel.stringValue=@"Waiting for a drawing.";return;
        }
        _runPixels=drawing.pixels;
    } else _runPixels=_rawPixels;
    _native=v::compare(_model,_runPixels);_lastBaseline=_native.floating;_lastFloatMs=_native.floatMs;
    _guestRun=paused||(_benchmark?!_batchNative:_execution.indexOfSelectedItem==0);
    if(_guestRun) {_session->start(_runPixels,paused);_pendingNative=NO;}
    else {_session->cancel();_pendingNative=YES;}
    _manualDebug=paused;_hasResult=NO;_map.result=nullptr;_nativePaused=NO;
    _scores.result=nullptr;_scores.needsDisplay=YES;_scores.accessibilityValue=@"Inference has not finished";
    _prediction.stringValue=paused?@"Paused":@"Running…";
    _baselineLabel.stringValue=[NSString stringWithFormat:@"Float32: %d · 8-bit weights: %d\nSame input; independent predictions.",_lastBaseline.prediction(),_native.quantized.prediction()];
    [_debugger imageDidChange];[self refresh];
}
- (void)run:(id)sender {
    [self cancel:nil];
    try { [self startPaused:NO]; } catch(const std::exception& e) { [self error:e]; }
}
- (void)pause:(id)sender {
    if(_pendingNative) _nativePaused=!_nativePaused;
    else if(_session->active()) _session->runtime().setRunning(!_session->runtime().running());
    [self refresh];
}
- (void)cancel:(id)sender {
    if(_benchmark) _benchmarkStatus.stringValue=[NSString stringWithFormat:@"Cancelled after %d / %d samples. Partial results can be exported.",_batchDone,_batchTotal];
    _benchmark=NO;
    if(_pendingNative){_pendingNative=NO;_nativePaused=NO;_prediction.stringValue=@"Cancelled";_runStatus.stringValue=@"Run cancelled. Start a new inference to continue.";}
    if(_session && _session->active()) {
        _session->cancel(); _prediction.stringValue=@"Cancelled";
        _runStatus.stringValue=@"Run cancelled. Start a new inference to continue.";
    }
    [self refresh];
}
- (void)showDebugger:(id)sender { [self debug:sender]; }
- (void)debug:(id)sender {
    if(_benchmark) [self cancel:nil];
    try {
        if(!_session->active()) [self startPaused:YES];
        else _session->runtime().setRunning(false);
        if(!_session->active())return;
        _manualDebug=YES; _session->markDebugging();
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
    _ternaryCorrect=0; _floatCorrect=0; _int8Correct=0; _parityCount=0; _nativeParityCount=0; _answered=0; _answeredCorrect=0; _confusion={};
    _batchGuestMs=0; _batchFloatMs=0; _batchTernaryMs=0; _batchInt8Ms=0; _batchCycles=0; _records=[NSMutableArray array];
    _hasReport=YES; _batchStarted=NSDate.timeIntervalSinceReferenceDate;
    _progress.maxValue=_batchTotal; _progress.doubleValue=0;
    [self loadSample:0]; _benchmark=YES; _batchNative=_execution.indexOfSelectedItem==1;
    try { [self startPaused:NO]; } catch(const std::exception& e) { [self error:e]; }
}
- (void)recordResult {
    int predicted=_lastResult.prediction(),truth=_samples[_index].label;
    ++_batchDone;_ternaryCorrect+=predicted==truth;_floatCorrect+=_lastBaseline.prediction()==truth;_int8Correct+=_native.quantized.prediction()==truth;
    _parityCount+=_guestRun;_nativeParityCount+=!_guestRun;++_confusion[truth][predicted];
    if(!_lastResult.uncertain()){++_answered;_answeredCorrect+=predicted==truth;}
    double guestMs=_guestRun?_session->computeMilliseconds():0;uint64_t cycles=_guestRun?_session->instructions():0;
    _batchGuestMs+=guestMs;_batchFloatMs+=_native.floatMs;_batchTernaryMs+=_native.ternaryMs;_batchInt8Ms+=_native.int8Ms;_batchCycles+=cycles;
    [_records addObject:@{@"sample_index":@(_index),@"label":@(truth),@"ternary_prediction":@(predicted),
        @"float32_prediction":@(_lastBaseline.prediction()),@"int8_prediction":@(_native.quantized.prediction()),
        @"execution":_guestRun?@"guest":@"native",@"guest_instructions":@(cycles),@"guest_active_ms":@(guestMs),
        @"native_ternary_ms":@(_native.ternaryMs),@"float32_native_ms":@(_native.floatMs),@"int8_native_ms":@(_native.int8Ms),
        @"abstained":@(_lastResult.uncertain()),@"margin":@(_lastResult.margin()),@"reference_match":@YES}];
    _progress.doubleValue=_batchDone;
    NSString *selective=_answered?[NSString stringWithFormat:@"%.2f%%",100.0*_answeredCorrect/_answered]:@"n/a";
    _benchmarkStatus.stringValue=[NSString stringWithFormat:@"%@ %d / %d · Raw accuracy: ternary %.2f%% / float32 %.2f%% / 8-bit %.2f%% · Answered %.2f%% (%@ correct)\nTotals: guest %.1f ms · native ternary %.3f ms / float32 %.3f ms / 8-bit %.3f ms · %d verified · elapsed %.1f s",
        _batchDone==_batchTotal?@"Complete":@"Testing",_batchDone,_batchTotal,100.0*_ternaryCorrect/_batchDone,100.0*_floatCorrect/_batchDone,100.0*_int8Correct/_batchDone,
        100.0*_answered/_batchDone,selective,_batchGuestMs,_batchTernaryMs,_batchFloatMs,_batchInt8Ms,_parityCount+_nativeParityCount,NSDate.timeIntervalSinceReferenceDate-_batchStarted];
}
- (void)finishResult {
    _lastResult=_guestRun?_session->result():_native.ternary;
    const auto reference=_model.infer(_runPixels);
    if(_lastResult.scores!=reference.scores||_lastResult.hidden!=reference.hidden) throw std::runtime_error("Inference reference mismatch; result rejected");
    _hasResult=YES;_pendingNative=NO;_map.result=&_lastResult;_scores.result=&_lastResult;_scores.needsDisplay=YES;
    _prediction.stringValue=_lastResult.uncertain()?@"Not sure":[NSString stringWithFormat:@"Digit %d",_lastResult.prediction()];
    NSString *choice=[NSString stringWithFormat:@"Top choices: %d or %d. Score gap %d; uncertainty threshold %d.",_lastResult.prediction(),_lastResult.runnerUp(),_lastResult.margin(),v::model::uncertaintyMargin];
    _scores.accessibilityValue=[NSString stringWithFormat:@"%@ %@",_prediction.stringValue,choice];
    NSString *execution=_guestRun?[NSString stringWithFormat:@"%llu guest instructions · %.2f ms",(unsigned long long)_session->instructions(),_session->computeMilliseconds()]:[NSString stringWithFormat:@"Native ternary: %.3f ms",_native.ternaryMs];
    _runStatus.stringValue=[NSString stringWithFormat:@"%@\n%@\nExact reference match ✓\n%@",choice,_manualDebug?@"Timing omitted after debugging":execution,_guestRun?@"Runs on the ternary CPU":@"Runs directly on your Mac"];
    if(_benchmark) {
        [self recordResult];
        if(_batchDone<_batchTotal) {
            _index=_batchDone;_custom=NO;[_canvas setPixels:_samples[_index].pixels];
            _sampleLabel.stringValue=[NSString stringWithFormat:@"Held-out sample %ld / %lu\nTrue digit: %d",(long)_index+1,(unsigned long)_samples.size(),_samples[_index].label];
            [self startPaused:NO];
        } else _benchmark=NO;
    }
}
- (void)tick:(NSTimer*)timer {
    if(!_session->active()&&!_pendingNative)return;
    if(_pendingNative&&_nativePaused)return;
    try {
        if(_pendingNative) {
            // Amortize UI scheduling without blocking cancellation for a large batch.
            for(int i=0;i<8&&_pendingNative;++i)[self finishResult];
        } else {
            _session->pump(100000,5);
            if(_session->complete())[self finishResult];
        }
        [self refresh];
    } catch(const std::exception& e){[self error:e];}
}
- (void)refresh {
    if(!_session) return;
    _pause.enabled=_session->active()||_pendingNative; _pause.title=(_pendingNative?!_nativePaused:_session->runtime().running())?@"Pause":@"Resume";
    if(_pendingNative) {
        _prediction.stringValue=_nativePaused?@"Paused":@"Running…";
        _runStatus.stringValue=_nativePaused?@"Inference paused. Resume to continue.":@"Evaluating this input on your Mac.";
    }
    _cancel.enabled=_session->active()||_pendingNative||_benchmark; _export.enabled=_hasResult||_hasReport;
    if(_session->active()) {
        _prediction.stringValue=_session->runtime().running()?@"Running…":@"Paused";
        _runStatus.stringValue=[NSString stringWithFormat:@"%d / 64 neurons complete\n%llu guest instructions\n%@",_session->progress(),(unsigned long long)_session->instructions(),
            _session->runtime().stoppedAtBreakpoint()?@"Stopped at breakpoint":@"Inference executes inside Tunguska"];
    }
    [self updatePreview]; [self refreshNeuron]; [_debugger refresh];
}
- (void)exportReport:(id)sender {
    NSMutableDictionary *report=[@{@"format":@"tunguska-vision-report-v2",@"architecture":@[@64,@54,@10],
        @"dataset":@"UCI Optical Recognition of Handwritten Digits",@"dataset_doi":@"10.24432/C50P49",
        @"dataset_license":@"CC-BY-4.0",@"packed_weight_bytes":@800,@"float32_weight_bytes":@15984,@"bias_bytes_each":@256,@"int8_weight_bytes":@3996,@"int8_scale_bytes":@8,
        @"uncertainty_margin":@(v::model::uncertaintyMargin),@"timing_repetitions":@64,
        @"timing_note":@"Guest active compute excludes setup, UI waits and manual steps. All native paths are scalar C++; timings average 64 warmed calls. Int8 uses quantized weights with float hidden activations. Guest code embeds the sparse weight structure, in addition to the 800-byte payload. This is an emulator demonstration, not a hardware efficiency benchmark."} mutableCopy];
    if(_hasResult) {
        NSMutableArray *raw=[NSMutableArray array],*pixels=[NSMutableArray array],*scores=[NSMutableArray array],*hidden=[NSMutableArray array];
        for(int p:_rawPixels) [raw addObject:@(p)]; for(int p:_runPixels) [pixels addObject:@(p)]; for(int s:_lastResult.scores) [scores addObject:@(s)];
        for(int h:_lastResult.hidden) [hidden addObject:@(h)];
        report[@"current_inference"]=@{@"raw_pixels":raw,@"centered_resized":@(_runNormalized),@"pixels":pixels,@"scores":scores,@"hidden":hidden,@"ternary_prediction":@(_lastResult.prediction()),
            @"sample_index":_custom?(id)NSNull.null:@(_index),@"true_label":_custom?(id)NSNull.null:@(_samples[_index].label),
            @"execution":_guestRun?@"guest":@"native",@"abstained":@(_lastResult.uncertain()),@"runner_up":@(_lastResult.runnerUp()),@"margin":@(_lastResult.margin()),@"int8_prediction":@(_native.quantized.prediction()),@"float32_prediction":@(_lastBaseline.prediction()),@"manually_debugged":@(_manualDebug),@"reference_match":@YES};
    }
    if(_hasReport) {
        NSMutableArray *matrix=[NSMutableArray array];
        for(const auto& row:_confusion) { NSMutableArray *values=[NSMutableArray array]; for(int n:row) [values addObject:@(n)]; [matrix addObject:values]; }
        report[@"benchmark"]=@{@"selection":@"First N records in official held-out test file",@"requested":@(_batchTotal),@"completed":@(_batchDone),
            @"ternary_correct":@(_ternaryCorrect),@"float32_correct":@(_floatCorrect),@"guest_reference_matches":@(_parityCount),@"native_reference_matches":@(_nativeParityCount),@"int8_correct":@(_int8Correct),
            @"answered":@(_answered),@"answered_correct":@(_answeredCorrect),@"abstained":@(_batchDone-_answered),@"int8_native_ms":@(_batchInt8Ms),@"ternary_native_ms":@(_batchTernaryMs),
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
