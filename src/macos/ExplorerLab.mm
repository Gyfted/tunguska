// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native Ternary Explorer, 2026-09-24. Original emulator: Viktor Lofgren.
#import "ExplorerLab.h"
#import "Interface.h"
#import "DebuggerWindow.h"
#import "FileAccess.h"
#include "explorer.h"
#include <algorithm>

namespace ex=tunguska::explorer;
static NSColor *Color(unsigned rgb) {
    return [NSColor colorWithSRGBRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
}
static NSTextField *Text(NSString *s,CGFloat size=12,BOOL mono=NO) { return TGText(s,size,mono); }
static NSString *String(const std::string& s){return [NSString stringWithUTF8String:s.c_str()];}
static NSString *ReasonName(ex::Reason reason) {
    switch(reason) {
        case ex::Reason::Goal:return @"known route to goal";
        case ex::Reason::Frontier:return @"approach unexplored cells";
        case ex::Reason::Return:return @"return to base";
        case ex::Reason::Arrived:return @"goal reached";
        case ex::Reason::Docked:return @"docked at base";
        case ex::Reason::NoRoute:return @"no reachable frontier or goal";
        case ex::Reason::Battery:return @"battery depleted";
        case ex::Reason::Scan:return @"retry missing observation";
        case ex::Reason::NoReturn:return @"return route unavailable";
        case ex::Reason::Limit:return @"turn limit reached";
    }
    return @"unknown";
}
static NSStackView *Stack(NSArray<NSView*> *views,BOOL vertical=NO) { return TGStack(views,vertical,10); }
static NSButton *Button(NSString *title,id target,SEL action){return TGButton(title,nil,target,action);}
static void Draw(NSString *s,NSRect rect,CGFloat size,NSColor *color) {
    NSMutableParagraphStyle *paragraph=[[NSMutableParagraphStyle alloc] init];paragraph.alignment=NSTextAlignmentCenter;
    [s drawInRect:rect withAttributes:@{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:size weight:NSFontWeightSemibold],NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:paragraph}];
}
@interface ExplorerMap : NSView
@property(assign) const ex::Simulation *simulation;
@property(assign) const ex::Decision *decision;
@property BOOL belief;
@property int selected;
@property(copy) void (^edit)(int);
@property(copy) void (^selectionChanged)(int);
@end
@implementation ExplorerMap
- (instancetype)init {
    if((self=[super initWithFrame:NSZeroRect])) {
        _selected=16;self.accessibilityElement=YES;self.accessibilityRole=NSAccessibilityImageRole;
        [self.widthAnchor constraintEqualToConstant:360].active=YES;[self.heightAnchor constraintEqualToConstant:360].active=YES;
    }return self;
}
- (BOOL)isFlipped{return YES;}
- (BOOL)acceptsFirstResponder{return !_belief;}
- (void)drawRect:(NSRect)dirty {
    if(!_simulation)return;
    const auto& sim=*_simulation;const auto& grid=_belief?sim.known():sim.world().ground;
    [Color(0x101918) setFill];NSRectFill(self.bounds);
    for(int cell=0;cell<ex::cells;++cell) {
        NSRect rect=NSMakeRect((cell%15)*24+1,(cell/15)*24+1,22,22);int value=grid[cell];
        [Color(value<0?0x634034:value>0?0x244C40:0x202A2E) setFill];NSRectFill(rect);
        if(value<0)Draw(@"−",NSInsetRect(rect,0,3),13,Color(0xDB9B79));
        if(_belief&&value==0)Draw(@"?",NSInsetRect(rect,0,3),11,Color(0x76838C));
        if(_belief&&std::find(sim.observed().begin(),sim.observed().end(),cell)!=sim.observed().end()) {
            [Color(0x5D987C) setStroke];NSFrameRectWithWidth(NSInsetRect(rect,1,1),1);
        }
    }
    if(_decision&&!_decision->route.empty()) {
        NSBezierPath *path=[NSBezierPath bezierPath];path.lineWidth=2.5;
        [path moveToPoint:NSMakePoint((sim.position()%15)*24+12,(sim.position()/15)*24+12)];
        for(int cell:_decision->route) [path lineToPoint:NSMakePoint((cell%15)*24+12,(cell/15)*24+12)];
        [Color(0xEAC76E) setStroke];[path stroke];
    }
    for(int cell:sim.trail()) {
        [Color(0x579885) setFill];[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect((cell%15)*24+10,(cell/15)*24+10,4,4)] fill];
    }
    int home=sim.world().home,goal=sim.world().goal,robot=sim.position();
    Draw(@"B",NSMakeRect((home%15)*24,(home/15)*24+3,24,22),14,Color(0xA6CFED));
    Draw(@"G",NSMakeRect((goal%15)*24,(goal/15)*24+3,24,22),14,Color(0xF4D681));
    [Color(0x91E4B4) setFill];[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect((robot%15)*24+4,(robot/15)*24+4,16,16)] fill];
    Draw(@"R",NSMakeRect((robot%15)*24,(robot/15)*24+4,24,20),11,Color(0x12352A));
    if(!_belief) {
        [NSColor.whiteColor setStroke];NSFrameRectWithWidth(NSMakeRect((_selected%15)*24+1,(_selected/15)*24+1,22,22),1.5);
    }
}
- (void)mouseDown:(NSEvent*)event {
    if(_belief)return;[self.window makeFirstResponder:self];NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];
    if(p.x<0||p.y<0||p.x>=360||p.y>=360)return;
    _selected=int(p.y/24)*15+int(p.x/24);if(self.selectionChanged)self.selectionChanged(_selected);if(self.edit)self.edit(_selected);self.needsDisplay=YES;
}
- (void)keyDown:(NSEvent*)event {
    int direction=event.keyCode==126?0:event.keyCode==124?1:event.keyCode==125?2:event.keyCode==123?3:-1;
    if(direction>=0){int next=ex::neighbor(_selected,direction);if(next>=0)_selected=next;if(self.selectionChanged)self.selectionChanged(_selected);self.needsDisplay=YES;return;}
    if(event.keyCode==49){if(self.edit)self.edit(_selected);return;}[super keyDown:event];
}
@end

@implementation ExplorerLab {
    ex::Simulation _simulation;
    std::unique_ptr<ex::Session> _session;
    ex::Decision _lastDecision;
    BOOL _hasDecision,_automatic,_debugging;
    uint32_t _seed;
    NSTimeInterval _nextTurn;
    NSTimer *_timer;
    ExplorerMap *_world,*_belief;
    DebuggerWindow *_debugger;
    NSPopUpButton *_preset,*_policy,*_sensors,*_battery,*_brush;
    NSButton *_run,*_step,*_debug,*_export,*_newMaze;
    NSTextField *_headline,*_metrics,*_reason,*_brain,*_history,*_selection;
    NSString *_notice;
}
- (NSPopUpButton*)popup:(NSArray<NSString*>*)titles label:(NSString*)label action:(SEL)action {
    NSPopUpButton *p=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];[p addItemsWithTitles:titles];p.accessibilityLabel=label;p.target=self;p.action=action;return p;
}
- (instancetype)init {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1180,780)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if(!(self=[super initWithWindow:window]))return nil;
    window.title=@"Tunguska — Explorer";window.delegate=self;TGConfigureWindow(window,@"Explorer",NSMakeSize(980,600));_seed=729;
    try{_session=std::make_unique<ex::Session>([[NSBundle.mainBundle pathForResource:@"explorer" ofType:@"ternobj"] fileSystemRepresentation]);}
    catch(const std::exception& error){NSAlert *alert=[[NSAlert alloc] init];alert.messageText=@"Explorer could not load";alert.informativeText=String(error.what());[alert runModal];return nil;}
    _preset=[self popup:@[@"Switchback",@"Open rooms",@"Seeded maze"] label:@"World preset" action:@selector(presetChanged:)];
    _newMaze=Button(@"New maze",self,@selector(newMaze:));
    _run=TGButton(@"Run",@"play.fill",self,@selector(run:));TGPrimary(_run);_step=Button(@"Step turn",self,@selector(stepTurn:));
    _debug=Button(@"Debug brain",self,@selector(debugBrain:));_export=Button(@"Export mission…",self,@selector(exportMission:));
    NSStackView *toolbar=Stack(@[_preset,_newMaze,Button(@"Restart / recharge",self,@selector(restart:)),_run,_step,_debug,_export]);
    _policy=[self popup:@[@"Reach goal",@"Explore first"] label:@"Mission priority" action:@selector(optionsChanged:)];
    _sensors=[self popup:@[@"Reliable scans",@"Intermittent scans"] label:@"Sensor reliability" action:@selector(optionsChanged:)];
    _battery=[self popup:@[@"80 energy",@"360 energy",@"999 energy"] label:@"Battery capacity" action:@selector(optionsChanged:)];[_battery selectItemAtIndex:1];
    _brush=[self popup:@[@"Toggle wall",@"Move base",@"Move goal"] label:@"Map editing tool" action:@selector(brushChanged:)];
    NSStackView *settings=Stack(@[TGHeading(@"Priority",11),_policy,_sensors,_battery,TGHeading(@"Edit map",11),_brush]);
    _world=[[ExplorerMap alloc] init];_belief=[[ExplorerMap alloc] init];_belief.belief=YES;
    _world.simulation=_belief.simulation=&_simulation;
    _world.accessibilityLabel=@"Editable real world";_world.accessibilityHelp=@"Click a cell to use the selected editing tool. Arrow keys select a cell; Space edits it. B is base, G is goal, R is robot.";
    _belief.accessibilityLabel=@"Robot knowledge: blocked minus one, unknown zero, clear plus one";
    _selection=Text(@"",11);[_selection.widthAnchor constraintEqualToConstant:360].active=YES;
    NSStackView *actual=Stack(@[TGHeading(@"The world · editable"),_world,_selection],YES);
    NSTextField *legend=Text(@"−1 blocked    0 unknown    +1 clear\nGold: planned route · Dots: traveled route",11,YES);[legend.widthAnchor constraintEqualToConstant:360].active=YES;
    NSStackView *known=Stack(@[TGHeading(@"What the robot knows"),_belief,legend],YES);
    _headline=TGHeading(@"Ready",24);_metrics=Text(@"",13,YES);_reason=Text(@"",14);_brain=Text(@"",11,YES);
    for(NSTextField *label in @[_headline,_metrics,_reason,_brain])[label.widthAnchor constraintEqualToConstant:300].active=YES;
    NSTextField *rules=Text(@"Each scan costs 1 energy; each move costs 1. Sensors see up to two cells in each direction and stop at walls. Missing readings never become clear cells.",12);[rules.widthAnchor constraintEqualToConstant:300].active=YES;
    NSStackView *dashboard=Stack(@[_headline,_metrics,_reason,_brain,rules],YES);dashboard.spacing=16;
    NSStackView *body=Stack(@[actual,known,dashboard]);body.alignment=NSLayoutAttributeTop;body.spacing=22;
    _history=Text(@"",11,YES);[_history.widthAnchor constraintEqualToConstant:1060].active=YES;[_history.heightAnchor constraintEqualToConstant:115].active=YES;
    NSTextField *help=Text(@"Edit walls while running to trigger a new scan and plan. Moving base/goal or changing options restarts the mission. Restart keeps your edited maze.",11);[help.widthAnchor constraintEqualToConstant:1060].active=YES;
    NSView *mission=TGCard(TGStack(@[settings,body,help],YES,18));
    NSView *history=TGSection(@"Recent decisions",_history);
    NSStackView *content=TGStack(@[toolbar,mission,history,Text(@"Original Tunguska: Viktor Lofgren · Explorer: Vinny Lingham · GPL v2 or later · Offline simulation",10)],YES,20);
    [mission.widthAnchor constraintEqualToAnchor:content.widthAnchor].active=YES;
    [history.widthAnchor constraintEqualToAnchor:content.widthAnchor].active=YES;
    TGInstallPage(window,@"Explorer",@"A robot that treats blocked, unknown and clear as three different states.",@"map",content,1096);
    __weak ExplorerLab *weak=self;_world.edit=^(int cell){[weak edit:cell];};_world.selectionChanged=^(int cell){[weak refreshSelection];};
    [self presetChanged:nil];return self;
}
- (ex::Options)options {
    const int capacities[]={80,360,999};return {ex::Policy(_policy.indexOfSelectedItem),capacities[_battery.indexOfSelectedItem],_sensors.indexOfSelectedItem==1};
}
- (void)showWindow:(id)sender {
    [super showWindow:sender];[self.window makeKeyAndOrderFront:sender];
    if(!_timer){_timer=[NSTimer timerWithTimeInterval:1.0/60 target:self selector:@selector(tick:) userInfo:nil repeats:YES];[NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];}
}
- (void)cancelPlan {
    if(_session)_session->cancel();_simulation.cancelPlanning();_hasDecision=NO;_world.decision=_belief.decision=nullptr;
}
- (void)windowWillClose:(NSNotification*)notification {_automatic=NO;[self cancelPlan];[_timer invalidate];_timer=nil;[_debugger close];}
- (void)resetWorld:(const ex::World&)world {
    _automatic=NO;[self cancelPlan];_simulation.reset(world,[self options]);_notice=nil;_debugging=NO;
    [_debugger close];_world.selected=world.home;[self refresh];
}
- (void)presetChanged:(id)sender {try{[self resetWorld:ex::scenario(int(_preset.indexOfSelectedItem),_seed)];}catch(const std::exception& e){[self error:e];}}
- (void)newMaze:(id)sender {++_seed;[self presetChanged:sender];}
- (void)restart:(id)sender {auto world=_simulation.world();[self resetWorld:world];}
- (void)optionsChanged:(id)sender {[self restart:sender];}
- (void)brushChanged:(id)sender {[self refreshSelection];}
- (void)refreshSelection {
    int cell=_world.selected;
    _selection.stringValue=[NSString stringWithFormat:@"Selected (%d, %d) · %@\nClick a cell, or use arrows then Space. R robot · B base · G goal.",cell%15+1,cell/15+1,_brush.titleOfSelectedItem];
    _world.accessibilityValue=[NSString stringWithFormat:@"Selected column %d row %d, %@. Robot column %d row %d.",cell%15+1,cell/15+1,_simulation.world().ground[cell]<0?@"wall":@"clear",_simulation.position()%15+1,_simulation.position()/15+1];
}
- (void)edit:(int)cell {
    try {
        [self cancelPlan];_notice=nil;
        if(_brush.indexOfSelectedItem==0)_simulation.editWall(cell);
        else { _automatic=NO;if(_brush.indexOfSelectedItem==1)_simulation.setHome(cell);else _simulation.setGoal(cell);[_debugger close]; }
        _nextTurn=0;[self refresh];
    }catch(const std::exception& error){_notice=String(error.what());[self refresh];}
}
- (void)error:(const std::exception&)error {_automatic=NO;[self cancelPlan];_notice=String(error.what());[self refresh];}
- (void)beginTurn:(BOOL)paused {
    _notice=nil;_debugging=paused;
    _session->start(_simulation.prepare(),paused);[_debugger imageDidChange];[self refresh];
}
- (void)run:(id)sender {
    try {
        if(_automatic){_automatic=NO;_session->runtime().setRunning(false);}
        else if(!_simulation.finished()) {
            _automatic=YES;
            if(_session->active())_session->runtime().setRunning(true);else [self beginTurn:NO];
        }
        [self refresh];
    }catch(const std::exception& error){[self error:error];}
}
- (void)stepTurn:(id)sender {
    try{_automatic=NO;if(_session->active())_session->runtime().setRunning(true);else if(!_simulation.finished())[self beginTurn:NO];[self refresh];}
    catch(const std::exception& error){[self error:error];}
}
- (void)showDebugger:(id)sender { [self debugBrain:sender]; }
- (void)debugBrain:(id)sender {
    try {
        _automatic=NO;
        if(!_session->active()) {if(_simulation.finished())return;[self beginTurn:YES];}
        else _session->runtime().setRunning(false);
        _debugging=YES;
        if(!_debugger) {
            _debugger=[[DebuggerWindow alloc] init];_debugger.runtime=&_session->runtime();_debugger.window.title=@"Tunguska — Explorer Guest Debugger";
            __weak ExplorerLab *weak=self;_debugger.didChange=^{[weak refresh];};
        }
        [_debugger imageDidChange];[_debugger showWindow:sender];[self refresh];
    }catch(const std::exception& error){[self error:error];}
}
- (void)tick:(NSTimer*)timer {
    try {
        if(_session->active()) {
            _session->pump();
            if(_session->complete()) {
                _lastDecision=_session->result();_hasDecision=YES;
                _simulation.apply(_lastDecision,_session->runtime().cycles(),_debugging?0:_session->computeMilliseconds());
                _world.decision=_belief.decision=&_lastDecision;_nextTurn=NSDate.timeIntervalSinceReferenceDate+.18;
                if(_simulation.finished())_automatic=NO;
            }
            [self refresh];
        } else if(_automatic&&NSDate.timeIntervalSinceReferenceDate>=_nextTurn) [self beginTurn:NO];
    }catch(const std::exception& error){[self error:error];}
}
- (void)refresh {
    if(!_session)return;
    bool active=_session->active(),paused=active&&!_session->runtime().running();
    _run.title=_automatic?@"Pause":paused?@"Resume":@"Run";_run.enabled=_step.enabled=_debug.enabled=!_simulation.finished();
    _run.image=[NSImage imageWithSystemSymbolName:_automatic?@"pause.fill":@"play.fill" accessibilityDescription:nil];
    _run.accessibilityLabel=_run.title;
    _export.enabled=YES;_newMaze.enabled=_preset.indexOfSelectedItem==2;
    _headline.stringValue=_notice?@"Check this":_simulation.finished()?(_simulation.position()==_simulation.world().goal?@"Goal reached":_simulation.position()==_simulation.world().home?@"At base":@"Mission stopped"):paused?@"Brain paused":active?@"Planning…":_automatic?(_simulation.returning()?@"Returning home":@"Exploring"):@"Ready to step";
    _metrics.stringValue=[NSString stringWithFormat:@"Energy %d / %d\nMap known %d / 225 · %.0f%%\nMoves %d · Scans %d\nRobot (%d, %d) · Seed %u",_simulation.energy(),_simulation.options().capacity,_simulation.knownCount(),100.0*_simulation.knownCount()/225,_simulation.moves(),_simulation.scans(),_simulation.position()%15+1,_simulation.position()/15+1,_simulation.world().seed];
    _reason.stringValue=_notice?:String(_simulation.message());
    if(active)_brain.stringValue=[NSString stringWithFormat:@"GUEST BRAIN\n%llu instructions\n%@",(unsigned long long)_session->runtime().cycles(),paused?@"Step in the debugger or Resume.":@"Searching only observed clear cells."];
    else if(_hasDecision) {
        NSString *action=_lastDecision.action==ex::Action::Move?[NSString stringWithFormat:@"Move (%+d, %+d)",_lastDecision.dx,_lastDecision.dy]:_lastDecision.action==ex::Action::Scan?@"Scan in place":@"Stop";
        _brain.stringValue=[NSString stringWithFormat:@"GUEST VERIFIED ✓\n%llu instructions · %@\n%@ · %d reachable cells",(unsigned long long)_session->runtime().cycles(),_debugging?@"debug timing omitted":[NSString stringWithFormat:@"%.1f ms",_session->computeMilliseconds()],action,_lastDecision.expanded];
    }
    else _brain.stringValue=@"GUEST BRAIN\n3CC program → ternary CPU\nEvery plan checked before movement.";
    NSMutableString *history=[NSMutableString string];const auto& events=_simulation.history();size_t first=events.size()>6?events.size()-6:0;
    for(size_t i=first;i<events.size();++i) {
        const auto& event=events[i];NSString *verb=event.blocked?@"BLOCKED":event.decision.action==ex::Action::Move?@"MOVE":event.decision.action==ex::Action::Scan?@"SCAN":@"STOP";
        [history appendFormat:@"%03d  %-7@ (%2d,%2d) → (%2d,%2d)  energy %3d  known %3d  %@\n",event.turn,verb,event.from%15+1,event.from/15+1,event.to%15+1,event.to/15+1,event.energy,event.known,event.blocked?@"changed obstacle; move rejected":ReasonName(event.decision.reason)];
    }
    _history.stringValue=history.length?history:@"No decisions yet. Run explores automatically; Step turn performs one scan and one guest decision.";
    _world.needsDisplay=_belief.needsDisplay=YES;
    _belief.accessibilityValue=[NSString stringWithFormat:@"%d known cells, %d unknown. Robot at column %d row %d. %@",_simulation.knownCount(),225-_simulation.knownCount(),_simulation.position()%15+1,_simulation.position()/15+1,_reason.stringValue];
    [self refreshSelection];[_debugger refresh];
}
- (void)exportMission:(id)sender {
    NSMutableArray *ground=[NSMutableArray array],*known=[NSMutableArray array],*events=[NSMutableArray array];
    for(int v:_simulation.world().ground)[ground addObject:@(v)];for(int v:_simulation.known())[known addObject:@(v)];
    for(const auto& event:_simulation.history()) {
        NSMutableArray *route=[NSMutableArray array];for(int cell:event.decision.route)[route addObject:@(cell)];
        [events addObject:@{@"turn":@(event.turn),@"from":@(event.from),@"to":@(event.to),@"energy":@(event.energy),@"known_count":@(event.known),@"action":@(int(event.decision.action)),@"reason":@(int(event.decision.reason)),@"explanation":String(ex::explain(event.decision)),@"target":@(event.decision.target),@"route":route,@"blocked_by_world":@(event.blocked),@"guest_instructions":@(event.instructions),@"guest_active_ms":@(event.computeMs),@"reference_match":@YES}];
    }
    NSDictionary *report=@{@"format":@"tunguska-explorer-mission-v1",@"app_version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],@"side":@15,@"cell_encoding":@{@"blocked":@(-1),@"unknown":@0,@"clear":@1},@"indexing":@"zero-based row-major; UI coordinates are one-based",@"world_name":String(_simulation.world().name),@"seed":@(_simulation.world().seed),@"world":ground,@"knowledge":known,@"home":@(_simulation.world().home),@"goal":@(_simulation.world().goal),@"position":@(_simulation.position()),@"capacity":@(_simulation.options().capacity),@"energy":@(_simulation.energy()),@"policy":_simulation.options().policy==ex::Policy::Goal?@"reach-goal":@"explore-first",@"intermittent_sensors":@(_simulation.options().intermittent),@"finished":@(_simulation.finished()),@"scans":@(_simulation.scans()),@"moves":@(_simulation.moves()),@"events":events,@"snapshot_note":@"World and knowledge are export-time snapshots; the decision history is not a full replay of world edits or cancelled scans.",@"timing_note":@"Active guest time excludes setup, UI waits and debugger steps; manually debugged decisions use zero. This is an offline simulation, not a physical robot controller."};
    NSError *error=nil;NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    if(!data){_notice=error.localizedDescription;[self refresh];return;}
    NSSavePanel *panel=[NSSavePanel savePanel];panel.nameFieldStringValue=@"tunguska-explorer-mission.json";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if(response!=NSModalResponseOK)return;tunguska::macos::ScopedURL scope(panel.URL);
        NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];__block NSError *writeError=nil;NSError *coordinateError=nil;
        [coordinator coordinateWritingItemAtURL:panel.URL options:NSFileCoordinatorWritingForReplacing error:&coordinateError byAccessor:^(NSURL *url){[data writeToURL:url options:NSDataWritingAtomic error:&writeError];}];
        if(coordinateError||writeError){self->_notice=(coordinateError?:writeError).localizedDescription;[self refresh];}
    }];
}
@end
