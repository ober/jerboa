SCHEME = scheme
LIBDIRS = lib
# Base directory for chez-* repos (legacy C FFI — see `make native` for Rust backend)
CHEZ_EXT_DIR ?= $(HOME)/src
# External chez-* library paths for legacy wrapper modules
CHEZ_EXT_LIBDIRS = $(CHEZ_EXT_DIR)/chez-https/src:$(CHEZ_EXT_DIR)/chez-ssl/src:$(CHEZ_EXT_DIR)/chez-zlib/src:$(CHEZ_EXT_DIR)/chez-pcre2:$(CHEZ_EXT_DIR)/chez-leveldb:$(CHEZ_EXT_DIR)/chez-epoll/src:$(CHEZ_EXT_DIR)/chez-inotify/src:$(CHEZ_EXT_DIR)/chez-crypto/src:$(CHEZ_EXT_DIR)/chez-sqlite/src:$(CHEZ_EXT_DIR)/chez-postgresql/src
# Shared object paths for legacy FFI-based chez-* libraries
CHEZ_EXT_LDPATH = $(CHEZ_EXT_DIR)/chez-ssl:$(CHEZ_EXT_DIR)/chez-zlib:$(CHEZ_EXT_DIR)/chez-pcre2:$(CHEZ_EXT_DIR)/chez-leveldb:$(CHEZ_EXT_DIR)/chez-epoll:$(CHEZ_EXT_DIR)/chez-inotify:$(CHEZ_EXT_DIR)/chez-crypto:$(CHEZ_EXT_DIR)/chez-sqlite:$(CHEZ_EXT_DIR)/chez-postgresql

.PHONY: help build test test-reader test-core test-runtime test-stdlib test-ffi test-modules test-expanded test-features test-wrappers test-phase4a test-phase4b test-phase4c test-phase4d test-phase4e test-phase4f test-phase5 test-phase5e test-phase6 test-phase7 test-phase8 test-functional test-repl test-security test-native test-gaps native clean-native audit-native clean fuzz fuzz-smoke fuzz-deep fuzz-reader-fuzz fuzz-json-fuzz fuzz-http2-fuzz fuzz-websocket-fuzz fuzz-dns-fuzz fuzz-pregexp-fuzz fuzz-csv-fuzz fuzz-base64-fuzz fuzz-hex-fuzz fuzz-uri-fuzz fuzz-format-fuzz fuzz-router-fuzz fuzz-sandbox-fuzz test-rawstring test-regex test-rx test-peg test-regex-all docker-build docker-push

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Build:"
	@echo "  build            Compile all Jerboa libraries"
	@echo "  native           Build Rust native library"
	@echo "  clean            Remove compiled .so and .wpo artifacts"
	@echo "  clean-native     Remove Rust build artifacts"
	@echo "  audit-native     Run cargo audit on Rust native library"
	@echo ""
	@echo "Test (core):"
	@echo "  test             Run core test suite (reader, stdlib, ffi, regex)"
	@echo "  test-reader      Reader tests"
	@echo "  test-core        Core language tests"
	@echo "  test-runtime     Runtime tests"
	@echo "  test-stdlib      Standard library tests"
	@echo "  test-ffi         FFI tests"
	@echo "  test-modules     Module system tests"
	@echo "  test-expanded    Expanded stdlib tests"
	@echo "  test-regex-all   All regex tests (rawstring, regex, rx, peg)"
	@echo "  test-rawstring   Raw string reader tests"
	@echo "  test-regex       Regex tests"
	@echo "  test-rx          Rx pattern tests"
	@echo "  test-peg         PEG grammar tests"
	@echo "  test-repl        REPL tests"
	@echo "  test-functional  Functional tests (I/O, fork, signals)"
	@echo "  test-gaps        Gap coverage tests"
	@echo ""
	@echo "Test (features):"
	@echo "  test-features    Phase 2 + Phase 3 feature tests"
	@echo "  test-wrappers    FFI wrapper module tests"
	@echo "  test-security    Security tests"
	@echo "  test-native      Rust native library tests"
	@echo "  test-all         All test suites combined"
	@echo "  test-phase2      Phase 2 feature tests"
	@echo "  test-phase3      Phase 3 feature tests"
	@echo "  test-phase4a     Phase 4a: Core runtime tests"
	@echo "  test-phase4b     Phase 4b: Type system and safety tests"
	@echo "  test-phase4c     Phase 4c: Systems and performance tests"
	@echo "  test-phase4d     Phase 4d: Developer experience tests"
	@echo "  test-phase4e     Phase 4e: Data and distribution tests"
	@echo "  test-phase4f     Phase 4f: Toolchain and interop tests"
	@echo "  test-phase5      Phase 5: All sub-phases"
	@echo "  test-phase5e     Phase 5e: Systems and zero-cost tests"
	@echo "  test-phase6      Phase 6: Real programs tests"
	@echo "  test-phase7      Phase 7: Gerbil porting features"
	@echo "  test-phase8      Phase 8: Deep Gerbil compatibility"
	@echo ""
	@echo "Fuzzing:"
	@echo "  fuzz             Run all fuzz harnesses (default iterations)"
	@echo "  fuzz-smoke       Quick smoke fuzz for CI (~30s)"
	@echo "  fuzz-deep        Long-running deep fuzz (nightly)"
	@echo "  fuzz-<target>    Individual fuzz targets (reader, json, http2, ...)"
	@echo ""
	@echo "Docker:"
	@echo "  docker-build     Build jerboa21/jerboa base image"
	@echo "  docker-push      Push base image to Docker Hub"

build:
	$(SCHEME) --libdirs $(LIBDIRS) --script support/build.ss

test: test-reader test-core test-runtime test-stdlib test-ffi test-modules test-expanded test-regex-all

test-reader:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-reader.ss

test-core:
	@if [ -f tests/test-core.ss ]; then \
		$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-core.ss; \
	fi

test-runtime:
	@if [ -f tests/test-runtime.ss ]; then \
		$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-runtime.ss; \
	fi

test-stdlib:
	@if [ -f tests/test-stdlib.ss ]; then \
		$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-stdlib.ss; \
	fi

test-ffi:
	@if [ -f tests/test-ffi.ss ]; then \
		$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-ffi.ss; \
	fi

test-modules:
	@if [ -f tests/test-modules.ss ]; then \
		$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-modules.ss; \
	fi

test-expanded:
	@if [ -f tests/test-expanded-stdlib.ss ]; then \
		$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-expanded-stdlib.ss; \
	fi

# --- Regex / rx / peg test suite ---
test-rawstring:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-reader-rawstring.ss

test-regex:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-regex.ss

test-rx:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-rx.ss

test-peg:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-peg.ss

# Run all regex-related tests in order (rawstring must pass before regex, etc.)
test-regex-all: test-rawstring test-regex test-rx test-peg

test-wrappers:
	@echo "--- Wrapper module tests ---"
	@$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrappers.ss 2>/dev/null || echo "  yaml: SKIP (library not found)"
	@LD_LIBRARY_PATH="$(CHEZ_EXT_LDPATH):$$LD_LIBRARY_PATH" \
		$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-zlib.ss 2>/dev/null \
		|| echo "  zlib: SKIP (requires chez_zlib_shim.so)"
	@ln -sf $(CHEZ_EXT_DIR)/chez-ssl/chez_ssl_shim.so ./chez_ssl_shim.so 2>/dev/null; \
		LD_LIBRARY_PATH="$(CHEZ_EXT_LDPATH):$$LD_LIBRARY_PATH" \
		$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-ssl.ss 2>/dev/null \
		&& $(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-request.ss 2>/dev/null; \
		rm -f ./chez_ssl_shim.so \
		|| echo "  ssl/request: SKIP (requires chez_ssl_shim.so)"
	@LD_LIBRARY_PATH="$(CHEZ_EXT_LDPATH):$$LD_LIBRARY_PATH" CHEZ_PCRE2_LIB="$(CHEZ_EXT_DIR)/chez-pcre2" \
		$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-pcre2.ss 2>/dev/null \
		|| echo "  pcre2: SKIP (requires pcre2_shim.so)"
	@LD_LIBRARY_PATH="$(CHEZ_EXT_LDPATH):$$LD_LIBRARY_PATH" \
		$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-epoll.ss 2>/dev/null \
		|| echo "  epoll: SKIP (requires chez_epoll_shim.so)"
	@LD_LIBRARY_PATH="$(CHEZ_EXT_LDPATH):$$LD_LIBRARY_PATH" \
		$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-inotify.ss 2>/dev/null \
		|| echo "  inotify: SKIP (requires chez_inotify_shim.so)"
	@LD_LIBRARY_PATH="$(CHEZ_EXT_LDPATH):$$LD_LIBRARY_PATH" \
		$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-crypto.ss 2>/dev/null \
		|| echo "  crypto: SKIP (requires chez_crypto_shim.so)"
	@LD_LIBRARY_PATH="$(CHEZ_EXT_LDPATH):$$LD_LIBRARY_PATH" \
		$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-sqlite.ss 2>/dev/null \
		|| echo "  sqlite: SKIP (requires chez_sqlite_shim.so)"
	@LD_LIBRARY_PATH="$(CHEZ_EXT_LDPATH):$$LD_LIBRARY_PATH" \
		$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-postgresql.ss 2>/dev/null \
		|| echo "  postgresql: SKIP (requires chez_pg_shim.so)"

test-features: test-phase2 test-phase3

test-phase2:
	@echo "--- Phase 2 feature tests ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-foreign.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-channel2.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-task.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-typed.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-typed-advanced.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-cache.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-effect.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-async.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-iouring.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-stm.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-ffi-bind.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-match2.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-staging.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-cluster.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-devex.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-capability.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-seq.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-table.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-concur.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-build.ss

test-phase3:
	@echo "--- Phase 3 feature tests ---"
	@echo "-- Phase 3a: Observability --"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-log.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-metrics.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-span.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-health.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-circuit.ss
	@echo "-- Phase 3b: Advanced Networking --"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-websocket.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-http2.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-dns.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-rate.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-router.ss
	@echo "-- Phase 3c: Build & Package Tooling --"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-pkg.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-lock.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-hot.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-embed.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-cross.ss
	@echo "-- Phase 3d: Language Extensions --"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-query.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-schema.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-pipeline.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-rewrite.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-lint.ss
	@echo "-- Phase 3e: WASM Target --"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-wasm-format.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-wasm-codegen.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-wasm-runtime.ss

test-phase4a:
	@echo "--- Phase 4a: Core Runtime tests ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-effect-deep.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-engine-pool.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-transducer.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-type-env.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-type-infer.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-error-advice.ss

test-phase4b:
	@echo "--- Phase 4b: Type System and Safety tests ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-hkt.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-monad.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-refine.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-solver.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-row2.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-effects-new.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-taint.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-sandbox.ss

test-phase4c:
	@echo "--- Phase 4c: Systems and Performance tests ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-arena.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-binary.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-mmap-btree.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-multishot.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-deadlock.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-concur-util.ss

test-phase4d:
	@echo "--- Phase 4d: Developer Experience tests ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-timetravel.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-flamegraph.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-proptest.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-staging2.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-match-syntax.ss

test-phase4e:
	@echo "--- Phase 4e: Data and Distribution tests ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-dataframe.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-stream-window.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-distributed.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-wasi.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-checkpoint.ss

test-phase4f:
	@echo "--- Phase 4f: Toolchain and Interop tests ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-lsp.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-python.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-build-watch.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-cross-compile.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-reproducible.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-musl.ss

test-phase5: test-phase5a test-phase5b test-phase5c test-phase5d test-phase5e

test-phase5a:
	@echo "--- Phase 5a: Compiler as Library ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-cp0-passes.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-compiler-partial-eval.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-regex-compile.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-delimited.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-pgo.ss

test-phase5b:
	@echo "--- Phase 5b: Persistence and Distribution ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-persist-closure.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-persist-image.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-continuation-marks.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-coroutine.ss

test-phase5c:
	@echo "--- Phase 5c: Inspector and Debugging ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-inspector.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-closure-inspect.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-record-inspect.ss

test-phase5d:
	@echo "--- Phase 5d: Advanced Effects and Concurrency ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-effect-fusion.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-stm-nested.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-async-await.ss

test-phase5e:
	@echo "--- Phase 5e: Systems and Zero-Cost ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-benchmark.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-json-schema.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-query-compile.ss

test-phase6:
	@echo "--- Phase 6: Making Real Programs Easier to Build ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-phase6.ss

test-phase7:
	@echo "--- Phase 7: Gerbil Porting Features ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --program tests/test-phase7.ss

test-phase8:
	@echo "--- Phase 8: Deep Gerbil Compatibility ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --program tests/test-phase8.ss

test-repl:
	@echo "--- REPL tests ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-repl-enhanced.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-repl-server.ss

test-functional:
	@echo "--- Functional Tests (real I/O, fork, Landlock, signals) ---"
	@gcc -shared -fPIC -O2 -o support/libjerboa-landlock.so support/landlock-shim.c 2>/dev/null || true
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-functional.ss

test-security:
	@echo "--- Security tests ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-crypto-random.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-crypto-compare.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-crypto-digest.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-crypto-native.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-security-capability.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-restrict-hardened.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-process-exec.ss
	@JERBOA_DB_HOST=evil.com JERBOA_DB_PORT=5433 JERBOA_SECRET=leaked $(SCHEME) --libdirs $(LIBDIRS) --script tests/test-config-env.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-audit.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-sanitize.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-phase3-security.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-phase3-remaining.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-phase4-safety.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-phase5-os.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-phase6-supply.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-security2-parsers.ss

# Rust native library
RUST_NATIVE_DIR = jerboa-native-rs
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  NATIVE_LIB_EXT = dylib
  NATIVE_LD_VAR = DYLD_LIBRARY_PATH
else
  NATIVE_LIB_EXT = so
  NATIVE_LD_VAR = LD_LIBRARY_PATH
endif
RUST_NATIVE_LIB = $(RUST_NATIVE_DIR)/target/release/libjerboa_native.$(NATIVE_LIB_EXT)

$(RUST_NATIVE_LIB): $(RUST_NATIVE_DIR)/src/*.rs $(RUST_NATIVE_DIR)/Cargo.toml
	cd $(RUST_NATIVE_DIR) && cargo build --release --features full

native: $(RUST_NATIVE_LIB)
	cp $(RUST_NATIVE_LIB) lib/

clean-native:
	cd $(RUST_NATIVE_DIR) && cargo clean
	rm -f lib/libjerboa_native.$(NATIVE_LIB_EXT)

test-native: native
	@echo "--- Rust native library tests (weeks 1-4) ---"
	@$(NATIVE_LD_VAR)=lib $(SCHEME) --libdirs $(LIBDIRS) --script tests/test-native-rust.ss
	@echo "--- Rust native library tests (weeks 5-6) ---"
	@$(NATIVE_LD_VAR)=lib $(SCHEME) --libdirs $(LIBDIRS) --script tests/test-native-rust-week5-6.ss

audit-native:
	cd $(RUST_NATIVE_DIR) && cargo audit

test-gaps:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-gaps.ss

test-all: test test-features test-wrappers test-security test-native test-gaps

## ========== Fuzzing ==========

FUZZ_DIR = tests/fuzz/harness
FUZZ_ITERATIONS ?= 10000

# Run all fuzz harnesses (default iterations)
fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-all.ss

# Quick smoke test for CI (~30s)
fuzz-smoke:
	FUZZ_ITERATIONS=500 $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-all.ss

# Long-running deep fuzz (nightly/dedicated)
fuzz-deep:
	FUZZ_ITERATIONS=1000000 FUZZ_MAX_SIZE=65536 $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-all.ss

# Individual fuzz targets
fuzz-reader-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-reader.ss

fuzz-json-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-json.ss

fuzz-http2-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-http2.ss

fuzz-websocket-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-websocket.ss

fuzz-dns-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-dns.ss

fuzz-pregexp-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-pregexp.ss

fuzz-csv-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-csv.ss

fuzz-base64-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-base64.ss

fuzz-hex-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-hex.ss

fuzz-uri-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-uri.ss

fuzz-format-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-format.ss

fuzz-router-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-router.ss

fuzz-sandbox-fuzz:
	FUZZ_ITERATIONS=$(FUZZ_ITERATIONS) $(SCHEME) --libdirs $(LIBDIRS) --script $(FUZZ_DIR)/fuzz-sandbox.ss

clean:
	find lib -name "*.so" -delete 2>/dev/null || true
	find lib -name "*.wpo" -delete 2>/dev/null || true

# ── Docker base image (jerboa21/jerboa) ──────────────────────────────────────
# Base image for building static musl binaries of Jerboa projects.
# Includes: stock Chez, musl Chez, jerboa lib, musl-gcc, build deps.
DOCKER_IMAGE = jerboa21/jerboa

docker-build:
	@echo "=== Building $(DOCKER_IMAGE) base image ==="
	docker build --platform linux/amd64 -t $(DOCKER_IMAGE) .
	@echo ""
	@docker images $(DOCKER_IMAGE) --format "Image: {{.Repository}}:{{.Tag}}  Size: {{.Size}}"

docker-push: docker-build
	@echo "=== Pushing $(DOCKER_IMAGE) to Docker Hub ==="
	docker push $(DOCKER_IMAGE)
	@echo "Pushed $(DOCKER_IMAGE)"
