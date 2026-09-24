# SPDX-License-Identifier: GPL-2.0-or-later
# New Mac fork build, 2026-09-24. Upstream build files are preserved under upstream/.
CXX := clang++
SDKROOT := $(shell xcrun --show-sdk-path)
DEVELOPER := $(shell xcode-select -p)
CPPFLAGS := -Isrc/core -Isrc/assembler -Ibuild -I$(DEVELOPER)/usr/include
CXXFLAGS := -std=c++17 -mmacosx-version-min=12.0 -O2 -g -Wall -Wextra -Wno-unused-parameter -Wno-unused-but-set-variable
LDLIBS := -lz
CORE := trit tryte memory machine interrupt agdp disk
OBJECTS := $(addprefix build/,$(addsuffix .o,$(CORE)))

.PHONY: all app test sanitize security-check run
all: app build/tg_assembler build/tunguska-cli

build:
	mkdir -p build

build/%.o: src/core/%.cc Makefile | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -MMD -MP -c $< -o $@

build/parser.cc: src/assembler/parser.yy | build
	bison --defines=build/parser.h -o $@ $<

build/parser.h: build/parser.cc
	@test -f $@

build/scanner.cc: src/assembler/scanner.ll build/parser.h
	flex -o $@ $<

build/tg_assembler: src/assembler/assembler.cc build/parser.cc build/scanner.cc $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) src/assembler/assembler.cc build/parser.cc build/scanner.cc $(OBJECTS) $(LDLIBS) -o $@

build/boot.ternobj: build/tg_assembler $(wildcard resources/memory_image_asm/*.asm)
	cd resources/memory_image_asm && ../../build/tg_assembler -o ../../build/boot.ternobj ram.asm

build/runtime.o: src/runtime.cc src/runtime.h Makefile | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -MMD -MP -c $< -o $@

build/tunguska-cli: src/cli.cc build/runtime.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc $^ $(LDLIBS) -o $@

build/Tunguska: src/macos/main.mm build/runtime.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -fobjc-arc $^ $(LDLIBS) -framework Cocoa -o $@

app: build/Tunguska build/boot.ternobj
	mkdir -p build/Tunguska.app/Contents/MacOS build/Tunguska.app/Contents/Resources
	cp build/Tunguska build/Tunguska.app/Contents/MacOS/Tunguska.new
	mv -f build/Tunguska.app/Contents/MacOS/Tunguska.new build/Tunguska.app/Contents/MacOS/Tunguska
	cp build/boot.ternobj LICENSE AUTHORS NOTICE.md build/Tunguska.app/Contents/Resources/
	cp src/macos/Info.plist build/Tunguska.app/Contents/Info.plist
	codesign --force --sign - build/Tunguska.app

build/core-tests: tests/core_tests.cc build/runtime.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc $^ $(LDLIBS) -o $@

test: build/core-tests build/boot.ternobj
	build/core-tests build/boot.ternobj

build/core-tests-sanitized: tests/core_tests.cc src/runtime.cc src/runtime.h $(wildcard src/core/*.cc src/core/*.h) Makefile | build
	$(CXX) $(CPPFLAGS) -Isrc -std=c++17 -mmacosx-version-min=12.0 -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer tests/core_tests.cc src/runtime.cc $(addprefix src/core/,$(addsuffix .cc,$(CORE))) $(LDLIBS) -o $@

sanitize: build/core-tests-sanitized build/boot.ternobj
	UBSAN_OPTIONS=halt_on_error=1 build/core-tests-sanitized build/boot.ternobj

build/security-tests: tests/security_tests.cc src/runtime.cc src/runtime.h $(wildcard src/core/*.cc src/core/*.h) Makefile | build
	$(CXX) $(CPPFLAGS) -Isrc -std=c++17 -mmacosx-version-min=12.0 -g -O1 -fsanitize=address,undefined,float-cast-overflow -fno-omit-frame-pointer tests/security_tests.cc src/runtime.cc $(addprefix src/core/,$(addsuffix .cc,$(CORE))) $(LDLIBS) -o $@

security-check: build/security-tests
	UBSAN_OPTIONS=halt_on_error=1 build/security-tests > build/security-tests.log 2>&1 || { tail -50 build/security-tests.log; exit 1; }
	@tail -1 build/security-tests.log

run: app
	open build/Tunguska.app

-include $(wildcard build/*.d)
