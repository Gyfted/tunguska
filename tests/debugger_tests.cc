// SPDX-License-Identifier: GPL-2.0-or-later
#include "debugger.h"
#include "runtime.h"
#include "core/values.h"
#include <climits>
#include <iostream>
#include <stdexcept>

static void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
void debuggerTests(const char* image) {
    namespace dbg = tunguska::debugger;
    for (int i = -MEMSIZ/2; i <= MEMSIZ/2; ++i)
        check(dbg::parseAddress(dbg::formatAddress(i)) == i, "all nonary address roundtrips");
    for (const char* invalid : {"", " ", "265721", "-265721", "2147483648", "999999999999999999999999", "12junk", "0x10",
                              "000:005", "FFF:FFF", "0:0", "--1", "+-1", "++1", "+", "1 2", "000:000junk"})
        check(!dbg::parseAddress(invalid), "invalid debugger address rejected");
    check(dbg::parseAddress(" +265720 ") == 265720 && dbg::parseAddress(" -265720 ") == -265720, "decimal address boundaries");
    check(dbg::parseAddress("ddd:ddd") == -265720, "lowercase nonary address");
    check(dbg::ternary(tryte(-364)) == "------" && dbg::ternary(tryte(364)) == "++++++" && dbg::ternary(tryte(0)) == "000000", "trit display");
    check(dbg::wrapAddress(INT_MAX) >= -MEMSIZ/2 && dbg::wrapAddress(INT_MIN) <= MEMSIZ/2, "large address wrapping");

    machine cpu;
    const char* expected[] = {"LDA 001:00A", "LDA #001", "LDA 001:00A,X", "LDA 001:00A,Y", "LDA",
                             "LDA (001:00A,X)", "LDA (001:00A),Y", "LDA (001:00A)", "LDA X,Y"};
    for (int mode = -4; mode <= 4; ++mode) {
        cpu.memref(265720) = machine::qop(mode, machine::LDA);
        cpu.memref(-265720) = 1; cpu.memref(-265719) = -1;
        const auto instruction = dbg::disassemble(cpu, 265720);
        check(instruction.text == expected[mode+4], "all addressing syntaxes and operands wrapping across end of memory");
        check(instruction.length == (mode == 0 || mode == 4 ? 1 : mode == -3 ? 2 : 3), "instruction lengths");
    }
    for (int raw = -364; raw <= 364; ++raw) {
        cpu.memref(0) = raw;
        const auto decoded = dbg::disassemble(cpu, 0);
        check(decoded.length >= 1 && decoded.length <= 3 && !decoded.text.empty(), "every instruction encoding can be inspected");
    }
    cpu.memref(0) = machine::qop(0, 37);
    check(dbg::disassemble(cpu, 0).text == "???", "undefined opcode is visibly unknown");
    cpu.memref(0) = machine::qop(0, machine::DEBUG);
    check(dbg::disassemble(cpu, 0).text == "DEBUG", "last opcode is decoded");

    tunguska::Runtime runtime(image);
    auto& c = runtime.cpu();
    c.P[machine::I] = 1;
    c.PCH = c.PCL = c.A = 0;
    c.memref(0) = machine::qop(machine::IMMEDIATE, machine::LDA);
    c.memref(1) = 42;
    c.memref(2) = machine::qop(machine::ABS, machine::JMP);
    c.memref(3) = c.memref(4) = 0;
    runtime.toggleBreakpoint(0);
    check(runtime.run(100) == 0 && runtime.cycles() == 0 && c.A.to_int() == 0, "breakpoint stops before execution");
    check(!runtime.running() && runtime.stoppedAtBreakpoint() == 0, "breakpoint stop reason");
    const auto pending = c.pending_interrupts();
    runtime.setRunning(true);
    check(runtime.run(100) == 2 && c.A.to_int() == 42 && runtime.programCounter() == 0, "continue passes current breakpoint once and catches loop");
    check(runtime.stoppedAtBreakpoint() == 0 && c.pending_interrupts() == pending, "breakpoint resume does not duplicate clock requests");
    runtime.step();
    check(runtime.cycles() == 3 && runtime.programCounter() == 2 && !runtime.running() && !runtime.stoppedAtBreakpoint(), "single step bypasses breakpoint and stays paused");
    runtime.setRunning(true);
    check(runtime.run(10) == 1 && runtime.stoppedAtBreakpoint() == 0, "breakpoint remains armed after step");
    runtime.toggleBreakpoint(0);
    runtime.setRunning(true);
    check(runtime.run(4) == 4 && runtime.running(), "removed breakpoint does not stop");
    bool rejected = false;
    try { runtime.toggleBreakpoint(265721); } catch (const std::out_of_range&) { rejected = true; }
    check(rejected, "out-of-range breakpoint rejected");
    runtime.toggleBreakpoint(2);
    try { runtime.reset("/nonexistent/tunguska-debugger-image"); } catch (const std::runtime_error&) {}
    check(runtime.breakpoints().count(2) == 1, "failed reset preserves debugger state");
    runtime.reset(image);
    check(runtime.breakpoints().empty() && runtime.cycles() == 0, "successful reset clears breakpoints");

    // A clock interrupt is raised before the first instruction. The breakpoint
    // must see the dispatched handler, not just the pre-interrupt PC.
    auto& handlerCPU = runtime.cpu();
    handlerCPU.P = handlerCPU.CL = handlerCPU.PCH = handlerCPU.PCL = 0;
    handlerCPU.memrefi(TV_444, TV_442) = 0;
    handlerCPU.memrefi(TV_444, TV_443) = 100;
    handlerCPU.memref(100) = machine::qop(machine::IMMEDIATE, machine::LDA);
    handlerCPU.memref(101) = 73;
    handlerCPU.memref(102) = machine::qop(machine::IMPLICIT, machine::RTI);
    runtime.toggleBreakpoint(100);
    check(runtime.run(10) == 0 && runtime.stoppedAtBreakpoint() == 100 && handlerCPU.A.to_int() == 0, "breakpoint catches interrupt handler before its first instruction");
    const int stack = handlerCPU.S.to_int();
    check(handlerCPU.pending_interrupts() == 0, "clock interrupt was dispatched");
    runtime.setRunning(true);
    check(runtime.run(1) == 1 && handlerCPU.A.to_int() == 73 && runtime.programCounter() == 102, "handler resumes at the stopped instruction");
    check(handlerCPU.S.to_int() == stack && handlerCPU.pending_interrupts() == 0, "resume neither repeats dispatch nor queues a duplicate clock");
    runtime.step();
    check(runtime.programCounter() == 0 && !runtime.running(), "return from interrupted breakpoint restores original PC");
    std::cout << "PASS debugger addresses, disassembly, breakpoints, stepping, and interrupt dispatch\n";
}
