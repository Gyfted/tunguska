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
bin_PROGRAMS = tunguska tg_assembler
AM_YFLAGS = -d
AM_LFLAGS= -+ -olex.yy.c
tunguska_LDADD = -lz 
tg_assembler_LDADD = -lz @LEXLIB@
AM_CPPFLAGS= -DSHARE_DIR=\"${datadir}/tunguska/\"

tunguska_SOURCES = tunguska.cc display.cc keyboard.cc trit.cc tryte.cc interrupt.cc machine.cc disk.cc agdp.cc memory.cc
tg_assembler_SOURCES = assembler.cc trit.cc tryte.cc interrupt.cc machine.cc memory.cc agdp.cc
nodist_tg_assembler_SOURCES = parser.h scanner.ll parser.yy
BUILT_SOURCES = parser.h
CLEANFILES = parser.h parser.cc scanner.cc
noinst_HEADERS = assembler.h trit.h tryte.h display.h keyboard.h interrupt.h machine.h disk.h error.h agdp.h values.h memory.h scanner.ll parser.yy
