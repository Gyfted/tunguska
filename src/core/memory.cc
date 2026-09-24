/* Tunguska, ternary virtual machine
 *
 * Copyright (C) 2007,2008 Viktor Lofgren
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

/* Mac fork modification notice — 2026-09-24
 * Maintained by Vinny Lingham (https://github.com/Gyfted).
 * Validate images transactionally and encode little-endian storage explicitly.
 * Save through a temporary sibling file and atomic replacement; add const reads.
 * Original authorship and GPL-2.0-or-later terms are retained.
 * See docs/PORTING.md for provenance and details.
 */
// Mac port: validate complete images and encode their historical little-endian format.
#include "memory.h"
#include "values.h"
#include <zlib.h>
#include <cstdint>
#include <memory>
#include <vector>
#include <filesystem>
#include <cerrno>
#include <sys/stat.h>
#include <unistd.h>

void memory::load(const char* filename) {
    if (!filename) throw std::runtime_error("No image path supplied");
    std::unique_ptr<gzFile_s, decltype(&gzclose)> file(gzopen(filename, "rb"), gzclose);
    if (!file) throw std::runtime_error("Cannot open memory image");
    std::vector<unsigned char> bytes(MEMSIZ * 2 + 1);
    const int count = gzread(file.get(), bytes.data(), static_cast<unsigned>(bytes.size()));
    if (count != MEMSIZ * 2) throw std::runtime_error("Invalid image: expected 531441 little-endian trytes");
    int code = Z_OK;
    gzerror(file.get(), &code);
    if (code != Z_OK && code != Z_STREAM_END) throw std::runtime_error("Corrupt compressed image");
    std::vector<int> values(MEMSIZ);
    for (int i = 0; i < MEMSIZ; ++i) {
        int value = bytes[2*i] | (int(bytes[2*i+1]) << 8);
        if (value >= 32768) value -= 65536;
        if (value < -364 || value > 364) throw std::runtime_error("Invalid image: tryte outside -364...364");
        values[i] = value;
    }
    for (int i = 0; i < MEMSIZ; ++i) mem[i] = values[i];
}

void memory::save(const char* filename) {
    if (!filename || !*filename) throw std::runtime_error("No output path supplied");
    std::vector<unsigned char> bytes(MEMSIZ * 2);
    for (int i = 0; i < MEMSIZ; ++i) {
        const auto value = static_cast<uint16_t>(mem[i].to_int());
        bytes[2*i] = value & 255;
        bytes[2*i+1] = value >> 8;
    }
    struct stat previous;
    const bool exists = lstat(filename, &previous) == 0;
    if (exists && !S_ISREG(previous.st_mode))
        throw std::runtime_error("Choose a regular output file, not a directory or symbolic link");
    if (!exists && errno != ENOENT) throw std::runtime_error("Cannot inspect output path");

    // The sibling stays on the same filesystem, so rename is atomic. RAII also
    // removes partial output after compression, disk-full, or rename failures.
    struct Temporary {
        std::string path;
        int fd = -1;
        ~Temporary() { if (fd >= 0) { close(fd); if (!path.empty()) unlink(path.c_str()); } }
    } temporary;
    auto parent = std::filesystem::path(filename).parent_path();
    if (parent.empty()) parent = ".";
    temporary.path = (parent / ".tunguska-save-XXXXXX").string();
    temporary.fd = mkstemp(temporary.path.data());
    if (temporary.fd < 0) throw std::runtime_error("Cannot create temporary image in the output folder");
    if (exists && fchmod(temporary.fd, previous.st_mode & 0777) != 0)
        throw std::runtime_error("Cannot preserve output file permissions");
    const int compressedFD = dup(temporary.fd);
    if (compressedFD < 0) throw std::runtime_error("Cannot open compressed output");
    std::unique_ptr<gzFile_s, decltype(&gzclose)> file(gzdopen(compressedFD, "wb9"), gzclose);
    if (!file) { close(compressedFD); throw std::runtime_error("Cannot create compressed output"); }
    if (gzwrite(file.get(), bytes.data(), static_cast<unsigned>(bytes.size())) != int(bytes.size()))
        throw std::runtime_error("Unable to write complete memory image");
    if (gzclose(file.release()) != Z_OK) throw std::runtime_error("Unable to finish memory image");
    if (fsync(temporary.fd) != 0) throw std::runtime_error("Unable to flush memory image");
    if (rename(temporary.path.c_str(), filename) != 0)
        throw std::runtime_error("Unable to replace memory image; the original file was preserved");
    temporary.path.clear();
}

tryte& memory::memref(int pos) {
    return const_cast<tryte&>(static_cast<const memory&>(*this).memref(pos));
}
const tryte& memory::memref(int pos) const {
    const int64_t shifted = int64_t(pos) + MEMSIZ/2;
    const auto index = (shifted % MEMSIZ + MEMSIZ) % MEMSIZ;
    return mem[index];
}
tryte& memory::memrefi(int high, int low) { return memref(PODWORD_TO_INT(high, low)); }
tryte& memory::memref(const tryte& high, const tryte& low) {
    return memref(tryte::word_to_int(high, low));
}
