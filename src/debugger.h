// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac fork debugger, 2026-09-24.
#pragma once
#include "core/machine.h"
#include <optional>
#include <string>
#include <string_view>

namespace tunguska::debugger {
struct Instruction {
    int address, length;
    std::string bytes, text;
};
int wrapAddress(int address);
std::string formatAddress(int address);
std::optional<int> parseAddress(std::string_view text);
std::string nonary(tryte value);
std::string ternary(const tryte& value);
Instruction disassemble(const memory& memory, int address);
}
