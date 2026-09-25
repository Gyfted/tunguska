// SPDX-License-Identifier: GPL-2.0-or-later
#include "search.h"
#include <algorithm>
#include <cmath>
#include <stdexcept>
#ifdef __APPLE__
#include <Accelerate/Accelerate.h>
#endif

namespace tunguska::search {
std::vector<std::string> tokens(const std::string& text) {
    std::vector<std::string> result; std::string word;
    for (unsigned char c : text) {
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c >= 128) {
            if (word.size() < 256) word += char(c);
        } else if (!word.empty()) { result.push_back(std::move(word)); word.clear(); }
    }
    if (!word.empty()) result.push_back(std::move(word));
    return result;
}
static double normSquared(const float* v) {
    double n = 0;
    for (size_t j=0;j<dimensions;++j) {
        if (!std::isfinite(v[j])) throw std::invalid_argument("Non-finite search vector");
        n += double(v[j])*v[j];
    }
    return n;
}
Packed pack(const float* v) {
    const double n=normSquared(v);
    Packed p; if (!n) return p;
    const double threshold = std::sqrt(n/dimensions)*0.5;
    unsigned count=0;
    for (size_t j=0;j<dimensions;++j) {
        if (v[j]>threshold) { p.positive[j/64] |= uint64_t(1)<<(j%64); ++count; }
        else if (v[j]<-threshold) { p.negative[j/64] |= uint64_t(1)<<(j%64); ++count; }
    }
    p.inverseNorm = count ? 1/std::sqrt(float(count)) : 0;
    return p;
}
int dot(const Packed& a,const Packed& b) {
    int result=0;
    for (size_t j=0;j<8;++j)
        result += __builtin_popcountll(a.positive[j]&b.positive[j]) + __builtin_popcountll(a.negative[j]&b.negative[j])
                - __builtin_popcountll(a.positive[j]&b.negative[j]) - __builtin_popcountll(a.negative[j]&b.positive[j]);
    return result;
}
static bool better(const Hit& a,const Hit& b) { return a.score>b.score || (a.score==b.score && a.id<b.id); }
static void top(std::vector<Hit>& hits,size_t limit) {
    limit=std::min(limit,hits.size());
    if (limit<hits.size()) { std::nth_element(hits.begin(),hits.begin()+limit,hits.end(),better); hits.resize(limit); }
    std::sort(hits.begin(),hits.end(),better);
}
void Index::add(Passage p,const std::string& canonical,const std::vector<float>& embedding) {
    if (passages_.size()>=maxPassages || p.text.size()>16384 || p.path.size()>8192 || p.title.size()>8192 || canonical.size()>32768)
        throw std::invalid_argument("Search index size limit reached");
    if (!embedding.empty() && embedding.size()!=dimensions) throw std::invalid_argument("Unexpected embedding dimensions");
    std::vector<float> normalized;
    if (!embedding.empty()) {
        const double n=normSquared(embedding.data());
        if (n>0) { normalized=embedding; for(float& v:normalized) v=float(v/std::sqrt(n)); }
    }
    auto words=tokens(canonical);
    std::unordered_map<std::string,uint32_t> counts;
    for(const auto& word:words) ++counts[word];
    const uint32_t id=uint32_t(passages_.size());
    passages_.push_back(std::move(p)); canonical_.push_back(canonical);
    lengths_.push_back(uint32_t(words.size())); totalLength_+=words.size();
    for(const auto& pair:counts) postings_[pair.first].push_back({id,pair.second});
    if (!normalized.empty()) {
        vectorIDs_.push_back(id); packed_.push_back(pack(normalized.data()));
        vectors_.insert(vectors_.end(),normalized.begin(),normalized.end());
    }
}
QueryResult Index::keywords(const std::string& canonical,size_t limit) const {
    if(canonical.size()>4096 || limit>100) throw std::invalid_argument("Search query is too large");
    auto words=tokens(canonical); if(words.size()>64) throw std::invalid_argument("Use at most 64 query terms");
    std::sort(words.begin(),words.end()); words.erase(std::unique(words.begin(),words.end()),words.end());
    QueryResult result; if(passages_.empty() || !totalLength_)return result;
    std::vector<double> scores(passages_.size(),0);
    std::vector<uint32_t> touched; std::vector<uint8_t> seen(passages_.size(),0);
    const double average=double(totalLength_)/passages_.size();
    for(const auto& word:words) {
        auto it=postings_.find(word); if(it==postings_.end())continue;
        const double idf=std::max(1e-6,std::log((passages_.size()-it->second.size()+0.5)/(it->second.size()+0.5)));
        for(const auto& posting:it->second) {
            const uint32_t id=posting.id;
            if(!seen[id]) { seen[id]=1; touched.push_back(id); }
            scores[id]+=idf*(posting.count*2.2)/(posting.count+1.2*(0.25+0.75*lengths_[id]/average));
        }
    }
    result.candidates=touched.size(); result.hits.reserve(touched.size());
    for(uint32_t id:touched) result.hits.push_back({id,scores[id]});
    top(result.hits,limit); return result;
}
QueryResult Index::meaning(const std::vector<float>& input,size_t limit,bool reference) const {
    if(input.size()!=dimensions || limit>100) throw std::invalid_argument("Invalid semantic query");
    QueryResult result; const double n=normSquared(input.data());if(!n || packed_.empty())return result;
    std::array<float,dimensions> query;
    for(size_t j=0;j<dimensions;++j)query[j]=float(input[j]/std::sqrt(n));
    // Small collections use exhaustive retrieval: approximation has no useful benefit.
    const size_t candidateCount=std::min(packed_.size(),std::max(size_t(512),packed_.size()/10));
    if(reference || candidateCount==packed_.size()) {
        std::vector<float> scores(vectorIDs_.size());
#ifdef __APPLE__
        cblas_sgemv(CblasRowMajor,CblasNoTrans,int(vectorIDs_.size()),int(dimensions),1,vectors_.data(),int(dimensions),query.data(),1,0,scores.data(),1);
#else
        for(size_t i=0;i<vectorIDs_.size();++i)for(size_t j=0;j<dimensions;++j)scores[i]+=vectors_[i*dimensions+j]*query[j];
#endif
        for(size_t i=0;i<vectorIDs_.size();++i)result.hits.push_back({vectorIDs_[i],scores[i]});
        result.candidates=vectorIDs_.size();
    } else {
        const Packed q=pack(query.data());std::vector<Hit> coarse;coarse.reserve(packed_.size());
        for(size_t i=0;i<packed_.size();++i)coarse.push_back({uint32_t(i),dot(q,packed_[i])*q.inverseNorm*packed_[i].inverseNorm});
        top(coarse,candidateCount);result.candidates=coarse.size();
        for(const Hit& h:coarse) {
            float score=0;
#ifdef __APPLE__
            vDSP_dotpr(vectors_.data()+size_t(h.id)*dimensions,1,query.data(),1,&score,dimensions);
#else
            for(size_t j=0;j<dimensions;++j)score+=vectors_[size_t(h.id)*dimensions+j]*query[j];
#endif
            result.hits.push_back({vectorIDs_[h.id],score});
        }
    }
    top(result.hits,limit);return result;
}
}
