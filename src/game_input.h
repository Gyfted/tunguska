// SPDX-License-Identifier: GPL-2.0-or-later
// Local, bounded held-key state for Ternary Breach. No game simulation here.
#pragma once
#include <array>
#include <string>

namespace tunguska {
class GameInput {
public:
    static char normalize(char key) {
        if (key >= 'A' && key <= 'Z') key += 'a' - 'A';
        return key;
    }
    static bool accepts(char key) {
        key = normalize(key);
        return std::string("wsadqe mr").find(key) != std::string::npos;
    }
    bool press(char key, double now) {
        key = normalize(key);
        if (!accepts(key) || held_[size_t(key)]) return false;
        held_[size_t(key)] = true;
        next_[size_t(key)] = now + interval(key);
        return true;
    }
    void release(char key) {
        key = normalize(key);
        if (accepts(key)) held_[size_t(key)] = false;
    }
    std::string repeat(double now) {
        std::string result;
        for (char key : std::string("wsadqe ")) {
            if (held_[size_t(key)] && now >= next_[size_t(key)]) {
                result += key;
                // Never catch up missed repeats after a slow frame or pause.
                next_[size_t(key)] = now + interval(key);
            }
        }
        return result;
    }
    void clear() { held_.fill(false); }
private:
    static double interval(char key) { return key == ' ' ? 0.18 : 0.075; }
    std::array<bool, 128> held_{};
    std::array<double, 128> next_{};
};
}
