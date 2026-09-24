// SPDX-License-Identifier: GPL-2.0-or-later
#include "runtime.h"
#include <iostream>
int main(int argc, char** argv) {
    if (argc < 2 || argc > 3) {
        std::cerr << "Usage: tunguska-cli image.ternobj [command]\n";
        return 1;
    }
    try {
        tunguska::Runtime runtime(argv[1]);
        runtime.run(500000);
        if (argc == 3) {
            for (char c : std::string(argv[2]) + '\n') { runtime.key(c); runtime.run(10000); }
            runtime.run(500000);
        }
        runtime.capture(true);
        std::cout << runtime.text();
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
