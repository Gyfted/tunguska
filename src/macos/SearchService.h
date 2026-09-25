// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#include <atomic>
#include <functional>
#include <memory>
@interface SearchService : NSObject
@property(readonly) NSUInteger passageCount;
@property(readonly) NSUInteger fileCount;
@property(readonly) NSUInteger skippedCount;
@property(readonly) NSUInteger semanticCount;
@property(readonly) NSString *rootPath;
@property(readonly) NSString *modelDescription;
@property(readonly) double buildMilliseconds;
@property(readonly) NSArray<NSString *> *warnings;
// All methods on one serial worker. The caller retains the selected URL's scope.
+ (instancetype)indexFolder:(NSURL *)folder cancel:(const std::atomic<bool>&)cancel
                  progress:(const std::function<void(NSString *)>&)progress semantic:(BOOL)semantic;
- (NSDictionary *)search:(NSString *)query meaning:(BOOL)meaning reference:(BOOL)reference;
- (NSDictionary *)benchmark:(NSArray<NSString *> *)queries meaning:(BOOL)meaning
                     rounds:(NSUInteger)rounds cancel:(const std::atomic<bool>&)cancel;
- (BOOL)canReveal:(NSString *)path;
@end
