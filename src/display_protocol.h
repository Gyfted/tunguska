// SPDX-License-Identifier: GPL-2.0-or-later
// Mac fork display extension, 2026-09-25; existing raster modes are unchanged.
#ifndef TUNGUSKA_DISPLAY_PROTOCOL_H
#define TUNGUSKA_DISPLAY_PROTOCOL_H
#define TG_VIDEO_BITMAP -264262
#define TG_VIDEO_WORDS 13122
// Raster auxiliary -1: six trit pixels per tryte plus one palette attribute.
#define TG_VIDEO_ATTRIBUTES -251140
#define TG_VIDEO_PALETTES -238018
// Attribute -364..364 selects one of 729 three-color palettes. Each entry is
// an ordinary Tunguska 729-color tryte, ordered by pixel trit -1, 0, +1.
#define TG_VIDEO_PALETTE_ZERO -236926
#endif
