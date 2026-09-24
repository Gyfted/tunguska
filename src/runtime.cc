// SPDX-License-Identifier: GPL-2.0-or-later
// Adapted from Tunguska's execution loop and display semantics.
// Original work Copyright (C) 2007,2008 Viktor Lofgren.
// Mac fork adaptation: 2026-09-24, maintained by Vinny Lingham.
#include "runtime.h"
#include "core/values.h"
#include <algorithm>
#include <chrono>

namespace tunguska {
Runtime::Runtime(const std::string& image) { reset(image); }
void Runtime::reset(const std::string& image) {
    // Construct first so a failed load leaves the running machine intact.
    auto next = std::make_unique<machine>();
    next->load(image.c_str());
    auto drive = std::make_unique<disk>(next.get());
    disk_ = std::move(drive);
    cpu_ = std::move(next);
    coprocessor_ = agdp();
    cycles_ = 0;
    frame_ = Frame();
    capture(true);
}
void Runtime::cycle() {
    if (cpu_->CL.to_int() == 0) cpu_->queue_interrupt(new clock_interrupt());
    disk_->heartbeat();
    coprocessor_.heartbeat(*cpu_);
    cpu_->instruction();
    ++cycles_;
}
uint64_t Runtime::run(uint64_t instructions, double maxMilliseconds) {
    const auto start = std::chrono::steady_clock::now();
    uint64_t count = 0;
    for (; count < instructions && running(); ++count) {
        cycle();
        // Service display handshakes even when running without a window.
        if ((count & 1023) == 1023) {
            capture();
            if (maxMilliseconds > 0 &&
                std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count() >= maxMilliseconds) {
                ++count;
                break;
            }
        }
    }
    capture();
    return count;
}
void Runtime::step() { setRunning(false); cycle(); capture(); }
void Runtime::setRunning(bool run) {
    if (run == running()) return;
    if (run) cpu_->set_state(new machine::running_state());
    else cpu_->set_state(new machine::paused_state());
}
void Runtime::key(char ascii) {
    if (ascii == '\r') ascii = '\n';
    if (ascii == 127) ascii = '\b';
    const int value = asciitoternary(ascii);
    if (value) cpu_->queue_interrupt(new keyboard_interrupt(value));
}
void Runtime::breakKey() { cpu_->queue_interrupt(new keybreak_interrupt()); }
void Runtime::mouse(int dx, int dy) {
    while (dx || dy) {
        const int x = std::clamp(dx, -13, 13), y = std::clamp(dy, -13, 13);
        cpu_->queue_interrupt(new mousemotion_interrupt(x, y));
        dx -= x; dy -= y;
    }
}
void Runtime::mouseButton(bool down) { cpu_->queue_interrupt(new mousepress_interrupt(down ? 1 : -1)); }
void Runtime::mount(const std::string& path) { disk_->load(path.c_str()); }
void Runtime::saveDisk(const std::string& path) { disk_->save(path.c_str()); }
void Runtime::eject() { disk_->unload(); }
std::array<uint8_t, 3> Runtime::color(int value) {
    tryte t(value);
    return {uint8_t(28 * (4 + 3*t[0].to_int() + t[1].to_int())),
            uint8_t(28 * (4 + 3*t[2].to_int() + t[3].to_int())),
            uint8_t(28 * (4 + 3*t[4].to_int() + t[5].to_int()))};
}
bool Runtime::capture(bool force) {
    auto& control = cpu_->memrefi(TV_DDD, TV_DDB);
    if (!force && control[5].to_int() != 1) return false;
    control[5] = 0;
    frame_.mode = control[4].to_int();
    frame_.auxiliary = control[3].to_int();
    ++frame_.revision;
    if (frame_.mode == 0) {
        for (int i = 0; i < columns * rows; ++i) frame_.text[i] = cpu_->memref(-264262 + i).to_int();
    } else if (frame_.mode == 1) {
        frame_.vertices.clear();
        for (int i = -364; i <= 364; i += 3) {
            const int color = cpu_->memrefi(TV_DDB, i).to_int();
            const double x = (cpu_->memrefi(TV_DDB, i+1) ^ TV_ADD).to_int() / 242.0 + 0.5;
            const double y = (cpu_->memrefi(TV_DDB, i+2) ^ TV_ADD).to_int() / 242.0 + 0.5;
            frame_.vertices.push_back({x, y, color});
        }
    } else {
        const int offset = PODWORD_TO_INT(TV_DDB, TV_DDD);
        for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
            const int value = frame_.auxiliary == 1
                ? 364 * cpu_->memref(offset + x/6 + (width/6)*y)[x%6].to_int()
                : cpu_->memref(offset + x + width*y).to_int();
            const auto rgb = color(value);
            const int i = 4 * (x + width*y);
            frame_.pixels[i] = rgb[0]; frame_.pixels[i+1] = rgb[1]; frame_.pixels[i+2] = rgb[2]; frame_.pixels[i+3] = 255;
        }
    }
    return true;
}
std::string Runtime::text() const {
    std::string result;
    for (int y = 0; y < rows; ++y) {
        std::string line;
        for (int x = 0; x < columns; ++x) {
            const char c = ternarytoascii(frame_.text[y*columns+x]);
            line += c >= 32 ? c : ' ';
        }
        const auto last = line.find_last_not_of(' ');
        if (last != std::string::npos) line.resize(last+1); else line.clear();
        result += line + '\n';
    }
    return result;
}
}
