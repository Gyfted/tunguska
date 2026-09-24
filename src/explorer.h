// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Ternary Explorer, 2026-09-24. Original emulator: Viktor Lofgren.
#pragma once
#include "runtime.h"
#include "explorer_protocol.h"

namespace tunguska::explorer {
constexpr int side=EXP_SIDE, cells=EXP_CELLS;
using Grid=std::array<int8_t,cells>;
enum class Cell : int8_t { Blocked=-1, Unknown=0, Clear=1 };
enum class Policy { Goal=0, Explore=1 };
enum class Action { Stop=-1, Scan=0, Move=1 };
enum class Reason { Goal=EXP_GOAL_ROUTE, Frontier=EXP_FRONTIER, Return=EXP_RETURN,
    Arrived=EXP_ARRIVED, Docked=EXP_DOCKED, NoRoute=EXP_NO_ROUTE, Battery=EXP_BATTERY,
    Scan=EXP_SCAN, NoReturn=EXP_NO_RETURN, Limit=EXP_TURN_LIMIT };
struct World { Grid ground{}; int home=16, goal=208; std::string name; uint32_t seed=729; };
struct Options { Policy policy=Policy::Goal; int capacity=360; bool intermittent=false; };
struct Input { Grid known{}; int position=0, home=0, goal=0, energy=0; Policy policy=Policy::Goal; bool returning=false; };
struct Decision {
    Action action=Action::Stop; Reason reason=Reason::NoRoute;
    int target=0, dx=0, dy=0, expanded=0;
    std::vector<int> route;
    bool operator==(const Decision& other) const;
};
int neighbor(int cell,int direction); // north, east, south, west; -1 outside map
Decision reference(const Input& input);
World scenario(int preset,uint32_t seed=729);
std::string explain(const Decision& decision);
struct Event { int turn,from,to,energy,known; Decision decision; bool blocked; uint64_t instructions; double computeMs; };
// Host owns the simulated environment/sensors; the guest only receives Input.
class Simulation {
public:
    Simulation();
    void reset(const World& world,const Options& options);
    Input prepare();
    void apply(const Decision& decision,uint64_t instructions=0,double computeMs=0);
    void cancelPlanning() { pending_.reset(); }
    void editWall(int cell);
    void setHome(int cell);
    void setGoal(int cell);
    const World& world() const { return world_; }
    const Options& options() const { return options_; }
    const Grid& known() const { return known_; }
    const std::vector<int>& observed() const { return observed_; }
    const std::vector<int>& trail() const { return trail_; }
    const std::vector<Event>& history() const { return history_; }
    const std::string& message() const { return message_; }
    int position() const { return position_; }
    int energy() const { return energy_; }
    int scans() const { return scans_; }
    int moves() const { return moves_; }
    int knownCount() const;
    bool finished() const { return finished_; }
    bool returning() const { return returning_; }
private:
    World world_; Options options_; Grid known_{};
    int position_=16,energy_=360,scans_=0,moves_=0;
    bool returning_=false,finished_=false;
    std::optional<Input> pending_;
    std::vector<int> observed_,trail_;
    std::vector<Event> history_;
    std::string message_;
};
class Session {
public:
    explicit Session(const std::string& image);
    void start(const Input& input,bool paused=false);
    void pump(uint64_t instructions=50000,double milliseconds=4);
    void cancel();
    Runtime& runtime() { return runtime_; }
    const Decision& result() const { return result_; }
    bool active() const { return active_; }
    bool complete() const { return complete_; }
    double computeMilliseconds() const { return computeMs_; }
private:
    std::string image_; Runtime runtime_;
    Decision expected_,result_;
    bool active_=false,complete_=false;
    double computeMs_=0;
};
}
