/* Modified 2026-09-24 for the independent Mac fork: C++17 portability and error handling. */
#include "tables.h"
#include "function.h"
#include "variable.h"

const symbol_table_entry* symbol_table::lookup(const char* name) {
	if(function::get_current()) {
		try { 
			return function::get_current()->sym_ref(name);
		} catch(const std::invalid_argument& e) { }
	}

	if(variable_set::glob_instance()->is_var(name)) {
		int offset = variable_set::glob_instance()->get_offset(name);
		variable* v = variable_set::glob_instance()->get_variable(name);
	
		return new symbol_table_entry(name, offset, v);
	}

	throw runtime_error("Symbol lookup failure");
}
