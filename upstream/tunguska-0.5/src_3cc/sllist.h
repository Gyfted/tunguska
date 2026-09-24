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
#ifndef sllist_h
#define sllist_h

/* Standard, run of the mill linked list, mostly used by the parser and
 * function-related classes */
class sllist {
	public:
		sllist(void* data, void* data2 = NULL) {
			this->data = data;
			this->data2 = data2;
			this->next = NULL;
		}

		sllist(sllist* next, void* data, void* data2 = NULL) {
			this->data = data;
			this->data2 = data2;
			this->next = next;
		}

		static sllist* reverse(sllist* l) {
			sllist* node = NULL;
			while(l) {
				node = new sllist(node, l->data, l->data2);
				l = l->next;
			}
			return node;
		}

		void* data;
		void* data2;
		sllist* next;
};

#endif
