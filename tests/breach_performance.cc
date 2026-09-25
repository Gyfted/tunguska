// SPDX-License-Identifier: GPL-2.0-or-later
// Compare actual guest frames and state; report CPU work and 60 Hz scheduling cost.
#include "runtime.h"
#include "breach_protocol.h"
#include "display_protocol.h"
#ifndef TUNGUSKA_BASELINE_RUNTIME
#include "game_audio.h"
#endif
#include <algorithm>
#include <chrono>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>
using Clock=std::chrono::steady_clock;
struct Sample { uint64_t instructions; double milliseconds; int ticks; };
struct Bench {
    tunguska::Runtime runtime;
    std::vector<Sample> samples;
    bool legacy;
    bool colorBudget;
    Bench(const char* image,bool old,bool color=false):runtime(image),legacy(old),colorBudget(color){
#ifdef TUNGUSKA_BASELINE_RUNTIME
        legacy=true;
        colorBudget=false;
#endif
        finish(-1);
    }
    int byte(int a){return runtime.cpu().memref(a).to_int();}
    int word(int a){return tryte::word_to_int(runtime.cpu().memref(a),runtime.cpu().memref(a+1));}
    void word(int a,int v){tryte::int_to_word(v,runtime.cpu().memref(a),runtime.cpu().memref(a+1));}
    void finish(int previous) {
        auto begin=Clock::now();auto cycles=runtime.cycles();int ticks=0;
        auto revision=runtime.frame().revision;
        // Same instruction and time caps as each version's UI; omit timer sleeps. Ticks
        // estimate 60 Hz scheduling latency, not measured event-to-photon time.
        while(ticks++<300){
#ifdef TUNGUSKA_BASELINE_RUNTIME
            runtime.run(legacy && byte(BR_STATUS)!=1 ? 18000:100000,7);
#else
            runtime.run(legacy && byte(BR_STATUS)!=1 ? 18000:colorBudget?120000:100000,colorBudget?9:7,!legacy);
            tunguska::drainGameSounds(runtime.cpu());
#endif
            if(runtime.frame().revision!=revision && word(BR_FRAME)!=previous && word(BR_FRAME)>0 && byte(BR_STATUS)!=1){
                samples.push_back({runtime.cycles()-cycles,std::chrono::duration<double,std::milli>(Clock::now()-begin).count(),ticks});return;
            }
        }
        throw std::runtime_error("Frame did not finish");
    }
    void key(char key){int frame=word(BR_FRAME);runtime.key(key);finish(frame);}
    void position(int x,int y,int angle){word(BR_X,x);word(BR_Y,y);word(BR_ANGLE,angle);}
    void report(const char* label){
        std::vector<double> times,ticks,counts;
        for(auto s:samples){times.push_back(s.milliseconds);ticks.push_back(s.ticks*1000.0/60);counts.push_back(s.instructions);}
        auto pct=[](std::vector<double> v,double p){std::sort(v.begin(),v.end());return v[size_t((v.size()-1)*p)];};
        std::cout<<label<<": "<<samples.size()<<" frames; CPU ms p50="<<pct(times,.5)<<" p95="<<pct(times,.95)
            <<"; 60Hz tick estimate ms p50="<<pct(ticks,.5)<<" p95="<<pct(ticks,.95)
            <<"; instructions p50="<<pct(counts,.5)<<" max="<<pct(counts,1)<<'\n';
    }
};
static void compare(Bench& a,Bench& b){
    const bool paletteChange=a.runtime.frame().auxiliary!=b.runtime.frame().auxiliary;
    if(paletteChange) {
        for(int i=0;i<TG_VIDEO_WORDS;++i)if(a.byte(TG_VIDEO_BITMAP+i)!=b.byte(TG_VIDEO_BITMAP+i))
            throw std::runtime_error("Guest geometry mask differs from reference");
    } else if(a.runtime.frame().pixels!=b.runtime.frame().pixels){
        const auto& ap=a.runtime.frame().pixels;const auto& bp=b.runtime.frame().pixels;
        for(size_t i=0;i<ap.size();i+=4)if(ap[i]!=bp[i]){std::cerr<<"Frame "<<a.word(BR_FRAME)<<" pixel "<<(i/4)%324<<","<<(i/4)/324<<" candidate="<<int(ap[i])<<" reference="<<int(bp[i])<<"\n";break;}
        throw std::runtime_error("Framebuffer differs from reference");
    }
    for(int address:{BR_STATUS,BR_HEALTH,BR_AMMO,BR_KILLS,BR_CELLS,BR_MAP_VISIBLE,BR_MESSAGE,BR_FLASH})
        if(a.byte(address)!=b.byte(address))throw std::runtime_error("Game state differs from reference");
    for(int address:{BR_X,BR_Y,BR_ANGLE,BR_TURN})if(a.word(address)!=b.word(address))throw std::runtime_error("Game position/turn differs from reference");
}
int main(int argc,char**argv){try{
    if(argc<2)throw std::runtime_error("usage: breach-performance candidate.ternobj [reference.ternobj [--legacy-schedule]]");
    Bench candidate(argv[1],false,true);
    std::unique_ptr<Bench> reference;if(argc>2)reference=std::make_unique<Bench>(argv[2],argc>3 && std::string(argv[3])=="--legacy-schedule");
    if(reference)compare(candidate,*reference);
    auto key=[&](char c){candidate.key(c);if(reference){reference->key(c);compare(candidate,*reference);}};
    for(char c:std::string("qqq mmmwsade r"))key(c);
    // Every viewing direction from the start, center, distant corridors and exit.
    for(auto p:std::vector<std::pair<int,int>>{{121,121},{364,364},{688,202},{850,607},{445,688}}){
        key('r');candidate.position(p.first,p.second,0);if(reference)reference->position(p.first,p.second,0);
        // Ignore combat here, since repeated angles must remain visible.
        candidate.runtime.cpu().memref(BR_HEALTH)=99;if(reference)reference->runtime.cpu().memref(BR_HEALTH)=99;
        for(int angle=0;angle<36;++angle)key('d');
        key('m');key('m');
    }
    candidate.report("candidate");if(reference){reference->report("reference");std::cout<<"PASS exact "
        <<(candidate.runtime.frame().auxiliary==reference->runtime.frame().auxiliary?"pixels":"guest geometry masks")
        <<" and state for every paired frame\n";}
}catch(const std::exception& e){std::cerr<<"FAIL: "<<e.what()<<'\n';return 1;}}
