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

/* Mac fork security hardening — 2026-09-25. Checked host arithmetic, bounded
 * image input and guest diagnostics; original authorship and license retained. */

/* Mac fork modification notice — 2026-09-24
 * Maintained by Vinny Lingham (https://github.com/Gyfted).
 * Make host file access and saving explicit; release mounted resources.
 * Original authorship and GPL-2.0-or-later terms are retained.
 * See docs/PORTING.md for provenance and details.
 */

#include "disk.h"

disk::disk(machine* m) {
	this->m = m;
	this->is_loaded = false;
	this->filename = NULL;
	this->page = "DDD";
}

disk::~disk() { unload(); }

void disk::load(const char* filename) {
	if(!filename) return;


	memory::load(filename);
	if(is_loaded) unload();

	this->filename = strdup(filename);
	is_loaded = true;
}

void disk::unload() {
	if(!is_loaded) return;

	is_loaded = false;
	if(filename) free(filename);
	filename = NULL;
}

/* Floppy disk communication works through the memory position
 * DDD:DDA. In general, the A specifies the operation
 * (see enumeration in disk.h), and Y the memory position in the
 * machine. The disk keeps track of it's internal position, which
 * auto increments after reading or writing. It can be manually set
 * with seek, and checked with getpos. It will wrap around from 444:444
 * to DDD:DDD. 
 *
 * Whenever data has been written, a sync call must be
 * made to actually write it to disk.
 *
 */

void disk::heartbeat() {
	static int offset = tryte::word_to_int("DDD", "DDA");
	tryte &d = m->memref(offset);
	switch(d.to_int()) {
		case DISKOP_NOOP: return;
		case DISKOP_READ: read(); break;
		case DISKOP_WRITE: write(); break;
		case DISKOP_SYNC: {
			// Host saves are explicit through the native app. Guest writes stay in memory.
		     } break;
		case DISKOP_SEEK: seek(m->A); break;
		case DISKOP_GETPOS: m->A = getpos(); break;
		case DISKOP_STATUS: m->A = is_loaded; break;
		case DISKOP_UNLOAD: unload(); break;
		case DISKOP_LOAD: do_load(); break;

		default: if (m->allow_diagnostic()) printf("Unknown disk operation %d\n", d.to_int());
	}

	d = DISKOP_NOOP;
}
void disk::read() {
	for(int o = -364; o <= 364; o++) {
		int diskpos = tryte::word_to_int(page, o);
		int mempos = tryte::word_to_int(m->Y, o);

		m->memref(mempos) = memref(diskpos);
	}

	page = page + 1;
}

void disk::write() {
	for(int o = -364; o <= 364; o++) {
		int diskpos = tryte::word_to_int(page, o);
		int mempos = tryte::word_to_int(m->Y, o);

		memref(diskpos) = m->memref(mempos);
	}

	page = page + 1;
}

void disk::seek(const tryte& t) {
	page = t;
}

void disk::status() {
	m->A = is_loaded;
}

tryte disk::getpos() const {
	return page;
}

void disk::do_load() {
    // Select host files through the native Mount Disk panel.
    // Guest code cannot open arbitrary host paths.
    status();
}
