// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#include <cstdint>
@interface GameAudio : NSObject
@property(nonatomic,readonly) BOOL available;
@property(nonatomic,readonly) uint64_t renderedFrames;
- (void)playEffects:(uint32_t)effects audible:(BOOL)audible;
- (void)silence;
@end
