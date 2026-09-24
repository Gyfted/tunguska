/* Modified 2026-09-24 for the independent Mac fork: C++17 portability and error handling. */
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
 
// The historical AST/type graph still contains process-lifetime allocations.
// This compiler is a short-lived tool, not an in-process compilation service.

#include "compiler.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "type.h"
#include "variable.h"
#include <stdarg.h>
#include <fstream>
#include <unistd.h>
#include <filesystem>
#include <sys/stat.h>
#include <vector>
#include <cerrno>

extern int yyparse();


extern int atoinontri(const char* c);

compiler::compiler() : origin(0), PA(false), PXY(false), line(1), effective_filename("<input>"), filename("<input>") {
	lexer = new yyFlexLexer();
	output = tmpfile();
	if (!output) throw runtime_error("Cannot create compiler staging file");
}

compiler::~compiler() {
	delete lexer;
	fclose(output);
}
void compiler::pushA() {
	if(PXY) { PXY=false; this->printf("		PHX\n		PHY\n"); }
	else if(PA) { this->printf("		PSH	A\n"); }
	PA = true;
}

void compiler::pushXY()	{
	if(PA) { PA = false;this->printf("		PSH	A\n"); }
	else if(PXY) { this->printf("		PHX\n		PHY\n"); }
	PXY = true;
}

void compiler::pullA() {
	if(PXY) { PXY = false; this->printf("		PHX\n		PHY\n");  }
	if(PA) { PA = false; return; }
	else this->printf("		PLL	A\n");
}
void compiler::pullXY() {
	if(PA) { PA = false; this->printf("		PSH	A\n"); }
	if(PXY) { PXY = false; return; }
	else this->printf("		PLY\n		PLX\n");
}

int compiler::printf(const char* arg, ...) {
	if(PA) { PA = false; this->printf("		PSH	A\n"); }
	if(PXY) { PXY = false; this->printf("		PHX\n		PHY\n");  }

	va_list t;
	va_start(t, arg);
	int ret = vfprintf(output, arg, t);
	va_end(t);

	return ret;
}

void compiler::decl_struct(const char* name, t_struct* typ) {
	if(structs.find(name) != structs.end()) {
		if(*structs[name] != *typ)
			throw runtime_error("Redeclaration of struct");
		return;
	}

	structs[name] = typ;
}

t_struct* compiler::struct_ref(const char* name) const {
	if(structs.find(name) != structs.end())
		 return (*structs.find(name)).second;

	throw runtime_error("Unknown struct: " + std::string(name));

}
void compiler::decl_fun(const char* name, const function_prototype& fp) {
	if(functions.find(name) != functions.end()) {
		const function_prototype& fp2 = functions.at(name);
		if(fp2 != fp) {
			throw runtime_error("Conflicting function declaration: " + std::string(name));
		}
	} else functions.emplace(name, fp);
}

const function_prototype& compiler::fun_ref(const char* name) const {
	if(functions.find(name) != functions.end())
		 return (*functions.find(name)).second;

	throw runtime_error("Unknown function: " + std::string(name));

}
void cio::op(const char* op, const char* arg) {
	if(arg) printf("	%s	%s\n", op, arg);
	else printf("	%s\n", op);
}

void cio::label(const char* name) {
	printf("%s:\n", name);
}

void compiler::pragma(const char* command, int data) {
	if(strcasecmp(command, "ORIGIN") == 0) {
		compiler::printf("@ORG	%d\n", data);
	} else {
		compiler::printf("; Unrecognized pragma %s = %d\n", command, data);
	}
}

void compiler::pragma(const char* command) {
	if(strcasecmp(command, "SCL") == 0) {
		compiler::printf("@EQU	__CURRENT_LOCATION	$$\n");
	} else if(strcasecmp(command, "RCL") == 0) {
		compiler::printf("@ORG	__CURRENT_LOCATION+1\n");
	} else {
		compiler::printf("; Unrecognized pragma %s\n", command);
	}
}

void compiler::begin() {
	compiler::printf("@EQU	tmp	%%DDD443\n");
}

void compiler::compile_file(const char* filename) {
	this->filename = filename;
	this->effective_filename = filename;
	this->line = 1;

	if (!std::filesystem::is_regular_file(filename) || std::filesystem::file_size(filename) > 4*1024*1024)
		throw runtime_error("Input must be a regular file no larger than 4 MiB");
	std::ifstream stream(filename);
	if (!stream) throw runtime_error("Cannot open input file");
	lexer->yyrestart(&stream);
	if (yyparse() != 0 || stream.bad()) throw runtime_error("Cannot parse input file");
}
void compiler::set_output(const char* outfile) { output_name = outfile; }

void compiler::finish() {
	if (fflush(output) || ferror(output) || fseek(output, 0, SEEK_SET))
		throw runtime_error("Cannot finalize compiler output");
	FILE* destination = stdout;
	std::string temporary;
	if (!output_name.empty()) {
		struct stat info;
		if (lstat(output_name.c_str(), &info) == 0 && !S_ISREG(info.st_mode))
			throw runtime_error("Output must be a regular file, not a symlink or device");
		std::string pattern = output_name + ".XXXXXX";
		std::vector<char> path(pattern.begin(), pattern.end()); path.push_back(0);
		int fd = mkstemp(path.data());
		if (fd < 0) throw runtime_error("Cannot create output file");
		temporary = path.data();
		destination = fdopen(fd, "w");
		if (!destination) { close(fd); unlink(temporary.c_str()); throw runtime_error("Cannot open output stream"); }
	}
	bool failed = false;
	char buffer[16384]; size_t count;
	while ((count = fread(buffer, 1, sizeof(buffer), output)))
		if (fwrite(buffer, 1, count, destination) != count) { failed = true; break; }
	failed = ferror(output) || fflush(destination) || failed;
	if (destination != stdout) {
		if (fsync(fileno(destination))) failed = true;
		if (fclose(destination)) failed = true;
		if (!failed && rename(temporary.c_str(), output_name.c_str())) failed = true;
		if (failed) unlink(temporary.c_str());
	}
	if (failed) throw runtime_error("Failed to write compiler output");
}

int yylex() { return compiler::instance()->get_lexer()->yylex(); }

compiler* compiler::compiler_instance = 0;

void help(const char* command) {
	printf("Usage: %s [-h] [-o filename] [-O origin] file1 [file2 ... fileN]\n", command);
	printf("	 -o	 Set output file\n");
	printf("	 -O	 Set origin\n");
	printf("	 -h	 Show this screen\n\n");
}

int main(int argc, char* argv[]) {
    compiler* c = nullptr;
    try {
        c = compiler::instance();
        int origin = 0, optret;
        const char* outfile = nullptr;
        while ((optret = getopt(argc, argv, "ho:O:")) != -1) {
            switch (optret) {
                case 'h': help(argv[0]); return EXIT_SUCCESS;
                case 'o': outfile = optarg; break;
                case 'O': origin = atoinontri(optarg); break;
                default: return EXIT_FAILURE;
            }
        }
        if (optind == argc) { help(argv[0]); return EXIT_FAILURE; }
        if (outfile) c->set_output(outfile);
        c->begin();
        c->printf("@ORG\t%d\n", origin);
        for (int i = optind; i < argc; ++i) c->compile_file(argv[i]);
        c->printf("; Begin string constants\n");
        c->get_mmgr()->define();
        c->printf("; Define variable stack pointer\n__VSS:\t@DT %%444\n");
        c->printf("@ORG\t%%CAADDD\n; Define variable stack\n@REST\t%%444\n__VS @EQU %%CAA000\n");
        c->finish();
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        fprintf(stderr, "%s:%d: error: %s\n", c ? c->get_effective_file() : "3cc",
                c ? c->get_line() : 0, error.what());
        return EXIT_FAILURE;
    }
}
