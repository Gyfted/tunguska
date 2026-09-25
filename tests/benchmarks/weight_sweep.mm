// SPDX-License-Identifier: GPL-2.0-or-later
// Export the existing native Metal benchmark, including submission/wait latency.
#import <Foundation/Foundation.h>
#include "weight_benchmark.h"
#include <iostream>
using namespace tunguska::weights;
static NSArray* values(const std::vector<double>& input){NSMutableArray *a=[NSMutableArray array];for(double x:input)[a addObject:@(x)];return a;}
int main(int argc,char** argv){@autoreleasepool{try{
    if(argc!=3)throw std::runtime_error("usage: weight-sweep SHADER OUTPUT.json");
    Runner runner(argv[1]);std::atomic<bool> cancel{false};NSMutableArray *runs=[NSMutableArray array];
    for(uint32_t seed:{729,730})for(uint32_t size:{1024,4096,8192,16384}){
        auto result=runner.run({size,size,seed,51},cancel);NSMutableArray *paths=[NSMutableArray array];
        for(const auto& p:result.paths)[paths addObject:@{@"name":@(p.name.c_str()),@"gpu_ms":values(p.gpuMs),@"wall_ms":values(p.wallMs),
            @"gpu_median_ms":@(p.gpu.median),@"gpu_p10_ms":@(p.gpu.p10),@"gpu_p90_ms":@(p.gpu.p90),
            @"wall_median_ms":@(p.wall.median),@"wall_p10_ms":@(p.wall.p10),@"wall_p90_ms":@(p.wall.p90)}];
        [runs addObject:@{@"seed":@(seed),@"rows":@(size),@"columns":@(size),@"rounds":@(result.config.rounds),@"warmups":@(warmupRounds),
            @"device":@(result.device.c_str()),@"os":@(result.os.c_str()),@"shader_sha256":@(result.shaderHash.c_str()),
            @"fp16_weight_bytes":@(result.sizes.halfBytes),@"packed_weight_bytes":@(result.sizes.packedBytes),
            @"combined_working_buffer_bytes":@(result.workingBufferBytes),@"setup_ms":@(result.setupMs),
            @"checked_output_values":@(result.checkedValues),@"max_error":@(result.maxError),@"paths":paths}];
        std::cout<<"PASS seed="<<seed<<" size="<<size<<" fp16_gpu_ms="<<result.paths[0].gpu.median<<" mps_gpu_ms="<<result.paths[2].gpu.median
                 <<" ternary_gpu_ms="<<result.paths[1].gpu.median<<" fp16_wall_ms="<<result.paths[0].wall.median<<" mps_wall_ms="<<result.paths[2].wall.median
                 <<" ternary_wall_ms="<<result.paths[1].wall.median<<" error="<<result.maxError<<std::endl;
    }
    NSError *error=nil;NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"runs":runs} options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    if(!json||![json writeToFile:@(argv[2]) options:NSDataWritingAtomic error:&error])throw std::runtime_error("Could not write benchmark JSON");
}catch(const std::exception& e){std::cerr<<"FAIL: "<<e.what()<<std::endl;return 1;}}}
