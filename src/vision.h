// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "runtime.h"
#include <array>
#include <string>
#include <vector>

namespace tunguska::vision {
constexpr int inputs = 64, neurons = 54, classes = 10;
constexpr int weightCount = inputs * neurons + neurons * classes;
constexpr int statusAddress = 100000, progressAddress = 100001;
constexpr int inputAddress = 100010, hiddenAddress = 100100, scoreAddress = 100200;
constexpr int weightAddress = 110000, biasAddress = 114000;
using Pixels = std::array<int, inputs>;
struct Sample { Pixels pixels; int label; };
struct Result {
    std::array<int, neurons> hidden{};
    std::array<int, classes> scores{};
    int prediction() const;
};
struct Baseline {
    std::array<float, classes> scores{};
    int prediction() const;
};
class Model {
public:
    Model();
    Result infer(const Pixels& pixels) const;
    Baseline baseline(const Pixels& pixels) const;
    const std::array<int8_t, weightCount>& weights() const { return weights_; }
    int nonzeroWeights() const;
private:
    std::array<int8_t, weightCount> weights_{};
};
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
    Runtime& runtime() { return runtime_; }
private:
    const Model& model_;
    std::string image_;
    Runtime runtime_;
    Result reference_{}, result_{};
    bool active_ = false, complete_ = false, matches_ = false;
    double computeMilliseconds_ = 0;
};
}
