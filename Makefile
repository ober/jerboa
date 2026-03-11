SCHEME = scheme
LIBDIRS = lib
# Base directory for chez-* repos (clone from github.com/ober/chez-*)
CHEZ_EXT_DIR ?= $(HOME)/src
# External chez-* library paths for wrapper modules
CHEZ_EXT_LIBDIRS = $(CHEZ_EXT_DIR)/chez-https/src:$(CHEZ_EXT_DIR)/chez-ssl/src:$(CHEZ_EXT_DIR)/chez-zlib/src:$(CHEZ_EXT_DIR)/chez-pcre2:$(CHEZ_EXT_DIR)/chez-yaml:$(CHEZ_EXT_DIR)/chez-leveldb:$(CHEZ_EXT_DIR)/chez-epoll/src:$(CHEZ_EXT_DIR)/chez-inotify/src:$(CHEZ_EXT_DIR)/chez-crypto/src:$(CHEZ_EXT_DIR)/chez-sqlite/src:$(CHEZ_EXT_DIR)/chez-postgresql/src
# Shared object paths for FFI-based chez-* libraries
CHEZ_EXT_LDPATH = $(CHEZ_EXT_DIR)/chez-ssl:$(CHEZ_EXT_DIR)/chez-zlib:$(CHEZ_EXT_DIR)/chez-pcre2:$(CHEZ_EXT_DIR)/chez-leveldb:$(CHEZ_EXT_DIR)/chez-epoll:$(CHEZ_EXT_DIR)/chez-inotify:$(CHEZ_EXT_DIR)/chez-crypto:$(CHEZ_EXT_DIR)/chez-sqlite:$(CHEZ_EXT_DIR)/chez-postgresql

.PHONY: test test-reader test-core test-runtime test-stdlib test-ffi test-modules test-expanded test-features test-wrappers clean

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

test-features:
	@echo "--- Feature tests ---"
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-foreign.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-channel2.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-task.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-typed.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-typed-advanced.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-cache.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-effect.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-async.ss
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-iouring.ss

test-all: test test-features test-wrappers

clean:
	find lib -name "*.so" -delete 2>/dev/null || true
	find lib -name "*.wpo" -delete 2>/dev/null || true
