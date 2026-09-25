// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "macos/SearchService.h"
#include <cstdio>
#include <stdexcept>
int main(int argc,char**argv){@autoreleasepool{try{
    if(argc<3){fprintf(stderr,"Usage: search-cli FOLDER QUERY [--meaning] [--benchmark QUERIES.txt] [--keywords-only]\n");return 2;}
    bool meaning=false,semantic=true;NSString *queriesPath=nil;
    for(int i=3;i<argc;++i){std::string arg=argv[i];if(arg=="--meaning")meaning=true;else if(arg=="--keywords-only")semantic=false;else if(arg=="--benchmark"&&i+1<argc)queriesPath=[NSString stringWithUTF8String:argv[++i]];else throw std::invalid_argument("Unknown argument");}
    std::atomic<bool> cancel{false};
    SearchService *service=[SearchService indexFolder:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES] cancel:cancel progress:{} semantic:semantic];
    NSDictionary *result;
    if(queriesPath){NSString *text=[NSString stringWithContentsOfFile:queriesPath encoding:NSUTF8StringEncoding error:nil];if(!text)throw std::runtime_error("Cannot read query file");NSMutableArray *queries=[NSMutableArray array];for(NSString *q in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])if(q.length)[queries addObject:q];result=[service benchmark:queries meaning:meaning rounds:9 cancel:cancel];}
    else result=[service search:[NSString stringWithUTF8String:argv[2]] meaning:meaning reference:NO];
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];if(!data)throw std::runtime_error("Cannot serialize search result");fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);
    fprintf(stderr,"Indexed %lu files / %lu passages in %.1f ms; skipped %lu\n",(unsigned long)service.fileCount,(unsigned long)service.passageCount,service.buildMilliseconds,(unsigned long)service.skippedCount);return 0;
}catch(const std::exception&e){fprintf(stderr,"Search failed: %s\n",e.what());return 1;}}}
