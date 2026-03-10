SCHEME = scheme
LIBDIRS = lib

.PHONY: test test-reader test-core test-runtime test-stdlib test-ffi test-modules test-expanded clean

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

clean:
	find lib -name "*.so" -delete 2>/dev/null || true
	find lib -name "*.wpo" -delete 2>/dev/null || true
