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
 
%option noyywrap
%option	yylineno
%{

#include "type.h"
#include "expression.h"
#include "parser.h"

extern void newline();
#include "checked.h"
#include <cerrno>
#include <cstdlib>
int atoinontri(const char* s) {
    if (s[0] == '0' && (s[1] == 'n' || s[1] == 't')) {
        const int base = s[1] == 'n' ? 9 : 3;
        s += 2;
        if (!*s) throw std::runtime_error("Empty ternary/nonary constant");
        int value = 0;
        for (; *s; ++s) {
            int digit;
            if (base == 9 && *s >= '0' && *s <= '4') digit = *s - '0';
            else if (base == 9 && (*s == 'A' || *s == 'Q')) digit = -1;
            else if (base == 9 && (*s == 'B' || *s == 'W')) digit = -2;
            else if (base == 9 && (*s == 'C' || *s == 'E')) digit = -3;
            else if (base == 9 && (*s == 'D' || *s == 'R')) digit = -4;
            else if (base == 3 && (*s == 'N' || *s == '-')) digit = -1;
            else if (base == 3 && (*s == '0' || *s == 'O')) digit = 0;
            else if (base == 3 && (*s == 'P' || *s == '+')) digit = 1;
            else throw std::runtime_error("Invalid ternary/nonary digit");
            value = checked_word(int64_t(value) * base + digit);
        }
        return value;
    }
    char* end = nullptr;
    errno = 0;
    long value = strtol(s, &end, 10);
    if (errno || !*s || *end) throw std::runtime_error("Invalid decimal constant");
    return checked_word(value);
}

int char_constant(char c) {
	char translation[] = {  0, ' ','\n','\t','\b',   0,  0,   0,   0,   0,
			    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
			    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
			    'U', 'V', 'W', 'X', 'Y', 'Z', '0', '1', '2', '3',
			    '4', '5', '6', '7', '8', '9', '.', ',', '!', '?',
			    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
			    'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't',
			    'u', 'v', 'w', 'x', 'y', 'z',  0 ,   0,   0,   0,
			      0,   0,   0,   0,   0,   0, '=', '-', '*', '/',
			    '%', '<', '>',   0,   0, '(', ')', '$', '+', '#' };

	for(int i  = 0; i < 100; i++) {
		if(translation[i] == c) return i;

	}

	throw std::runtime_error("Unsupported character");

}

int escape_char(char c) {
	switch(c) {
		case '\\': return char_constant(c);
		case '\'': return char_constant(c);
		case 'n': return 2;
		case 't': return 3;
		case 'b': return 4;
		case '0': return 0;
		default: throw std::runtime_error("Unimplemented/unsupported escape sequence");
	}
}

#include <string.h>
extern YYSTYPE yylval;
int comment_state = 0;
%}
%s METASTATE
%x COMMENT
%%
\/\/[^\n]*                    /* line comment */
\/\*                          { comment_state = YY_START; BEGIN(COMMENT); }
<COMMENT>\*\/                 { BEGIN(comment_state); }
<COMMENT>\n                    newline();
<COMMENT>.                     /* block comment */
<COMMENT><<EOF>>               throw std::runtime_error("Unterminated block comment");
\"([^\"\\\n]|\\.)*\"       { yylval.strval = strndup(yytext+1, yyleng-2); return STRING; }
\"                             throw std::runtime_error("Unterminated string literal");
char				yylval.tval = new t_i6(); return TYPE;
int				yylval.tval = new t_i12(); return TYPE;
void				yylval.tval = new t_void(); return TYPE;
return				return RETURN;
static				return STATIC;
if				return IF;
else				return ELSE;
while				return WHILE;
for				return FOR;
asm				return ASM;
continue			return CONTINUE;
extern				return EXTERN;
volatile			return VOLATILE;
reentrant			return REENTRANT;
break				return BREAK;
sizeof				return SIZEOF;
struct				return STRUCT;
typedebug			return TYPEDEBUG;
sptest				return SPTEST;
\-\>				return PTRFIELD;
\#				BEGIN(METASTATE); return '#';
<METASTATE>\n			BEGIN(INITIAL); newline(); return '\n'; 
pragma				return PRAGMA;
0n[ABCDQWER01234]+		yylval.ival = atoinontri(yytext); return DECIMAL;
0t[N\-0OP\+]+			yylval.ival = atoinontri(yytext); return DECIMAL;
[0-9]+				yylval.ival = atoinontri(yytext); return DECIMAL;
\'\\[^\']\'			yylval.ival = escape_char(*(yytext+2)); return DECIMAL;
\'[^\'\\]\'			yylval.ival = char_constant(*(yytext+1)); return DECIMAL;
[a-zA-Z_][a-zA-Z0-9_]*		yylval.strval = (char*) strdup((char*)yytext); return IDENTIFIER;
\(				return '(';
\)				return ')';
\{				return '{';
\}				return '}';
[\[]				return '[';
[\]]				return ']';

\|\|				return LOG_OR;
\&\&				return LOG_AND;

\|				return '|';
\^				return '^';
\&				return '&';
\~				return '~';
\?				return '?';
\:				return ':';

\>				return '>';
\<				return '<';
\>\=				return GE;
\<\=				return LE;
\=\=				return EQ;
\!\=				return NE;

\+\=				return ADDASSIGN;
\-\=				return SUBASSIGN;
\*\=				return MULASSIGN;
\&\=				return ANDASSIGN;
\^\=				return XORASSIGN;
\|\=				return ORASSIGN;

\<P\>				return PRM;
\<S\>				return TSH;

\+\+				return INC;
\-\-				return DEC;

\=				return '=';
\+				return '+';
\-				return '-';
\%				return '%';
\/				return '/';
\*				return '*';
\,				return ',';
\;				return ';';
\.				return '.';

\n				newline();
[\t\r\ ]+			//


<METASTATE><<EOF>> { BEGIN(INITIAL); return '\n'; }
. throw std::runtime_error("Unexpected character in source");

%%
