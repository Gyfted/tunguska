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

/* Mac fork security hardening — 2026-09-25. Checked host arithmetic, bounded
 * image input and guest diagnostics; original authorship and license retained. */

/* Mac fork modification notice — 2026-09-24
 * Maintained by Vinny Lingham (https://github.com/Gyfted).
 * C++17 compatibility and const-correct nonary string conversion.
 * Original authorship and GPL-2.0-or-later terms are retained.
 * See docs/PORTING.md for provenance and details.
 */

#include "trit.h"
#include "tryte.h"
#include "machine.h"
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <string.h>
#include <cstdint>
#include <stdexcept>

// Security hardening, 2026-09-25: normalize before narrowing or indexing.
static int wrapped_tryte(int64_t value) {
	return int(((value + 364) % 729 + 729) % 729 - 364);
}

tryte::tryte() : changed(false), cache(0) { } 

tryte::tryte(const tryte& t) {
	for(int i = 0; i < 6; i++) {
		this->trits[i] = t[i];
	}
	carry = t.get_carry();
	changed = false;
	updatecache();
}
tryte::tryte(trit* trits) {
	this->trits[0] = trits[0];
	this->trits[1] = trits[1];
	this->trits[2] = trits[2];
	this->trits[3] = trits[3];
	this->trits[4] = trits[4];
	this->trits[5] = trits[5];

	changed = false;
	updatecache();
}

/* From balanced base9 */
tryte::tryte(const char* s) {
	if (!s || strlen(s) != 3) throw std::invalid_argument("Expected three balanced nonary digits");
	const char* translation = "DCBA01234";
	int power = 81; int num; int val = 0;
	for(num = 0; num < 3; num++) {
		const char* idx = strchr(translation, s[num]);
		if(idx == NULL) {
			throw std::invalid_argument("Invalid balanced nonary digit");
		} else {
			val += power * int(idx - translation - 4);
			power /= 9;
		}
	}

	*this = tryte( val );
	changed = false;
	updatecache();
}

tryte tryte::intval_lookup[730];
tryte::tryte(int i) {
	static bool initialized = false;

	if(!initialized) {
		for(int j = 0; j < 730; j++) {
			tryte* value = from_int(j-364);
			intval_lookup[j] = *value;
			delete value;

		}
		initialized = true;
	}

	if(i > 364) {
		carry = trit::TRTRUE;
		i = wrapped_tryte(i);
	} else if(i < -364) {
		carry = trit::TRFALSE;
		i = wrapped_tryte(i);
	} else {
		carry = trit::TRMU;

	}

	trits[0] = intval_lookup[i+364].trits[0];
	trits[1] = intval_lookup[i+364].trits[1];
	trits[2] = intval_lookup[i+364].trits[2];
	trits[3] = intval_lookup[i+364].trits[3];
	trits[4] = intval_lookup[i+364].trits[4];
	trits[5] = intval_lookup[i+364].trits[5];

	cache = i;
	changed = false;

}

/* DO NOT USE DIRECTLY.
 * Use tryte(int) instead. It's a lookup table of this
 * algorithm's return values. */
tryte* tryte::from_int(int i) {
	int t, sign = trit::TRTRUE;
	long power = 243; 
	trit trits[6];
	trit carry;

	if(i < 0) { sign = -sign; i = -i; }

	if(i > 364) {
		i = (i + 364)%729-364;
		carry = sign;
	} else carry = trit::TRMU;


	for(t = 0; t < 6; t++) {
		if((i - power + (power-1)/2) >= 0) {
			trits[t] = sign;
			i -= power;

			if(i < 0) { sign = -sign; i *= -1; }
		} 
		power /= 3;
	}

	tryte* return_value = new tryte(trits);
	return_value->carry = carry;
	return return_value;
}

tryte tryte :: operator~() const {
	trit tritset[6];
	for(int i = 0; i < 6; i++) tritset[i] = !trits[i];
	return tryte(tritset);
}

tryte tryte :: operator&(const tryte a) const {
	trit tritset[6];
	for(int i = 0; i < 6; i++) tritset[i] = (a.trits[i]) & (trits[i]);
	return tryte(tritset);
}

tryte tryte :: operator|(const tryte a) const {
	trit tritset[6];
	for(int i = 0; i < 6; i++) tritset[i] = (a.trits[i]) | (trits[i]);
	return tryte(tritset);
}

tryte tryte :: operator^(const tryte a) const {
	trit tritset[6];
	for(int i = 0; i < 6; i++) tritset[i] = (a.trits[i]) ^ (trits[i]);
	return tryte(tritset);
}

tryte& tryte :: operator&=(tryte &a) {
	(*this) = ((*this) & a);
	changed = true;
	return *this;
}

tryte& tryte :: operator|=(tryte &a) {
	(*this) = ((*this) | a);
	changed = true;
	return *this;
}

int tryte::operator==(const tryte &a) const {
	if(to_int() == a.to_int()) return trit::TRTRUE; 
	return trit::TRFALSE;
}

int tryte::operator!=(const tryte &a) const { return -1 * (*this == a); }

int tryte::operator>(const tryte& a) const {
	if(to_int() > a.to_int()) return trit::TRTRUE;
	else if(to_int() == a.to_int()) return trit::TRMU;
	else return trit::TRFALSE;
}

int tryte::operator<(const tryte& a) const {
	return -1 * ((*this) > a);
}

tryte& tryte :: operator=(const tryte &a) {
	for(int i = 0; i < 6; i++) trits[i] = a[i];
	carry = a.get_carry();
	if(!a.changed) {
		cache = a.cache;
		changed = false;
	} else changed = true;
	return *this;
}

tryte& tryte :: operator=(const int v) {
	operator=((tryte)v);
	changed = true;
	return *this;
}
tryte tryte :: operator<<(int s) const {
	if (s < 0) throw std::out_of_range("Negative tryte shift");
	tryte t;
	if (s >= 6) return t;
	for(int i = 0; i < 6-s; i++) { t[i] = (*this)[i+s]; }
	return t;
}
tryte tryte :: operator>>(int s) const {
	if (s < 0) throw std::out_of_range("Negative tryte shift");
	tryte t;
	if (s >= 6) return t;
	for(int i = 0; i < 6-s; i++) { 
		t[i+s] = trits[i]; 
	}
	return t;
}

tryte tryte::operator+(const tryte& a) const {
	return to_int() + a.to_int();
}
tryte& tryte::operator+=(const tryte& a) {
	*this = tryte(to_int() + a.to_int());
	changed = true;
	return *this;
}
tryte& tryte::operator+=(const int v) {
	*this = *this + v;
	changed = true;
	return *this;
}

tryte tryte::operator+(const int v) const {
	const int64_t sum = int64_t(to_int()) + v;
	tryte result(wrapped_tryte(sum));
	result.carry = sum > 364 ? trit::TRTRUE : sum < -364 ? trit::TRFALSE : trit::TRMU;
	return result;
}

/* Low tryte in multiplication */
tryte tryte::operator*(const tryte& a) const {
	tryte high, low;
	int_to_word(to_int() * a.to_int(), high, low);

	return low;
}

/* High tryte in multiplication */
/*tryte tryte::operator,(const tryte& a) const {
	tryte high, low;
	int_to_word(to_int() * a.to_int(), high, low);

	return high;
} 

Deprecated! USE mlh instead! */

tryte tryte::mlh(const tryte& a) const {
	tryte high, low;
	int_to_word(to_int() * a.to_int(), high, low);

	return high;
}

tryte tryte::operator%(const tryte& a) const {
	if(a.to_int() == 0) return 0;
	return to_int() % a.to_int();
}

tryte tryte::operator%(const int v) const {
	if(v == 0) return 0;
	return to_int() % v;
}

tryte tryte::operator/(const tryte& a) const {
	if(a.to_int() == 0) return 0;
	return to_int() / a.to_int();
}

tryte tryte::operator/(const int v) const {
	if(v == 0) return 0;
	return to_int() / v;
}

tryte tryte::permute(const tryte& t) const {
	tryte ret = t;
	for(int i = 0; i < 6; i++) {
		ret.trits[i] = ret.trits[i] > trits[i];
	}
	return ret;
}

tryte& tryte::permute_this(const tryte& t) {
	for(int i = 0; i < 6; i++) {
		trits[i] = trits[i] > t.trits[i];
	}
	changed = true;
	return *this;
}

tryte tryte::shift(const tryte& t) const {
	tryte ret = t;
	for(int i = 0; i < 6; i++) {
		ret.trits[i] = ret.trits[i] >> trits[i];
	}
	return ret;
}

tryte& tryte::shift_this(const tryte& t) {
	for(int i = 0; i < 6; i++) {
		trits[i] = trits[i] >> t.trits[i];
	}
	changed = true;
	return *this;
}

tryte tryte::but(const tryte& t) const {
	tryte ret = t;
	for(int i = 0; i < 6; i++) {
		ret.trits[i] = ret.trits[i] >> trits[i];
	}
	return ret;
}

tryte& tryte::but_this(const tryte& t) {
	for(int i = 0; i < 6; i++) {
		trits[i].but_this(t.trits[i]);
	}
	changed = true;
	return *this;
}

tryte tryte::comm_op(int op, const tryte& t) const {
	tryte ret = t;
	for(int i = 0; i < 6; i++) {
		ret.trits[i] = ret.trits[i].comm_op(op, trits[i]);
	}
	return ret;
}

tryte& tryte::comm_op_this(int op, const tryte& t) {
	for(int i = 0; i < 6; i++) {
		trits[i].comm_op_this(op, t.trits[i]);
	}
	changed = true;
	return *this;
}

trit tryte::parity() const {
	int sum = (trits[5].to_int() + trits[4].to_int() + trits[3].to_int() +
		   trits[2].to_int() + trits[1].to_int() + trits[0].to_int()); 
	if(sum > 0) return 1;
	else if(sum < 0) return -1;
	return 0;
}
