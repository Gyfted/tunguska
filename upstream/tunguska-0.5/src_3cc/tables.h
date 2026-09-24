/*  3cc - Ternary C Compiler for Tunguska
 *  Copyright (C) 2008  Viktor Lofgren
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#include "type.h"
#include "variable.h"
#ifndef tables_h
#define tables_h
class symbol_table_entry {
	public:
		~symbol_table_entry() {}// delete[] ename; }
		symbol_table_entry(const char* ename, int offset, variable* v) {
			this->ename = ename;
			this->offset = offset;
			this->var = v;
			this->typ = var->get_type();
		}

		const char* effective_name() const { return ename; };
		const type* get_type() const { return typ; };
		int get_offset() const { return offset; }
		variable* get_variable() const { return var; }
	private:
		const char* ename;
		const type* typ;
		variable* var;
		int offset;
};


class symbol_table {
public:
	static const symbol_table_entry* lookup(const char* name);
private:
	
};

#endif
