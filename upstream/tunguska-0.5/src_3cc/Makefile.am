# Copyright (C) 2008 Viktor Lofgren <vlofgren@gmail.com>
#  
# This file is free software; as a special exception the author gives
# unlimited permission to copy and/or distribute it, with or without 
# modifications, as long as this notice is preserved.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY, to the extent permitted by law; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
bin_PROGRAMS = tunguska_3cc
AM_YFLAGS = -d
AM_LFLAGS= -+ -olex.yy.c
tunguska_3cc_LDADD = -lz @LEXLIB@

tunguska_3cc_SOURCES = compiler.cc expression.cc tables.cc bivalent.cc conditional.cc function.cc memory.cc variable.cc 
nodist_tunguska_3cc_SOURCES = parser.h scanner.ll parser.yy
BUILT_SOURCES = parser.h 
CLEANFILES = parser.h parser.cc scanner.cc
noinst_HEADERS = bivalent.h conditional.h function.h sllist.h type.h compiler.h expression.h memory.h tables.h variable.h scanner.ll parser.yy
