# Building a Self-Contained Chez Scheme Binary: Tricks and Techniques

This document captures every trick used to build jerboa-shell's `jsh` — a single ELF binary that embeds Chez Scheme's runtime, boot files, 30+ Gerbil-to-Chez compiled modules, a Gerbil reader/compiler, and POSIX FFI bindings. The binary works from any directory with zero external dependencies (beyond libc and system libraries).

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Embedding Boot Files as C Byte Arrays](#2-embedding-boot-files-as-c-byte-arrays)
3. [The Threading Bug: Separating Libraries from Program](#3-the-threading-bug-separating-libraries-from-program)
4. [Loading the Program via memfd](#4-loading-the-program-via-memfd)
5. [Custom C Main: Bypassing Chez's Argument Parsing](#5-custom-c-main-bypassing-chezs-argument-parsing)
6. [The Jerboa Compilation Pipeline](#6-the-jerboa-compilation-pipeline)
7. [Import Conflict Resolution (R6RS Constraints)](#7-import-conflict-resolution-r6rs-constraints)
8. [Mutable Export Workaround (identifier-syntax)](#8-mutable-export-workaround-identifier-syntax)
9. [Chez Lazy Library Invocation Workaround](#9-chez-lazy-library-invocation-workaround)
10. [Post-Build Patching](#10-post-build-patching)
11. [The Gambit-to-Chez Compatibility Layer](#11-the-gambit-to-chez-compatibility-layer)
12. [FFI via C Shim (No Foreign Library Dependencies)](#12-ffi-via-c-shim-no-foreign-library-dependencies)
13. [WPO Incompatibility with identifier-syntax](#13-wpo-incompatibility-with-identifier-syntax)
14. [Boot File Dependency Ordering](#14-boot-file-dependency-ordering)
15. [Build Pipeline Summary](#15-build-pipeline-summary)

---

## 1. Architecture Overview

The binary packs four layers into one ELF:

```
┌──────────────────────────────────────────┐
│  jsh-main.c (custom C entry point)       │
├──────────────────────────────────────────┤
│  petite.boot  ─┐                         │
│  scheme.boot   ├─ C byte arrays          │
│  jsh.boot     ─┘  (Sregister_boot_file_bytes) │
├──────────────────────────────────────────┤
│  jsh_program.h  (compiled program .so    │
│                   as C byte array,       │
│                   loaded via memfd)       │
├──────────────────────────────────────────┤
│  ffi-shim.c  (POSIX C bindings)         │
├──────────────────────────────────────────┤
│  libkernel  (Chez Scheme runtime, linked)│
└──────────────────────────────────────────┘
```

The key insight: everything that would normally be separate files (boot files, compiled .so modules, the program itself) is converted to C byte arrays at build time and compiled directly into the binary.

---

## 2. Embedding Boot Files as C Byte Arrays

**Problem**: Chez Scheme normally locates boot files by searching paths relative to the executable name. If you rename or move the binary, it can't find them. The traditional workaround — appending boot files to the ELF with `cat` — still depends on the binary name matching the boot file name (e.g., `jsh` needs `jsh.boot`).

**Solution**: Use `Sregister_boot_file_bytes()` to register boot file contents from memory. At build time, each `.boot` file is serialized into a C header:

```scheme
;; build-binary.ss — generates C headers from binary files
(define (file->c-header input-path output-path array-name size-name)
  (let* ((data (get-bytevector-all (open-file-input-port input-path)))
         (size (bytevector-length data)))
    (call-with-output-file output-path
      (lambda (out)
        (fprintf out "static const unsigned char ~a[] = {~n" array-name)
        (let loop ((i 0))
          (when (< i size)
            (fprintf out "0x~2,'0x" (bytevector-u8-ref data i))
            ...))
        (fprintf out "static const unsigned int ~a = ~a;~n" size-name size)))))
```

This produces headers like:
```c
// jsh_petite_boot.h — ~1.9 MB as C array
static const unsigned char petite_boot_data[] = {
  0x00,0x00,0x00,0x00,0x63,0x68,0x65,0x7a,...
};
static const unsigned int petite_boot_size = 1961464;
```

At startup, the C main registers them:
```c
Sregister_boot_file_bytes("petite", (void*)petite_boot_data, petite_boot_size);
Sregister_boot_file_bytes("scheme", (void*)scheme_boot_data, scheme_boot_size);
Sregister_boot_file_bytes("jsh",    (void*)jsh_boot_data,    jsh_boot_size);
Sbuild_heap(NULL, NULL);  // NULL — no need to search the filesystem
```

The boot files total ~5.5 MB (petite ~1.9 MB, scheme ~1.0 MB, jsh ~2.6 MB), all compiled into the binary's `.rodata` section.

---

## 3. The Threading Bug: Separating Libraries from Program

**Problem**: When a Chez Scheme program is included in a boot file via `make-boot-file`, any threads created by `fork-thread` will deadlock. The child threads block forever on an internal GC futex. This is a Chez Scheme bug.

**Discovery**: The shell uses threads for pipeline parallelism and background jobs. Including the program in the boot file caused every pipeline to hang.

**Solution**: Split the boot file into **libraries-only** (no program code). The program is compiled separately and loaded at runtime:

```scheme
;; Boot file contains ONLY libraries — no program
(apply make-boot-file "jsh.boot" '("scheme" "petite")
  (append
    jerboa-runtime-modules    ; types, MOP, error, hash, compiler...
    compat-layer-modules      ; gambit shims, misc, sugar, pregexp...
    jsh-modules))             ; all shell modules in dependency order

;; Program is compiled separately
(compile-program "jsh.ss")    ; produces jsh.so
```

The program `.so` is then embedded as a C byte array and loaded via `Sscheme_script` at runtime (see next section).

---

## 4. Loading the Program via memfd

**Problem**: `Sscheme_script()` takes a file path, but the program `.so` is embedded in the binary — there's no file on disk.

**Solution**: Use Linux's `memfd_create()` to create an anonymous in-memory file descriptor, write the embedded program data to it, and pass `/proc/self/fd/N` as the path:

```c
// Create anonymous memory-backed fd
int fd = memfd_create("jsh-program", MFD_CLOEXEC);
write(fd, jsh_program_data, jsh_program_size);

// Chez can load it via /proc/self/fd/N
char prog_path[64];
snprintf(prog_path, sizeof(prog_path), "/proc/self/fd/%d", fd);

// Sbuild_heap loads libraries from boot files
Sbuild_heap(NULL, NULL);

// Sscheme_script loads+runs the program (preserves threading!)
int status = Sscheme_script(prog_path, 1, script_args);
```

**Why `Sscheme_script` instead of `Sscheme_start`**: `Sscheme_start` is for programs baked into boot files (which deadlock threads). `Sscheme_script` loads and runs a `.so` file after the heap is built, preserving full threading support.

---

## 5. Custom C Main: Bypassing Chez's Argument Parsing

**Problem**: Chez Scheme's default `main()` interprets command-line flags. The shell's `-c` flag (run command string) is swallowed by Chez as `--compact` (heap compaction). Similar conflicts with `-e`, `-q`, etc.

**Solution**: Write a custom `jsh-main.c` that saves all arguments in numbered environment variables before Chez sees them:

```c
// C main saves args in env vars
setenv("JSH_ARGC", "3", 1);
setenv("JSH_ARG0", "-c", 1);
setenv("JSH_ARG1", "echo hello", 1);
setenv("JSH_ARG2", "world", 1);

// Chez is initialized with NO user args
Sscheme_init(NULL);
Sbuild_heap(NULL, NULL);
```

The Scheme entry point reads them back:
```scheme
(define (get-real-args)
  (let ((argc-str (getenv "JSH_ARGC")))
    (if argc-str
      ;; Binary mode: read from env vars
      (let ((argc (string->number argc-str)))
        (let loop ((i 0) (acc '()))
          (if (>= i argc) (reverse acc)
            (loop (+ i 1) (cons (getenv (format "JSH_ARG~a" i)) acc)))))
      ;; Interpreted mode: use (command-line)
      (cdr (command-line)))))
```

Link with the custom main instead of Chez's `main.o`:
```
gcc -rdynamic -o jsh jsh-main.o ffi-shim.o -lkernel -llz4 -lz -lm -ldl -lpthread -luuid -lncurses
```

---

## 6. The Jerboa Compilation Pipeline

**Problem**: Source files are written in Gerbil Scheme (`.ss`) which uses syntax, macros, and module system conventions incompatible with Chez's R6RS. The files must be preserved as `.ss` and only converted at build time.

**Solution**: The Jerboa compiler (`gerbil-compile-to-library`) transforms each `.ss` file into an R6RS `(library ...)` form. An import map translates Gerbil module references to Chez library names:

```scheme
(define jsh-import-map
  '((:std/sugar        . (compat sugar))     ; Gerbil sugar -> our compat lib
    (:std/format       . (compat format))
    (:std/pregexp      . (compat pregexp))
    (:std/iter         . #f)                  ; stripped — Jerboa handles natively
    (:std/foreign      . #f)                  ; stripped — not needed on Chez
    (:gerbil/core      . #f)                  ; stripped
    ("./pregexp-compat" . (jsh pregexp-compat)) ; relative import
    ...))
```

Base imports provide the Gambit/Gerbil runtime compatibility layer that every module needs:
```scheme
(define jsh-base-imports
  '((except (chezscheme) void box box? unbox set-box! ...)  ; exclude conflicts
    (compat types)          ; Gerbil type system
    (runtime util)          ; Gerbil runtime utilities
    (runtime mop)           ; Meta-object protocol
    (runtime error)         ; Gerbil error types
    (runtime hash)          ; Hash tables
    (compat gambit)         ; Gambit compatibility shims
    (compat misc)))         ; String/list/path utilities
```

Modules must be compiled in dependency order (7 tiers, from `ast` up to `main`).

---

## 7. Import Conflict Resolution (R6RS Constraints)

**Problem**: R6RS forbids local definitions that shadow imported bindings. After Jerboa compilation, many modules define names that conflict with their imports (e.g., a module defines `find` which conflicts with `(compat misc)`'s `find`).

**Solution**: A post-compilation pass (`fix-import-conflicts`) introspects each library's imports using `library-exports`, identifies conflicts with local definitions, and automatically adds `(except ...)` clauses:

```scheme
;; Before: bare import conflicts with local (define find ...)
(import (compat misc))

;; After: automatically patched
(import (except (compat misc) find string-split))
```

The algorithm also handles **import-vs-import** conflicts where two imported libraries export the same name — the later import gets an `except` clause for names already provided by earlier imports.

As a fallback when `library-exports` fails (library not yet loaded), the system reads exports directly from `.sls` files by parsing the `(library <name> (export ...) ...)` header.

---

## 8. Mutable Export Workaround (identifier-syntax)

**Problem**: R6RS forbids `set!` on exported variables. Gerbil code frequently uses patterns like:

```scheme
(export *my-parameter*)
(define *my-parameter* #f)
...
(set! *my-parameter* new-value)
```

This is legal in Gerbil but illegal in R6RS.

**Solution**: The build system scans for `(set! name ...)` where `name` is in the export list, then rewrites the definition to use `identifier-syntax` — a Chez macro that provides transparent get/set:

```scheme
;; Original (illegal in R6RS):
(define *foo* initial-value)
(set! *foo* new-value)        ; ERROR: exported variable

;; Rewritten (transparent to all code):
(define *foo*-cell (vector initial-value))
(define-syntax *foo*
  (identifier-syntax
    (id (vector-ref *foo*-cell 0))
    ((set! id v) (vector-set! *foo*-cell 0 v))))

;; All existing (set! *foo* ...) and *foo* references work unchanged
```

This transformation is invisible to all consuming code — reads and writes work exactly as before.

---

## 9. Chez Lazy Library Invocation Workaround

**Problem**: Chez Scheme lazily invokes library bodies. A library's top-level expressions only run when a *runtime* export (not a macro) is first referenced. The `builtins.ss` module has side-effecting top-level expressions (`defbuiltin` calls) that register builtin commands into a global registry. If no code explicitly references a builtins export, these registrations never happen.

**Solution**: Inject a dummy reference in `main.sls` that forces Chez to invoke `(jsh builtins)`:

```scheme
;; Patched into main.sls after Jerboa compilation:
(define _force-builtins special-builtin?)  ; references a builtins export
```

The entry point `jsh.ss` also forces it:
```scheme
(let () special-builtin? (void))  ; force (jsh builtins) invocation
```

---

## 10. Post-Build Patching

After Jerboa compilation, several patterns in the generated `.sls` files need fixing. These are applied as string-level patches on the generated code:

### 10a. Keyword Dispatch in defclass Constructors

**Bug**: Jerboa's `defclass` constructor translation incorrectly appends keyword argument *values* to the positional argument list. The generated `init!` method is a `case-lambda` dispatching on positional arity, so extra values cause the wrong clause to match.

**Patch**:
```scheme
;; Before: keyword values added to positional args
(lp (cddr rest) (cons (cadr rest) acc))

;; After: skip keyword pairs entirely
(lp (cddr rest) acc)
```

Callers that used keyword syntax are also patched to positional:
```scheme
;; Before:
(make-shell-environment 'parent: env 'name: name)

;; After:
(make-shell-environment env name)
```

### 10b. Exception Messages

**Bug**: Chez's `condition-message` returns raw format templates (e.g., `"variable ~:s is not bound"`) with `~:s` placeholders, unlike Gambit which returns formatted strings.

**Patch**: Replace `exception-message` to use `display-condition` which formats the message with its irritants, then strip the `"Exception: "` or `"Exception in <who>: "` prefix.

### 10c. make-mutex Argument Type

**Bug**: Gambit's `make-mutex` accepts strings; Chez requires a symbol or `#f`.

**Patch**: `(make-mutex "pipeline-fd")` -> `(make-mutex 'pipeline-fd)`

### 10d. Recursive void Definition

**Bug**: Gerbil's `void` is variadic (accepts any args, returns void). Jerboa translates `(define (void) (void))` which creates a 0-arg function that infinitely recurses.

**Patch**: `(define (void) (void))` -> `(define (void . _) (if #f #f))`

---

## 11. The Gambit-to-Chez Compatibility Layer

The `src/compat/` directory provides ~900 lines of shims translating Gambit APIs to Chez equivalents. Key modules:

### gambit.sls (~645 lines)
- **u8vector/bytevector**: Gambit's `u8vector` API mapped to Chez bytevectors
- **Threading**: `spawn`, `thread-join!`, `mutex-lock!`/`mutex-unlock!` -> Chez `fork-thread`, `mutex-acquire`/`mutex-release`
- **Processes**: `open-process`, `process-status`, `process-pid` -> Chez `process` with pipe-based communication
- **File system**: `file-info`, `file-type`, `directory-files` -> Chez equivalents with Gambit-compatible return types
- **I/O**: `/dev/fd/N` support (Gambit feature), keyword argument handling for `open-input-file`/`open-output-file`
- **tty-mode-set!**: Terminal raw mode via FFI

### sugar.sls (~184 lines)
- `def`, `def*`, `defrule` (Gerbil syntax macros)
- `try`/`catch`/`finally`, `with-catch`, `unwind-protect`
- `while`, `until` loops
- `defstruct` record type definitions
- Custom `error` function (Gerbil-style, no `who` parameter)

### misc.sls (~200 lines)
- String: `string-prefix?`, `string-suffix?`, `string-split`, `string-join`, `string-trim`, `string-contains`, `string-index`
- List: `flatten`, `unique`, `every`, `any`, `iota`, `last`
- Path: `path-expand`, `path-directory`, `path-extension`
- Hash: `hash-ref` with default, `hash-copy`, `hash->list`

### Runtime Shims in jsh.ss

The entry point installs additional Gambit primitives into the interaction environment for Gerbil eval:

```scheme
;; f64vector -> flvector
(define (make-f64vector n . rest) (make-flvector n ...))

;; Threading: vector-based thread objects with mutex+condition
(define (make-thread thunk) (vector thunk (make-mutex) (make-condition) #f #f))
(define (thread-start! thr) (fork-thread ...))
(define (thread-join! thr) (mutex-acquire ...) (condition-wait ...))

;; Gambit ##process-statistics -> flvector with cpu/real/gc times
(define (##process-statistics) ...)

;; SMP primitives -> no-ops
(define (##set-parallelism-level! n) (void))
```

---

## 12. FFI via C Shim (No Foreign Library Dependencies)

**Problem**: The shell needs low-level POSIX operations (fork/exec, signal handling, terminal control, job control) that Chez doesn't expose directly.

**Solution**: A single C file (`ffi-shim.c`, ~480 lines) provides all POSIX bindings. It's compiled as a shared library for interpreted mode and as an object file linked directly into the binary:

- **Signal handling**: Flag-based async-signal-safe mechanism (`_signal_flags[]` + `sigaction`)
- **Fork/exec**: `ffi_fork_exec()` handles fork, signal reset, fd cleanup, process groups, and execve in C (no Scheme in the child process)
- **Argument passing**: SOH (0x01) delimited packed strings for argv/envp — avoids marshaling string arrays across FFI
- **Pipe/fd management**: Cached pipe fds, bulk fd close via `/proc/self/fd`
- **Terminal**: Raw mode, termios save/restore, window size via `ioctl(TIOCGWINSZ)`
- **Read buffer**: 1 MB static buffer for `ffi_do_read_all()` — avoids Scheme-side allocation for command substitution

All functions use standard POSIX libc — zero external library dependencies for the FFI layer.

---

## 13. WPO Incompatibility with identifier-syntax

**Problem**: Chez's Whole-Program Optimization (WPO) analyzes all code and eliminates dead definitions. The `identifier-syntax` macros generated for mutable exports (see section 8) appear to WPO as unused macro-only definitions — it eliminates the underlying vector-cell storage, breaking everything.

**Solution**: Skip WPO entirely. Use the plain `jsh.so` from `compile-program` without running `compile-whole-program`:

```scheme
;; DO NOT use compile-whole-program — it eliminates identifier-syntax cells
(compile-program "jsh.ss")    ; produces jsh.so
(system "cp jsh.so jsh-all.so")  ; use directly, no WPO pass
```

The binary size penalty is minimal (~10%) and avoids subtle runtime crashes.

---

## 14. Boot File Dependency Ordering

The `make-boot-file` call must list `.so` files in strict dependency order. A module can only reference definitions from modules listed before it. The order for jerboa-shell:

```
1. Jerboa runtime (9 modules):
   types -> gambit-compat -> util -> table -> c3 -> mop -> error -> hash
   -> syntax -> eval -> reader -> compile -> jerboa

2. Compat layer (9 modules):
   gambit -> misc -> sort -> sugar -> format -> pregexp
   -> signal -> signal-handler -> fdio

3. JSH modules (30 modules, 7 tiers):
   Tier 1: ffi, pregexp-compat, stage, static-compat
   Tier 2: ast, registry, macros, util
   Tier 3: environment, lexer, arithmetic, glob, fuzzy, history
   Tier 4: parser, functions, signals, expander
   Tier 5: redirect, control, jobs, builtins
   Tier 6: pipeline, executor, completion, prompt
   Tier 7: lineedit, fzf, script, startup, main
```

Getting this order wrong produces cryptic "unbound variable" errors at runtime.

---

## 15. Build Pipeline Summary

```
Step 1: gcc -> libjsh-ffi.so          (C FFI shim, shared lib for interpreted mode)
Step 2: Jerboa -> src/jsh/*.sls       (30 .ss files -> 30 .sls R6RS libraries)
        + post-build patches           (import conflicts, mutable exports, Chez compat)
Step 3: Chez compile-program          (jsh.ss -> jsh.so, compiles all imported libs)
Step 4: make-boot-file                (48 .so files -> jsh.boot, libs-only)
Step 5: file->c-header x 4            (petite.boot, scheme.boot, jsh.boot, jsh.so -> .h)
Step 6: gcc -> jsh-main.o             (custom main with embedded boot+program arrays)
        gcc -> ffi-shim.o             (POSIX bindings)
Step 7: gcc -> jsh                    (link with -lkernel -llz4 -lz -lm -ldl -lpthread -luuid -lncurses)

Result: ./jsh  (~6.5 MB, fully self-contained ELF)
```

### What's Inside the Binary

| Component | Size | Purpose |
|-----------|------|---------|
| petite.boot | ~1.9 MB | Chez base runtime (I/O, syntax, eval) |
| scheme.boot | ~1.0 MB | Full Chez compiler |
| jsh.boot | ~2.6 MB | Jerboa runtime + compat + 30 shell modules |
| jsh program | ~9 KB | Entry point + Gerbil eval handler |
| ffi-shim | ~15 KB | POSIX C bindings |
| libkernel | ~1.0 MB | Chez Scheme runtime (GC, threads, FFI) |

The binary runs from any directory, under any name, with no external Chez/Gerbil/Gambit installation required.
