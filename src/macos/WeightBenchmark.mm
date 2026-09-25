// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native Metal benchmark, 2026-09-25.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CommonCrypto/CommonDigest.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#include "weight_benchmark.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>

namespace tunguska::weights {
namespace {
using Clock=std::chrono::steady_clock;
double elapsed(Clock::time_point start){return std::chrono::duration<double,std::milli>(Clock::now()-start).count();}
void checkCancel(const std::atomic<bool>& cancel){if(cancel.load())throw Cancelled();}
std::string message(NSError *error){return error?std::string(error.localizedDescription.UTF8String):"Unknown Metal error";}
struct Shape {uint32_t rows,columns,rowBytes,halfStride,simdWidth;};
}
struct Runner::Impl {
    id<MTLDevice> device;
    id<MTLCommandQueue> queue;
    id<MTLComputePipelineState> half,packed;
    std::string shaderHash;
};
Runner::Runner(const std::string& path):impl_(std::make_unique<Impl>()) {
    auto& p=*impl_;p.device=MTLCreateSystemDefaultDevice();
    if(!p.device)throw std::runtime_error("No Metal GPU is available on this Mac");
    if(!MPSSupportsMTLDevice(p.device))throw std::runtime_error("This GPU does not support the Apple matrix baseline");
    p.queue=[p.device newCommandQueue];if(!p.queue)throw std::runtime_error("Could not create a GPU command queue");
    NSError *error=nil;
    NSString *source=[NSString stringWithContentsOfFile:[NSString stringWithUTF8String:path.c_str()] encoding:NSUTF8StringEncoding error:&error];
    if(!source)throw std::runtime_error("Could not read bundled benchmark shader: "+message(error));
    NSData *sourceData=[source dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(sourceData.bytes,CC_LONG(sourceData.length),digest);
    for(unsigned char byte:digest){const char hex[]="0123456789abcdef";p.shaderHash+=hex[byte>>4];p.shaderHash+=hex[byte&15];}
    MTLCompileOptions *options=[[MTLCompileOptions alloc] init];
    if (@available(macOS 15.0,*)) options.mathMode=MTLMathModeSafe;
    else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        options.fastMathEnabled=NO;
#pragma clang diagnostic pop
    }
    id<MTLLibrary> library=[p.device newLibraryWithSource:source options:options error:&error];
    if(!library)throw std::runtime_error("Could not compile benchmark shader: "+message(error));
    auto pipeline=[&](NSString *name){id<MTLFunction> function=[library newFunctionWithName:name];
        if(!function)throw std::runtime_error("Benchmark shader function is missing");
        id<MTLComputePipelineState> result=[p.device newComputePipelineStateWithFunction:function error:&error];
        if(!result||result.maxTotalThreadsPerThreadgroup<result.threadExecutionWidth*4)throw std::runtime_error("GPU cannot run the benchmark kernel: "+message(error));return result;};
    p.half=pipeline(@"fp16_matvec");p.packed=pipeline(@"packed_matvec");
}
Runner::~Runner()=default;
std::string Runner::deviceName()const{return impl_->device.name.UTF8String;}
Result Runner::run(const Config& config,const std::atomic<bool>& cancel,const Progress& progress) {
    @autoreleasepool {
    Result result;result.config=config;result.sizes=layout(config);result.device=deviceName();
    result.os=NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String;result.shaderHash=impl_->shaderHash;
    result.paths[0].name="FP16 matched Metal";result.paths[1].name="Packed ternary Metal";result.paths[2].name="FP16 Apple MPS";
    auto setup=Clock::now();auto& p=*impl_;const auto sizes=result.sizes;
    checkCancel(cancel);if(progress)progress("Preparing identical weights and three independent reference vectors…",0);
    uint64_t inputBytes=uint64_t(config.columns)*sizeof(uint16_t),outputBytes=uint64_t(config.rows)*sizeof(float);
    result.workingBufferBytes=sizes.halfBytes+sizes.packedBytes+inputBytes*inputCount+outputBytes*3;
    if(sizes.halfBytes>p.device.maxBufferLength||sizes.packedBytes>p.device.maxBufferLength||
       result.workingBufferBytes>p.device.recommendedMaxWorkingSetSize/2)
        throw std::runtime_error("This layer exceeds the benchmark's GPU memory budget; choose a smaller size");
    auto buffer=[&](uint64_t bytes){id<MTLBuffer> b=[p.device newBufferWithLength:NSUInteger(bytes) options:MTLResourceStorageModeShared];
        if(!b)throw std::runtime_error("GPU buffer allocation failed; choose a smaller layer");return b;};
    id<MTLBuffer> half=buffer(sizes.halfBytes),packed=buffer(sizes.packedBytes);
    std::array<id<MTLBuffer>,inputCount> input;
    std::array<id<MTLBuffer>,3> output;
    std::array<std::vector<int32_t>,inputCount> expected;
    std::array<std::vector<int>,inputCount> integers;
    for(int j=0;j<inputCount;++j){input[j]=buffer(inputBytes);integers[j].resize(config.columns);expected[j].resize(config.rows);
        for(uint32_t c=0;c<config.columns;++c){integers[j][c]=inputValue(config.seed,j,c);const uint16_t fraction[]={0,0x3000,0x3400,0x3600,0x3800,0x3900,0x3a00,0x3b00};
            int v=integers[j][c];((uint16_t*)input[j].contents)[c]=fraction[std::abs(v)]|(v<0?0x8000:0);}}
    for(auto& b:output)b=buffer(outputBytes);
    auto *halves=(uint16_t*)half.contents;auto *bytes=(uint8_t*)packed.contents;
    std::memset(bytes,0,size_t(sizes.packedBytes));std::memset(halves,0,size_t(sizes.halfBytes));uint32_t state=config.seed?config.seed:0x6d2b79f5u;
    for(uint32_t r=0;r<config.rows;++r) {
        if(r%64==0){checkCancel(cancel);if(progress)progress("Preparing weights and checking the packing…",.3*double(r)/config.rows);}
        std::array<int32_t,inputCount> sums{};
        for(uint32_t c=0;c<config.columns;++c){int weight=int(randomStep(state)%3)-1;uint8_t code=encode(weight);
            halves[uint64_t(r)*(sizes.halfRowBytes/2)+c]=halfBits(weight);
            bytes[uint64_t(r)*sizes.rowBytes+c/4]|=code<<((c%4)*2);
            for(int j=0;j<inputCount;++j)sums[j]+=weight*integers[j][c];}
        for(int j=0;j<inputCount;++j)expected[j][r]=sums[j];
    }
    // Verify every stored value independently of the packing loop before timing.
    for(uint32_t r=0;r<config.rows;++r){if(r%64==0)checkCancel(cancel);
        for(uint32_t c=0;c<config.columns;++c){int value=decode((bytes[uint64_t(r)*sizes.rowBytes+c/4]>>((c%4)*2))&3);
            if(halves[uint64_t(r)*(sizes.halfRowBytes/2)+c]!=halfBits(value))throw std::runtime_error("Weight packing mismatch");}}
    Shape shape{config.rows,config.columns,uint32_t(sizes.rowBytes),uint32_t(sizes.halfRowBytes/2),0};
    MPSMatrixDescriptor *md=[MPSMatrixDescriptor matrixDescriptorWithRows:config.rows columns:config.columns rowBytes:NSUInteger(sizes.halfRowBytes) dataType:MPSDataTypeFloat16];
    MPSMatrix *matrix=[[MPSMatrix alloc] initWithBuffer:half descriptor:md];
    MPSVectorDescriptor *ivd=[MPSVectorDescriptor vectorDescriptorWithLength:config.columns dataType:MPSDataTypeFloat16];
    MPSVectorDescriptor *ovd=[MPSVectorDescriptor vectorDescriptorWithLength:config.rows dataType:MPSDataTypeFloat32];
    std::array<MPSVector*,inputCount> vectors;for(int j=0;j<inputCount;++j)vectors[j]=[[MPSVector alloc] initWithBuffer:input[j] descriptor:ivd];
    MPSVector *outVector=[[MPSVector alloc] initWithBuffer:output[2] descriptor:ovd];
    MPSMatrixVectorMultiplication *mps=[[MPSMatrixVectorMultiplication alloc] initWithDevice:p.device rows:config.rows columns:config.columns];
    if(!matrix||!outVector||!mps)throw std::runtime_error("Could not initialize the Apple matrix baseline");
    result.setupMs=elapsed(setup);
    auto execute=[&](int path,int pattern,bool record) {
        @autoreleasepool {
        checkCancel(cancel);
        float *out=(float*)output[path].contents;
        std::fill(out,out+config.rows,std::numeric_limits<float>::quiet_NaN());
        auto started=Clock::now();id<MTLCommandBuffer> command=[p.queue commandBuffer];
        if(!command)throw std::runtime_error("Could not allocate a Metal command buffer");
        if(path==2)[mps encodeToCommandBuffer:command inputMatrix:matrix inputVector:vectors[pattern] resultVector:outVector];
        else {
            id<MTLComputeCommandEncoder> encoder=[command computeCommandEncoder];
            if(!encoder)throw std::runtime_error("Could not create a Metal encoder");
            id<MTLComputePipelineState> pipeline=path==0?p.half:p.packed;shape.simdWidth=uint32_t(pipeline.threadExecutionWidth);
            [encoder setComputePipelineState:pipeline];
            [encoder setBuffer:path==0?half:packed offset:0 atIndex:0];[encoder setBuffer:input[pattern] offset:0 atIndex:1];
            [encoder setBuffer:output[path] offset:0 atIndex:2];[encoder setBytes:&shape length:sizeof(shape) atIndex:3];
            [encoder dispatchThreadgroups:MTLSizeMake((config.rows+3)/4,1,1) threadsPerThreadgroup:MTLSizeMake(shape.simdWidth*4,1,1)];[encoder endEncoding];
        }
        [command commit];[command waitUntilCompleted];double wall=elapsed(started);
        checkCancel(cancel);
        if(command.status!=MTLCommandBufferStatusCompleted)throw std::runtime_error("GPU execution failed: "+message(command.error));
        double gpu=(command.GPUEndTime-command.GPUStartTime)*1000;
        if(!std::isfinite(gpu)||gpu<=0)throw std::runtime_error("This GPU did not supply valid execution timestamps");
        for(uint32_t r=0;r<config.rows;++r){double error=std::abs(double(out[r])-expected[pattern][r]/8.0);
            if(!std::isfinite(out[r])||error!=0)throw std::runtime_error(result.paths[path].name+" output differs from the independent integer reference at row "+std::to_string(r)+": got "+std::to_string(out[r])+", expected "+std::to_string(expected[pattern][r]/8.0));
            result.maxError=std::max(result.maxError,error);++result.checkedValues;}
        if(record){result.paths[path].gpuMs.push_back(gpu);result.paths[path].wallMs.push_back(wall);}
        }
    };
    // Each path sees each input three times in warm-up. Setup is never timed.
    if(progress)progress("Warming all three paths…",.3);
    for(int round=0;round<warmupRounds;++round)for(int offset=0;offset<3;++offset)execute((round+offset)%3,round%inputCount,false);
    if(progress)progress("Measuring; GPU unpacking is included…",.45);
    for(int round=0;round<config.rounds;++round){checkCancel(cancel);
        for(int offset=0;offset<3;++offset)execute((round+offset)%3,round%inputCount,true);
    }
    if(progress)progress("Complete; every output matches exactly.",1);
    for(auto& path:result.paths){path.gpu=statistics(path.gpuMs);path.wall=statistics(path.wallMs);}
    return result;
    }
}
}
