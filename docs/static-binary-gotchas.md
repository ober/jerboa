# Static Binary Gotchas — Lessons from jerboa-shell

This document captures practical, hard-won knowledge from building jerboa-shell as both a glibc dynamic binary and a musl fully-static binary. These are real bugs encountered and fixed, not theoretical concerns.

**Reference project**: `~/mine/jerboa-shell`

---

## 1. `load-shared-object` Crashes Static Builds

### The Problem

Any call to `(load-shared-object ...)` in a statically-linked musl binary raises:

```
Exception in load-shared-object: not supported
```

musl's static libc does not include `dlopen`. When Chez Scheme is built with `--static CC=musl-gcc`, the `load-shared-object` function raises an exception unconditionally.

### Why It's Insidious

The crash happens during **library initialization** — before any user code runs. If any `.so` in the boot file chain calls `load-shared-object` at the top level, the entire binary fails to start.

### Affected Patterns

Every module that does `(load-shared-object ...)` at library init time is a landmine for static builds:

```scheme
;; Pattern 1: dlopen(NULL) to resolve linked symbols
(define _lib (load-shared-object ""))

;; Pattern 2: Loading libc explicitly for foreign-procedure
(define libc (load-shared-object "libc.so.6"))

;; Pattern 3: Loading project-specific FFI shared libs
(define _ffi (load-shared-object "./libfoo.so"))
```

### The Fix

Wrap every `load-shared-object` call in `guard`:

```scheme
;; Safe for both dynamic and static builds
(define _lib
  (guard (e [#t #f])    ;; silently skip if dlopen unavailable
    (load-shared-object "")))

(define libc
  (guard (e [#t #f])
    (load-shared-object "libc.so.6")))
```

In static builds, `foreign-procedure` still works for symbols registered via `Sforeign_symbol()` in C — it doesn't need `load-shared-object` for those.

### Files That Needed This Fix in jerboa-shell

| File | Call | Why it exists |
|------|------|---------------|
| `src/compat/gambit.sls` | `(load-shared-object "")` | dlopen(NULL) for -rdynamic symbols |
| `src/compat/gambit.sls` | `(load-shared-object "./libjsh-ffi.so")` | FFI shim for interpreted mode |
| `src/jsh/ffi.sls` | `(load-shared-object "")` | Same as gambit.sls |
| `src/jsh/ffi.sls` | `(load-shared-object "./libjsh-ffi.so")` | Same |
| `~/mine/jerboa/lib/std/os/signal.sls` | `(load-shared-object "libc.so.6")` | For `kill()` via foreign-procedure |

### Rule for Jerboa Library Authors

**Any module that might end up in a boot file MUST guard its `load-shared-object` calls.** The modules `std/os/signal`, `std/os/temporaries`, and `std/net/grpc` all call `load-shared-object` — if they're in the boot file, they'll crash static builds.

---

## 2. `Sforeign_symbol` — The Complete FFI Registration Table

### The Problem

In a static binary (no `dlopen`), Chez Scheme's `foreign-procedure` can only find C functions that were explicitly registered via `Sforeign_symbol()` in C code before the Scheme heap boots.

If you miss even one symbol, you get:

```
Exception in foreign-procedure: no entry for "ffi_file_uid"
```

### The Fix

The musl build script (`build-jsh-musl.ss`) generates a C function `register_ffi_symbols()` that registers every C function used by any Scheme module in the boot file. This must be called **after** `Sbuild_heap()` but before any Scheme code runs that calls `foreign-procedure`.

### Three Categories of Symbols to Register

#### Category 1: Project FFI Functions (from ffi-shim.c)

These are custom C functions written for the project. Grep for them:

```bash
# Find all ffi_ functions defined in your C shim
grep '^[a-z_].*ffi_' ffi-shim.c | grep -oP 'ffi_\w+' | sort -u
```

**Every one must be registered** with both `extern void` declarations and `Sforeign_symbol()` calls.

#### Category 2: POSIX libc Functions

Functions called via `foreign-procedure` or `define-foreign` directly by name:

```bash
# Find all C function names referenced in Scheme code
grep -rh 'define-foreign\b\|foreign-procedure' src/ | \
  grep -oP '"[a-zA-Z_][a-zA-Z0-9_]*"' | sort -u
```

For jerboa-shell, this includes: `fork`, `_exit`, `close`, `dup`, `dup2`, `read`, `write`, `lseek`, `access`, `unlink`, `getpid`, `getppid`, `kill`, `sysconf`, `setpgid`, `getpgid`, `tcsetpgrp`, `tcgetpgrp`, `setsid`, `getuid`, `geteuid`, `getegid`, `isatty`, `unsetenv`.

**Don't forget jerboa library modules in the boot file** — e.g., `std/os/signal.sls` uses `kill`, and `std/os/fdio.sls` uses `read`, `write`, `close`.

#### Category 3: Variadic/Macro POSIX Functions

Some POSIX "functions" are actually macros or variadic functions that can't be passed to `Sforeign_symbol()` by address. These need thin C wrappers:

```c
// Wrappers for variadic/macro POSIX functions
static int wrap_open(const char *path, int flags, int mode) {
    return open(path, flags, mode);
}
static int wrap_fcntl(int fd, int cmd, int arg) {
    return fcntl(fd, cmd, arg);
}
static int wrap_mkfifo(const char *path, int mode) {
    return mkfifo(path, mode);
}
static int wrap_umask(int mask) {
    return (int)umask((mode_t)mask);
}

// Register wrapper under the original name
Sforeign_symbol("open", (void*)wrap_open);
Sforeign_symbol("fcntl", (void*)wrap_fcntl);
```

### Maintenance Process

When adding new `foreign-procedure` or `define-foreign` calls to any module in the boot file:

1. Add the C function name to the `register_ffi_symbols()` lists in `build-jsh-musl.ss`
2. If it's a variadic/macro function, add a wrapper
3. Rebuild the musl binary and test

---

## 3. `Sregister_boot_file_bytes` — The Right API

### The Problem

There are multiple Chez Scheme APIs for registering boot files. Using the wrong one causes subtle failures.

### API Comparison

| API | Use Case | Status |
|-----|----------|--------|
| `Sregister_boot_file_bytes(name, data, len)` | Embedded byte arrays in C | **Correct** — simple, works everywhere |
| `Sregister_boot_file_fd(name, fd)` | File descriptor based | **Avoid** — requires memfd, more complex, same result |
| `Sregister_boot_file(path)` | File on disk | Not useful for self-contained binaries |

### Why `Sregister_boot_file_bytes` Is Better

The boot data is already in the binary's `.rodata` section as a C byte array. `Sregister_boot_file_bytes` reads directly from that memory — zero copies, zero syscalls, zero failure modes.

The memfd approach (`Sregister_boot_file_fd`) writes the data to a kernel-backed anonymous file, seeks back to 0, and then Chez reads it back. This is strictly worse:
- Extra syscalls (`memfd_create`, `write`, `lseek`)
- Extra memory (kernel buffer + user buffer)
- Extra failure modes (memfd_create can fail, write can be short)
- More code to maintain

### Pattern

```c
// In the C main:
#include "jsh_petite_boot.h"   // petite_boot_data[], petite_boot_size
#include "jsh_scheme_boot.h"   // scheme_boot_data[], scheme_boot_size
#include "jsh_jsh_boot.h"      // jsh_boot_data[], jsh_boot_size

Sscheme_init(NULL);
Sregister_boot_file_bytes("petite", (void*)petite_boot_data, petite_boot_size);
Sregister_boot_file_bytes("scheme", (void*)scheme_boot_data, scheme_boot_size);
Sregister_boot_file_bytes("jsh",    (void*)jsh_boot_data,    jsh_boot_size);
Sbuild_heap(NULL, NULL);
```

Note: The **program** `.so` still uses memfd (for `Sscheme_script`), because `Sscheme_script` requires a file path. But boot files don't need this — they have a dedicated bytes API.

---

## 4. The Gerbil→Chez Post-Build Patching System

### The Problem

jerboa-shell's `.sls` files are auto-generated from Gerbil `.ss` sources by the Gherkin compiler (via `build-jerboa.ss`). The generated code frequently needs fixes that can't be done at the source level because:

1. The Gerbil compiler drops `(only ...)` imports that look unused (e.g., parameter mutations)
2. The Gerbil compiler transforms `let` to `let*` and reorders definitions
3. Keyword-style constructor calls need positional conversion for Chez
4. R6RS restrictions on mutable exports require `identifier-syntax` rewrites

### The Patch System

`build-jerboa.ss` defines `patch-file!` inside a `(let () ...)` block:

```scheme
(let ()
  (define (patch-file! path old new)
    ;; string-replace on file contents
    ...)

  ;; All patches must be INSIDE this let block
  (patch-file! "src/jsh/environment.sls" old-string new-string)
  (patch-file! "src/jsh/main.sls" old-string new-string)
  ...)
```

**Critical**: `patch-file!` is local to the `let` block. New patches must be added INSIDE the closing `)`. If you add them after, you get `variable patch-file! is not bound`.

### Gotcha: Matching Generated Code

When writing patch strings, you must match the **generated** `.sls` code exactly, not the `.ss` source. Common differences:

| .ss Source | Generated .sls |
|-----------|---------------|
| `(let ((x ...)))` | `(let* ([x ...]))` |
| `(let* ...)` | `(let* ...)` (preserved) |
| Keywords: `parent: env` | Dropped or rewritten |
| `(only :jsh/sandbox ...)` | May be dropped entirely if "unused" |

**Always rebuild, then inspect the generated `.sls` to find the exact string to match.**

### Example: Wiring `*current-jsh-env*`

The Gerbil compiler drops `(only :jsh/sandbox *current-jsh-env*)` and `(*current-jsh-env* env)` because it looks like a side-effect-only parameter mutation with no visible use. The fix is a post-build patch:

```scheme
;; Add import
(patch-file! "src/jsh/main.sls"
  "(jsh stage))"
  "(jsh stage)\n   (only (jsh sandbox) *current-jsh-env*))")

;; Set parameter after env creation
(patch-file! "src/jsh/main.sls"
  "(let* ([env (init-shell-env args-hash)])\n              (cond"
  "(let* ([env (init-shell-env args-hash)])\n              (*current-jsh-env* env)\n              (cond")
```

---

## 5. musl vs glibc Build: Two Separate Pipelines

### Architecture

The project has two independent build pipelines that share source code but diverge at the C compilation/linking stage:

| Aspect | glibc (`make jsh`) | musl (`make musl-jsh`) |
|--------|---------------------|------------------------|
| Build script | `build-binary-jsh.ss` | `build-jsh-musl.ss` |
| C main | `jsh-main.c` (separate file) | Generated inline in build script |
| WPO | Yes (`compile-whole-program`) | No (uses `jsh.so` directly) |
| FFI resolution | `load-shared-object` + `-rdynamic` | `Sforeign_symbol()` registration |
| Boot API | `Sregister_boot_file_bytes` | `Sregister_boot_file_bytes` |
| Linker | `gcc -rdynamic` | `musl-gcc -static` |
| Headers | Generated → compiled → deleted | Generated in /tmp → compiled → deleted |
| Output | `./jsh` (dynamic ELF) | `./jsh-musl` (static ELF, ~6.5 MB) |

### Key Difference: The Generated C Main

The musl build generates `jsh_main_musl.c` inline (as Scheme string output). It includes:

1. `Sforeign_symbol` registration for ALL FFI functions
2. C wrappers for variadic/macro POSIX functions (`open`, `fcntl`, `mkfifo`, `umask`)
3. The same memfd + `Sscheme_script` pattern as the glibc build

Changes to FFI bindings require updating BOTH:
- `jsh-main.c` (if it has FFI declarations — currently it doesn't)
- `build-jsh-musl.ss` (the `register_ffi_symbols` function and extern declarations)

---

## 6. Boot File Module Ordering

### The Problem

`make-boot-file` requires modules in strict dependency order. If module A imports module B, B must appear **before** A in the boot file list.

### The Ordering

The boot file loads modules in this order:

1. **Jerboa stdlib** — `jerboa/core`, `jerboa/runtime`, `std/error`, `std/format`, `std/sort`, `std/pregexp`, `std/sugar`, `std/misc/*`, `std/stm`, `std/foreign`, `std/os/*`, `std/transducer`, `std/log`, `std/capability/*`
2. **Gherkin runtime** — `compat/types`, `compat/gambit-compat`, `runtime/*`, `reader/reader`, `compiler/compile`, `boot/gherkin`
3. **Compat layer** — `src/compat/gambit.so`
4. **Application modules** — `ffi`, `pregexp-compat`, `stage`, `static-compat`, `ast`, `registry`, `macros`, `util`, `environment`, `lexer`, `arithmetic`, `glob`, `fuzzy`, `history`, `parser`, `functions`, `signals`, `expander`, `redirect`, `control`, `jobs`, `builtins`, `pipeline`, `executor`, `completion`, `prompt`, `lineedit`, `fzf`, `script`, `startup`, `sandbox`, `main`

### Adding a New Module

When adding a new jsh module:

1. Add it to the compile list in `build-jsh-musl.ss` step 1 (correct tier)
2. Add it to the boot file module list in step 4 (after its dependencies)
3. If it uses `foreign-procedure`, add symbols to the `register_ffi_symbols` list in step 5
4. Add it to `build-binary-jsh.ss` in the same places (for glibc builds)

---

## 7. WPO (Whole-Program Optimization) Fragility

### The Problem

`compile-whole-program` requires `.wpo` files with matching compilation instances for every library. If even one module was compiled in a different Scheme session or with different parameters, WPO fails with:

```
Exception in compile-whole-program: "src/jsh/ast.wpo" does not define
expected compilation instance of library (jsh ast)
```

### The musl Workaround

The musl build skips WPO entirely and uses the direct `jsh.so` from `compile-program`:

```scheme
;; Step 3: Skip WPO for musl builds
(define program-so "jsh.so")
```

This is simpler, more reliable, and the binary size difference is negligible (~100 KB).

### When WPO Works

WPO works when ALL modules are compiled in the same Scheme session with `compile-imported-libraries` and `generate-wpo-files` enabled. The glibc build (`build-binary-jsh.ss`) does this but can still fail if stale `.wpo` files exist from a previous session.

**Fix**: `rm -f src/jsh/*.wpo` before a clean build.

---

## 8. Testing Static Binaries

### Smoke Tests

```bash
# Basic execution
./jsh-musl -c 'echo hello'

# Variable assignment
./jsh-musl -c 'x=42; echo $x'

# Command substitution
./jsh-musl -c 'echo $(echo nested)'

# Loops
./jsh-musl -c 'for i in 1 2 3; do echo $i; done'

# Meta-commands (requires *current-jsh-env* wiring)
./jsh-musl -c ',trace echo test'
./jsh-musl -c ',profile echo test'

# Portability test
cp jsh-musl /tmp/jsh-test && /tmp/jsh-test -c 'echo works from /tmp'
```

### Verification

```bash
# Confirm fully static
file jsh-musl
# Expected: ELF 64-bit LSB executable, x86-64, ... statically linked

ldd jsh-musl
# Expected: not a dynamic executable
```

### Common Failure Modes

| Error | Cause | Fix |
|-------|-------|-----|
| `load-shared-object: not supported` | Unguarded `load-shared-object` call | Add `guard` wrapper |
| `no entry for "foo"` | Missing `Sforeign_symbol` registration | Add to `register_ffi_symbols` |
| `shell not initialized` | `*current-jsh-env*` not set | Check post-build patches |
| Segfault on startup | Boot file ordering wrong | Check dependency order |
| Binary hangs | Threading bug (program in boot file) | Use `Sscheme_script` for program |
