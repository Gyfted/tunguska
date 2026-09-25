// SPDX-License-Identifier: GPL-2.0-or-later
// Native local search, independent Mac fork addition, 2026-09-25.
#pragma once
#include <array>
#include <atomic>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace tunguska::search {
constexpr size_t dimensions = 512, maxPassages = 100000;
struct Passage { std::string path, title, text; int page = 0; };
struct Hit { uint32_t id; double score; };
struct Packed { std::array<uint64_t,8> positive{}, negative{}; float inverseNorm = 0; };
struct QueryResult { std::vector<Hit> hits; size_t candidates = 0; };
std::vector<std::string> tokens(const std::string& canonical);
Packed pack(const float* vector);
int dot(const Packed& a, const Packed& b);
class Index {
public:
    void add(Passage passage, const std::string& canonical, const std::vector<float>& embedding);
    QueryResult keywords(const std::string& canonical, size_t limit = 20) const;
    QueryResult meaning(const std::vector<float>& query, size_t limit = 20, bool reference = false) const;
    const std::vector<Passage>& passages() const { return passages_; }
    const std::vector<std::string>& canonicalTexts() const { return canonical_; }
    size_t vectorBytes() const { return vectors_.size()*sizeof(float); }
    size_t packedBytes() const { return packed_.size()*sizeof(Packed); }
    size_t semanticCount() const { return vectorIDs_.size(); }
private:
    struct Posting { uint32_t id, count; };
    std::vector<Passage> passages_;
    std::vector<std::string> canonical_;
    std::unordered_map<std::string,std::vector<Posting>> postings_;
    std::vector<uint32_t> lengths_, vectorIDs_;
    uint64_t totalLength_ = 0;
    std::vector<float> vectors_;
    std::vector<Packed> packed_;
};
}
