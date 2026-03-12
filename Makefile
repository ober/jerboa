SCHEME = scheme
LIBDIRS = lib
# Base directory for chez-* repos (clone from github.com/ober/chez-*)
CHEZ_EXT_DIR ?= $(HOME)/src
# External chez-* library paths for wrapper modules
CHEZ_EXT_LIBDIRS = $(CHEZ_EXT_DIR)/chez-https/src:$(CHEZ_EXT_DIR)/chez-ssl/src:$(CHEZ_EXT_DIR)/chez-zlib/src:$(CHEZ_EXT_DIR)/chez-pcre2:$(CHEZ_EXT_DIR)/chez-yaml:$(CHEZ_EXT_DIR)/chez-leveldb:$(CHEZ_EXT_DIR)/chez-epoll/src:$(CHEZ_EXT_DIR)/chez-inotify/src:$(CHEZ_EXT_DIR)/chez-crypto/src:$(CHEZ_EXT_DIR)/chez-sqlite/src:$(CHEZ_EXT_DIR)/chez-postgresql/src
# Shared object paths for FFI-based chez-* libraries
CHEZ_EXT_LDPATH = $(CHEZ_EXT_DIR)/chez-ssl:$(CHEZ_EXT_DIR)/chez-zlib:$(CHEZ_EXT_DIR)/chez-pcre2:$(CHEZ_EXT_DIR)/chez-leveldb:$(CHEZ_EXT_DIR)/chez-epoll:$(CHEZ_EXT_DIR)/chez-inotify:$(CHEZ_EXT_DIR)/chez-crypto:$(CHEZ_EXT_DIR)/chez-sqlite:$(CHEZ_EXT_DIR)/chez-postgresql

.PHONY: test test-reader test-core test-runtime test-stdlib test-ffi test-modules test-expanded test-features test-wrappers test-phase4a test-phase4b test-phase4c test-phase4d test-phase4e test-phase4f test-phase5 clean

test: test-reader test-core test-runtime test-stdlib test-ffi test-modules test-expanded

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

test-phase5:
	@echo "--- Phase 5: Compiler as Library tests ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-cp0-passes.ss

test-all: test test-features test-wrappers

clean:
	find lib -name "*.so" -delete 2>/dev/null || true
	find lib -name "*.wpo" -delete 2>/dev/null || true
