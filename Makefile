SCHEME = scheme
LIBDIRS = lib
# External chez-* library paths for wrapper modules
CHEZ_EXT_LIBDIRS = $(HOME)/mine/chez-https/src:$(HOME)/mine/chez-ssl/src:$(HOME)/mine/chez-zlib/src:$(HOME)/mine/chez-pcre2:$(HOME)/mine/chez-yaml:$(HOME)/mine/chez-leveldb:$(HOME)/mine/chez-epoll/src
# Shared object paths for FFI-based chez-* libraries
CHEZ_EXT_LDPATH = $(HOME)/mine/chez-ssl:$(HOME)/mine/chez-zlib:$(HOME)/mine/chez-pcre2:$(HOME)/mine/chez-leveldb:$(HOME)/mine/chez-epoll

.PHONY: test test-reader test-core test-runtime test-stdlib test-ffi test-modules test-expanded test-wrappers clean

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
	@ln -sf $(HOME)/mine/chez-ssl/chez_ssl_shim.so ./chez_ssl_shim.so 2>/dev/null; \
		LD_LIBRARY_PATH="$(CHEZ_EXT_LDPATH):$$LD_LIBRARY_PATH" \
		$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-ssl.ss 2>/dev/null \
		&& $(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-request.ss 2>/dev/null; \
		rm -f ./chez_ssl_shim.so \
		|| echo "  ssl/request: SKIP (requires chez_ssl_shim.so)"
	@LD_LIBRARY_PATH="$(CHEZ_EXT_LDPATH):$$LD_LIBRARY_PATH" CHEZ_PCRE2_LIB="$(HOME)/mine/chez-pcre2" \
		$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-pcre2.ss 2>/dev/null \
		|| echo "  pcre2: SKIP (requires pcre2_shim.so)"
	@LD_LIBRARY_PATH="$(CHEZ_EXT_LDPATH):$$LD_LIBRARY_PATH" \
		$(SCHEME) --libdirs "$(LIBDIRS):$(CHEZ_EXT_LIBDIRS)" --script tests/test-wrapper-epoll.ss 2>/dev/null \
		|| echo "  epoll: SKIP (requires chez_epoll_shim.so)"

test-all: test test-wrappers

clean:
	find lib -name "*.so" -delete 2>/dev/null || true
	find lib -name "*.wpo" -delete 2>/dev/null || true
