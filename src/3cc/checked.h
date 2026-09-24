// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac fork, 2026-09-24. Checked host-side constant evaluation.
#pragma once
#include <cstdint>
#include <stdexcept>

inline int checked_word(int64_t value) {
    if (value < -265720 || value > 265720)
        throw std::runtime_error("Constant is outside the 12-trit range [-265720, 265720]");
    return static_cast<int>(value);
}
inline int checked_quotient(int a, int b, bool remainder = false) {
    if (!b) throw std::runtime_error("Division by zero in constant expression");
    return checked_word(remainder ? int64_t(a) % b : int64_t(a) / b);
}
