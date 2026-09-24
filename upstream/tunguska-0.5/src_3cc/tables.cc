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
#include "tables.h"
#include "function.h"
#include "variable.h"

const symbol_table_entry* symbol_table::lookup(const char* name) {
	if(function::get_current()) {
		try { 
			return function::get_current()->sym_ref(name);
		} catch(std::invalid_argument* e) { }
	}

	if(variable_set::glob_instance()->is_var(name)) {
		int offset = variable_set::glob_instance()->get_offset(name);
		variable* v = variable_set::glob_instance()->get_variable(name);
	
		return new symbol_table_entry(name, offset, v);
	}

	throw new runtime_error("Symbol lookup failure");
}
