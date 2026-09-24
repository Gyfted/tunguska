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
 * Use modern exceptions, a memory-size constant, and noncopyable ownership.
 * Provide const memory access for read-only debugger inspection.
 * Original authorship and GPL-2.0-or-later terms are retained.
 * See docs/PORTING.md for provenance and details.
 */

#include "tryte.h"
#include <stdexcept>

#ifndef memory_h
#define memory_h

inline constexpr int MEMSIZ = 729 * 729;

class memory { 
	public:
		memory() {
			mem = new tryte[MEMSIZ];
		}
		~memory() { delete[] mem; }
		memory(const memory&) = delete;
		memory& operator=(const memory&) = delete;
		tryte& memref(int pos);
		const tryte& memref(int pos) const;
		tryte& memref(const tryte& low, const tryte& high);
		tryte& memrefi(int low, int high);

		/* Memory image management */
		void load(const char* filename);
		void save(const char* filename);
	protected:
		/* Virtual memory */
		tryte* mem;
};


#endif
