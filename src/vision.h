// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "runtime.h"
#include <array>
#include <string>
#include <vector>
#include <utility>

namespace tunguska::vision {
constexpr int inputs = 64, neurons = 54, classes = 10;
constexpr int weightCount = inputs * neurons + neurons * classes;
constexpr int statusAddress = 100000, progressAddress = 100001;
constexpr int inputAddress = 100010, hiddenAddress = 100100, scoreAddress = 100200;
constexpr int weightAddress = 110000, biasAddress = 114000;
using Pixels = std::array<int, inputs>;
using Ink = std::array<float, 32*32>;
enum class InputQuality { Ready, Empty, TooSmall, TooDense };
struct Drawing {
    Pixels raw{}, pixels{};
    InputQuality quality = InputQuality::Empty;
    bool normalized = false;
};
Drawing prepareDrawing(const Ink& ink, bool normalize = true);
struct Sample { Pixels pixels; int label; };
struct Result {
    std::array<int, neurons> hidden{};
    std::array<int, classes> scores{};
    int prediction() const;
    int runnerUp() const;
    int margin() const;
    bool uncertain() const;
};
struct Baseline {
    std::array<float, classes> scores{};
    int prediction() const;
};
class Model {
public:
    Model();
    Result infer(const Pixels& pixels) const;
    Result fast(const Pixels& pixels) const;
    Baseline baseline(const Pixels& pixels) const;
    Baseline int8(const Pixels& pixels) const;
    // Change in the predicted-class score when each cell is erased, not causality.
    std::array<int, inputs> sensitivity(const Pixels& pixels) const;
    const std::array<int8_t, weightCount>& weights() const { return weights_; }
    int nonzeroWeights() const;
private:
    std::array<int8_t, weightCount> weights_{};
    std::array<std::vector<std::pair<int,int>>, neurons+classes> sparse_;
};
struct Comparison {
    Result ternary;
    Baseline floating, quantized;
    double ternaryMs = 0, floatMs = 0, int8Ms = 0;
    int repetitions = 64;
};
Comparison compare(const Model& model, const Pixels& pixels);
struct Mistake { int sample, truth, ternary, floating, quantized, margin; };
std::vector<Mistake> mistakes(const Model& model, const std::vector<Sample>& samples);
std::vector<Sample> loadSamples(const std::string& path);
// No background threads: pump() runs a bounded batch, then gives control to AppKit.
// Host inference is only a reference. The guest computes its own activations/scores.
class Session {
public:
    Session(const std::string& image, const Model& model);
    void start(const Pixels& pixels, bool paused = false);
    void pump(uint64_t instructions = 18000, double milliseconds = 5);
    void cancel();
    bool active() const { return active_; }
    bool complete() const { return complete_; }
    int progress() const;
    const Result& result() const { return result_; }
    double computeMilliseconds() const { return computeMilliseconds_; }
    bool matchesReference() const { return matches_; }
    uint64_t instructions() const { return runtime_.cycles()-startCycles_; }
    bool reusedMachine() const { return reused_; }
    void markDebugging() { reusable_ = false; debugged_ = true; }
    Runtime& runtime() { return runtime_; }
private:
    const Model& model_;
    std::string image_;
    Runtime runtime_;
    Result reference_{}, result_{};
    bool active_ = false, complete_ = false, matches_ = false;
    double computeMilliseconds_ = 0;
    uint64_t startCycles_ = 0;
    bool reusable_ = false, reused_ = false, debugged_ = false;
};
}
