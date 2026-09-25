// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "core/machine.h"
#include "core/disk.h"
#include "core/agdp.h"
#include <array>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include <optional>
#include <set>

namespace tunguska {
constexpr int columns = 54, rows = 27, width = 324, height = 243;
struct Frame {
    int mode = 0, auxiliary = 0;
    uint64_t revision = 0;
    std::array<int, columns * rows> text{};
    std::vector<uint8_t> pixels = std::vector<uint8_t>(width * height * 4, 0);
    struct Vertex { double x, y; int color; };
    std::vector<Vertex> vertices;
};

// Access only from one thread. The native app runs bounded batches on its UI thread.
class Runtime {
public:
    explicit Runtime(const std::string& image);
    void reset(const std::string& image);
    // Interactive callers can return a newly captured guest frame immediately;
    // headless/default callers retain the requested instruction budget.
    uint64_t run(uint64_t instructions, double maxMilliseconds = 0, bool yieldAfterFrame = false);
    void step();
    void key(char ascii);
    void breakKey();
    void mouse(int dx, int dy);
    void mouseButton(bool down);
    bool capture(bool force = false);
    void mount(const std::string& path);
    void saveDisk(const std::string& path);
    void eject();
    std::string text() const;
    machine& cpu() { return *cpu_; }
    const machine& cpu() const { return *cpu_; }
    int programCounter() const { return tryte::word_to_int(cpu_->PCH, cpu_->PCL); }
    void toggleBreakpoint(int address);
    void clearBreakpoints();
    const std::set<int>& breakpoints() const { return breakpoints_; }
    std::optional<int> stoppedAtBreakpoint() const { return stoppedAt_; }
    const Frame& frame() const { return frame_; }
    uint64_t cycles() const { return cycles_; }
    bool running() const { return cpu_->get_state()->is_running(); }
    void setRunning(bool running);
    static std::array<uint8_t, 3> color(int value);
private:
    bool cycle(bool checkBreakpoints = true);
    std::unique_ptr<machine> cpu_;
    std::unique_ptr<disk> disk_;
    agdp coprocessor_;
    Frame frame_;
    uint64_t cycles_ = 0;
    bool cyclePrepared_ = false;
    std::set<int> breakpoints_;
    std::optional<int> stoppedAt_, skipBreakpoint_;
};
}
