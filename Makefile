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
all: app build/tg_assembler build/tunguska-cli build/3cc

TRICC_SOURCES := $(wildcard src/3cc/*.cc)
TRICC_HEADERS := $(wildcard src/3cc/*.h)

build/3cc-generated: | build
	mkdir -p $@

build/3cc-generated/parser.cc: src/3cc/parser.ypp | build/3cc-generated
	bison --defines=build/3cc-generated/parser.h -o $@ $<

build/3cc-generated/parser.h: build/3cc-generated/parser.cc
	@test -f $@

build/3cc-generated/scanner.cc: src/3cc/scanner.l build/3cc-generated/parser.h
	flex -+ -o $@ $<

build/3cc: $(TRICC_SOURCES) $(TRICC_HEADERS) build/3cc-generated/parser.cc build/3cc-generated/scanner.cc Makefile
	$(CXX) -Isrc/3cc -Ibuild/3cc-generated -I$(DEVELOPER)/usr/include $(CXXFLAGS) $(filter %.cc,$^) -o $@

build/3cc-sanitized: $(TRICC_SOURCES) $(TRICC_HEADERS) build/3cc-generated/parser.cc build/3cc-generated/scanner.cc Makefile
	$(CXX) -Isrc/3cc -Ibuild/3cc-generated -I$(DEVELOPER)/usr/include -std=c++17 -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer $(filter %.cc,$^) -o $@

build/compiler-runner: tests/compiler_runner.cc build/runtime.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc $^ $(LDLIBS) -o $@

.PHONY: compiler-check compiler-sanitize guest-3cc
compiler-check: build/3cc build/tg_assembler build/compiler-runner build/tunguska-cli
	python3 tests/compiler_tests.py

compiler-sanitize: build/3cc-sanitized build/tg_assembler build/compiler-runner build/tunguska-cli
	UBSAN_OPTIONS=halt_on_error=1 python3 tests/compiler_tests.py --sanitized

GUEST_3CC := $(addprefix resources/memory_image_3cc/,$(addsuffix .c,string stdio math main system graphics demos))
build/boot-3cc.ternobj: $(GUEST_3CC) $(wildcard resources/memory_image_3cc/*.3h) build/3cc build/tg_assembler scripts/compile_3cc.py
	python3 scripts/compile_3cc.py -O 0n400000 -o $@ $(GUEST_3CC)

guest-3cc: build/boot-3cc.ternobj

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

build/vision-reference.ternobj: resources/vision/inference.3c build/3cc build/tg_assembler scripts/compile_3cc.py
	python3 scripts/compile_3cc.py $< -o $@

build/vision.asm: resources/vision/vision-weights.bin scripts/build_vision_guest.py | build
	python3 scripts/build_vision_guest.py $< $@

build/vision.ternobj: build/vision.asm build/tg_assembler
	build/tg_assembler -o $@ $<

build/vision.o: src/vision.cc src/vision.h resources/vision/model.h Makefile | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -MMD -MP -c $< -o $@

build/debugger.o: src/debugger.cc src/debugger.h Makefile | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -MMD -MP -c $< -o $@

build/tunguska-cli: src/cli.cc build/runtime.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc $^ $(LDLIBS) -o $@

build/Tunguska: src/macos/Interface.mm src/macos/Interface.h src/macos/WeightLab.mm src/macos/WeightLab.h src/macos/WeightBenchmark.mm src/weight_benchmark.h build/weight_benchmark.o src/macos/ExplorerLab.mm src/macos/ExplorerLab.h build/explorer.o src/macos/main.mm src/macos/VisionLab.mm src/macos/VisionLab.h build/vision.o src/macos/DebuggerWindow.mm src/macos/DebuggerWindow.h src/macos/FileAccess.mm src/macos/FileAccess.h build/runtime.o build/debugger.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -fobjc-arc $(filter-out %.h,$^) $(LDLIBS) -framework Cocoa -framework Metal -framework MetalPerformanceShaders -o $@

app: build/Tunguska build/boot.ternobj build/boot-3cc.ternobj build/vision.ternobj build/explorer.ternobj
	mkdir -p build/Tunguska.app/Contents/MacOS build/Tunguska.app/Contents/Resources
	cp build/Tunguska build/Tunguska.app/Contents/MacOS/Tunguska.new
	mv -f build/Tunguska.app/Contents/MacOS/Tunguska.new build/Tunguska.app/Contents/MacOS/Tunguska
	cp build/boot.ternobj build/boot-3cc.ternobj build/vision.ternobj build/explorer.ternobj resources/vision/vision-digits.bin resources/vision/vision-model.json resources/vision/vision-weights.bin resources/vision/vision-int8-weights.bin resources/vision/VISION-NOTICE.md LICENSE AUTHORS NOTICE.md build/Tunguska.app/Contents/Resources/
	cp src/macos/Info.plist build/Tunguska.app/Contents/Info.plist
	cp resources/benchmark/matvec.metal build/Tunguska.app/Contents/Resources/
	codesign --force --sign - --options runtime --entitlements src/macos/Tunguska.entitlements build/Tunguska.app

verify-app: app
	python3 scripts/verify_app.py build/Tunguska.app

release-check:
	python3 tests/release_tests.py

.PHONY: rendering-check
build/rendering-tests: tests/macos_rendering_tests.mm src/macos/Interface.mm src/macos/Interface.h src/macos/ExplorerLab.mm src/macos/ExplorerLab.h src/macos/DebuggerWindow.mm src/macos/DebuggerWindow.h src/macos/FileAccess.mm src/macos/FileAccess.h build/explorer.o build/runtime.o build/debugger.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -fobjc-arc $(filter-out %.h,$^) $(LDLIBS) -framework Cocoa -o $@

rendering-check: build/rendering-tests
	build/rendering-tests

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

.PHONY: vision-check vision-sanitize
build/vision-tests: tests/vision_tests.cc build/vision.o build/runtime.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc $^ $(LDLIBS) -o $@

vision-check: build/vision-tests build/vision.ternobj build/vision-reference.ternobj
	python3 tests/vision_assets.py
	build/vision-tests build/vision.ternobj resources/vision/vision-digits.bin --reference build/vision-reference.ternobj > build/vision-tests.log 2>&1 || { tail -30 build/vision-tests.log; exit 1; }
	@tail -3 build/vision-tests.log

build/vision-tests-sanitized: tests/vision_tests.cc src/vision.cc src/vision.h resources/vision/model.h src/runtime.cc src/runtime.h $(wildcard src/core/*.cc src/core/*.h) Makefile | build
	$(CXX) $(CPPFLAGS) -Isrc -std=c++17 -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer tests/vision_tests.cc src/vision.cc src/runtime.cc $(addprefix src/core/,$(addsuffix .cc,$(CORE))) $(LDLIBS) -o $@

vision-sanitize: build/vision-tests-sanitized build/vision.ternobj build/vision-reference.ternobj
	UBSAN_OPTIONS=halt_on_error=1 build/vision-tests-sanitized build/vision.ternobj resources/vision/vision-digits.bin --quick --reference build/vision-reference.ternobj > build/vision-sanitized.log 2>&1 || { tail -30 build/vision-sanitized.log; exit 1; }
	@tail -3 build/vision-sanitized.log

.PHONY: explorer-check explorer-sanitize
build/explorer.ternobj: resources/explorer/navigator.3c src/explorer_protocol.h build/3cc build/tg_assembler scripts/compile_3cc.py
	python3 scripts/compile_3cc.py $< -o $@

build/explorer.o: src/explorer.cc src/explorer.h src/explorer_protocol.h Makefile | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -MMD -MP -c $< -o $@

build/explorer-tests: tests/explorer_tests.cc build/explorer.o build/runtime.o $(OBJECTS)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc $^ $(LDLIBS) -o $@

explorer-check: build/explorer-tests build/explorer.ternobj
	build/explorer-tests build/explorer.ternobj > build/explorer-tests.log 2>&1 || { tail -30 build/explorer-tests.log; exit 1; }
	@tail -1 build/explorer-tests.log

build/explorer-tests-sanitized: tests/explorer_tests.cc src/explorer.cc src/explorer.h src/explorer_protocol.h src/runtime.cc src/runtime.h $(wildcard src/core/*.cc src/core/*.h) Makefile | build
	$(CXX) $(CPPFLAGS) -Isrc -std=c++17 -g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer tests/explorer_tests.cc src/explorer.cc src/runtime.cc $(addprefix src/core/,$(addsuffix .cc,$(CORE))) $(LDLIBS) -o $@

explorer-sanitize: build/explorer-tests-sanitized build/explorer.ternobj
	UBSAN_OPTIONS=halt_on_error=1 build/explorer-tests-sanitized build/explorer.ternobj --quick > build/explorer-sanitized.log 2>&1 || { tail -30 build/explorer-sanitized.log; exit 1; }
	@tail -1 build/explorer-sanitized.log

.PHONY: weight-check weight-sanitize
build/weight_benchmark.o: src/weight_benchmark.cc src/weight_benchmark.h Makefile | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -MMD -MP -c $< -o $@

build/weight-benchmark-tests: tests/weight_benchmark_tests.mm src/macos/WeightBenchmark.mm src/weight_benchmark.h build/weight_benchmark.o Makefile
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -Isrc -fobjc-arc $(filter %.mm %.o,$^) -framework Foundation -framework Metal -framework MetalPerformanceShaders -o $@

weight-check: build/weight-benchmark-tests
	python3 tests/weight_report_tests.py
	build/weight-benchmark-tests resources/benchmark/matvec.metal

build/weight-benchmark-tests-sanitized: tests/weight_benchmark_tests.mm src/macos/WeightBenchmark.mm src/weight_benchmark.cc src/weight_benchmark.h Makefile | build
	$(CXX) $(CPPFLAGS) -Isrc -std=c++17 -g -O1 -fobjc-arc -fsanitize=address,undefined -fno-omit-frame-pointer $(filter %.mm %.cc,$^) -framework Foundation -framework Metal -framework MetalPerformanceShaders -o $@

weight-sanitize: build/weight-benchmark-tests-sanitized
	UBSAN_OPTIONS=halt_on_error=1 build/weight-benchmark-tests-sanitized resources/benchmark/matvec.metal

.PHONY: weight-gpu-validation
weight-gpu-validation: build/weight-benchmark-tests
	MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 build/weight-benchmark-tests resources/benchmark/matvec.metal
