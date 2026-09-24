// SPDX-License-Identifier: GPL-2.0-or-later
#include "explorer.h"
#include <algorithm>
#include <iostream>
#include <random>
#include <stdexcept>
namespace e=tunguska::explorer;
void require(bool value,const char* message){if(!value)throw std::runtime_error(message);}
template<class F> void rejects(F f){bool rejected=false;try{f();}catch(const std::exception&){rejected=true;}require(rejected,"Invalid operation was accepted");}
int main(int argc,char** argv) {
    try {
        require(argc>=2,"Usage: explorer-tests IMAGE [--quick]");bool quick=argc>2;
        e::Session guest(argv[1]);uint64_t total=0;int plans=0;
        auto finish=[&] {
            for(int i=0;i<110&&guest.active();++i)guest.pump(100000,0);
            require(guest.complete(),"Guest did not complete");total+=guest.runtime().cycles();++plans;
        };
        auto check=[&](const e::Input& input) {
            auto expected=e::reference(input);guest.start(input);finish();
            require(expected==guest.result(),"Guest/reference mismatch");
            int previous=input.position;
            for(int cell:expected.route) {
                require(cell>=0&&cell<e::cells&&input.known[cell]==1,"Route used unknown/blocked/out-of-range cell");
                require(std::abs(cell%15-previous%15)+std::abs(cell/15-previous/15)==1,"Route teleported");previous=cell;
            }
            if(!expected.route.empty())require(previous==expected.target,"Route does not end at target");
            return expected;
        };
        e::Input input;input.known.fill(1);input.position=input.home=16;input.goal=208;input.energy=999;
        auto open=check(input);require(open.reason==e::Reason::Goal&&open.route.size()==24,"Open-grid shortest path incorrect");
        input.known.fill(0);input.known[16]=1;
        require(check(input).action==e::Action::Scan,"Unknown neighbors should require a scan");
        input.known.fill(-1);input.known[16]=1;
        require(check(input).reason==e::Reason::NoRoute,"Enclosed robot should stop");
        input.known.fill(1);input.energy=0;require(check(input).reason==e::Reason::Battery,"Empty battery should stop");
        input.position=input.goal;require(check(input).reason==e::Reason::Arrived,"Arrival must win over battery stop");
        input.position=17;input.energy=7;require(check(input).reason==e::Reason::Return,"Low battery must return");
        input.position=16;require(check(input).reason==e::Reason::Goal,"Return threshold boundary incorrect");
        input.energy=6;require(check(input).reason==e::Reason::Docked,"Low battery at base must dock");
        input.energy=999;input.returning=true;input.position=18;require(check(input).reason==e::Reason::Return,"Return mode must remain sticky");
        input.known.fill(-1);input.known[input.position]=input.known[input.home]=1;
        require(check(input).reason==e::Reason::NoReturn,"Lost return route should stop");
        input.returning=false;input.known.fill(1);input.position=16;
        // Invalid input must not replace the preceding accepted result.
        auto before=guest.result();auto invalid=input;invalid.known[1]=2;rejects([&]{guest.start(invalid);});
        require(guest.complete()&&guest.result()==before,"Invalid input replaced an accepted plan");
        invalid=input;invalid.position=-1;rejects([&]{e::reference(invalid);});
        invalid=input;invalid.energy=1000;rejects([&]{e::reference(invalid);});
        invalid=input;invalid.policy=e::Policy(2);rejects([&]{e::reference(invalid);});
        guest.start(input,true);guest.pump();require(guest.runtime().cycles()==0,"Paused guest ran");
        guest.runtime().step();guest.pump();require(guest.runtime().cycles()==1,"Step did not execute one instruction");
        guest.runtime().toggleBreakpoint(1);guest.runtime().setRunning(true);guest.pump();
        require(guest.runtime().stoppedAtBreakpoint()==1,"Guest breakpoint missed");
        guest.runtime().setRunning(true);finish();
        guest.start(input);guest.pump(1000,0);guest.cancel();auto cycles=guest.runtime().cycles();guest.pump();
        require(!guest.active()&&!guest.complete()&&guest.runtime().cycles()==cycles,"Cancel did not stop execution");
        guest.start(input);guest.runtime().cpu().memref(EXP_GOAL)=16;rejects(finish);
        require(!guest.complete(),"Corrupted decision was accepted");
        guest.start(input);auto& cpu=guest.runtime().cpu();cpu.memref(0)=machine::qop(machine::ABS,machine::JMP);cpu.memref(1)=0;cpu.memref(2)=0;
        rejects(finish);require(!guest.active(),"Infinite guest not stopped");
        guest.start(input,true);guest.runtime().cpu().memref(EXP_STATUS)=2;guest.runtime().cpu().memref(EXP_LENGTH)=225;
        rejects([&]{guest.pump();});require(!guest.complete(),"Oversized guest route accepted");
        std::mt19937 rng(730);
        for(int run=0;run<(quick?12:100);++run) {
            input.known.fill(0);for(auto& cell:input.known)cell=int(rng()%3)-1;
            input.position=rng()%225;input.home=rng()%225;input.goal=rng()%225;
            input.known[input.position]=input.known[input.home]=1;
            input.energy=rng()%1000;input.policy=e::Policy(run%2);input.returning=run%7==0;
            check(input);
        }
        // Full closed-loop missions, independent of any privileged world data in the guest.
        for(int preset=0;preset<3;++preset)for(int mode=0;mode<4;++mode) {
            e::Simulation simulation;e::Options options;options.capacity=mode==0?360:999;options.intermittent=(mode&2)!=0;options.policy=e::Policy(mode&1);
            simulation.reset(e::scenario(preset,729),options);
            require(simulation.knownCount()==1,"Initial map leaked the world");
            while(!simulation.finished()&&simulation.scans()<1000) {
                auto observation=simulation.prepare();auto decision=e::reference(observation);
                if(!quick&&(preset<2||simulation.scans()<5))decision=check(observation);
                simulation.apply(decision);
                require(simulation.world().ground[simulation.position()]==1,"Robot entered a wall");
                require(simulation.energy()>=0,"Battery became negative");
            }
            require(simulation.finished()&&simulation.position()==simulation.world().goal,"High-battery mission did not reach its goal");
            require(simulation.moves()>0&&simulation.knownCount()>1,"Mission did not explore");
            std::cout<<"PASS mission "<<preset<<" mode "<<mode<<": "<<simulation.moves()<<" moves, "<<simulation.scans()<<" scans\n";
        }
        e::Simulation low;e::Options lowOptions;lowOptions.capacity=36;low.reset(e::scenario(0),lowOptions);
        while(!low.finished()&&low.scans()<100) {auto observation=low.prepare();low.apply(check(observation));}
        require(low.finished()&&low.position()==low.world().home&&low.energy()>0,"Low battery failed to return safely");
        // A wall appears on previously clear ground just as that sensor drops out.
        // The brain may select its stale clear cell, but the simulator must prevent collision.
        e::Simulation changing;e::Options missing;missing.intermittent=true;
        changing.reset(e::scenario(0,729),missing);
        for(int i=0;i<3&&changing.moves()==0;++i){auto firstObservation=changing.prepare();changing.apply(check(firstObservation));}
        require(changing.position()==17&&changing.known()[18]==1,"Stale-reading fixture setup failed");
        changing.editWall(18);auto staleObservation=changing.prepare();
        require(staleObservation.known[18]==1,"Missing sensor reading unexpectedly revealed edited wall");
        auto stalePlan=check(staleObservation);require(stalePlan.route.front()==18,"Stale-reading route fixture changed");
        changing.apply(stalePlan);
        require(changing.position()==17&&changing.known()[18]==-1&&changing.history().back().blocked,"Physical obstacle guard failed");
        auto revised=changing.prepare();changing.apply(check(revised));
        require(changing.position()!=18,"Replan entered known wall");
        e::Simulation isolated;auto sealed=e::scenario(0);
        for(int d=0;d<4;++d)sealed.ground[e::neighbor(sealed.home,d)]=-1;
        isolated.reset(sealed,{});auto sealedInput=isolated.prepare();isolated.apply(check(sealedInput));
        require(isolated.finished()&&isolated.history().back().decision.reason==e::Reason::NoRoute,"Enclosed mission failed to stop");
        e::Simulation depleted;e::Options tiny;tiny.capacity=12;depleted.reset(e::scenario(0),tiny);
        for(int i=0;i<12;++i){depleted.prepare();depleted.cancelPlanning();}
        require(depleted.energy()==0&&depleted.scans()==12,"Cancelled scans did not consume energy");
        auto emptyInput=depleted.prepare();depleted.apply(check(emptyInput));
        require(depleted.finished()&&depleted.scans()==12&&depleted.energy()==0,"Empty battery performed a free scan");
        e::Simulation edited;auto old=edited.known();edited.editWall(32);
        require(edited.known()==old,"Editing the world leaked it to the robot");
        rejects([&]{edited.editWall(edited.position());});
        auto observation=edited.prepare();rejects([&]{edited.editWall(32);});
        auto decision=e::reference(observation),bad=decision;bad.dx=9;
        auto pos=edited.position();rejects([&]{edited.apply(bad);});require(edited.position()==pos,"Invalid decision moved the robot");
        edited.cancelPlanning();edited.editWall(32);rejects([&]{edited.apply(decision);});
        auto world=edited.world();edited.reset(world,{});require(edited.knownCount()==1&&edited.history().empty(),"Restart failed to clear knowledge/history");
        edited.setHome(18);require(edited.position()==18&&edited.world().home==18,"Moving base did not restart");
        edited.setGoal(200);require(edited.world().goal==200&&edited.knownCount()==1,"Moving goal did not restart");
        require(e::scenario(2,729).ground==e::scenario(2,729).ground,"Seeded maze not deterministic");
        require(e::scenario(2,729).ground!=e::scenario(2,730).ground,"Seed did not change maze");
        std::cout<<"PASS Explorer: "<<plans<<" guest/reference plans, "<<total<<" instructions; path safety, unknowns, policies, battery, sensor dropout, editing and debugger controls\n";
    }catch(const std::exception& error){std::cerr<<"FAIL Explorer: "<<error.what()<<'\n';return 1;}
}
