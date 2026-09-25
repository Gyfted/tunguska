// SPDX-License-Identifier: GPL-2.0-or-later
// Reproducible mutation testing; not a coverage-guided fuzzer.
#include "core/memory.h"
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <random>
#include <stdexcept>
#include <vector>
#include <zlib.h>

static std::vector<uint8_t> gzip(const std::vector<uint8_t>& raw) {
    z_stream z{};
    if (deflateInit2(&z, 1, Z_DEFLATED, 16+MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK)
        throw std::runtime_error("compression setup");
    std::vector<uint8_t> result(deflateBound(&z, raw.size()));
    z.next_in = const_cast<Bytef*>(raw.data()); z.avail_in = raw.size();
    z.next_out = result.data(); z.avail_out = result.size();
    const int status = deflate(&z, Z_FINISH);
    result.resize(z.total_out); deflateEnd(&z);
    if (status != Z_STREAM_END) throw std::runtime_error("compression failed");
    return result;
}
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    try {
        std::ifstream file(argv[1], std::ios::binary);
        std::vector<uint8_t> seed{std::istreambuf_iterator<char>(file), {}};
        memory image; image.load_bytes(seed.data(), seed.size());
        std::vector<uint8_t> raw(MEMSIZ*2);
        for (int i = 0; i < MEMSIZ; ++i) {
            const uint16_t v = image.memref(i-MEMSIZ/2).to_int();
            raw[i*2] = v & 255; raw[i*2+1] = v >> 8;
        }
        std::mt19937 random(0x7465726e);
        unsigned accepted = 0, rejected = 0;
        for (unsigned trial = 0; trial < 4096; ++trial) {
            auto bytes = trial%3 ? seed : raw;
            for (unsigned n = 1+random()%8; n; --n) bytes[random()%bytes.size()] ^= uint8_t(1+random()%255);
            if (trial%7 == 0) bytes.resize(random()%bytes.size());
            if (trial%11 == 0) bytes.insert(bytes.end(), 1+random()%64, uint8_t(random()));
            // Re-encode mutated payloads with a valid CRC to reach tryte validation.
            if (trial%6 == 0) bytes = gzip(bytes);
            const int before = image.memref(0).to_int();
            try { image.load_bytes(bytes.data(), bytes.size()); ++accepted; }
            catch (const std::runtime_error&) {
                ++rejected;
                if (image.memref(0).to_int() != before) throw std::logic_error("Rejected mutation changed memory");
            }
        }
        if (!accepted || !rejected) throw std::logic_error("Expected both valid and invalid mutations");
        std::cout << "PASS 4096 seeded image mutations: " << accepted << " accepted, " << rejected << " rejected\n";
    } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
