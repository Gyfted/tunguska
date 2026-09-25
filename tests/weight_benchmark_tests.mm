// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#include "weight_benchmark.h"
#include <cassert>
#include <iostream>
#include <fstream>
#include <limits>
using namespace tunguska::weights;
int main(int argc,char** argv){@autoreleasepool{try{
    assert(argc>=2);
    for(int v=-1;v<=1;++v)assert(decode(encode(v))==v);
    bool failed=false;try{decode(3);}catch(const std::invalid_argument&){failed=true;}assert(failed);
    failed=false;try{layout({16385,1,1,3});}catch(const std::invalid_argument&){failed=true;}assert(failed);
    for(const auto& invalid:std::vector<Config>{{0,1,1,3},{1,0,1,3},{1,16385,1,3},{1,1,1,2},{1,1,1,100}}){
        failed=false;try{layout(invalid);}catch(const std::invalid_argument&){failed=true;}assert(failed);
    }
    failed=false;try{encode(2);}catch(const std::invalid_argument&){failed=true;}assert(failed);
    for(const auto& invalid:std::vector<std::vector<double>>{{},{0},{-1},{std::numeric_limits<double>::quiet_NaN()},{std::numeric_limits<double>::infinity()}}){
        failed=false;try{statistics(invalid);}catch(const std::invalid_argument&){failed=true;}assert(failed);
    }
    auto l=layout({8192,8192,729,21});assert(l.halfBytes==134217728&&l.packedBytes==16777216);
    auto s=statistics({4,1,3,2,5});assert(s.median==3&&s.p10>1&&s.p90<5);
    Runner runner(argv[1]);std::atomic<bool> cancel{false};
    std::cout<<"GPU "<<runner.deviceName()<<std::endl;
    for(auto shape:std::vector<std::pair<uint32_t,uint32_t>>{{1,1},{7,13},{35,257},{128,1024}}){
        auto r=runner.run({shape.first,shape.second,729,3},cancel);
        assert(r.maxError==0&&r.checkedValues==uint64_t(shape.first)*3*(warmupRounds+3));
        for(auto& path:r.paths)assert(path.gpuMs.size()==3&&path.gpu.median>0);
        std::cout<<"PASS exact FP16/packed/MPS/reference "<<shape.first<<" x "<<shape.second<<std::endl;
    }
    // Stop midway through preparation, and again after warm-up before timing.
    for(bool late:{false,true}){
        cancel=false;failed=false;
        try{runner.run({128,1024,0,3},cancel,[&](const std::string&,double fraction){if(fraction>=(late?.45:.1))cancel=true;});}
        catch(const Cancelled&){failed=true;}assert(failed);
    }
    // Two mutually agreeing GPU bugs must still fail the independent oracle.
    NSString *source=[NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] encoding:NSUTF8StringEncoding error:nil];
    source=[source stringByReplacingOccurrencesOfString:@"output[row]=total;" withString:@"output[row]=total+1.0f;"];
    NSString *badPath=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".metal"]];
    assert([source writeToFile:badPath atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    cancel=false;failed=false;
    try{Runner wrong(badPath.fileSystemRepresentation);wrong.run({7,13,729,3},cancel);}
    catch(const std::runtime_error& e){failed=std::string(e.what()).find("output differs")!=std::string::npos;}
    [[NSFileManager defaultManager] removeItemAtPath:badPath error:nil];assert(failed);
    cancel=true;failed=false;try{runner.run({},cancel);}catch(const Cancelled&){failed=true;}assert(failed);
    std::cout<<"PASS packing, dimensions, timings, exact GPU outputs, oracle rejection and cancellation"<<std::endl;
    if(argc==3&&std::string(argv[2])=="--measure"){
        cancel=false;
        for(uint32_t size:{1024,4096,8192,16384}){
            auto r=runner.run({size,size,729,51},cancel);
            std::cout<<"MEASURE "<<size<<" fp16_ms="<<r.paths[0].gpu.median<<" mps_ms="<<r.paths[2].gpu.median<<" packed_ms="<<r.paths[1].gpu.median<<" ratio="<<std::min(r.paths[0].gpu.median,r.paths[2].gpu.median)/r.paths[1].gpu.median<<" error="<<r.maxError<<std::endl;
        }
    }
}catch(const std::exception& e){std::cerr<<"FAIL "<<e.what()<<std::endl;return 1;}return 0;}}
