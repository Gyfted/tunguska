# SPDX-License-Identifier: GPL-2.0-or-later
# New Mac fork build, 2026-09-24. Upstream build files are preserved under upstream/.
CXX := clang++
SDKROOT := $(shell xcrun --show-sdk-path)
DEVELOPER := $(shell xcode-select -p)
CPPFLAGS := -Isrc/core -Isrc/assembler -Ibuild -I$(DEVELOPER)/usr/include
ARCHS ?= $(shell uname -m)
CXXFLAGS := -std=c++17 -mmacosx-version-min=12.0 $(foreach arch,$(ARCHS),-arch $(arch)) -O2 -g -Wall -Wextra -Wno-unused-parameter -Wno-unused-but-set-variable
LDLIBS := -lz
CORE := trit tryte memory machine interrupt agdp disk
OBJECTS := $(addprefix build/,$(addsuffix .o,$(CORE)))
TEST_SOURCES := tests/core_tests.cc tests/debugger_tests.cc

.PHONY: all app test sanitize security-check sandbox-check verify-app release-check run
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

build/debugger.o: src/debugger.cc src/debugger.h Makefile | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -MMD -MP -c $< -o $@

build/tunguska-cli: src/cli.cc build/runtime.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc $^ $(LDLIBS) -o $@

build/Tunguska: src/macos/main.mm src/macos/DebuggerWindow.mm src/macos/DebuggerWindow.h src/macos/FileAccess.mm src/macos/FileAccess.h build/runtime.o build/debugger.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -fobjc-arc $(filter-out %.h,$^) $(LDLIBS) -framework Cocoa -o $@

app: build/Tunguska build/boot.ternobj
	mkdir -p build/Tunguska.app/Contents/MacOS build/Tunguska.app/Contents/Resources
	cp build/Tunguska build/Tunguska.app/Contents/MacOS/Tunguska.new
	mv -f build/Tunguska.app/Contents/MacOS/Tunguska.new build/Tunguska.app/Contents/MacOS/Tunguska
	cp build/boot.ternobj LICENSE AUTHORS NOTICE.md build/Tunguska.app/Contents/Resources/
	cp src/macos/Info.plist build/Tunguska.app/Contents/Info.plist
	codesign --force --sign - --options runtime --entitlements src/macos/Tunguska.entitlements build/Tunguska.app

verify-app: app
	python3 scripts/verify_app.py build/Tunguska.app

release-check:
	python3 tests/release_tests.py

build/sandbox-tests: tests/macos_sandbox_tests.mm src/macos/FileAccess.mm src/macos/FileAccess.h build/runtime.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -fobjc-arc $(filter-out %.h,$^) $(LDLIBS) -framework Cocoa -o $@

sandbox-check: build/sandbox-tests build/boot.ternobj
	mkdir -p build/SandboxTests.app/Contents/MacOS build/SandboxTests.app/Contents/Resources
	cp build/sandbox-tests build/SandboxTests.app/Contents/MacOS/SandboxTests
	python3 -c 'import plistlib; plistlib.dump(dict(CFBundleIdentifier="org.tunguska.mac.sandbox-tests", CFBundleExecutable="SandboxTests", CFBundlePackageType="APPL"), open("build/SandboxTests.app/Contents/Info.plist", "wb"))'
	cp build/boot.ternobj build/SandboxTests.app/Contents/Resources/
	codesign --force --sign - --options runtime --entitlements src/macos/Tunguska.entitlements build/SandboxTests.app
	python3 scripts/test_sandbox.py

build/core-tests: $(TEST_SOURCES) build/runtime.o build/debugger.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc $^ $(LDLIBS) -o $@

test: build/core-tests build/boot.ternobj
	build/core-tests build/boot.ternobj

build/core-tests-sanitized: $(TEST_SOURCES) src/runtime.cc src/runtime.h src/debugger.cc src/debugger.h $(wildcard src/core/*.cc src/core/*.h) Makefile | build
	$(CXX) $(CPPFLAGS) -Isrc -std=c++17 -mmacosx-version-min=12.0 -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer $(TEST_SOURCES) src/runtime.cc src/debugger.cc $(addprefix src/core/,$(addsuffix .cc,$(CORE))) $(LDLIBS) -o $@

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
