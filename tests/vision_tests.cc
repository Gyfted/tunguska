// SPDX-License-Identifier: GPL-2.0-or-later
#include "vision.h"
#include "../resources/vision/model.h"
#include <algorithm>
#include <fstream>
#include <iostream>
#include <random>
#include <stdexcept>
#include <cstdio>
#include <unistd.h>

namespace v=tunguska::vision;
void require(bool condition,const char* message) { if(!condition) throw std::runtime_error(message); }
template<class F> void rejects(F action) {
    bool rejected=false;
    try { action(); } catch(const std::exception&) { rejected=true; }
    require(rejected,"Invalid input was accepted");
}
int main(int argc,char**argv) {
    try {
        require(argc>=3,"Usage: vision-tests IMAGE DATASET [--quick]");
        bool quick=argc==4 && std::string(argv[3])=="--quick";
        v::Model model;
        require(model.nonzeroWeights()==2483,"Unexpected weight count");
        auto data=v::loadSamples(argv[2]);
        require(data.size()==1797,"Unexpected held-out sample count");
        v::Pixels invalid{}; invalid[0]=-1;
        rejects([&]{model.infer(invalid);}); rejects([&]{model.baseline(invalid);});
        invalid[0]=17; rejects([&]{model.infer(invalid);});
        v::Result ties; require(ties.prediction()==0,"Ties must prefer lowest index");
        v::Session session(argv[1],model);
        auto finish=[&] {
            for(int i=0;i<110 && session.active();++i) session.pump(100000,0);
            require(session.complete()&&session.matchesReference(),"Guest did not complete with exact parity");
            require(!session.runtime().running(),"Completed guest must be paused");
            require(session.progress()==64,"Incomplete neuron progress");
        };
        session.start(data[0].pixels,true);
        session.pump(); require(session.runtime().cycles()==0,"Paused guest executed");
        session.runtime().step(); session.pump(); require(session.runtime().cycles()==1,"Debugger step count wrong");
        session.runtime().setRunning(true); finish();
        auto previous=session.result();
        rejects([&]{session.start(invalid);});
        require(session.complete()&&session.result().scores==previous.scores,"Invalid input replaced previous result");
        session.start(data[1].pixels); session.pump(1000,0); session.cancel();
        auto cycles=session.runtime().cycles(); session.pump();
        require(!session.active()&&!session.complete()&&session.runtime().cycles()==cycles,"Cancellation did not stop guest");
        session.start(data[0].pixels);
        session.runtime().toggleBreakpoint(0); session.pump();
        require(session.active()&&session.runtime().stoppedAtBreakpoint()==0,"Guest breakpoint missed");
        session.runtime().setRunning(true); finish();
        // A changed guest/model must be detected and never accepted as a prediction.
        session.start(data[0].pixels);
        session.runtime().cpu().memref(v::biasAddress+1) += 8;
        rejects(finish);
        require(!session.complete()&&!session.active(),"Reference mismatch did not invalidate result");
        // A non-terminating guest is bounded even when there is no UI timer.
        session.start(data[0].pixels);
        session.runtime().cpu().memref(0)=machine::qop(machine::ABS,machine::JMP);
        session.runtime().cpu().memref(1)=0; session.runtime().cpu().memref(2)=0;
        rejects(finish);
        require(!session.active()&&!session.complete(),"Instruction limit did not cancel guest");
        // Boundary and seeded out-of-distribution inputs test clipping/signs, not model accuracy.
        std::mt19937 rng(729);
        for(int row=0;row<14;++row) {
            v::Pixels pixels{};
            for(int i=0;i<64;++i) pixels[i]=row==0?0:row==1?16:row==2?(i%2)*16:int(rng()%17);
            session.start(pixels); finish();
        }
        int ternary=0,baseline=0,guest=0;
        double activeMs=0;
        for(size_t i=0;i<data.size();++i) {
            auto reference=model.infer(data[i].pixels);
            ternary+=reference.prediction()==data[i].label;
            baseline+=model.baseline(data[i].pixels).prediction()==data[i].label;
            if(!quick || i<30) {
                session.start(data[i].pixels); finish(); ++guest;
                require(session.result().scores==reference.scores,"Different integer scores");
                activeMs+=session.computeMilliseconds();
            }
        }
        require(ternary==v::model::ternaryCorrect && baseline==v::model::floatCorrect,"Held-out accuracy changed");
        // Dataset loader must fail closed before accepting corrupt records or lengths.
        std::ifstream source(argv[2],std::ios::binary);
        std::string original((std::istreambuf_iterator<char>(source)),{});
        char name[]="/private/tmp/tunguska-vision-tests-XXXXXX";
        int fd=mkstemp(name); require(fd>=0,"Could not create corrupt-input fixture"); close(fd);
        std::string temporary=name;
        auto corrupt=[&](std::string bytes){
            {std::ofstream f(temporary,std::ios::binary);f.write(bytes.data(),bytes.size());}
            rejects([&]{v::loadSamples(temporary);}); std::remove(temporary.c_str());
        };
        corrupt(original.substr(0,12));
        auto bytes=original;bytes[0]='X';corrupt(bytes);
        bytes=original;bytes[8]=0;corrupt(bytes);
        bytes=original;bytes[12]=17;corrupt(bytes);
        bytes=original;bytes[12+64]=10;corrupt(bytes);
        std::cout<<"PASS vision: "<<guest<<" held-out guest parity checks; ternary "<<ternary<<"/1797; float32 "<<baseline<<"/1797; guest active "<<activeMs<<" ms\n";
        std::cout<<"PASS vision boundary/random inputs, pause/step/breakpoint/cancel/restart and malformed dataset checks\n";
    } catch(const std::exception&e) {std::cerr<<"FAIL vision: "<<e.what()<<'\n';return 1;}
}
