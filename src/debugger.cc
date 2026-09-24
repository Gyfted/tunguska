// SPDX-License-Identifier: GPL-2.0-or-later
// Independent Mac fork debugger, 2026-09-24.
// Instruction names and addressing syntax follow Viktor Lofgren's Tunguska.
#include "debugger.h"
#include <charconv>
#include <cstdint>
#include <cstdio>

namespace tunguska::debugger {
int wrapAddress(int address) {
    return int(((int64_t(address) + MEMSIZ/2) % MEMSIZ + MEMSIZ) % MEMSIZ - MEMSIZ/2);
}
std::string nonary(tryte value) {
    char buffer[4];
    snprintf(buffer, sizeof(buffer), "%03X", value.nonaryhex());
    return buffer;
}
std::string ternary(const tryte& value) {
    std::string result;
    for (int i = 0; i < 6; ++i) result += "-0+"[value[i].to_int() + 1];
    return result;
}
std::string formatAddress(int address) {
    tryte high, low;
    tryte::int_to_word(wrapAddress(address), high, low);
    return nonary(high) + ":" + nonary(low);
}
std::optional<int> parseAddress(std::string_view text) {
    const auto begin = text.find_first_not_of(" \t\r\n");
    if (begin == std::string_view::npos) return {};
    const auto end = text.find_last_not_of(" \t\r\n");
    text = text.substr(begin, end - begin + 1);
    if (text.size() == 7 && text[3] == ':') {
        int address = 0;
        for (size_t i = 0; i < text.size(); ++i) {
            if (i == 3) continue;
            const char c = text[i];
            int digit;
            if (c >= '0' && c <= '4') digit = c - '0';
            else if (c >= 'A' && c <= 'D') digit = -(c - 'A' + 1);
            else if (c >= 'a' && c <= 'd') digit = -(c - 'a' + 1);
            else return {};
            address = address * 9 + digit;
        }
        return address;
    }
    if (text.front() == '+') {
        text.remove_prefix(1);
        if (text.empty() || text.front() < '0' || text.front() > '9') return {};
    }
    int value;
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), value);
    if (parsed.ec != std::errc() || parsed.ptr != text.data() + text.size() || value < -MEMSIZ/2 || value > MEMSIZ/2)
        return {};
    return value;
}
Instruction disassemble(const memory& memory, int address) {
    address = wrapAddress(address);
    const tryte raw = memory.memref(address);
    const int mode = (raw >> 4).to_int();
    const int opcode = ((raw << 2) >> 2).to_int();
    const int length = mode == machine::ACC || mode == machine::XY ? 1 : mode == machine::IMMEDIATE ? 2 : 3;
    const std::string high = nonary(memory.memref(address + 1));
    const std::string operand = high + ":" + nonary(memory.memref(address + 2));
    std::string name = machine::opcode_to_string(opcode);
    if (name.empty()) name = "???";
    switch (mode) {
        case machine::ABS: name += " " + operand; break;
        case machine::IMMEDIATE: name += " #" + high; break;
        case machine::AX: name += " " + operand + ",X"; break;
        case machine::AY: name += " " + operand + ",Y"; break;
        case machine::INDX: name += " (" + operand + ",X)"; break;
        case machine::INDY: name += " (" + operand + "),Y"; break;
        case machine::INDIRECT: name += " (" + operand + ")"; break;
        case machine::XY: name += " X,Y"; break;
        default: break; // Shared accumulator/implicit mode has no operand bytes.
    }
    std::string bytes;
    for (int i = 0; i < length; ++i) {
        if (i) bytes += ' ';
        bytes += nonary(memory.memref(address + i));
    }
    return {address, length, bytes, name};
}
}
