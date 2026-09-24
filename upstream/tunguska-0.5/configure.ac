# Copyright (C) 2008 Viktor Lofgren <vlofgren@gmail.com>
#  
# This file is free software; as a special exception the author gives
# unlimited permission to copy and/or distribute it, with or without 
# modifications, as long as this notice is preserved.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY, to the extent permitted by law; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

AC_INIT([tunguska],
        [0.5],
        [Viktor Lofgren vlofgren@gmail.com],
        [tunguska])
AC_CONFIG_AUX_DIR(config)
AM_CONFIG_HEADER(config.h)
AM_INIT_AUTOMAKE([dist-bzip2])

AC_PROG_YACC
AC_PROG_LEX
AC_PROG_CC
AC_PROG_CXX
AC_PROG_INSTALL

dnl SDL please!
AM_PATH_SDL(1.2.0, :, AC_MSG_ERROR([*** SDL version 1.2.0 missing!]))
CXXFLAGS="$CXXFLAGS $SDL_CFLAGS"
LDFLAGS="$CXXFLAGS $SDL_LIBS"

AC_CHECK_HEADER(zlib.h)

AC_PROG_RANLIB

AC_CONFIG_FILES([
   Makefile
   README
   doc/Makefile
   m4/Makefile
   share/Makefile
   src_tunguska/Makefile
   src_3cc/Makefile
])

AC_OUTPUT
