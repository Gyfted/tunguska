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
 * Define floating-point edge cases and report guest arithmetic errors.
 * Original authorship and GPL-2.0-or-later terms are retained.
 * See docs/PORTING.md for provenance and details.
 */

#include "agdp.h"
#include <math.h>
#include <time.h>
#include <algorithm>
#include <cmath>
#include <stdexcept>

void agdp::float2_to_float3(float f, tryte& high, tryte& low) {
	if (!std::isfinite(f)) throw std::domain_error("Non-finite ternary floating-point result");
	if (f == 0) { high = low = 0; return; }
	int exponent = int(std::floor(std::log(std::fabs(double(f))) / std::log(3.0)));
	exponent = std::clamp(exponent, -TFP_EMAX, TFP_EMAX);
	const double significand = double(f) * std::pow(3.0, -exponent) * 729;
	const int mantissa = int(std::clamp(significand, -double(TFP_SMAX), double(TFP_SMAX)));
	if (mantissa == 0) { high = low = 0; return; }
	tryte::int_to_word(mantissa, high, low);
	tryte et = exponent;
	high = high << 4;
	high[5] = et[5];
	high[4] = et[4];
	high[3] = et[3];
	high[2] = et[2];
}

float agdp::float3_to_float2(const tryte& high, const tryte& low) {
	float exponent = high[5].to_int() + high[4].to_int() * 3 
			+ high[3].to_int() * 9 + high[2].to_int() * 27;
	float significand = tryte::word_to_int(high>>4, low) / 729.0;

	return significand * pow(3, exponent);
}

agdp::agdp() {
	M_OP = tryte::word_to_int("DDD", "DD0");
	M_R1 = tryte::word_to_int("DDD", "DD1");
	M_R2 = tryte::word_to_int("DDD", "DD3");
	M_R3 = tryte::word_to_int("DDD", "DCD");
}

void agdp::heartbeat(machine& m) {
	try {
	switch(m.memref(M_OP).to_int()) {
		case COP_NOOP: return;
		case COP_ITOF: itof(m); break;
		case COP_FTOI: ftoi(m); break;
		case COP_FADD: fadd(m); break;
		case COP_FMUL: fmul(m); break;
		case COP_FDIV: fdiv(m); break;
		case COP_FEXP: fexp(m); break;
		case COP_FLOG: flog(m); break;
		case COP_FCOS: fcos(m); break;
		case COP_FSIN: fsin(m); break; 
		case COP_BLT: blt(m); break;
		case COP_BLS: bls(m); break;
		case COP_BLA: bla(m); break;
		case COP_BLX: blx(m); break;
		case COP_BLO: blo(m); break;
		case COP_BSH: bsh(m); break;
		case COP_BLP: blp(m); break;
		case COP_WHEN: when(m); break;
		case COP_IDIVW: divw(m); break;
		case COP_IMODW: modw(m); break;
		default: if (m.allow_diagnostic()) printf("Unknown or unimplemented "
				"AGDP instruction :-(\n");
	}
	} catch (const std::domain_error&) {
		m.queue_interrupt(new arith_interrupt());
	} catch (const std::overflow_error&) {
		m.queue_interrupt(new arith_interrupt());
	}
	m.memref(M_OP) = COP_NOOP;
}

void agdp::itof(machine& m) {
	int i = tryte::word_to_int(m.memref(M_R1), m.memref(M_R1+1));
	float2_to_float3(float(i), m.memref(M_R1), m.memref(M_R1+1));
}
void agdp::ftoi(machine& m) {
	const double value = std::round(double(float3_to_float2(m.memref(M_R1), m.memref(M_R1+1))));
	if (!std::isfinite(value) || value < -MEMSIZ/2 || value > MEMSIZ/2)
		throw std::overflow_error("Float does not fit in a ternary word");
	int i = int(value);
	tryte::int_to_word(i, m.memref(M_R1),    m.memref(M_R1+1));
}

void agdp::fadd(machine& m) {
	float f1 = float3_to_float2(m.memref(M_R1), m.memref(M_R1+1));
	float f2 = float3_to_float2(m.memref(M_R2), m.memref(M_R2+1));
	float2_to_float3(f1+f2, m.memref(M_R1), m.memref(M_R1+1));
}

void agdp::fmul(machine& m) {
	float f1 = float3_to_float2(m.memref(M_R1), m.memref(M_R1+1));
	float f2 = float3_to_float2(m.memref(M_R2), m.memref(M_R2+1));
	float2_to_float3(f1*f2, m.memref(M_R1), m.memref(M_R1+1));
}

void agdp::fdiv(machine& m) {
	float f1 = float3_to_float2(m.memref(M_R1), m.memref(M_R1+1));
	float f2 = float3_to_float2(m.memref(M_R2), m.memref(M_R2+1));
	if(f2 == 0) {
		m.queue_interrupt(new arith_interrupt()); 
		return; 
	}
	float2_to_float3(f1/f2, m.memref(M_R1), m.memref(M_R1+1));
}

void agdp::fexp(machine& m) {
	float f1 = float3_to_float2(m.memref(M_R1), m.memref(M_R1+1));
	float f2 = float3_to_float2(m.memref(M_R2), m.memref(M_R2+1));
	float2_to_float3(pow(f1, f2), m.memref(M_R1), m.memref(M_R1+1));
}

void agdp::flog(machine& m) {
	float f1 = float3_to_float2(m.memref(M_R1), m.memref(M_R1+1));
	if(f1 <= 0) {
		m.queue_interrupt(new arith_interrupt()); 
		return; 
	}
	float2_to_float3(log(f1), m.memref(M_R1), m.memref(M_R1+1));
} 

void agdp::fcos(machine& m) {
	float f1 = float3_to_float2(m.memref(M_R1), m.memref(M_R1+1));
	float2_to_float3(cos(f1), m.memref(M_R1), m.memref(M_R1+1));
}

void agdp::fsin(machine& m) {
	float f1 = float3_to_float2(m.memref(M_R1), m.memref(M_R1+1));
	float2_to_float3(sin(f1), m.memref(M_R1), m.memref(M_R1+1));
}


/* Block transfer */
void agdp::blt(machine& m) {
	int addr1 = tryte::word_to_int(m.memref(M_R1), m.memref(M_R1+1));
	int addr2 = tryte::word_to_int(m.memref(M_R2), m.memref(M_R2+1));
	int length = tryte::word_to_int(m.memref(M_R3), m.memref(M_R3+1));

	if(length < 0 && m.allow_diagnostic()) printf("Warning: BLT with length < 0\n");

	int offset = 0;
	if(addr1 + length > addr2) 
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr2);
			addr1 ++;
			addr2 ++;
		}
	else {
		addr2 = addr2 + length; 
		addr1 = addr1 + length;
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr2);

			addr1 --;
			addr2 --; 

		}
	}
}

/* Block set */
void agdp::bls(machine& m) {
	int addr1 = tryte::word_to_int(m.memref(M_R1), m.memref(M_R1+1));
	int length = tryte::word_to_int(m.memref(M_R3), m.memref(M_R3+1));

	int offset = 0;
	for(offset = 0; offset < length; offset++) {
		m.memref(addr1) = m.memref(M_R2+1);
		addr1++;
	}

}

/* Block AND */
void agdp::bla(machine& m) {
	int addr1 = tryte::word_to_int(m.memref(M_R1), m.memref(M_R1+1));
	int addr2 = tryte::word_to_int(m.memref(M_R2), m.memref(M_R2+1));
	int length = tryte::word_to_int(m.memref(M_R3), m.memref(M_R3+1));

	if(length < 0 && m.allow_diagnostic()) printf("Warning: BLA with length < 0\n");

	int offset = 0;
	if(addr1 + length > addr2) 
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr1) & m.memref(addr2);
			addr1 ++;
			addr2 ++;
		}
	else {
		addr2 = addr2 + length; 
		addr1 = addr1 + length;
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr1) & m.memref(addr2);

			addr1 --;
			addr2 --; 

		}
	}

}

/* Block XOR */
void agdp::blx(machine& m) {
	int addr1 = tryte::word_to_int(m.memref(M_R1), m.memref(M_R1+1));
	int addr2 = tryte::word_to_int(m.memref(M_R2), m.memref(M_R2+1));
	int length = tryte::word_to_int(m.memref(M_R3), m.memref(M_R3+1));

	if(length < 0 && m.allow_diagnostic()) printf("Warning: BLX with length < 0\n");

	int offset = 0;
	if(addr1 + length > addr2) 
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr1)^m.memref(addr2);
			addr1 ++;
			addr2 ++;
		}
	else {
		addr2 = addr2 + length; 
		addr1 = addr1 + length;
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr1)^m.memref(addr2);

			addr1 --;
			addr2 --; 

		}
	}


};

/* Block OR */
void agdp::blo(machine& m) {
	int addr1 = tryte::word_to_int(m.memref(M_R1), m.memref(M_R1+1));
	int addr2 = tryte::word_to_int(m.memref(M_R2), m.memref(M_R2+1));
	int length = tryte::word_to_int(m.memref(M_R3), m.memref(M_R3+1));

	if(length < 0 && m.allow_diagnostic()) printf("Warning: BLO with length < 0\n");

	int offset = 0;
	if(addr1 + length > addr2) 
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr1) | m.memref(addr2);
			addr1 ++;
			addr2 ++;
		}
	else {
		addr2 = addr2 + length; 
		addr1 = addr1 + length;
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr1) | m.memref(addr2);

			addr1 --;
			addr2 --; 
		}
	}


};

void agdp::bsh(machine& m) {
	int addr1 = tryte::word_to_int(m.memref(M_R1), m.memref(M_R1+1));
	int addr2 = tryte::word_to_int(m.memref(M_R2), m.memref(M_R2+1));
	int length = tryte::word_to_int(m.memref(M_R3), m.memref(M_R3+1));

	if(length < 0 && m.allow_diagnostic()) printf("Warning: BSH with length < 0\n");

	int offset = 0;
	if(addr1 + length > addr2) 
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr1).shift(m.memref(addr2));
			addr1 ++;
			addr2 ++;
		}
	else {
		addr2 = addr2 + length; 
		addr1 = addr1 + length;
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr1).shift(m.memref(addr2));

			addr1 --;
			addr2 --; 
		}
	}


};


void agdp::blp(machine& m) {
	int addr1 = tryte::word_to_int(m.memref(M_R1), m.memref(M_R1+1));
	int addr2 = tryte::word_to_int(m.memref(M_R2), m.memref(M_R2+1));
	int length = tryte::word_to_int(m.memref(M_R3), m.memref(M_R3+1));

	if(length < 0 && m.allow_diagnostic()) printf("Warning: BLP with length < 0\n");

	int offset = 0;
	if(addr1 + length > addr2) 
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr1).permute(m.memref(addr2));
			addr1 ++;
			addr2 ++;
		}
	else {
		addr2 = addr2 + length; 
		addr1 = addr1 + length;
		for(offset = 0; offset < length; offset++) {
			m.memref(addr1) = m.memref(addr1).permute(m.memref(addr2));

			addr1 --;
			addr2 --; 
		}
	}


}

void agdp::when(machine& m) {
	time_t tt_now = time(NULL);
	struct tm* now = localtime(&tt_now);

	/* First six fields in struct tm are stored into
	 * M_R1 through M_R3. */

	m.memref(M_R1) = now->tm_sec;
	m.memref(M_R1+1) = now->tm_min;
	m.memref(M_R2) = now->tm_hour;
	m.memref(M_R2+1) = now->tm_mday;
	m.memref(M_R3) = now->tm_mon;
	m.memref(M_R3+1) =  now->tm_year;

}

void agdp::divw(machine& m) {
	int dividend = tryte::word_to_int(m.memref(M_R1), m.memref(M_R1+1));
	int divisor = tryte::word_to_int(m.memref(M_R2), m.memref(M_R2+1));
	if(divisor == 0) {
		// XXX: Raise arithmetic error?
		m.memref(M_R3) = m.memref(M_R3+1) = 0;
	} else {
		int result = dividend / divisor;
		tryte::int_to_word(result, m.memref(M_R3), m.memref(M_R3+1));
	}

}

void agdp::modw(machine& m) {
	int dividend = tryte::word_to_int(m.memref(M_R1), m.memref(M_R1+1));
	int divisor = tryte::word_to_int(m.memref(M_R2), m.memref(M_R2+1));
	if(divisor == 0) {
		// XXX: Raise arithmetic error?
		m.memref(M_R3) = m.memref(M_R3+1) = 0;
	} else {
		int result = dividend % divisor;
		tryte::int_to_word(result, m.memref(M_R3), m.memref(M_R3+1));
	}

}
