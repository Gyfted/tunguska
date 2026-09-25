// SPDX-License-Identifier: GPL-2.0-or-later
#include "runtime.h"
#include "core/values.h"
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>
#include <zlib.h>
#include <chrono>
#include <climits>
#include <sys/stat.h>
#include <unistd.h>

static void require(bool result, const char* message) {
    if (!result) throw std::runtime_error(message);
}
static int wordWrap(int64_t n) {
    return int(((n + MEMSIZ/2) % MEMSIZ + MEMSIZ) % MEMSIZ - MEMSIZ/2);
}
static void trits() {
    for (int a = -1; a <= 1; ++a) for (int b = -1; b <= 1; ++b) {
        trit x(a), y(b);
        for (int v : {x & y, x | y, x ^ y, x > y, x >> y, x.but(y)})
            require(v >= -1 && v <= 1, "ternary operators must never create an invalid trit");
    }
}
static void floats() {
    for (float n : {0.f, -0.f, 1.f, -1.f, std::numeric_limits<float>::denorm_min(),
                    std::numeric_limits<float>::max(), -std::numeric_limits<float>::max(),
                    INFINITY, -INFINITY, NAN}) {
        tryte high, low;
        try { agdp::float2_to_float3(n, high, low); }
        catch (const std::domain_error&) { require(!std::isfinite(n), "finite conversions should be defined"); }
        require(high.to_int() >= -364 && high.to_int() <= 364, "bounded float encoding");
        require(low.to_int() >= -364 && low.to_int() <= 364, "bounded float encoding");
    }
    machine m;
    agdp coprocessor;
    constexpr int op = PODWORD_TO_INT(TV_DDD, TV_DD0);
    constexpr int r1 = PODWORD_TO_INT(TV_DDD, TV_DD1);
    constexpr int r2 = PODWORD_TO_INT(TV_DDD, TV_DD3);
    for (int operation = COP_ITOF; operation <= COP_FSIN; ++operation) {
        for (int h : {-364, -1, 0, 1, 364}) for (int l : {-364, 0, 364}) {
            m.memref(r1) = h; m.memref(r1+1) = l;
            m.memref(r2) = l; m.memref(r2+1) = h;
            m.memref(op) = operation;
            coprocessor.heartbeat(m);
            require(m.memref(op).to_int() == 0, "coprocessor fault must acknowledge request");
        }
    }
}
static void words() {
    machine m;
    for (int a : {-265720, -265719, -1, 0, 1, 265719, 265720})
    for (int b : {-265720, -265719, -1, 0, 1, 265719, 265720}) {
        m.PCH = m.PCL = 0; m.S = 0; m.SP = 1; m.P = 0;
        m.memref(0) = machine::qop(machine::ABS, machine::MLW);
        tryte::int_to_word(a, m.memref(1), m.memref(2));
        tryte::int_to_word(b, m.memref(730), m.memref(729));
        m.instruction();
        require(tryte::word_to_int(m.X, m.Y) == wordWrap(int64_t(a)*b), "word multiply wraps in ternary, without host overflow");
    }
}
static void hostIntegers() {
    memory m;
    for (int value : {INT_MIN, INT_MIN+1, -730, -365, -364, 0, 364, 365, 730, INT_MAX-1, INT_MAX}) {
        const auto wrap = [](int64_t n) { return int(((n+364)%729+729)%729-364); };
        tryte v(value), high, low;
        require(v.to_int() == wrap(value), "host integer conversion must wrap without overflow");
        require(v.get_carry().to_int() == (value > 364 ? 1 : value < -364 ? -1 : 0), "conversion carry");
        tryte::int_to_word(value, high, low);
        require(tryte::word_to_int(high, low) == wordWrap(value), "wide word conversion");
        for (int n : {-364, 0, 364}) {
            tryte sum(n); sum += value;
            require(sum.to_int() == wrap(int64_t(n)+value), "host addition must wrap without overflow");
            require((tryte(n)+value).to_int() == sum.to_int(), "addition agreement");
        }
        m.memrefi(value, value) = 17;
        require(m.memref(wordWrap(int64_t(value)*729+value)).to_int() == 17, "wide split address");
    }
    for (const char* s : {static_cast<const char*>(nullptr), "", "D", "DD", "DDDD", "???"}) {
        bool failed = false;
        try { tryte t(s); } catch (const std::invalid_argument&) { failed = true; }
        require(failed, "invalid nonary strings must be rejected before indexing");
    }
    for (int shift : {INT_MIN, -1}) {
        for (bool left : {false, true}) {
            bool failed = false;
            try { auto t = left ? tryte(364)<<shift : tryte(364)>>shift; (void)t; }
            catch (const std::out_of_range&) { failed = true; }
            require(failed, "negative shifts must be rejected");
        }
    }
    for (int shift : {6, 7, INT_MAX})
        require((tryte(364)<<shift).to_int() == 0 && (tryte(364)>>shift).to_int() == 0, "wide shifts produce zero");
}

static void executionBudget() {
    tunguska::Runtime r("build/boot.ternobj");
    auto& m = r.cpu(); m.P = 0; m.P[machine::I] = 1;
    const int pc = -10000;
    tryte::int_to_word(pc, m.PCH, m.PCL);
    m.memref(pc) = machine::qop(machine::IMMEDIATE, machine::LDA); m.memref(pc+1) = COP_BLS;
    m.memref(pc+2) = machine::qop(machine::ABS, machine::STA);
    tryte::int_to_word(PODWORD_TO_INT(TV_DDD,TV_DD0), m.memref(pc+3), m.memref(pc+4));
    m.memref(pc+5) = machine::qop(machine::ABS, machine::JMP);
    tryte::int_to_word(pc, m.memref(pc+6), m.memref(pc+7));
    tryte::int_to_word(0, m.memrefi(TV_DDD,TV_DD1), m.memrefi(TV_DDD,TV_DD2));
    tryte::int_to_word(MEMSIZ/2, m.memrefi(TV_DDD,TV_DCD), m.memrefi(TV_DDD,TV_DCC));
    const auto start = std::chrono::steady_clock::now();
    const auto count = r.run(4096, 1);
    require(count > 0 && count < 100, "heavy guest must yield before a 1024-instruction batch");
    std::cout << "Budget stress: " << count << " instructions, "
              << std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()
              << " ms (cooperative 1 ms budget)\n";
    r.mouse(INT_MIN, INT_MAX);
    require(m.pending_interrupts() == machine::max_interrupts, "extreme motion stops at interrupt capacity");
    r.mouse(INT_MAX, INT_MIN);
    require(m.pending_interrupts() == machine::max_interrupts, "full queue discards excess motion promptly");
}
static void diagnostics() {
    // Exercise guest instructions and peripherals through their real log paths.
    FILE* log = tmpfile(); require(log, "diagnostic capture");
    fflush(stdout);
    const int saved = dup(STDOUT_FILENO); require(saved >= 0, "save stdout");
    require(dup2(fileno(log), STDOUT_FILENO) >= 0, "redirect diagnostics");
    machine m; disk drive(&m); agdp coprocessor;
    for (int n = 0; n < 4096; ++n) {
        m.PCH = m.PCL = 0; m.P[machine::I] = 1;
        m.memref(0) = machine::qop(machine::IMPLICIT, machine::DEBUG); m.instruction();
        m.memrefi(TV_DDD, TV_DDA) = 364; drive.heartbeat();
        m.memrefi(TV_DDD, TV_DD0) = 364; coprocessor.heartbeat(m);
    }
    fflush(stdout); const long bytes = ftell(log);
    const bool restored = dup2(saved, STDOUT_FILENO) >= 0; close(saved); fclose(log);
    require(restored && bytes > 0 && bytes < 32768, "guest diagnostics must have a bounded shared output budget");
}
static void images() {
    char directory[] = "/tmp/tunguska-security-XXXXXX";
    require(mkdtemp(directory), "temporary directory");
    const auto path = std::string(directory) + "/bad.ternobj";
    memory m; m.memref(0) = 123;
    auto reject = [&] {
        bool failed = false;
        try { m.load(path.c_str()); } catch (const std::runtime_error&) { failed = true; }
        require(failed && m.memref(0).to_int() == 123, "malformed input must fail without changing memory");
    };
    require(mkfifo(path.c_str(), 0600) == 0, "create nonregular input"); reject();
    std::filesystem::remove(path);
    { std::ofstream f(path); f << 'x'; }
    std::filesystem::resize_file(path, memory::max_image_bytes+1); reject();
    // Legacy raw images remain valid; malformed values cannot partly replace memory.
    std::vector<uint8_t> raw(MEMSIZ*2);
    m.load_bytes(raw.data(), raw.size()); require(m.memref(0).to_int() == 0, "raw image compatibility");
    m.memref(0) = 123;
    raw[raw.size()-1] = 0x7f;
    bool rejected = false;
    try { m.load_bytes(raw.data(), raw.size()); } catch (const std::runtime_error&) { rejected = true; }
    require(rejected && m.memref(0).to_int() == 123, "late invalid tryte must preserve memory");
    // Valid payload followed by excess decompressed bytes; includes a compressed expansion test.
    for (size_t size : {size_t(0), size_t(1), size_t(MEMSIZ*2-1), size_t(MEMSIZ*2+1), size_t(16*1024*1024)}) {
        std::vector<unsigned char> zeros(size);
        gzFile z = gzopen(path.c_str(), "wb9"); gzwrite(z, zeros.data(), unsigned(zeros.size())); gzclose(z);
        reject();
    }
    m.save(path.c_str());
    // Corrupt the gzip trailer CRC, then truncate the stream.
    auto length = std::filesystem::file_size(path);
    { std::fstream f(path, std::ios::in | std::ios::out | std::ios::binary); f.seekg(length-8); char c; f.get(c); f.seekp(length-8); f.put(c^0x7f); }
    reject();
    std::filesystem::resize_file(path, length/2); reject();
    m.save(path.c_str());
    { std::ofstream f(path, std::ios::binary | std::ios::app); f << "trailing junk"; }
    reject();
    m.save(path.c_str());
    { gzFile z = gzopen(path.c_str(), "ab"); gzclose(z); }
    reject();
    // A guest-provided filename cannot load a host file; sync cannot overwrite a mounted source.
    machine cpu; disk drive(&cpu); m.save(path.c_str()); drive.load(path.c_str());
    drive.memref(0) = 42;
    cpu.memrefi(TV_DDD, TV_DDA) = disk::DISKOP_SYNC; drive.heartbeat();
    memory verify; verify.load(path.c_str()); require(verify.memref(0).to_int() == 123, "guest sync must not write host file");
    drive.unload();
    tryte::int_to_word(0, cpu.X, cpu.Y);
    for (size_t i = 0; i <= path.size(); ++i) cpu.memref(int(i)) = asciitoternary(path.c_str()[i]);
    drive.do_load(); drive.status(); require(cpu.A.to_int() == 0, "guest load must not open host path");
    std::filesystem::remove_all(directory);
}
static void instructions() {
    machine m; std::mt19937 random(0x7465726e);
    m.queue_interrupt(nullptr);
    require(m.pending_interrupts() == 0, "ignore null host interrupt requests");
    for (int opcode = -364; opcode <= 364; ++opcode) for (int trial = 0; trial < 32; ++trial) {
        m.PCH = m.PCL = 0; m.P = 0;
        m.A = int(random()%729)-364; m.X = int(random()%729)-364; m.Y = int(random()%729)-364;
        m.S = int(random()%729)-364; m.SP = 2;
        for (int n = 1094; n <= 1822; ++n) m.memref(n) = int(random()%729)-364;
        m.memref(0) = opcode; m.memref(1) = int(random()%729)-364; m.memref(2) = int(random()%729)-364;
        m.instruction();
        for (const tryte* r : {&m.A, &m.X, &m.Y, &m.P, &m.S, &m.SP, &m.PCH, &m.PCL})
            require(r->to_int() >= -364 && r->to_int() <= 364, "instruction preserves valid trytes");
    }
}
int main(int argc, char** argv) {
    try {
        const std::string mode = argc > 1 ? argv[1] : "all";
        if (mode == "all" || mode == "trits") trits();
        if (mode == "all" || mode == "floats") floats();
        if (mode == "all" || mode == "words") words();
        if (mode == "all" || mode == "host") hostIntegers();
        if (mode == "all" || mode == "budget") executionBudget();
        if (mode == "all" || mode == "diagnostics") diagnostics();
        if (mode == "all" || mode == "images") images();
        if (mode == "all" || mode == "instructions") instructions();
        std::cout << "PASS security regression checks: " << mode << '\n';
    } catch (const std::exception& e) { std::cerr << "FAIL: " << e.what() << '\n'; return 1; }
}
