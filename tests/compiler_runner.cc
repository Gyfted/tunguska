// SPDX-License-Identifier: GPL-2.0-or-later
// Execute generated guest code and check results independently of compiler output.
#include "runtime.h"
#include <iostream>
#include <stdexcept>

int main(int argc, char** argv) {
    try {
        if (argc < 2) throw std::runtime_error("Expected image and result words");
        tunguska::Runtime runtime(argv[1]);
        runtime.cpu().P[machine::I] = 1;
        for (int i = 0; i < 10000 && runtime.cpu().memref(100000).to_int() != 99; ++i)
            runtime.run(1000);
        if (runtime.cpu().memref(100000).to_int() != 99)
            throw std::runtime_error("Compiled guest did not complete within 10 million instructions");
        for (int i = 2; i < argc; ++i) {
            int address = 100010 + 2 * (i - 2);
            int actual = tryte::word_to_int(runtime.cpu().memref(address), runtime.cpu().memref(address+1));
            int expected = std::stoi(argv[i]);
            if (actual != expected)
                throw std::runtime_error("Result " + std::to_string(i-2) + ": expected " +
                                         std::to_string(expected) + ", got " + std::to_string(actual));
        }
        std::cout << "PASS compiled guest results\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
