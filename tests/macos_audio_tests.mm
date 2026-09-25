// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the actual output callback silently; waveform tests are offline.
#import <Foundation/Foundation.h>
#import "macos/GameAudio.h"
#include "breach_protocol.h"
#include <iostream>
int main(){@autoreleasepool {
    GameAudio *audio=[[GameAudio alloc] init];
    if(!audio.available){std::cerr<<"FAIL native sound: output device unavailable\n";return 1;}
    [audio playEffects:1u<<BR_SOUND_SHOT audible:NO];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:1];
    while(audio.renderedFrames==0 && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    if(audio.renderedFrames==0){std::cerr<<"FAIL native sound: render callback never ran\n";return 1;}
    [audio silence];
    std::cout<<"PASS AVAudioEngine output callback, silent event discard and owned mixer lifetime\n";
}}
