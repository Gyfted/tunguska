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

/* Mac fork security fixes — 2026-09-25: checked numeric parsing and bounded
 * emission; original authorship and GPL-2.0-or-later terms retained. */

/* Mac fork modification notice — 2026-09-24
 * Maintained by Vinny Lingham (https://github.com/Gyfted).
 * C++17/macOS compatibility and explicit output error handling.
 * Original authorship and GPL-2.0-or-later terms are retained.
 * See docs/PORTING.md for provenance and details.
 */

#include <stdlib.h>
#include <stdio.h>
#include <map>
#include <string>
#include <getopt.h>
#include <iostream>
#include <fstream>
#include <sstream>
#include <cerrno>
#include <climits>
#include <cmath>
#include <filesystem>
#include <FlexLexer.h>
#include "machine.h"
#include "agdp.h"
#include "assembler.h"
#include "error.h"

using namespace std;

extern int yyparse();

int checked_assembly_integer(int64_t value) {
    if (value < INT_MIN || value > INT_MAX)
        throw new error(WHERE, "Integer expression exceeds the host integer range");
    return int(value);
}

int assembly_decimal(const char* text) {
    errno = 0;
    char* end = nullptr;
    const auto value = strtoll(text, &end, 10);
    if (errno || end == text || *end)
        throw new error(WHERE, "Invalid decimal integer");
    return checked_assembly_integer(value);
}

int assembly_quotient(int numerator, int denominator) {
    if (!denominator) {
        // A forward label is unresolved during the first pass.
        if (assembler::instance()->get_state() == INITIAL_SWEEP) return 0;
        throw new error(WHERE, "Division by zero");
    }
    return checked_assembly_integer(int64_t(numerator) / denominator);
}

/* C style global assembler helper functions
 * 
 *
 */



int lowtryte(int v) {
	tryte low, high;
	tryte::int_to_word(v, high, low);
	return low.to_int();
}
int hightryte(int v) {
	tryte low, high;
	tryte::int_to_word(v, high, low);
	return high.to_int();
}

int nontriplet(char* s) {
	tryte t = (s+1);
	return t.to_int();
}

int nonsextet(char* s) {
	if(strlen(s) != 7) throw new error(WHERE, "Bad nonary sextet");
	char s1[4];
	char s2[4];
	s1[0] = s[1]; s1[1] = s[2]; s1[2] = s[3]; s1[3] = 0;
	s2[0] = s[4]; s2[1] = s[5]; s2[2] = s[6]; s2[3] = 0;
	tryte high = s1, low = s2; 
	return tryte::word_to_int(high, low);
}

int floatval(char* s) {
	tryte high, low;
	errno = 0;
	char* end = nullptr;
	float f = strtof(s, &end);
	if(errno || end == s || *end != 'f' || end[1] || !std::isfinite(f)) {
		throw new error(WHERE, "Bad floating point value");
		return 0;
	}
	agdp::float2_to_float3(f, low, high);
	return tryte::word_to_int(low, high);
}
unsigned int strtoopc(char* s) {
	int i;
	for(i = -40; i <= 40; i++) {
		if(strcasecmp(s, machine::opcode_to_string(i)) == 0) {
			return i;
		}
	}

	string err = string("Couldn't identify opcode ") + s; 
	throw new error((WHERE), err);
}
bool islocal(const string& s) { 
	return s[0] == '.'; 
}
/* Source class stuff
 *
 *
 *
 */

source::source(const char* filename) {
	this->filename = filename;
	std::error_code ec;
	if (!std::filesystem::is_regular_file(filename, ec) || ec ||
	    std::filesystem::file_size(filename, ec) > 4 * 1024 * 1024 || ec)
		throw new error(WHERE, "Source must be a regular file no larger than 4 MiB");
	this->filestream = std::make_shared<ifstream>(filename);
	this->line = 1;
}

source::source(const source& s) {
	this->filename = s.filename;
	this->filestream = s.filestream;
	this->line = s.line;	
}


/* Assembler class functions go here
 *
 *
 *
 *
 */

/* Set origin */
void assembler::org(int p) { 
	if (p < -MEMSIZ/2 || p > MEMSIZ/2)
		throw new error(WHERE, "Origin is outside guest memory");
	pc = p; 
}

/* Define tryte */
void assembler::dt(int v) { 
	if (emitted >= MEMSIZ) throw new error(WHERE, "Output exceeds guest memory");
	++emitted;
	m.memref(pc) = v;
	pc = pc == MEMSIZ/2 ? -MEMSIZ/2 : pc + 1;
}

/* Define string of trytes */
void assembler::dtstring(const char* s) {
	while(*s) {
		dt(asciitoternary(*s));
		s++;
	}
}

/* Define word */
void assembler::dw(int v) { 
	tryte high, low;
	tryte::int_to_word(v, high, low);
	dt(high.to_int()); dt(low.to_int());
}

void assembler::reserve(int count, int value) {
    if (count < 0 || size_t(count) > MEMSIZ - emitted)
        throw new error(WHERE, "Reservation exceeds remaining guest memory");
    for (int n = 0; n < count; ++n) dt(value);
}

int assembler::lineno() {
	return sources.top().lineno();
}

void assembler::inc_line() {
	sources.top().inc_line();
}

/* Create a variable */
void assembler::equ(const char* c, int p) { 
	if(!islocal(c)) { /* Global variable */
		variables[c] = p; 
		variable_tracker.insert(pair<string, string>(sources.top().get_filename(), c));
		return;
	} else { /* Local variable, need to find parent and store it's full name,
       		    so .foo will be stored as bar.foo */

		map<string,int>::iterator closest = labels.end();
		
		/* Iterate through the list of labels and find the closest label
		 * that is no greater than PC */ 
		for(map<string,int>::iterator i = labels.begin();
				i != labels.end(); i++) {
			if((*i).first.find(".", 0) < (*i).first.npos) continue;
			if((*i).second <= pc) {
				if(closest == labels.end() ||
					((*closest).second < (*i).second)) {
					closest = i;
				}
			}
		}

		/* Add variable with full name */
		if(closest != labels.end()) {
			string name = (*closest).first + string(c);
			equ(name.c_str(), p);
		} else throw new error(WHERE, string("Unable to add local variable ") + c);
	}
}



/* Define a label */
void assembler::ldef(const char* c) { 
	if(!islocal(c)) { /* Global */
		if(labels.find(c) != labels.end()) {
			if(state == INITIAL_SWEEP) printf("Warning! Redefining '%s'\n", c);
		}
		labels[c] = pc; 
		label_tracker.insert(pair<string, string>(sources.top().get_filename(), c));

		return;
	} else { /* Local -- same algorithm as equ. See equ's coments for further
       				desc. */
		map<string,int>::iterator closest = labels.end();
		
		for(map<string,int>::iterator i = labels.begin();
				i != labels.end(); i++) {
			if((*i).first.find(".", 0) < (*i).first.npos) continue;
			if((*i).second <= pc) {
				if(closest == labels.end() ||
					((*closest).second < (*i).second)) {
					closest = i;
				}
			}
		}

		if(closest != labels.end()) {
			string name = (*closest).first + string(c);
			ldef(name.c_str());
		} else throw new error(WHERE, string("Unable to add local variable ") + c);
	}
}

/* Evaluate label or label */
int assembler::label_eval(const char* c) { 
	if(islocal(c)) { /* Local label */
		map<string,int>::iterator closest = labels.end();
		
		/* Find the parent */
		for(map<string,int>::iterator i = labels.begin();
				i != labels.end(); i++) {
			if((*i).first.find(".", 0) < (*i).first.npos) continue;
			if((*i).second <= pc) {
				if(closest == labels.end() ||
						((*closest).second <
						 (*i).second)) {
					closest = i;
				}
			}
		}

		if(closest != labels.end()) {
			string name = (*closest).first + string(c);

			/* Recurse with the full name */
			return label_eval(name.c_str());
		} else {
			string err = string("Unable to evaluate local variable ") + c;
			throw new error(WHERE, err);
		}
	}

	/* Try looking in labels and variables */
	if(labels.find(c) != labels.end()) {
		return labels[c]; 
	} else if(variables.find(c) != variables.end()) {
		return variables[c];
	}

	if(state == FINAL_SWEEP) {
		string err = string("Unresolved varaible ") + c;
		throw new error(WHERE, err);
	}
	else return 0; // It's only the initial sweep
}

void assembler::addop(char* c, op_mode mode, int val) {
	/* Find numeric opcode */
	unsigned int opc = strtoopc(c);

	/* Add opcode to memory */
	switch(mode) {
		case OP_IMPLICIT: 
			dt(m.qop(machine::IMPLICIT, opc).to_int()); break;
		case OP_ACC: 
			dt(m.qop(machine::ACC, opc).to_int()); break;
		case OP_XY: 
			dt(m.qop(machine::XY, opc).to_int()); break;
		case OP_IMMEDIATE: 
			dt(m.qop(machine::IMMEDIATE, opc).to_int()); break;
		case OP_ABSOLUTE: 
			dt(m.qop(machine::ABS, opc).to_int()); break;
		case OP_ABSOLUTE_X: 
			dt(m.qop(machine::AX, opc).to_int()); break;
		case OP_ABSOLUTE_Y: 
			dt(m.qop(machine::AY, opc).to_int()); break;
		case OP_INDIRECT: 
			dt(m.qop(machine::INDIRECT, opc).to_int()); break;
		case OP_INDIRECT_X: 
			dt(m.qop(machine::INDX, opc).to_int()); break;
		case OP_INDIRECT_Y: 
			dt(m.qop(machine::INDY, opc).to_int()); break;
	}

	/* Add operation argument(s) */
	if(mode == OP_IMMEDIATE) { dt(val); }
	else if(mode > OP_IMMEDIATE) { 
		dw(val);
	}
}

/* Print a bunch of debug info */
void assembler::verbose_info() {
	printf("LABELS:\n");
	printf("%40s\t%7s\t%7s\n", "LABEL", "DEC", "NON");
	multimap<string, string>::iterator prev = label_tracker.end();

	for(multimap<string, string>::iterator i = label_tracker.begin();
			i != label_tracker.end(); i++) {
		tryte high, low;
		int v = labels[(*i).second];
		tryte::int_to_word(v, high, low);
		if(prev == label_tracker.end() || 
				(*prev).first != (*i).first) {
			printf("%s:\n", (*i).first.c_str());
		}

		printf("%40s\t%7.6d\t%.3X:%.3X\n", (*i).second.c_str(),
			       	labels[(*i).second],
				high.nonaryhex(), low.nonaryhex());
		prev = i;
		
	} 

	printf("VARIABLES:\n");
	printf("%40s\t%7s\t%7s\n", "LABEL", "DEC", "NON");

	prev = variable_tracker.end();
	for(multimap<string, string>::iterator i = variable_tracker.begin();
			i != variable_tracker.end(); i++) {
		tryte high, low; 
		tryte::int_to_word(variables[(*i).second], high, low);
		
		if(prev == variable_tracker.end() || 
				(*prev).first != (*i).first) {
			printf("%s:\n", (*i).first.c_str());
		} 

		printf("%40s\t%7.6d\t%.3X:%.3X\n", (*i).second.c_str(), variables[(*i).second],
				high.nonaryhex(), low.nonaryhex());
		prev = i; 
		
	} 
}

/* Include a source file 
 *
 * XXX: The recursion check is really underdimensioned.
 *
 */
void assembler::inc(const char* s) {
	sources.push(source(s));
	if(sources.top().get_fs()->fail()) {
		string ermsg = string("Error opening ") + s;
		throw new error(WHERE, ermsg, NULL);
	}

	lexer()->switch_streams(sources.top().get_fs(), NULL);

	if(sources.size() > 100) {
		throw new error(WHERE, "Over 100 files included? Smells of recursive inclusion :-(", NULL);
	}
}

/* Instantiation of assembler and lexer */
assembler* assembler::a_instance = NULL;
yyFlexLexer* assembler::l_instance = NULL;

assembler* assembler::instance() {
	if(a_instance == NULL) a_instance = new assembler();

	return a_instance;
}

yyFlexLexer* assembler::lexer() {
	if(l_instance == NULL) l_instance = new yyFlexLexer();
	return l_instance;
}


/* Read input files from program argument list */
void assembler::read_files(int argc, int findex, char** argv) {

	/* Iterate through program arguments */
	for(int i = findex; i < argc; i++) {

		if(strcmp(argv[i], "stdin") == 0) {
			printf("Sorry, no stdin, need to scan the file twice :-(\n");
			exit(EXIT_FAILURE);
		}

		/* Add source to source list */
		source source_file = source(argv[i]);
		sources.push(source_file);


		if(source_file.get_fs()->fail()) {
			throw new error(WHERE, 
					string("Unable to open ") + 
					source_file.get_filename()+ string(" for reading"));
		}


		try {
			/* inc() might add new sources to the source stack, so it's
			 * necessary to keep looping until the source stack is empty
			 * even if there initally is only one source on the stack. */
			do {
				lexer()->switch_streams(sources.top().get_fs(), NULL);
				yyparse();
				sources.pop();
			} while(!sources.empty());

		} catch (error* e) {
			ostringstream msgstr;
			msgstr << "Error during assembly of " << sources.top().get_filename() << ", line " << lineno();
			throw new error(WHERE, msgstr.str(), e);
			e->trace();
			printf("\n");
			exit(EXIT_FAILURE);
		}
	}


}


/* Used by the parser */
int yylex() { return assembler::lexer()->yylex(); }

void help(char* argv0) {
	printf("\nUsage: %s [-h] [-v] [-o outfile] file [file2 ... filen]\n"
		"\t-h\tThis message\n"
		"\t-v\tVerbose mode\n"
		"\t-o\tSpecify output file\n"
		"\n", argv0);
}


int main(int argc, char* argv[]) {
	bool verbose = false;
	int optret;
	const char* outfile = NULL;

	/* Check command arguments */
	while((optret = getopt(argc, argv, "o:hv")) != -1) {
		switch(optret) {
			case 'h': help(argv[0]); exit(EXIT_SUCCESS);
			case 'o': outfile = optarg; break;
			case 'v': verbose = true; break;
			case '?':
			case ':': help(argv[0]); exit(EXIT_FAILURE);
		}
	}
	if(outfile == NULL) outfile = "out.ternobj";
	int fileindex = optind;

	/* Initiation done */

	if(fileindex >= argc) {
		printf("No files to process\n");
		help(argv[0]);
		return EXIT_FAILURE;
	}
	
	try {
		/* Do the first assembly sweep */
		if(verbose) printf("Initial sweep...\n");
		assembler::instance()->set_state(INITIAL_SWEEP);
		assembler::instance()->set_pc(0);
		assembler::instance()->read_files(argc, fileindex, argv);
	} catch (error* e) {
		printf("\nCaught error during assembly (first sweep) \n\n");
		e->trace();
		printf("\n");
		return EXIT_FAILURE;
	}

	/* Print info about labels and variables if necessary */
	if(verbose) { assembler::instance()->verbose_info(); }

	try {
		/* Do the final assembly sweep */
		if(verbose) printf("Final sweep...\n");
		assembler::instance()->set_state(FINAL_SWEEP);
		assembler::instance()->set_pc(0);
		assembler::instance()->read_files(argc, fileindex, argv);
	} catch (error* e) {
		printf("\nCaught error during assembly (final sweep) \n\n");
		e->trace();
		printf("\n");
		return EXIT_FAILURE;
	}


	/* Save to disk */
	if(verbose) printf("Done.\n");

	try { assembler::instance()->save(outfile); }
    catch (const std::exception& e) {
        fprintf(stderr, "%s\n", e.what());
        return EXIT_FAILURE;
    }

	if(verbose) printf("Saved to '%s'.\n", outfile);

	return EXIT_SUCCESS;
}
