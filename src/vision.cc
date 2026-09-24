// SPDX-License-Identifier: GPL-2.0-or-later
#include "vision.h"
#include "../resources/vision/model.h"
#include <algorithm>
#include <chrono>
#include <fstream>
#include <cmath>
#include <numeric>
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
int Result::runnerUp() const {
    int first=prediction(),second=first==0?1:0;
    for(int i=0;i<classes;++i) if(i!=first && scores[i]>scores[second]) second=i;
    return second;
}
int Result::margin() const { return scores[prediction()]-scores[runnerUp()]; }
bool Result::uncertain() const { return margin()<model::uncertaintyMargin; }
Drawing prepareDrawing(const Ink& ink, bool normalize) {
    Drawing result;
    double mass=0; int left=32,top=32,right=-1,bottom=-1;
    for(int y=0;y<32;++y) for(int x=0;x<32;++x) {
        float value=ink[y*32+x];
        if(!std::isfinite(value)||value<0||value>1) throw std::invalid_argument("Ink values must be finite and between 0 and 1");
        mass+=value;
        if(value>=.05f) {left=std::min(left,x);right=std::max(right,x);top=std::min(top,y);bottom=std::max(bottom,y);}
    }
    auto reduce=[](const Ink& source) {
        Pixels pixels{};
        for(int y=0;y<8;++y) for(int x=0;x<8;++x) {
            double sum=0;
            for(int j=0;j<4;++j) for(int i=0;i<4;++i) sum+=source[(y*4+j)*32+x*4+i];
            pixels[y*8+x]=std::clamp(int(std::floor(sum+.5)),0,16);
        }
        return pixels;
    };
    result.raw=reduce(ink); result.pixels=result.raw;
    if(mass<1 || right<left) return result;
    if(mass<8 || bottom-top+1<8) {result.quality=InputQuality::TooSmall;return result;}
    if(mass>900) {result.quality=InputQuality::TooDense;return result;}
    result.quality=InputQuality::Ready;
    if(!normalize) return result;
    // Fit the ink bounding box in 28x28, preserving aspect ratio and margins.
    double scale=28.0/std::max(right-left+1,bottom-top+1);
    double centerX=(left+right)/2.0,centerY=(top+bottom)/2.0;
    Ink centered{};
    for(int y=0;y<32;++y) for(int x=0;x<32;++x) {
        double sx=(x-15.5)/scale+centerX,sy=(y-15.5)/scale+centerY;
        int ix=int(std::floor(sx)),iy=int(std::floor(sy));
        double fx=sx-ix,fy=sy-iy,value=0;
        for(int j=0;j<2;++j) for(int i=0;i<2;++i) {
            int xx=ix+i,yy=iy+j;
            if(xx>=0&&xx<32&&yy>=0&&yy<32) value+=ink[yy*32+xx]*(i?fx:1-fx)*(j?fy:1-fy);
        }
        centered[y*32+x]=std::clamp(float(value),0.0f,1.0f);
    }
    result.pixels=reduce(centered);result.normalized=true;
    return result;
}
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
    for(int row=0;row<neurons+classes;++row) {
        int size=row<neurons?inputs:neurons;
        int base=row<neurons?row*inputs:neurons*inputs+(row-neurons)*neurons;
        for(int col=0;col<size;++col) if(weights_[base+col]) sparse_[row].emplace_back(col,weights_[base+col]);
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
Result Model::fast(const Pixels& pixels) const {
    validate(pixels);
    Result result;
    for(int row=0;row<neurons;++row) {
        int sum=model::bias1[row];
        for(auto [col,sign]:sparse_[row]) sum+=sign>0?pixels[col]:-pixels[col];
        result.hidden[row]=std::clamp(std::max(0,sum)/8,0,81);
    }
    for(int row=0;row<classes;++row) {
        int sum=model::bias2[row];
        for(auto [col,sign]:sparse_[neurons+row]) sum+=sign>0?result.hidden[col]:-result.hidden[col];
        result.scores[row]=sum;
    }
    return result;
}
Baseline Model::int8(const Pixels& pixels) const {
    validate(pixels);
    std::array<float,neurons> hidden{};
    for(int row=0;row<neurons;++row) {
        int sum=0;
        for(int col=0;col<inputs;++col) sum+=model::int8Weights1[row*inputs+col]*pixels[col];
        hidden[row]=std::max(0.0f,sum*(model::int8Scales[0]/16.0f)+model::floatBias1[row]);
    }
    Baseline result;
    for(int row=0;row<classes;++row) {
        float sum=0;
        for(int col=0;col<neurons;++col) sum+=model::int8Weights2[row*neurons+col]*hidden[col];
        result.scores[row]=sum*model::int8Scales[1]+model::floatBias2[row];
    }
    return result;
}
std::array<int,inputs> Model::sensitivity(const Pixels& pixels) const {
    const auto original=fast(pixels);
    int digit=original.prediction();
    std::array<int,inputs> changes{};
    for(int i=0;i<inputs;++i) {
        auto erased=pixels;erased[i]=0;
        changes[i]=original.scores[digit]-fast(erased).scores[digit];
    }
    return changes;
}
Comparison compare(const Model& model, const Pixels& pixels) {
    Comparison result;
    result.ternary=model.fast(pixels);result.floating=model.baseline(pixels);result.quantized=model.int8(pixels);
    // Warm outputs above; repeated calls amortize the clock cost. Keep results observable.
    volatile double checksum=0;
    auto measure=[&](auto call) {
        const auto start=std::chrono::steady_clock::now();
        for(int i=0;i<result.repetitions;++i) { auto value=call();checksum+=value.scores[i%classes]; }
        return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()/result.repetitions;
    };
    result.ternaryMs=measure([&]{return model.fast(pixels);});
    result.floatMs=measure([&]{return model.baseline(pixels);});
    result.int8Ms=measure([&]{return model.int8(pixels);});
    return result;
}
std::vector<Mistake> mistakes(const Model& model,const std::vector<Sample>& samples) {
    std::vector<Mistake> result;
    for(size_t i=0;i<samples.size();++i) {
        const auto& sample=samples[i];auto ternary=model.fast(sample.pixels);
        int t=ternary.prediction(),f=model.baseline(sample.pixels).prediction(),q=model.int8(sample.pixels).prediction();
        if(t!=sample.label||f!=sample.label||q!=sample.label) result.push_back({int(i),sample.label,t,f,q,ternary.margin()});
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
    reused_=complete_ && reusable_ && !paused && runtime_.breakpoints().empty();
    if(!reused_) runtime_.reset(image_);
    else {runtime_.cpu().PCH=0;runtime_.cpu().PCL=0;runtime_.clearBreakpoints();}
    startCycles_=runtime_.cycles();
    runtime_.cpu().memref(statusAddress)=0;runtime_.cpu().memref(progressAddress)=0;
    for(int i=0;i<neurons;++i) runtime_.cpu().memref(hiddenAddress+i)=0;
    for(int i=0;i<classes*2;++i) runtime_.cpu().memref(scoreAddress+i)=0;
    runtime_.cpu().P[machine::I] = 1;
    for (int i = 0; i < inputs; ++i) runtime_.cpu().memref(inputAddress+i) = pixels[i];
    for (int i = 0; i < weightCount; ++i) runtime_.cpu().memref(weightAddress+i) = model_.weights()[i];
    for (int i = 0; i < neurons+classes; ++i) {
        int value = i < neurons ? model::bias1[i] : model::bias2[i-neurons];
        tryte::int_to_word(value, runtime_.cpu().memref(biasAddress+2*i), runtime_.cpu().memref(biasAddress+2*i+1));
    }
    reference_ = next; result_ = {}; computeMilliseconds_ = 0;
    active_ = true; complete_ = false; matches_ = false; reusable_ = false; debugged_ = paused;
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
        reusable_=!debugged_ && !runtime_.running() && !runtime_.stoppedAtBreakpoint() && runtime_.breakpoints().empty();
        active_ = false; complete_ = true; runtime_.setRunning(false);
        if (!matches_) {
            cancel();
            throw std::runtime_error("Guest inference differs from the integer reference; result rejected");
        }
    } else if (this->instructions() >= 10000000) {
        cancel();
        throw std::runtime_error("Guest inference exceeded its instruction limit");
    }
}
void Session::cancel() { runtime_.setRunning(false); active_ = false; complete_ = false; matches_ = false; reusable_ = false; }
}
