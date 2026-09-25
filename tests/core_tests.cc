// SPDX-License-Identifier: GPL-2.0-or-later
#include "runtime.h"
#include "core/values.h"
#include "display_protocol.h"
#include <climits>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <zlib.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <signal.h>
#include <unistd.h>

void debuggerTests(const char* image);

static void check(bool ok, const char *message) {
    if (!ok) throw std::runtime_error(message);
}
static int wrap(int64_t n, int base = 729) {
    return int(((n + base/2) % base + base) % base - base/2);
}
static int sign(int n) { return (n > 0) - (n < 0); }
static void command(tunguska::Runtime& r, const std::string& text) {
    for (char c : text + '\n') { r.key(c); r.run(10000); }
    r.run(500000);
    r.capture(true);
}
int main(int argc, char **argv) {
    try {
        check(argc == 2, "Pass the boot image path");
        for (int i = -364; i <= 364; ++i) {
            tryte t(i);
            check(t.to_int() == i, "tryte roundtrip");
            char nonary[4]; snprintf(nonary, sizeof(nonary), "%03X", t.nonaryhex());
            check(tryte(nonary).to_int() == i, "nonary roundtrip");
            for (int j = -364; j <= 364; ++j) {
                check((t + j).to_int() == wrap(i+j), "tryte addition");
                check((t * tryte(j)).to_int() == wrap(i*j), "tryte multiplication");
            }
        }
        for (int i = -265720; i <= 265720; ++i) {
            tryte high, low; tryte::int_to_word(i, high, low);
            check(tryte::word_to_int(high, low) == i, "word roundtrip");
        }
        std::cout << "PASS exhaustive tryte arithmetic and 531441 word roundtrips\n";

        machine cpu;
        for (int a = -364; a <= 364; ++a) for (int b = -364; b <= 364; ++b) {
            for (int carry = -1; carry <= 1; ++carry) {
                cpu.PCH = cpu.PCL = 0; cpu.A = a; cpu.P = 0; cpu.P[machine::C] = carry;
                cpu.memref(0) = machine::qop(machine::IMMEDIATE, machine::ADD); cpu.memref(1) = b;
                cpu.instruction(); const int sum = a+b+carry;
                const int overflow = sum > 364 ? 1 : sum < -364 ? -1 : 0;
                check(cpu.A.to_int() == wrap(sum), "ADD result");
                check(cpu.P[machine::V].to_int() == overflow, "ADD overflow flag");
                check(cpu.P[machine::C].to_int() == overflow, "ADD carry flag");
                check(cpu.P[machine::G].to_int() == sign(wrap(sum)), "ADD sign flag");
            }
            cpu.PCH = cpu.PCL = 0; cpu.A = a; cpu.P = 0;
            cpu.memref(0) = machine::qop(machine::IMMEDIATE, machine::CMP); cpu.memref(1) = b;
            cpu.instruction();
            check(cpu.A.to_int() == a, "CMP preserves accumulator");
            check(cpu.P[machine::G].to_int() == sign(wrap(a-b)), "CMP result flag");
            check(cpu.P[machine::V].to_int() == (a-b > 364 ? 1 : a-b < -364 ? -1 : 0), "CMP overflow flag");
        }
        check(std::string(machine::opcode_to_string(40)) == "DEBUG", "last opcode lookup");
        check(ternarytoascii(100) == 0, "character map bounds");
        for (int i = 0; i < 10000; ++i) cpu.queue_interrupt(new clock_interrupt());
        check(cpu.pending_interrupts() == 1, "clock interrupts coalesce");
        for (int i = 0; i < 10000; ++i) cpu.queue_interrupt(new keyboard_interrupt(10));
        check(cpu.pending_interrupts() == 4096, "interrupt queue remains bounded");
        for (int n : {INT_MIN, -265721, -265720, 265720, 265721, INT_MAX})
            check(&cpu.memref(n) == &cpu.memref(wrap(n, MEMSIZ)), "memory wraps at boundaries");
        std::cout << "PASS 2.1 million ADD/CMP cases, opcode and memory boundaries\n";

        char directory[] = "/tmp/tunguska-tests-XXXXXX";
        check(mkdtemp(directory), "temporary directory");
        const auto image = std::string(directory) + "/image.ternobj";
        cpu.memref(-265720) = -364; cpu.memref(265720) = 364;
        cpu.save(image.c_str());
        memory restored; restored.load(image.c_str());
        check(restored.memref(-265720).to_int() == -364 && restored.memref(265720).to_int() == 364, "image save/load");
        auto bytes = [](const std::string& path) {
            std::ifstream file(path, std::ios::binary);
            return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
        };
        const std::string original = bytes(image);
        // Force an actual write failure after opening the temporary compressed
        // file, without filling the user's disk or changing the parent limit.
        const pid_t child = fork();
        check(child >= 0, "start save-failure test");
        if (child == 0) {
            signal(SIGXFSZ, SIG_IGN);
            struct rlimit limit = {128, 128};
            if (setrlimit(RLIMIT_FSIZE, &limit) != 0) _exit(2);
            try { cpu.save(image.c_str()); } catch (const std::runtime_error&) { _exit(0); }
            _exit(1);
        }
        int status = 0;
        check(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0, "compressed save reports write failure");
        check(bytes(image) == original, "failed save preserves original file byte for byte");
        check(std::distance(std::filesystem::directory_iterator(directory), std::filesystem::directory_iterator{}) == 1, "failed save removes temporary output");
        check(chmod(image.c_str(), 0640) == 0, "set output permissions");
        restored.memref(0) = 123; restored.save(image.c_str());
        memory replaced; replaced.load(image.c_str());
        check(replaced.memref(0).to_int() == 123, "atomic replacement publishes new image");
        struct stat metadata;
        check(stat(image.c_str(), &metadata) == 0 && (metadata.st_mode & 0777) == 0640, "replacement preserves permissions");
        const auto link = std::string(directory) + "/link.ternobj";
        check(symlink(image.c_str(), link.c_str()) == 0, "create test symlink");
        bool linkRejected = false;
        const auto replacedBytes = bytes(image);
        try { cpu.save(link.c_str()); } catch (const std::runtime_error&) { linkRejected = true; }
        check(linkRejected && std::filesystem::is_symlink(link) && bytes(image) == replacedBytes, "save refuses symbolic links without modifying target");
        auto rejects = [&](const std::string& path) {
            bool rejected = false;
            try { restored.load(path.c_str()); } catch (const std::runtime_error&) { rejected = true; }
            check(rejected, "reject malformed image");
            check(restored.memref(-265720).to_int() == -364, "failed load preserves memory");
        };
        rejects(std::string(directory)+"/missing");
        std::ofstream(image, std::ios::binary | std::ios::trunc) << "short";
        rejects(image);
        std::vector<unsigned char> invalid(MEMSIZ*2, 0); invalid[0]=255; invalid[1]=127;
        gzFile zipped = gzopen(image.c_str(), "wb"); gzwrite(zipped, invalid.data(), unsigned(invalid.size())); gzclose(zipped);
        rejects(image);
        std::filesystem::remove_all(directory);
        std::cout << "PASS atomic image saves, forced write failure, and malformed image rejection\n";

        debuggerTests(argv[1]);

        tunguska::Runtime runtime(argv[1]);
        runtime.run(500000); runtime.capture(true);
        check(runtime.text().find("TUNGUSKA STARTED") != std::string::npos, "original OS boot banner");
        command(runtime, "HELP");
        check(runtime.text().find("Available commands") != std::string::npos, "keyboard interrupts and HELP");
        const auto count = runtime.cycles(); runtime.setRunning(false);
        check(runtime.run(10000) == 0 && runtime.cycles() == count, "pause");
        runtime.step(); check(runtime.cycles() == count+1 && !runtime.running(), "single step");
        runtime.reset(argv[1]); check(runtime.cycles() == 0 && runtime.running(), "reset");
        runtime.run(500000); command(runtime, "BROWN");
        check(runtime.frame().mode == 1 && runtime.frame().vertices.size() == 243, "vector demo");
        runtime.reset(argv[1]); runtime.run(500000); command(runtime, "RASTERDEMO729");
        check(runtime.frame().mode == -1 && runtime.frame().auxiliary == 0, "729 color demo");
        runtime.reset(argv[1]); runtime.run(500000); command(runtime, "RASTERDEMO3");
        check(runtime.frame().mode == -1 && runtime.frame().auxiliary == 1, "3 color demo");
        runtime.reset(argv[1]); runtime.run(500000); command(runtime, "CHARMAP");
        check(runtime.frame().mode == 0, "character demo");
        // Palette attributes are signed trytes. Exercise every palette index,
        // every tone, both ends of the tables and the last framebuffer pixel.
        tryte pattern;
        for(int pixel=0;pixel<6;++pixel)pattern[pixel]=pixel%3-1;
        for(int p=0;p<729;++p) {
            runtime.cpu().memref(TG_VIDEO_BITMAP+p)=pattern;
            runtime.cpu().memref(TG_VIDEO_ATTRIBUTES+p)=p-364;
            for(int tone=0;tone<3;++tone)runtime.cpu().memref(TG_VIDEO_PALETTES+p*3+tone)=(p*3+tone)%729-364;
        }
        runtime.cpu().memref(TG_VIDEO_BITMAP+TG_VIDEO_WORDS-1)=pattern;
        runtime.cpu().memref(TG_VIDEO_ATTRIBUTES+TG_VIDEO_WORDS-1)=364;
        runtime.cpu().memrefi(TV_DDD,TV_DDB)=-11;
        runtime.capture();
        check(runtime.frame().mode==-1 && runtime.frame().auxiliary==-1,"palette raster mode");
        for(int p=0;p<729;++p)for(int pixel=0;pixel<6;++pixel) {
            const int color=(p*3+pixel%3)%729,offset=(p*6+pixel)*4;
            const auto& rgb=runtime.frame().pixels;
            check(rgb[offset]==28*(color/81) && rgb[offset+1]==28*(color/9%9) && rgb[offset+2]==28*(color%9) && rgb[offset+3]==255,
                  "palette raster differs from independent RGB reference");
        }
        const auto& rgb=runtime.frame().pixels;
        check(rgb[rgb.size()-4]==224 && rgb[rgb.size()-3]==224 && rgb[rgb.size()-2]==224,"last palette/framebuffer entry");
        auto& frameCPU = runtime.cpu();
        frameCPU.P[machine::I] = 1; frameCPU.PCH = frameCPU.PCL = 0;
        frameCPU.memref(0) = machine::qop(machine::ABS, machine::JMP);
        frameCPU.memref(1) = frameCPU.memref(2) = 0;
        frameCPU.memrefi(TV_DDD, TV_DDB) = 1;
        const auto revision = runtime.frame().revision;
        check(runtime.run(4096,0,true) == 1024 && runtime.frame().revision == revision+1,
              "interactive execution yields at the first captured frame");
        frameCPU.memrefi(TV_DDD, TV_DDB) = 1;
        check(runtime.run(4096) == 4096, "default execution keeps its instruction budget after capture");
        std::cout << "PASS original OS boot, HELP, pause/step/reset, character/vector/raster demos\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "FAIL: " << e.what() << '\n'; return 1;
    }
}
