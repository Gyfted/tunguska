// SPDX-License-Identifier: GPL-2.0-or-later
#include "weight_benchmark.h"
#include <algorithm>
#include <cmath>
namespace tunguska::weights {
Layout layout(const Config& config) {
    if(!config.rows||!config.columns||config.rows>maxDimension||config.columns>maxDimension)
        throw std::invalid_argument("Matrix dimensions must be 1 to 16,384");
    if(config.rounds<3||config.rounds>99)throw std::invalid_argument("Use 3 to 99 timing rounds");
    uint64_t count=uint64_t(config.rows)*config.columns,rowBytes=(uint64_t(config.columns)+3)/4;
    uint64_t halfRowBytes=((uint64_t(config.columns)*2+15)/16)*16;
    return {count,uint64_t(config.rows)*halfRowBytes,uint64_t(config.rows)*rowBytes,rowBytes,halfRowBytes};
}
uint8_t encode(int value) {
    if(value<-1||value>1)throw std::invalid_argument("Weight must be -1, 0 or +1");
    return value==0?0:value>0?1:2;
}
int decode(uint8_t code) {
    if(code>2)throw std::invalid_argument("Reserved ternary code");
    return code==2?-1:int(code);
}
uint16_t halfBits(int value) {
    (void)encode(value);return value<0?0xbc00:value>0?0x3c00:0;
}
uint32_t randomStep(uint32_t& state) {
    state^=state<<13;state^=state>>17;state^=state<<5;return state;
}
int inputValue(uint32_t seed,int pattern,uint32_t column) {
    // Dyadic values become exact FP16/FP32 inputs after division by 8.
    uint32_t v=seed^uint32_t(pattern+1)*0x9e3779b9u^column*0x85ebca6bu;
    v^=v>>16;v*=0x7feb352du;v^=v>>15;
    return int(v%15)-7;
}
Statistics statistics(std::vector<double> values) {
    if(values.empty())throw std::invalid_argument("No timing samples");
    for(double value:values)if(!std::isfinite(value)||value<=0)throw std::invalid_argument("Invalid timing sample");
    std::sort(values.begin(),values.end());
    auto percentile=[&](double p){double index=p*(values.size()-1);size_t lo=size_t(index),hi=std::min(lo+1,values.size()-1);return values[lo]+(values[hi]-values[lo])*(index-lo);};
    return {percentile(.5),percentile(.1),percentile(.9)};
}
}
