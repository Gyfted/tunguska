// SPDX-License-Identifier: GPL-2.0-or-later
// Matched integer DDA workload: actual 3CC guest cast() vs native C++17.
#include "runtime.h"
#include "breach_protocol.h"
#include "breach_ray_protocol.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
namespace assets {
// A guest char is a six-trit signed value, not an eight-bit C++ char.
#define char int16_t
#include "breach_assets.3h"
#undef char
}
using Clock=std::chrono::steady_clock;
using Rays=std::array<int,RAY_COLUMNS*3>;
struct Scene {int x,y,angle;};
static void check(bool ok,const char* why){if(!ok)throw std::runtime_error(why);}
// Independent native translation of the game's integer DDA, with the same
// divisions/truncation, wall map, precomputed rays and 24-cell traversal limit.
__attribute__((noinline)) static void nativeRays(const Scene& scene,Rays& result) {
    for(int col=0;col<RAY_COLUMNS;++col) {
        int rx=assets::rayX[scene.angle*54+col],ry=assets::rayY[scene.angle*54+col];
        int mx=scene.x/81,my=scene.y/81,sx=1,sy=1;
        int dx=20000,dy=20000,tx=20000,ty=20000,ax=rx,ay=ry;
        if(rx<0){sx=-1;ax=-rx;}if(ry<0){sy=-1;ay=-ry;}
        if(rx){dx=6561/ax;tx=(sx>0?(mx+1)*81-scene.x:scene.x-mx*81)*81/ax;}
        if(ry){dy=6561/ay;ty=(sy>0?(my+1)*81-scene.y:scene.y-my*81)*81/ay;}
        int distance=20000,side=0,cell=1;
        for(int i=0;i<24;++i) {
            if(tx<ty){distance=tx;tx+=dx;mx+=sx;side=0;}
            else {distance=ty;ty+=dy;my+=sy;side=1;}
            if(mx<0||my<0||mx>=12||my>=12)break;
            cell=my*12+mx;if(assets::level[cell]==1)break;
        }
        result[col*3]=distance;result[col*3+1]=side;result[col*3+2]=cell;
    }
}
struct Guest {
    tunguska::Runtime runtime;
    explicit Guest(const char* image):runtime(image){finish();}
    void word(int a,int v){tryte::int_to_word(v,runtime.cpu().memref(a),runtime.cpu().memref(a+1));}
    int word(int a){return tryte::word_to_int(runtime.cpu().memref(a),runtime.cpu().memref(a+1));}
    void prepare(const Scene& s){word(BR_X,s.x);word(BR_Y,s.y);word(BR_ANGLE,s.angle);runtime.cpu().memref(RAY_COMMAND)=1;}
    void finish(){
        auto cycles=runtime.cycles();
        while(runtime.cpu().memref(RAY_COMMAND).to_int()!=2 && runtime.cycles()-cycles<1000000)runtime.run(64);
        check(runtime.cpu().memref(RAY_COMMAND).to_int()==2,"Guest ray job exceeded instruction bound");
    }
    Rays output(){Rays r;for(int i=0;i<int(r.size());++i)r[i]=word(RAY_OUTPUT+i*2);return r;}
};
static double ns(Clock::time_point a){return std::chrono::duration<double,std::nano>(Clock::now()-a).count();}
static double percentile(std::vector<double> v,double q){std::sort(v.begin(),v.end());return v[size_t((v.size()-1)*q)];}
static void array(std::ostream& out,const std::vector<double>& v){out<<'[';for(size_t i=0;i<v.size();++i){if(i)out<<',';out<<v[i];}out<<']';}
int main(int argc,char** argv){try {
    check(argc==3||argc==4,"usage: breach-rays IMAGE OUTPUT.json [--check-only]");
    const bool checkOnly=argc==4 && std::string(argv[3])=="--check-only";
    check(argc==3||checkOnly,"Unknown argument");
    Guest guest(argv[1]);
    std::vector<Scene> all,measured;
    std::vector<int> floor;
    for(int cell=0;cell<144;++cell)if(assets::level[cell]!=1)floor.push_back(cell);
    // Every walkable tile at every heading; also displaced positions near edges.
    for(int cell:floor)for(int a=0;a<36;++a)all.push_back({cell%12*81+40,cell/12*81+40,a});
    for(size_t i=0;i<10;++i){int cell=floor[i*(floor.size()-1)/9];for(int a=0;a<36;++a){
        Scene s{cell%12*81+18+int(i%3)*20,cell/12*81+20+int(i%2)*40,a};measured.push_back(s);all.push_back(s);}}
    size_t compared=0;
    for(const auto& s:all){Rays expected;nativeRays(s,expected);guest.prepare(s);guest.finish();
        const auto actual=guest.output();
        if(actual!=expected){for(int i=0;i<int(actual.size());++i)if(actual[i]!=expected[i])
            std::cerr<<"Mismatch scene "<<s.x<<','<<s.y<<','<<s.angle<<" value "<<i<<" guest="<<actual[i]<<" native="<<expected[i]<<'\n';
            throw std::runtime_error("Native/guest ray results differ");}
        compared+=actual.size();
    }
    std::cerr<<"PASS "<<all.size()<<" scenes, "<<compared<<" exact distance/side/cell values\n"<<std::flush;
    if(checkOnly)return 0;
    constexpr int rounds=9,nativeRepeats=128;
    std::vector<double> guestSamples,nativeSamples,instructions,guestRound,nativeRound;
    Rays scratch;
    auto runGuest=[&](bool record){double total=0;
        for(const auto& s:measured){guest.prepare(s);auto cycles=guest.runtime.cycles();auto begin=Clock::now();guest.finish();double time=ns(begin);
            nativeRays(s,scratch);check(guest.output()==scratch,"Timed guest results differ");
            total+=time;if(record){guestSamples.push_back(time);instructions.push_back(double(guest.runtime.cycles()-cycles));}}
        if(record)guestRound.push_back(total/measured.size());
    };
    auto runNative=[&](bool record){auto begin=Clock::now();
        for(int repeat=0;repeat<nativeRepeats;++repeat)for(const auto& s:measured){nativeRays(s,scratch);
            // Force complete output materialization and forbid loop hoisting.
            asm volatile("" : : "r"(scratch.data()) : "memory");}
        double time=ns(begin)/(nativeRepeats*measured.size());
        if(record){nativeRound.push_back(time);nativeSamples.push_back(time);}
    };
    runGuest(false);runNative(false);
    for(int r=0;r<rounds;++r){if(r%2){runNative(true);runGuest(true);}else{runGuest(true);runNative(true);}}
    const double g=percentile(guestRound,.5),n=percentile(nativeRound,.5);
    std::ofstream out(argv[2]);check(bool(out),"Cannot open JSON output");out<<std::setprecision(12);
    out<<"{\n\"workload\":\"54 integer DDA wall rays, excluding rendering and gameplay\",\n"
       <<"\"compiler\":\""<<__clang_version__<<"\",\n\"correctness_scenes\":"<<all.size()<<",\n\"checked_values\":"<<compared
       <<",\n\"scenes_per_round\":"<<measured.size()<<",\n\"rounds\":"<<rounds<<",\n\"native_batch_repeats\":"<<nativeRepeats
       <<",\n\"guest_round_mean_ns\":";array(out,guestRound);out<<",\n\"native_round_mean_ns\":";array(out,nativeRound);
    out<<",\n\"guest_job_ns\":";array(out,guestSamples);out<<",\n\"guest_job_instructions\":";array(out,instructions);
    out<<",\n\"median_guest_round_ns\":"<<g<<",\n\"median_native_round_ns\":"<<n<<",\n\"native_speedup\":"<<g/n<<"\n}\n";
    check(bool(out),"Could not write JSON output");
    std::cout<<std::fixed<<std::setprecision(3)<<"54-ray job, median round mean: ternary guest "<<g/1000<<" us; native binary "<<n/1000
       <<" us; native faster "<<g/n<<"x; guest instructions p50="<<percentile(instructions,.5)<<"\n";
}catch(const std::exception& e){std::cerr<<"FAIL: "<<e.what()<<'\n';return 1;}}
