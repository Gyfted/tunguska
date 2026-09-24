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
    if (!filename) throw std::runtime_error("No output path supplied");
    std::unique_ptr<gzFile_s, decltype(&gzclose)> file(gzopen(filename, "wb9"), gzclose);
    if (!file) throw std::runtime_error("Cannot create memory image");
    std::vector<unsigned char> bytes(MEMSIZ * 2);
    for (int i = 0; i < MEMSIZ; ++i) {
        const auto value = static_cast<uint16_t>(mem[i].to_int());
        bytes[2*i] = value & 255;
        bytes[2*i+1] = value >> 8;
    }
    if (gzwrite(file.get(), bytes.data(), static_cast<unsigned>(bytes.size())) != int(bytes.size()))
        throw std::runtime_error("Unable to write complete memory image");
    if (gzclose(file.release()) != Z_OK) throw std::runtime_error("Unable to finish memory image");
}

tryte& memory::memref(int pos) {
    const int64_t shifted = int64_t(pos) + MEMSIZ/2;
    const auto index = (shifted % MEMSIZ + MEMSIZ) % MEMSIZ;
    return mem[index];
}
tryte& memory::memrefi(int high, int low) { return memref(PODWORD_TO_INT(high, low)); }
tryte& memory::memref(const tryte& high, const tryte& low) {
    return memref(tryte::word_to_int(high, low));
}
