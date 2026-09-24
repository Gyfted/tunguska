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
    uint64_t run(uint64_t instructions, double maxMilliseconds = 0);
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
    const Frame& frame() const { return frame_; }
    uint64_t cycles() const { return cycles_; }
    bool running() const { return cpu_->get_state()->is_running(); }
    void setRunning(bool running);
    static std::array<uint8_t, 3> color(int value);
private:
    void cycle();
    std::unique_ptr<machine> cpu_;
    std::unique_ptr<disk> disk_;
    agdp coprocessor_;
    Frame frame_;
    uint64_t cycles_ = 0;
};
}
