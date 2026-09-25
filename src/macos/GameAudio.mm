// SPDX-License-Identifier: GPL-2.0-or-later
// Native output device only: guest code decides which effects occur.
#import "GameAudio.h"
#import <AVFoundation/AVFoundation.h>
#include "game_audio.h"
#include <memory>
#include <cstring>

@implementation GameAudio {
    AVAudioEngine *_engine;
    AVAudioSourceNode *_source;
    std::shared_ptr<tunguska::GameAudioMixer> _mixer;
    BOOL _available;
    id _configurationObserver;
}
- (instancetype)init {
    if((self=[super init])) {
        _mixer=std::make_shared<tunguska::GameAudioMixer>();
        @try {
            _engine=[[AVAudioEngine alloc] init];
            AVAudioFormat *format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:tunguska::GameAudioMixer::sampleRate channels:1];
            // The render block owns the mixer until the audio engine releases it.
            auto mixer=_mixer;
            _source=[[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *silent,const AudioTimeStamp *,AVAudioFrameCount frames,AudioBufferList *buffers) {
                if(buffers->mNumberBuffers!=1 || buffers->mBuffers[0].mNumberChannels!=1 || !buffers->mBuffers[0].mData ||
                   buffers->mBuffers[0].mDataByteSize<size_t(frames)*sizeof(float)) {
                    for(UInt32 i=0;i<buffers->mNumberBuffers;++i)if(buffers->mBuffers[i].mData)
                        memset(buffers->mBuffers[i].mData,0,buffers->mBuffers[i].mDataByteSize);
                    *silent=YES;return noErr;
                }
                *silent=!mixer->render(static_cast<float*>(buffers->mBuffers[0].mData),frames);
                return noErr;
            }];
            [_engine attachNode:_source];
            [_engine connect:_source to:_engine.mainMixerNode format:format];
            _engine.mainMixerNode.outputVolume=.35f;
            [_engine prepare];
            NSError *error=nil;
            _available=[_engine startAndReturnError:&error];
            __weak GameAudio *weakSelf=self;
            _configurationObserver=[NSNotificationCenter.defaultCenter addObserverForName:AVAudioEngineConfigurationChangeNotification
                object:_engine queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) { [weakSelf restartOutput]; }];
        } @catch (NSException *exception) {
            // Missing/denied audio components must not take down guest execution.
            _available=NO;_source=nil;_engine=nil;
        }
    }
    return self;
}
- (BOOL)available { return _available && _engine.isRunning; }
- (void)restartOutput {
    [self silence];
    @try { NSError *error=nil;_available=[_engine startAndReturnError:&error]; }
    @catch (NSException *exception) { _available=NO; }
}
- (uint64_t)renderedFrames { return _mixer->renderedFrames(); }
- (void)playEffects:(uint32_t)effects audible:(BOOL)audible {
    if(!audible || !self.available) {_mixer->silence();return;}
    _mixer->enqueue(effects);
}
- (void)silence { _mixer->silence(); }
- (void)dealloc {
    if(_configurationObserver)[NSNotificationCenter.defaultCenter removeObserver:_configurationObserver];
    [_engine stop];
}
@end
