# Compiling Gerbil Projects with Jerboa

This guide walks through the complete process of taking an existing Gerbil
Scheme project and compiling it to run on Chez Scheme via Jerboa.

## Prerequisites

1. **Chez Scheme 10.x** with threads (`./configure --threads && make && make install`)
2. **Jerboa** built and ready:
   ```bash
   git clone https://github.com/ober/jerboa ~/mine/jerboa
   cd ~/mine/jerboa && make
   ```
3. **Gerbil source tree** (for the modules your project imports):
   ```bash
   # Only needed if your project imports :std/* modules
   git clone https://github.com/mighty-gerbils/gerbil ~/mine/gerbil
   ```

## Project Layout

A jerboa project wraps an existing Gerbil project with build scripts and a
compatibility layer:

```
my-jerboa-project/
  my-gerbil-project/        # Gerbil source (submodule or copy)
    gerbil.pkg
    *.ss                     # Gerbil source files (never modified)
  src/
    compat/                  # Chez compatibility shims (handwritten)
      sugar.sls              # :std/sugar equivalents
      format.sls             # :std/format equivalents
      ...
    mylib/                   # Generated .sls files (gitignored)
  build-jerboa.ss            # Jerboa translation driver
  build-all.ss               # Chez compilation trigger
  build-binary.ss            # Optional: standalone binary builder
  main.ss                    # Entry point program
  Makefile
```

## Step 1: Create the Makefile

```makefile
SCHEME = scheme
JERBOA = $(or $(JERBOA_DIR),$(HOME)/mine/jerboa/src)
LIBDIRS = src:$(JERBOA)
COMPILE = $(SCHEME) -q --libdirs $(LIBDIRS) --compile-imported-libraries

.PHONY: all jerboa compile binary run clean

all: jerboa compile

# Translate .ss -> .sls via jerboa
jerboa:
	$(COMPILE) < build-jerboa.ss

# Compile .sls -> .so via Chez
compile: jerboa
	$(COMPILE) < build-all.ss

# Build standalone binary
build: binary
binary: clean jerboa
	$(SCHEME) -q --libdirs $(LIBDIRS) --program build-binary.ss

# Run interpreted
run: all
	$(SCHEME) -q --libdirs $(LIBDIRS) --program main.ss

clean:
	find src -name '*.so' -o -name '*.wpo' | xargs rm -f 2>/dev/null || true
	rm -f src/mylib/*.sls
```

The `JERBOA` variable points to jerboa's `src/` directory. Override it:
```bash
JERBOA_DIR=/path/to/jerboa/src make
```

If your project depends on other jerboa-compiled libraries, add them to
`LIBDIRS`:
```makefile
JERBOA_AWS = $(or $(JERBOA_AWS_DIR),jerboa-aws/src)
LIBDIRS = src:$(JERBOA):$(JERBOA_AWS)
```

## Step 2: Write the Import Map

The import map is the most important part. It tells jerboa how to translate
Gerbil's `:module/path` imports into R6RS `(library name)` imports.

```scheme
(define my-import-map
  '(;; Standard library -> compat shims
    (:std/sugar        . (compat sugar))
    (:std/format       . (compat format))
    (:std/sort         . (compat sort))
    (:std/pregexp      . (compat pregexp))
    (:std/error        . (runtime error))
    (:std/misc/string  . (compat misc))
    (:std/misc/list    . (compat misc))
    (:std/misc/hash    . (compat misc))

    ;; Strip imports that have no Chez equivalent
    (:std/iter         . #f)   ;; jerboa compiles for-loops natively
    (:std/foreign      . #f)   ;; no FFI at this level
    (:gerbil/core      . #f)   ;; runtime provides these
    (:gerbil/runtime   . #f)

    ;; Project-internal imports (relative)
    ("./util"          . (mylib util))

    ;; Cross-project dependencies
    (:ober/aws/s3      . (jerboa-aws s3-api))
    ))
```

Three mapping types:
- **`(library name)`**: Replace the import with this R6RS library
- **`#f`**: Strip the import entirely (provided by base imports or unnecessary)
- Unmapped imports cause a compile error — this is intentional, so you catch
  missing mappings early

## Step 3: Define Base Imports

Base imports are injected into every compiled module. They provide the runtime
environment that Gerbil code expects:

```scheme
(define my-base-imports
  '(;; Chez Scheme with exclusions for Gambit-compatible replacements
    (except (chezscheme) void box box? unbox set-box!
            andmap ormap iota last-pair find
            1+ 1- fx/ fx1+ fx1-
            error error? raise with-exception-handler identifier?
            hash-table? make-hash-table)
    ;; Jerboa runtime
    (compat types)
    (runtime util)
    (runtime table)
    (runtime mop)
    (runtime error)
    (runtime hash)
    ;; Gambit compatibility (threading, u8vectors, etc.)
    (except (compat gambit) number->string make-mutex
            with-output-to-string)))
```

The `(except (chezscheme) ...)` clause is critical. Jerboa's runtime
redefines several Chez builtins with Gambit-compatible versions. Without
the exclusions, R6RS reports import conflicts.

## Step 4: Write build-jerboa.ss

The complete translation driver:

```scheme
#!chezscheme
(import
  (except (chezscheme) void box box? unbox set-box!
          andmap ormap iota last-pair find
          1+ 1- fx/ fx1+ fx1-
          error error? raise with-exception-handler identifier?
          hash-table? make-hash-table)
  (compiler compile))

(define output-dir "src/mylib")

;; Import map and base imports (as defined above)
(define my-import-map '(...))
(define my-base-imports '(...))

;; Compile one module
(define (compile-module name)
  (let* ((input  (string-append "my-gerbil-project/" name ".ss"))
         (output (string-append output-dir "/" name ".sls"))
         (lib    `(mylib ,(string->symbol name))))
    (printf "  Compiling ~a.ss~n" name)
    (guard (exn
             (#t (printf "  ERROR: ~a: ~a~n" name (condition-message exn))
                 #f))
      (let* ((lib-form (gerbil-compile-to-library
                         input lib my-import-map my-base-imports))
             (lib-form (fix-import-conflicts lib-form)))
        (call-with-output-file output
          (lambda (port)
            (display "#!chezscheme\n" port)
            (parameterize ([print-gensym #f])
              (pretty-print lib-form port)))
          'replace)
        (printf "  OK: ~a~n" output)
        #t))))

;; Compile in dependency order (leaves first)
(display "=== Translating .ss -> .sls ===\n")
(compile-module "util")
(compile-module "core")
(compile-module "main")

(display "=== Translation complete ===\n")
```

### Key functions from `(compiler compile)`:

- **`gerbil-compile-to-library`** `(input-path lib-name import-map base-imports)`
  Reads a `.ss` file, compiles it through jerboa, wraps in an R6RS library form.

- **`fix-import-conflicts`** `(lib-form)`
  Post-processes the library to add `(except ...)` for local definitions that
  shadow imports. Also fixes `set!`'d exports with `identifier-syntax`.

- **`jerboa-compile-file`** `(input-path)`
  Lower-level: compiles a file and returns the compiled forms (no library wrapper).

- **`jerboa-compile-string`** `(code-string)`
  Compiles a string of Gerbil code. Useful for testing.

## Step 5: Write build-all.ss

This simply imports every module, which triggers Chez's `--compile-imported-libraries`:

```scheme
#!chezscheme
(import (mylib util) (mylib core) (mylib main))
(printf "All modules compiled.~n")
```

## Step 6: Write Compatibility Shims

Your project likely imports Gerbil standard library modules (`:std/sugar`,
`:std/format`, etc.). These need Chez equivalents in `src/compat/`.

### Example: src/compat/sugar.sls

```scheme
#!chezscheme
(library (compat sugar)
  (export try catch finally with-catch
          hash hash-ref hash-set! hash-update! hash-keys hash-values
          defstruct defrules)
  (import (chezscheme))

  (define-syntax try
    (syntax-rules (catch finally)
      [(_ body (catch (var) handler ...))
       (guard (var [#t handler ...]) body)]
      [(_ body (finally cleanup ...))
       (dynamic-wind void (lambda () body) (lambda () cleanup ...))]))

  ;; ... more shims
  )
```

### Common Compat Modules

| Gerbil Module | Chez Equivalent | What It Provides |
|---------------|-----------------|------------------|
| `:std/sugar` | `(compat sugar)` | `try/catch/finally`, `hash` literals, `with-catch` |
| `:std/format` | `(compat format)` | `fprintf`, `printf`, `format` (Gambit-style) |
| `:std/sort` | `(compat sort)` | `sort`, `stable-sort` (Gambit arg order) |
| `:std/pregexp` | `(compat pregexp)` | Portable regex (pure Scheme) |
| `:std/misc/*` | `(compat misc)` | `string-split`, `string-join`, `path-expand`, etc. |
| `:std/error` | `(runtime error)` | `Error`, `error?`, `with-exception-catcher` |
| `:std/os/signal` | `(compat signal)` | Signal handling |
| `:std/os/fdio` | `(compat fdio)` | File descriptor I/O |

You don't always need to write these from scratch. Check if jerboa-shell's
`src/compat/` already has what you need — many shims are reusable.

## Step 7: Build and Test

```bash
make              # translate + compile
make run          # run interpreted
make build        # build standalone binary (if build-binary.ss exists)
```

## Common Issues and Fixes

### Import Conflicts

**Problem**: R6RS forbids a local `define` that shadows an imported name.

**Fix**: `fix-import-conflicts` handles this automatically. If you see
"multiple definitions" errors, ensure you're calling it on the library form
before writing it out.

### set! on Exported Variables

**Problem**: R6RS forbids `set!` on exported variables.

**Fix**: `fix-import-conflicts` rewrites these using `identifier-syntax` with
a vector cell:
```scheme
;; Before (forbidden in R6RS):
(export foo)
(define foo 0)
(set! foo 42)

;; After (automatic rewrite):
(export foo)
(define foo-cell (vector 0))
(define-syntax foo
  (identifier-syntax
    (id (vector-ref foo-cell 0))
    ((set! id v) (vector-set! foo-cell 0 v))))
```

### Keyword Arguments

**Problem**: Gerbil uses `key: value` keyword arguments. Jerboa translates
these, but `defclass` constructors may pass keyword values as positional args.

**Fix**: Post-build patch in `build-jerboa.ss`:
```scheme
(patch-file! "src/mylib/types.sls"
  "(lp (cddr rest) (cons (cadr rest) acc))]"
  "(lp (cddr rest) acc)]")
```

### make-mutex String Arguments

**Problem**: Gambit's `make-mutex` accepts strings; Chez requires symbols.

**Fix**: Post-build patch:
```scheme
(patch-file! "src/mylib/foo.sls"
  "(make-mutex \"my-lock\")"
  "(make-mutex 'my-lock)")
```

### void Recursion

**Problem**: Gerbil defines `(define (void) ...)` which creates a recursive
definition in the translated output.

**Fix**: Post-build patch:
```scheme
(patch-file! "src/mylib/foo.sls"
  "(define (void) (void))"
  "(define (void . _) (if #f #f))")
```

### Chez Lazy Library Invocation

**Problem**: Chez only invokes a library when one of its exports is first
referenced at runtime. If a module registers side effects at load time (like
registering builtins), they won't execute.

**Fix**: Add a dummy reference in a module that's guaranteed to be invoked:
```scheme
;; In main.sls, force invocation of side-effecting modules:
(define _force-builtins special-builtin?)  ;; references a builtins export
```

### Threading

**Problem**: Programs in Chez boot files cannot create threads (GC futex
deadlock).

**Fix**: Put only libraries in the boot file. Load the program at runtime via
`memfd` + `Sscheme_script`. See [docs/single-binary.md](single-binary.md).

## FFI (C Bindings)

For projects that need C FFI:

1. Write a C shim (`ffi-shim.c`) with the functions you need
2. Compile to a shared library: `gcc -shared -fPIC -o libffi.so ffi-shim.c`
3. Create `src/compat/ffi.sls` using Chez's `foreign-procedure` and `load-shared-object`
4. Map Gerbil's FFI imports to your compat module

For standalone binaries, the C shim is compiled directly into the binary. See
[docs/single-binary.md](single-binary.md).

## Optimization

For production builds:

```bash
make compile-opt3     # optimize-level 3
make compile-wpo      # whole-program optimization
```

See [docs/optimization.md](optimization.md) for tuning `cp0-effort-limit`,
per-file directives, and benchmark results.

## Reference: Existing Projects

Study these for real-world patterns:

| Project | Modules | Key Patterns |
|---------|---------|--------------|
| [jerboa-shell](https://github.com/ober/jerboa-shell) | 30+ | FFI shim, binary building, post-build patches |
| jerboa-kunabi | 10+ | Cross-project deps (jerboa-aws), sed-based patches |
| jerboa-lsp | 53 | Large module count, JSON/HTTP compat |
