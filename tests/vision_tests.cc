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
#include <limits>

namespace v=tunguska::vision;
void require(bool condition,const char* message) { if(!condition) throw std::runtime_error(message); }
template<class F> void rejects(F action) {
    bool rejected=false;
    try { action(); } catch(const std::exception&) { rejected=true; }
    require(rejected,"Invalid input was accepted");
}
int main(int argc,char**argv) {
    try {
        require(argc>=3,"Usage: vision-tests IMAGE DATASET [--quick] [--reference IMAGE]");
        bool quick=false;std::string referenceImage;
        for(int i=3;i<argc;++i) {if(std::string(argv[i])=="--quick")quick=true;else if(std::string(argv[i])=="--reference"&&i+1<argc)referenceImage=argv[++i];else throw std::runtime_error("Unknown argument");}
        v::Model model;
        require(model.nonzeroWeights()==v::model::nonzeroWeights,"Unexpected weight count");
        auto data=v::loadSamples(argv[2]);
        require(data.size()==1797,"Unexpected held-out sample count");
        v::Pixels invalid{}; invalid[0]=-1;
        rejects([&]{model.infer(invalid);}); rejects([&]{model.baseline(invalid);});
        rejects([&]{model.fast(invalid);}); rejects([&]{model.int8(invalid);});
        rejects([&]{model.sensitivity(invalid);});
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
        session.runtime().cpu().memref(v::biasAddress+2*v::neurons) += 1;
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
            auto fast=model.fast(pixels);
            require(fast.hidden==session.result().hidden&&fast.scores==session.result().scores,"Boundary/random native parity failed");
        }
        v::Ink ink{};
        require(v::prepareDrawing(ink).quality==v::InputQuality::Empty,"Blank input not detected");
        ink.fill(1);require(v::prepareDrawing(ink).quality==v::InputQuality::TooDense,"Solid canvas not detected");
        ink={};ink[16*32+16]=1;require(v::prepareDrawing(ink).quality==v::InputQuality::TooSmall,"Single dot not detected");
        for(float value:{std::numeric_limits<float>::quiet_NaN(),std::numeric_limits<float>::infinity(),-1.0f,1.01f}) {
            ink[0]=value;rejects([&]{v::prepareDrawing(ink);});
        }
        ink={};for(int y=8;y<24;++y)for(int x=6;x<10;++x)ink[y*32+x]=1;
        auto centered=v::prepareDrawing(ink);require(centered.quality==v::InputQuality::Ready&&centered.normalized,"Normalization missing");
        v::Ink translated{};for(int y=11;y<27;++y)for(int x=16;x<20;++x)translated[y*32+x]=1;
        require(v::prepareDrawing(translated).pixels==centered.pixels,"Centering depends on drawing position");
        require(v::prepareDrawing(ink,false).pixels==centered.raw,"Disabled normalization changed pixels");
        // The prepared ink is centered and remains within the model's pixel range.
        double cx=0,total=0;for(int i=0;i<64;++i){total+=centered.pixels[i];cx+=(i%8)*centered.pixels[i];}
        require(total>0&&std::abs(cx/total-3.5)<.1,"Drawing not horizontally centered");
        for(int value:centered.pixels)require(value>=0&&value<=16,"Prepared pixel outside model range");
        ties.scores[3]=v::model::uncertaintyMargin;
        require(!ties.uncertain()&&ties.runnerUp()==0,"Margin boundary or tie ordering wrong");
        ties.scores[3]--;require(ties.uncertain(),"Low margin not marked uncertain");
        auto measured=v::compare(model,data[0].pixels);
        require(measured.repetitions==64&&measured.ternaryMs>=0&&measured.floatMs>=0&&measured.int8Ms>=0,"Invalid native timings");
        auto effects=model.sensitivity(data[0].pixels);
        auto erased=data[0].pixels;erased[20]=0;int predicted=model.fast(data[0].pixels).prediction();
        require(effects[20]==model.fast(data[0].pixels).scores[predicted]-model.fast(erased).scores[predicted],"Sensitivity not computed from erasure");
        session.start(data[0].pixels);finish();session.start(data[1].pixels);
        require(session.reusedMachine(),"Completed machine was unnecessarily reloaded");finish();
        session.markDebugging();session.start(data[0].pixels);require(!session.reusedMachine(),"Debugged machine was reused");finish();
        std::unique_ptr<v::Session> referenceSession;
        if(!referenceImage.empty()) referenceSession=std::make_unique<v::Session>(referenceImage,model);
        int ternary=0,baseline=0,int8=0,guest=0,answered=0,answeredCorrect=0;
        uint64_t optimizedInstructions=0,originalInstructions=0;
        double activeMs=0;
        for(size_t i=0;i<data.size();++i) {
            auto reference=model.infer(data[i].pixels);
            ternary+=reference.prediction()==data[i].label;
            baseline+=model.baseline(data[i].pixels).prediction()==data[i].label;
            int8+=model.int8(data[i].pixels).prediction()==data[i].label;
            auto fast=model.fast(data[i].pixels);
            require(fast.scores==reference.scores&&fast.hidden==reference.hidden,"Fast native kernel differs from independent reference");
            if(!fast.uncertain()){++answered;answeredCorrect+=fast.prediction()==data[i].label;}
            if(referenceSession && i<30) {
                referenceSession->start(data[i].pixels);while(referenceSession->active())referenceSession->pump(100000,0);
                require(referenceSession->matchesReference(),"3CC guest differs from reference");originalInstructions+=referenceSession->instructions();
            }
            if(!quick || i<30) {
                session.start(data[i].pixels); finish(); ++guest;
                require(session.result().scores==reference.scores,"Different integer scores");
                activeMs+=session.computeMilliseconds();
                if(i<30)optimizedInstructions+=session.instructions();
                require(session.instructions()<15000,"Optimized guest instruction budget regressed");
            }
        }
        require(ternary==v::model::ternaryCorrect && baseline==v::model::floatCorrect && int8==v::model::int8Correct,"Held-out accuracy changed");
        if(referenceSession)require(optimizedInstructions*20<originalInstructions,"Guest optimization failed to reduce work");
        const auto errors=v::mistakes(model,data);
        for(const auto& e:errors)require(e.ternary!=e.truth||e.floating!=e.truth||e.quantized!=e.truth,"Correct sample included as a mistake");
        int actualErrors=0;for(const auto& e:errors)actualErrors+=e.ternary!=e.truth;
        require(actualErrors==1797-ternary,"Mistake browser omitted ternary errors");
        std::cout<<"PASS native/guest/3CC parity; int8 "<<int8<<"/1797; answered "<<answered<<"; correct answers "<<answeredCorrect<<"; 30 optimized instructions "<<optimizedInstructions<<" vs 3CC "<<originalInstructions<<"\n";
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
