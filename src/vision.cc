// SPDX-License-Identifier: GPL-2.0-or-later
#include "vision.h"
#include "../resources/vision/model.h"
#include <algorithm>
#include <chrono>
#include <fstream>
#include <stdexcept>

namespace tunguska::vision {
namespace {
template<class T> int winner(const T& scores) {
    return int(std::max_element(scores.begin(), scores.end()) - scores.begin());
}
void validate(const Pixels& pixels) {
    for (int value : pixels)
        if (value < 0 || value > 16) throw std::invalid_argument("Digit pixels must be between 0 and 16");
}
}
int Result::prediction() const { return winner(scores); }
int Baseline::prediction() const { return winner(scores); }
Model::Model() {
    for (int i = 0; i < weightCount; i += 5) {
        unsigned packed = model::packedWeights[i / 5];
        if (packed >= 243) throw std::runtime_error("Invalid packed ternary model");
        for (int j = 0; j < 5 && i+j < weightCount; ++j) {
            weights_[i+j] = int(packed % 3) - 1;
            packed /= 3;
        }
    }
}
int Model::nonzeroWeights() const {
    return int(std::count_if(weights_.begin(), weights_.end(), [](int w) { return w != 0; }));
}
Result Model::infer(const Pixels& pixels) const {
    validate(pixels);
    Result result;
    for (int row = 0; row < neurons; ++row) {
        int sum = model::bias1[row];
        for (int col = 0; col < inputs; ++col) sum += weights_[row*inputs+col] * pixels[col];
        result.hidden[row] = std::clamp(std::max(0, sum) / 8, 0, 81);
    }
    for (int row = 0; row < classes; ++row) {
        int sum = model::bias2[row];
        for (int col = 0; col < neurons; ++col)
            sum += weights_[inputs*neurons+row*neurons+col] * result.hidden[col];
        result.scores[row] = sum;
    }
    return result;
}
Baseline Model::baseline(const Pixels& pixels) const {
    validate(pixels);
    std::array<float, neurons> hidden{};
    for (int row = 0; row < neurons; ++row) {
        float sum = model::floatBias1[row];
        for (int col = 0; col < inputs; ++col)
            sum += model::floatWeights1[row*inputs+col] * (pixels[col] / 16.0f);
        hidden[row] = std::max(0.0f, sum);
    }
    Baseline result;
    for (int row = 0; row < classes; ++row) {
        float sum = model::floatBias2[row];
        for (int col = 0; col < neurons; ++col)
            sum += model::floatWeights2[row*neurons+col] * hidden[col];
        result.scores[row] = sum;
    }
    return result;
}
std::vector<Sample> loadSamples(const std::string& path) {
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    constexpr int expected = 12 + model::testCount * 65;
    if (!stream || stream.tellg() != expected) throw std::runtime_error("Digit dataset has an invalid size");
    stream.seekg(0);
    std::vector<unsigned char> bytes(expected);
    if (!stream.read(reinterpret_cast<char*>(bytes.data()), bytes.size()))
        throw std::runtime_error("Could not read digit dataset");
    const std::array<unsigned char, 8> magic{'T','V','D','I','G','I','T','1'};
    if (!std::equal(magic.begin(), magic.end(), bytes.begin()) ||
        (uint32_t(bytes[8]) | (uint32_t(bytes[9]) << 8) | (uint32_t(bytes[10]) << 16) |
         (uint32_t(bytes[11]) << 24)) != model::testCount)
        throw std::runtime_error("Digit dataset header is invalid");
    std::vector<Sample> samples;
    samples.reserve(model::testCount);
    for (int row = 0; row < model::testCount; ++row) {
        Sample sample{};
        for (int col = 0; col < inputs; ++col) sample.pixels[col] = bytes[12 + row*65 + col];
        validate(sample.pixels);
        sample.label = bytes[12 + row*65 + 64];
        if (sample.label >= classes) throw std::runtime_error("Digit dataset label is invalid");
        samples.push_back(sample);
    }
    return samples;
}
Session::Session(const std::string& image, const Model& model)
    : model_(model), image_(image), runtime_(image) { runtime_.setRunning(false); }
void Session::start(const Pixels& pixels, bool paused) {
    const auto next = model_.infer(pixels); // Validate before replacing the previous run.
    runtime_.reset(image_);
    runtime_.cpu().P[machine::I] = 1;
    for (int i = 0; i < inputs; ++i) runtime_.cpu().memref(inputAddress+i) = pixels[i];
    for (int i = 0; i < weightCount; ++i) runtime_.cpu().memref(weightAddress+i) = model_.weights()[i];
    for (int i = 0; i < neurons+classes; ++i) {
        int value = i < neurons ? model::bias1[i] : model::bias2[i-neurons];
        tryte::int_to_word(value, runtime_.cpu().memref(biasAddress+2*i), runtime_.cpu().memref(biasAddress+2*i+1));
    }
    reference_ = next; result_ = {}; computeMilliseconds_ = 0;
    active_ = true; complete_ = false; matches_ = false;
    runtime_.setRunning(!paused);
}
int Session::progress() const {
    return std::clamp(runtime_.cpu().memref(progressAddress).to_int(), 0, neurons+classes);
}
void Session::pump(uint64_t instructions, double milliseconds) {
    if (!active_) return;
    if (runtime_.running()) {
        const auto start = std::chrono::steady_clock::now();
        runtime_.run(std::min<uint64_t>(instructions, 100000), milliseconds);
        computeMilliseconds_ += std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now()-start).count();
    }
    if (runtime_.cpu().memref(statusAddress).to_int() == 2) {
        for (int i = 0; i < neurons; ++i) result_.hidden[i] = runtime_.cpu().memref(hiddenAddress+i).to_int();
        for (int i = 0; i < classes; ++i)
            result_.scores[i] = tryte::word_to_int(runtime_.cpu().memref(scoreAddress+2*i), runtime_.cpu().memref(scoreAddress+2*i+1));
        matches_ = result_.hidden == reference_.hidden && result_.scores == reference_.scores;
        active_ = false; complete_ = true; runtime_.setRunning(false);
        if (!matches_) {
            cancel();
            throw std::runtime_error("Guest inference differs from the integer reference; result rejected");
        }
    } else if (runtime_.cycles() >= 10000000) {
        cancel();
        throw std::runtime_error("Guest inference exceeded its instruction limit");
    }
}
void Session::cancel() { runtime_.setRunning(false); active_ = false; complete_ = false; matches_ = false; }
}
