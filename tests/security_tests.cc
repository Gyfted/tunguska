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
        if (mode == "all" || mode == "images") images();
        if (mode == "all" || mode == "instructions") instructions();
        std::cout << "PASS security regression checks: " << mode << '\n';
    } catch (const std::exception& e) { std::cerr << "FAIL: " << e.what() << '\n'; return 1; }
}
