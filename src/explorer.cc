// SPDX-License-Identifier: GPL-2.0-or-later
#include "explorer.h"
#include <algorithm>
#include <chrono>
#include <queue>
#include <random>
#include <stdexcept>

namespace tunguska::explorer {
namespace {
void checkCell(int cell) { if(cell<0||cell>=cells) throw std::invalid_argument("Cell is outside the 15 by 15 map"); }
void validate(const Input& input) {
    checkCell(input.position);checkCell(input.home);checkCell(input.goal);
    for(int v:input.known) if(v<-1||v>1) throw std::invalid_argument("Knowledge must be -1, 0 or +1");
    if(input.known[input.position]!=1||input.known[input.home]!=1) throw std::invalid_argument("Robot and home must be known clear");
    if(input.energy<0||input.energy>999) throw std::invalid_argument("Energy must be between 0 and 999");
    if(input.policy!=Policy::Goal&&input.policy!=Policy::Explore) throw std::invalid_argument("Unknown exploration policy");
}
int manhattan(int a,int b) { return std::abs(a%side-b%side)+std::abs(a/side-b/side); }
}
int neighbor(int cell,int direction) {
    checkCell(cell);
    switch(direction) {
        case 0:return cell>=side?cell-side:-1;
        case 1:return cell%side<side-1?cell+1:-1;
        case 2:return cell<cells-side?cell+side:-1;
        case 3:return cell%side>0?cell-1:-1;
        default:throw std::invalid_argument("Unknown direction");
    }
}
bool Decision::operator==(const Decision& other) const {
    return action==other.action&&reason==other.reason&&target==other.target&&dx==other.dx&&dy==other.dy&&expanded==other.expanded&&route==other.route;
}
Decision reference(const Input& input) {
    validate(input);
    std::array<int,cells> distance,parent;distance.fill(-1);parent.fill(-1);
    std::queue<int> queue;queue.push(input.position);distance[input.position]=0;
    Decision result;result.target=input.position;
    while(!queue.empty()) {
        int current=queue.front();queue.pop();++result.expanded;
        for(int direction=0;direction<4;++direction) {
            int next=neighbor(current,direction);
            if(next>=0&&input.known[next]==1&&distance[next]<0) {
                distance[next]=distance[current]+1;parent[next]=current;queue.push(next);
            }
        }
    }
    const int homeDistance=distance[input.home];
    if(input.position==input.goal) {result.reason=Reason::Arrived;return result;}
    if(input.energy<=1) {result.reason=Reason::Battery;return result;}
    if(input.returning||(homeDistance>=0&&input.energy<=2*homeDistance+6)) {
        if(input.position==input.home) {result.reason=Reason::Docked;return result;}
        if(homeDistance<0) {result.reason=Reason::NoReturn;return result;}
        result.target=input.home;result.reason=Reason::Return;
    } else {
        const int known=int(std::count_if(input.known.begin(),input.known.end(),[](int v){return v!=0;}));
        if(distance[input.goal]>=0&&(input.policy==Policy::Goal||known>=192)) {
            result.target=input.goal;result.reason=Reason::Goal;
        } else {
            int best=10000,target=-1;
            for(int cell=0;cell<cells;++cell) if(distance[cell]>=0) {
                int unknown=0;
                for(int dir=0;dir<4;++dir){int n=neighbor(cell,dir);if(n>=0&&input.known[n]==0)++unknown;}
                if(unknown==0)continue;
                int score=distance[cell]*4+(input.policy==Policy::Goal?manhattan(cell,input.goal):-unknown*6);
                if(score<best){best=score;target=cell;}
            }
            if(target<0) {
                if(distance[input.goal]<0) {result.reason=Reason::NoRoute;return result;}
                result.target=input.goal;result.reason=Reason::Goal;
            } else {result.target=target;result.reason=target==input.position?Reason::Scan:Reason::Frontier;}
        }
    }
    if(result.target==input.position){result.action=Action::Scan;return result;}
    for(int cell=result.target;cell!=input.position;cell=parent[cell])result.route.push_back(cell);
    std::reverse(result.route.begin(),result.route.end());
    result.action=Action::Move;
    result.dx=result.route.front()%side-input.position%side;
    result.dy=result.route.front()/side-input.position/side;
    return result;
}
World scenario(int preset,uint32_t seed) {
    if(preset<0||preset>2)throw std::invalid_argument("Unknown world preset");
    World world;world.seed=seed;world.ground.fill(1);
    for(int i=0;i<side;++i)world.ground[i]=world.ground[(side-1)*side+i]=world.ground[i*side]=world.ground[i*side+side-1]=-1;
    if(preset==0) {
        world.name="Switchback";
        for(int x:{4,8,11})for(int y=1;y<14;++y)if(y!=(x==8?2:12))world.ground[y*side+x]=-1;
    } else if(preset==1) {
        world.name="Open rooms";
        for(int y:{4,9})for(int x=2;x<13;++x)if(x!=3&&x!=10)world.ground[y*side+x]=-1;
        for(int y=5;y<9;++y)world.ground[y*side+7]=-1;
    } else {
        world.name="Seeded maze";
        // Depth-first carving has a connected passage between every odd-grid room.
        world.ground.fill(-1);std::mt19937 rng(seed);std::vector<int> stack{world.home};world.ground[world.home]=1;
        while(!stack.empty()) {
            int at=stack.back();std::vector<int> directions;
            for(int d=0;d<4;++d){int one=neighbor(at,d);int two=one<0?-1:neighbor(one,d);if(two>=0&&two/side>0&&two/side<14&&two%side>0&&two%side<14&&world.ground[two]<0)directions.push_back(d);}
            if(directions.empty()){stack.pop_back();continue;}
            int d=directions[rng()%directions.size()],one=neighbor(at,d),two=neighbor(one,d);
            world.ground[one]=world.ground[two]=1;stack.push_back(two);
        }
    }
    world.ground[world.home]=world.ground[world.goal]=1;
    return world;
}
std::string explain(const Decision& decision) {
    switch(decision.reason) {
        case Reason::Goal:return "A route to the goal is known. I will take its next clear cell.";
        case Reason::Frontier:return "I will follow clear ground toward unexplored cells, then scan to learn more.";
        case Reason::Return:return "Battery reserve is low. I am following a known route back to base.";
        case Reason::Arrived:return "Goal reached. Every move used a cell observed as clear.";
        case Reason::Docked:return "Back at base. Restart to recharge and begin a new mission.";
        case Reason::NoRoute:return "No goal route or reachable unexplored frontier remains in my map.";
        case Reason::Battery:return "There is not enough battery for another move. Mission stopped.";
        case Reason::Scan:return "A neighboring cell is still unknown. I will stay here and scan again.";
        case Reason::NoReturn:return "My return route is blocked. I am stopping instead of guessing a way home.";
        case Reason::Limit:return "The mission reached its 4,096-turn limit. Restart to continue experimenting.";
    }
    return "Unknown decision";
}
Simulation::Simulation() {reset(scenario(0),{});}
void Simulation::reset(const World& world,const Options& options) {
    checkCell(world.home);checkCell(world.goal);
    for(int value:world.ground)if(value!=-1&&value!=1)throw std::invalid_argument("World cells must be blocked or clear");
    if(world.ground[world.home]!=1||world.ground[world.goal]!=1)throw std::invalid_argument("Base and goal must be on clear ground");
    if(options.capacity<12||options.capacity>999)throw std::invalid_argument("Battery capacity must be 12 to 999");
    if(options.policy!=Policy::Goal&&options.policy!=Policy::Explore)throw std::invalid_argument("Unknown exploration policy");
    world_=world;options_=options;known_.fill(0);position_=world.home;known_[position_]=1;
    energy_=options.capacity;scans_=moves_=0;finished_=returning_=false;pending_.reset();
    history_.clear();observed_.clear();trail_={position_};message_="Ready. The robot knows only its starting cell. Run or step to scan and plan.";
}
int Simulation::knownCount() const {return int(std::count_if(known_.begin(),known_.end(),[](int v){return v!=0;}));}
Input Simulation::prepare() {
    if(finished_)throw std::logic_error("Mission has finished; restart first");
    if(pending_)throw std::logic_error("A decision is already being planned");
    if(scans_>=4096){finished_=true;message_=explain({Action::Stop,Reason::Limit,0,0,0,0,{}});throw std::runtime_error(message_);}
    const bool scanned=energy_>0;
    observed_.clear();
    if(scanned){--energy_;++scans_;observed_={position_};}
    known_[position_]=1;
    for(int direction=0;scanned&&direction<4;++direction) {
        int at=position_;
        for(int radius=1;radius<=2;++radius) {
            at=neighbor(at,direction);if(at<0)break;
            // Missing readings leave prior knowledge unchanged. No false-clear measurements.
            bool dropped=options_.intermittent&&((uint64_t(scans_)+at+world_.seed)%3==0);
            if(dropped)break;
            known_[at]=world_.ground[at];observed_.push_back(at);
            if(world_.ground[at]<0)break;
        }
    }
    pending_=Input{known_,position_,world_.home,world_.goal,energy_,options_.policy,returning_};
    message_=scanned?"Scan complete. The guest is choosing a route from its observed map.":"Battery depleted. The guest will stop this mission.";
    return *pending_;
}
void Simulation::apply(const Decision& decision,uint64_t instructions,double computeMs) {
    if(!pending_)throw std::logic_error("No pending observation to apply");
    if(!(decision==reference(*pending_)))throw std::runtime_error("Decision differs from the independent reference; movement rejected");
    int from=position_;bool blocked=false;message_=explain(decision);
    if(decision.action==Action::Move) {
        int next=decision.route.front();
        if(world_.ground[next]<0) {
            blocked=true;known_[next]=-1;
            message_="Obstacle changed since the last reading. The simulator blocked this move; the robot must replan.";
        } else {position_=next;--energy_;++moves_;trail_.push_back(position_);}
        if(decision.reason==Reason::Return)returning_=true;
        if(position_==world_.goal){finished_=true;message_=explain({Action::Stop,Reason::Arrived,0,0,0,0,{}});}
    } else if(decision.action==Action::Stop) finished_=true;
    history_.push_back({scans_,from,position_,energy_,knownCount(),decision,blocked,instructions,computeMs});
    pending_.reset();
}
void Simulation::editWall(int cell) {
    checkCell(cell);
    if(cell==position_||cell==world_.home||cell==world_.goal)throw std::invalid_argument("Keep the robot, base and goal on clear ground");
    if(pending_)throw std::logic_error("Cancel the current plan before editing");
    world_.ground[cell]=-world_.ground[cell];
    message_="World edited. The robot will learn about this change when a scan reaches it. Restart clears its old map.";
}
void Simulation::setHome(int cell) {
    checkCell(cell);World next=world_;next.home=cell;next.ground[cell]=1;reset(next,options_);
}
void Simulation::setGoal(int cell) {
    checkCell(cell);World next=world_;next.goal=cell;next.ground[cell]=1;reset(next,options_);
}
Session::Session(const std::string& image):image_(image),runtime_(image){runtime_.setRunning(false);}
void Session::start(const Input& input,bool paused) {
    Decision next=reference(input); // Validate before replacing a completed decision.
    runtime_.reset(image_);auto& cpu=runtime_.cpu();cpu.P[machine::I]=1;
    cpu.memref(EXP_STATUS)=0;cpu.memref(EXP_POSITION)=input.position;cpu.memref(EXP_HOME)=input.home;cpu.memref(EXP_GOAL)=input.goal;
    tryte::int_to_word(input.energy,cpu.memref(EXP_ENERGY),cpu.memref(EXP_ENERGY+1));
    cpu.memref(EXP_POLICY)=int(input.policy);cpu.memref(EXP_RETURNING)=input.returning?1:0;
    for(int i=0;i<cells;++i)cpu.memref(EXP_MAP+i)=input.known[i];
    expected_=next;result_={};active_=true;complete_=false;computeMs_=0;runtime_.setRunning(!paused);
}
void Session::pump(uint64_t instructions,double milliseconds) {
    if(!active_)return;
    if(runtime_.running()) {
        auto start=std::chrono::steady_clock::now();runtime_.run(std::min<uint64_t>(instructions,100000),milliseconds);
        computeMs_+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    }
    const auto& cpu=runtime_.cpu();
    if(cpu.memref(EXP_STATUS).to_int()==2) {
        int length=cpu.memref(EXP_LENGTH).to_int();
        if(length<0||length>=cells){cancel();throw std::runtime_error("Guest route length is invalid");}
        Decision next;next.action=Action(cpu.memref(EXP_ACTION).to_int());next.reason=Reason(cpu.memref(EXP_REASON).to_int());
        next.target=cpu.memref(EXP_TARGET).to_int();next.dx=cpu.memref(EXP_DX).to_int();next.dy=cpu.memref(EXP_DY).to_int();next.expanded=cpu.memref(EXP_EXPANDED).to_int();
        for(int i=0;i<length;++i)next.route.push_back(cpu.memref(EXP_ROUTE+i).to_int());
        if(!(next==expected_)){cancel();throw std::runtime_error("Guest plan differs from the reference; movement rejected");}
        result_=next;complete_=true;active_=false;runtime_.setRunning(false);
    } else if(runtime_.cycles()>=10000000) {cancel();throw std::runtime_error("Explorer guest exceeded its instruction limit");}
}
void Session::cancel(){active_=complete_=false;runtime_.setRunning(false);}
}
