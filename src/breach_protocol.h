// SPDX-License-Identifier: GPL-2.0-or-later
// Guest memory layout for the original Ternary Breach game, 2026-09-25.
#ifndef TUNGUSKA_BREACH_PROTOCOL_H
#define TUNGUSKA_BREACH_PROTOCOL_H
#define BR_STATUS 80000
#define BR_HEALTH 80002
#define BR_AMMO 80003
#define BR_KILLS 80004
#define BR_CELLS 80005
#define BR_X 80010
#define BR_Y 80012
#define BR_ANGLE 80014
#define BR_FRAME 80016
#define BR_MAP_VISIBLE 80018
#define BR_MESSAGE 80019
#define BR_TURN 80020
#define BR_FLASH 80022
#define BR_INPUT_HEAD 80023
#define BR_INPUT_TAIL 80024
#define BR_MAP 81000
#define BR_ENEMIES 82000
#define BR_DEPTH 83000
#define BR_INPUT_QUEUE 84000
#define BR_READY 2
#define BR_WON 3
#define BR_DEAD -1
#endif
