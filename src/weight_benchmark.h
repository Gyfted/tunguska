// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac fork addition, 2026-09-25. Original emulator: Viktor Lofgren.
#pragma once
#include <array>
#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace tunguska::weights {
constexpr uint32_t maxDimension=16384;
constexpr int inputCount=3, warmupRounds=9;
struct Config { uint32_t rows=8192, columns=8192, seed=729; int rounds=21; };
struct Layout { uint64_t count, halfBytes, packedBytes, rowBytes, halfRowBytes; };
Layout layout(const Config& config);
uint8_t encode(int value);
int decode(uint8_t code);
uint16_t halfBits(int value);
uint32_t randomStep(uint32_t& state);
int inputValue(uint32_t seed,int pattern,uint32_t column);
struct Statistics { double median=0,p10=0,p90=0; };
Statistics statistics(std::vector<double> values);
struct Samples {
    std::string name;
    std::vector<double> gpuMs,wallMs;
    Statistics gpu,wall;
};
struct Result {
    Config config;Layout sizes{};
    std::string device,os,shaderHash;
    uint64_t workingBufferBytes=0,checkedValues=0;
    double setupMs=0,maxError=0;
    std::array<Samples,3> paths;
};
struct Cancelled : std::runtime_error { Cancelled():std::runtime_error("Benchmark cancelled"){} };
using Progress=std::function<void(const std::string&,double)>;
// Native Metal execution; unrelated to the interpreted ternary CPU.
class Runner {
public:
    explicit Runner(const std::string& shaderPath);
    ~Runner();
    Runner(const Runner&)=delete;
    Runner& operator=(const Runner&)=delete;
    std::string deviceName() const;
    Result run(const Config&,const std::atomic<bool>& cancel,const Progress& progress={});
private:
    struct Impl;std::unique_ptr<Impl> impl_;
};
}
