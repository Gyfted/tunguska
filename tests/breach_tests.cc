// SPDX-License-Identifier: GPL-2.0-or-later
// Run the compiled game on the real guest CPU; no native simulation substitute.
#include "runtime.h"
#include "breach_protocol.h"
#include "game_input.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iostream>
#include <queue>
#include <set>
#include <stdexcept>

static void require(bool condition,const char* message) {
    if(!condition)throw std::runtime_error(message);
}
struct Game {
    tunguska::Runtime runtime;
    uint64_t maxFrameInstructions=0;
    explicit Game(const char* image):runtime(image){ready(-1);}
    int byte(int address){return runtime.cpu().memref(address).to_int();}
    int word(int address){return tryte::word_to_int(runtime.cpu().memref(address),runtime.cpu().memref(address+1));}
    void byte(int address,int value){runtime.cpu().memref(address)=value;}
    void word(int address,int value){tryte::int_to_word(value,runtime.cpu().memref(address),runtime.cpu().memref(address+1));}
    void ready(int previous) {
        const auto start=runtime.cycles();
        const auto revision=runtime.frame().revision;
        while(runtime.cycles()-start<4000000) {
            runtime.run(256);
            if(runtime.frame().revision!=revision && word(BR_FRAME)!=previous && word(BR_FRAME)>0 && byte(BR_STATUS)!=1) {
                maxFrameInstructions=std::max(maxFrameInstructions,runtime.cycles()-start);return;
            }
        }
        std::cerr<<"PC="<<runtime.programCounter()<<" status="<<byte(BR_STATUS)<<" frame="<<word(BR_FRAME)<<'\n';
        throw std::runtime_error("Guest frame exceeded four million instructions");
    }
    void key(char key){int previous=word(BR_FRAME);runtime.key(key);ready(previous);}
    void restart(){key('r');require(byte(BR_STATUS)==BR_READY,"Restart did not restore ready state");}
    void position(int x,int y,int angle){word(BR_X,x);word(BR_Y,y);word(BR_ANGLE,angle);}
    void dump(const char* file){runtime.capture(true);std::ofstream out(file,std::ios::binary);const auto& p=runtime.frame().pixels;out.write(reinterpret_cast<const char*>(p.data()),p.size());}
    void reach(int target) {
        int start=(word(BR_Y)/81)*12+word(BR_X)/81;
        std::vector<int> previous(144,-1);std::queue<int> queue;queue.push(start);previous[start]=start;
        while(!queue.empty()) {
            int cell=queue.front();queue.pop();
            for(int delta:{-12,1,12,-1}) {
                int next=cell+delta;
                if(next<0||next>=144||std::abs(next%12-cell%12)+std::abs(next/12-cell/12)!=1)continue;
                if(byte(BR_MAP+next)!=1 && previous[next]<0){previous[next]=cell;queue.push(next);}
            }
        }
        require(previous[target]>=0,"Objective is unreachable");
        std::vector<int> path;
        for(int at=target;at!=start;at=previous[at])path.push_back(at);
        std::reverse(path.begin(),path.end());
        for(int cell:path) {
            int dx=cell%12-start%12,dy=cell/12-start/12;
            // Isolate navigation/collectibles from turning, which is checked separately.
            word(BR_ANGLE,dx==1?0:dy==1?9:dx==-1?18:27);
            for(int step=0;step<3;++step)key('W');
            require((word(BR_Y)/81)*12+word(BR_X)/81==cell,"Guest could not traverse the independent BFS route");
            start=cell;
        }
    }
};
int main(int argc,char** argv) {
    try {
        tunguska::GameInput input;
        require(input.press('W',0),"Initial movement must be immediate");
        require(!input.press('w',0.01),"OS repeat duplicated a held key");
        require(input.repeat(0.074).empty() && input.repeat(0.076)=="w","Movement repeat delay/rate wrong");
        require(input.press('d',0.08) && input.repeat(0.16)=="wd","Combined movement/turn failed");
        input.release('W');require(input.repeat(0.24)=="d","Released key continued moving");
        require(input.press('m',0.25) && input.press('r',0.25),"Map/restart initial press failed");
        require(input.repeat(4)=="d" && input.repeat(4).empty(),"Slow frames accumulated repeats or toggled map/restart");
        input.clear();require(input.repeat(5).empty(),"Focus/pause clear left stuck keys");
        require(!input.press('x',5) && !input.press(char(255),5),"Unrecognized key accepted");
        require(input.press(' ',5) && input.repeat(5.17).empty() && input.repeat(5.19)==" ","Fire repeat rate wrong");
        const auto start=std::chrono::steady_clock::now();
        Game g(argc>1?argv[1]:"build/breach.ternobj");
        require(g.byte(BR_STATUS)==BR_READY && g.byte(BR_HEALTH)==9,"Boot state wrong");
        require(g.runtime.frame().mode==-1 && g.runtime.frame().auxiliary==1,"Expected ternary raster display");
        std::set<int> colors;for(size_t i=0;i<g.runtime.frame().pixels.size();i+=4)colors.insert(g.runtime.frame().pixels[i]);
        require(colors==std::set<int>({0,112,224}),"Frame did not use the three ternary pixel colors");
        if(argc>2)g.dump(argv[2]);
        std::cout<<"Boot frame: "<<g.runtime.cycles()<<" guest instructions\n"<<std::flush;
        int y=g.word(BR_Y);g.key('w');require(g.word(BR_Y)==y+27,"Forward movement failed");
        g.key('s');require(g.word(BR_Y)==y,"Backward movement failed");
        g.key('a');require(g.word(BR_ANGLE)==8,"Left turn failed");g.key('d');require(g.word(BR_ANGLE)==9,"Right turn failed");
        g.key('q');require(g.word(BR_X)==148,"Strafe failed");g.key('e');require(g.word(BR_X)==121,"Reverse strafe failed");
        g.key('m');require(g.byte(BR_MAP_VISIBLE)==1,"Map toggle failed");
        g.position(100,121,18);g.key('w');require(g.word(BR_X)==100,"Player entered a wall");
        g.restart();g.position(202,202,9);g.key(' ');
        require(g.byte(BR_ENEMIES)==0 && g.byte(BR_KILLS)==1 && g.byte(BR_AMMO)==15,"Visible sentinel was not hit");
        g.restart();g.position(121,283,0);g.key(' ');
        require(g.byte(BR_ENEMIES+1)==1 && g.byte(BR_KILLS)==0,"Weapon shot through a wall");
        g.byte(BR_AMMO,0);g.position(202,202,9);g.key(' ');
        require(g.byte(BR_AMMO)==0 && g.byte(BR_ENEMIES)==1,"Empty weapon fired");
        g.byte(BR_HEALTH,1);g.word(BR_TURN,3);g.key('a');
        require(g.byte(BR_STATUS)==BR_DEAD,"Sentinel damage/death failed");
        int deadX=g.word(BR_X);g.key('w');require(g.word(BR_X)==deadX,"Dead player moved");
        g.restart();require(g.byte(BR_AMMO)==16 && g.byte(BR_KILLS)==0 && g.byte(BR_CELLS)==0,"Restart did not reset inventory");
        // A burst must preserve the shot behind movement events while a frame draws.
        for(char key:std::string("qqq "))g.runtime.key(key);
        for(int i=0;i<2000 && (g.word(BR_TURN)!=4 || g.byte(BR_STATUS)!=BR_READY);++i)g.runtime.run(1000);
        require(g.word(BR_X)==202 && g.byte(BR_KILLS)==1 && g.byte(BR_AMMO)==15,"Rapid input dropped movement or fire");
        g.restart();
        g.position(850,148,27);g.key('w');require(g.byte(BR_STATUS)==BR_READY && g.byte(BR_MESSAGE)==3,"Exit opened without three cells");
        g.restart();for(int i=0;i<4;++i)g.byte(BR_ENEMIES+i,0);
        g.reach(3*12+4);require(g.byte(BR_CELLS)==1,"First cell was not collected");
        g.reach(7*12+2);require(g.byte(BR_CELLS)==2,"Second cell was not collected");
        g.byte(BR_HEALTH,2);g.byte(BR_AMMO,1);g.reach(10*12+1);
        require(g.byte(BR_HEALTH)==9 && g.byte(BR_AMMO)==13,"Supply cache did not replenish inventory");
        g.reach(10*12+7);require(g.byte(BR_CELLS)==3,"Third cell was not collected");
        g.reach(1*12+10);require(g.byte(BR_STATUS)==BR_WON,"Complete route did not reach victory");
        g.restart();require(g.byte(BR_MAP+3*12+4)==2,"Restart failed to restore pickups");
        require(g.maxFrameInstructions<350000,"Frame exceeds the optimized interactive guest budget");
        std::cout<<"PASS ternary guest: movement, wall collisions, turning, strafe, map, shooting, occlusion, ammo, damage, death, restart, supplies and complete collectible/exit route. Max frame "
                 <<g.maxFrameInstructions<<" instructions; "<<std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count()<<" seconds.\n";
    } catch(const std::exception& e){std::cerr<<"FAIL Breach: "<<e.what()<<'\n';return 1;}
}
