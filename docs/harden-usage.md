# Hardening API Usage Guide

Practical guide for using Jerboa's binary hardening modules from consumer projects like jerboa-shell. Covers the three new libraries — `(std os antidebug)`, `(std os seccomp)`, `(std os integrity)` — plus integration with the existing `(std os landlock-native)` and `(std crypto secure-mem)`.

All functions are backed by `libjerboa_native.so` (Rust/ring/libc). No OpenSSL dependency.

---

## Prerequisites

The consuming project needs `libjerboa_native.so` accessible at runtime. Options:

```bash
# Option 1: Copy to your project's lib/ directory
cp ~/mine/jerboa/lib/libjerboa_native.so ~/mine/jerboa-shell/lib/

# Option 2: Build it fresh
cd ~/mine/jerboa/jerboa-native-rs && cargo build --release
cp target/release/libjerboa_native.so ~/mine/jerboa-shell/lib/

# Option 3: For static musl builds, link libjerboa_native.a
cd ~/mine/jerboa/jerboa-native-rs && cargo build --release
# produces target/release/libjerboa_native.a
```

The Scheme wrappers search for the library in this order:
1. `libjerboa_native.so` (system library path / `LD_LIBRARY_PATH`)
2. `lib/libjerboa_native.so` (relative to working directory)
3. `./lib/libjerboa_native.so`

For static binaries (musl builds), symbols are pre-registered via `Sforeign_symbol` in the C main — no runtime loading needed.

---

## Quick Start: Minimal Hardening

Add this to your program's startup (e.g., in `main.sls` or the entry point script):

```scheme
(import (std os antidebug)
        (std os seccomp)
        (std os integrity))

;; 1. Block debugger attachment (one-shot, irreversible)
(guard (e [#t (void)])  ; tolerate failure in dev mode
  (antidebug-ptrace!))

;; 2. Check for existing tracers
(when (antidebug-traced?)
  (display "integrity violation\n" (current-error-port))
  (exit 1))

;; 3. Check for library injection
(when (antidebug-ld-preload?)
  (display "integrity violation\n" (current-error-port))
  (exit 1))

;; 4. Kernel-block debug syscalls (irreversible)
(when (seccomp-available?)
  (seccomp-lock!))
```

---

## Module Reference

### (std os antidebug)

#### antidebug-ptrace!

```scheme
(antidebug-ptrace!) → void
```

Calls `PTRACE_TRACEME` on the current process. If successful, no debugger can attach afterward. Raises `&antidebug-error` if a debugger is already attached.

**Irreversible.** Calling twice always fails the second time (process is already self-traced). Wrap in `guard` if you want to tolerate failure in development:

```scheme
(guard (e [(antidebug-error? e) (void)])
  (antidebug-ptrace!))
```

#### antidebug-traced?

```scheme
(antidebug-traced?) → boolean
```

Reads `/proc/self/status` and checks `TracerPid`. Returns `#t` if a debugger/tracer is attached, `#f` if clean. Raises on error (e.g., procfs unavailable).

#### antidebug-ld-preload?

```scheme
(antidebug-ld-preload?) → boolean
```

Checks both the current environment and `/proc/self/environ` for `LD_PRELOAD`. The `/proc/self/environ` check catches cases where an attacker set `LD_PRELOAD` at exec time then cleared it from the process environment.

Returns `#t` if `LD_PRELOAD` is set to a non-empty value, `#f` if clean.

#### antidebug-breakpoint?

```scheme
(antidebug-breakpoint? addr) → boolean
```

Checks if the byte at `addr` (a `uptr`, unsigned pointer) is `0xCC` (INT3 software breakpoint). Useful for verifying that key function entry points haven't been patched by a debugger.

**Warning:** `addr` must point to readable memory in the process's `.text` section. Passing an invalid address will crash.

To get a function's address in Chez Scheme:

```scheme
;; Use foreign-callable or inspect compiled code object addresses
;; Most useful in the C main, where you can take &function_name
```

#### antidebug-timing-anomaly?

```scheme
(antidebug-timing-anomaly? max-ns) → boolean
```

Runs a calibration loop and measures elapsed time. If it takes longer than `max-ns` nanoseconds, returns `#t` (indicating single-stepping in a debugger). Recommended threshold: `50000000` (50ms).

```scheme
(when (antidebug-timing-anomaly? 50000000)
  (exit 1))
```

#### antidebug-check-all

```scheme
(antidebug-check-all) → alist
```

Runs all non-destructive checks in one call. Returns an alist:

```scheme
((traced . #f) (ld-preload . #f) (timing . #f))
```

Any `#t` value indicates a detection. The timing check uses a 50ms internal threshold.

```scheme
(let ([results (antidebug-check-all)])
  (when (ormap cdr results)
    (display "debug environment detected\n" (current-error-port))
    (exit 1)))
```

Or check individually:

```scheme
(let ([results (antidebug-check-all)])
  (when (cdr (assq 'traced results))
    (log "tracer detected"))
  (when (cdr (assq 'ld-preload results))
    (log "LD_PRELOAD detected")))
```

---

### (std os seccomp)

#### seccomp-available?

```scheme
(seccomp-available?) → boolean
```

Returns `#t` if the kernel supports seccomp-bpf filtering. Should be `#t` on any Linux 3.5+ kernel with `CONFIG_SECCOMP_FILTER`.

#### seccomp-lock!

```scheme
(seccomp-lock!) → void
```

Installs a BPF filter that kills the process if any of these syscalls are attempted:

| Syscall | Number | Why blocked |
|---------|--------|-------------|
| `ptrace` | 101 | Prevents debugger attach after startup |
| `process_vm_readv` | 310 | Prevents cross-process memory reads |
| `process_vm_writev` | 311 | Prevents cross-process memory writes |
| `personality` | 135 | Prevents `READ_IMPLIES_EXEC` (NX bypass) |

All other syscalls remain allowed. **Irreversible** — the filter persists for the process lifetime. Also sets `PR_SET_NO_NEW_PRIVS` (required by seccomp, prevents suid escalation).

Raises `&seccomp-error` on failure.

**Call this AFTER all initialization is complete** — after loading shared libraries, opening files, spawning initial threads, etc.

#### seccomp-lock-strict!

```scheme
(seccomp-lock-strict! syscall-list) → void
```

Whitelist mode: ONLY the listed syscall numbers are allowed. Everything else kills the process. **Much more restrictive** — use only if you know exactly what syscalls your program needs.

```scheme
;; Minimal set for a program that only does I/O and exits
(seccomp-lock-strict!
  '(0     ; read
    1     ; write
    3     ; close
    9     ; mmap
    11    ; munmap
    12    ; brk
    60    ; exit
    231   ; exit_group
    ))
```

**Warning:** Chez Scheme's runtime (GC, threads, I/O) uses many syscalls. Getting the whitelist wrong will kill your process with SIGSYS. Start with `seccomp-lock!` (blocklist mode) unless you have a specific need for strict mode.

---

### (std os integrity)

#### integrity-hash-self

```scheme
(integrity-hash-self) → bytevector
```

Reads `/proc/self/exe` and returns its SHA-256 hash as a 32-byte bytevector. This always reads the actual binary on disk, even if the process was started via a symlink or with a different `argv[0]`.

```scheme
(let ([hash (integrity-hash-self)])
  (printf "binary SHA-256: ~a~%"
    (bytevector->hex hash)))  ; you'd need a hex conversion helper

;; Or just compare:
(define expected-hash #vu8(... 32 bytes ...))
(unless (integrity-verify-hash expected-hash)
  (exit 1))
```

#### integrity-verify-hash

```scheme
(integrity-verify-hash expected-hash) → boolean
```

Reads `/proc/self/exe`, SHA-256 hashes it, and compares against `expected-hash` using constant-time comparison (prevents timing side-channels).

`expected-hash` must be a 32-byte bytevector. Raises `&integrity-error` if not.

Returns `#t` if the binary matches, `#f` if modified.

#### integrity-verify-signature

```scheme
(integrity-verify-signature pubkey signature exclude-offset exclude-len) → boolean
```

Reads `/proc/self/exe`, optionally zeros out a region (where the signature is embedded), and verifies an Ed25519 signature.

- `pubkey`: 32-byte bytevector (Ed25519 public key)
- `signature`: 64-byte bytevector (Ed25519 signature)
- `exclude-offset`: byte offset of embedded signature in binary (0 if external)
- `exclude-len`: length of region to zero (0 if external)

Returns `#t` if the signature is valid, `#f` if not. Raises on invalid input sizes.

**Build-time signing workflow:**

1. Build the binary with a zeroed signature slot.
2. Hash the binary (with zeroed slot).
3. Sign the hash with your Ed25519 private key offline.
4. Patch the signature into the binary.
5. At runtime, `integrity-verify-signature` zeros the same region and verifies.

```scheme
;; Runtime verification (pubkey embedded in source or config)
(define my-pubkey #vu8(... 32 bytes ...))
(define my-sig   #vu8(... 64 bytes ...))

(unless (integrity-verify-signature my-pubkey my-sig
          #x1000  ; signature lives at offset 0x1000
          64)     ; 64 bytes to zero
  (display "signature verification failed\n" (current-error-port))
  (exit 1))
```

#### integrity-hash-file

```scheme
(integrity-hash-file path) → bytevector
```

SHA-256 hash of an entire file. `path` is a string. Returns 32-byte bytevector.

```scheme
;; Verify a companion file hasn't been tampered with
(define expected #vu8(...))
(unless (bytevector=? (integrity-hash-file "/etc/myapp/config.enc") expected)
  (error 'startup "config file tampered"))
```

#### integrity-hash-region

```scheme
(integrity-hash-region path offset length) → bytevector
```

SHA-256 hash of a specific byte range within a file. `offset` and `length` are exact integers. Pass `length` = 0 to hash from `offset` to end of file.

Useful for hashing only the `.text` section of an ELF (more robust than full-file hashing since ELF headers and debug sections may be modified by tools).

---

## Integration Patterns for jerboa-shell

### Pattern 1: Startup Hardening in main.sls

Add a hardening phase early in the jsh startup sequence, before loading user config files:

```scheme
;; In (jsh main) or a new (jsh harden) module

(define (harden-startup!)
  ;; Phase 1: Anti-debug (before anything sensitive loads)
  (guard (e [#t (void)])  ; don't crash in dev/test
    (antidebug-ptrace!))

  ;; Phase 2: Environment checks
  (let ([checks (antidebug-check-all)])
    (when (cdr (assq 'traced checks))
      (exit 1))
    (when (cdr (assq 'ld-preload checks))
      (exit 1)))

  ;; Phase 3: Kernel lockdown (AFTER all .so loading is complete)
  (when (seccomp-available?)
    (seccomp-lock!)))
```

Call `(harden-startup!)` from `main` after `Sbuild_heap` / library loading but before processing user input.

### Pattern 2: Conditional Hardening via Environment Variable

For development, you probably want to disable hardening:

```scheme
(define (harden-startup!)
  (unless (getenv "JSH_DEV")  ; skip in dev mode
    (guard (e [#t (void)])
      (antidebug-ptrace!))
    (let ([checks (antidebug-check-all)])
      (when (ormap cdr checks)
        (exit 1)))
    (when (seccomp-available?)
      (seccomp-lock!))))
```

### Pattern 3: Self-Integrity for Static Binary

For `jsh-musl` (the static musl binary), verify the binary hash at startup:

```scheme
;; Expected hash computed at build time and embedded in source
;; or loaded from a signed manifest file
(define (verify-binary-integrity!)
  (let ([expected (load-expected-hash)])  ; from embedded data or signed file
    (unless (integrity-verify-hash expected)
      (display "binary integrity check failed\n" (current-error-port))
      (exit 1))))
```

For the build script (`build-binary-jsh.ss`), compute the hash after linking:

```bash
# After building jsh-musl:
HASH=$(sha256sum jsh-musl | cut -d' ' -f1)
echo "Expected hash: $HASH"
# Embed in a config file or use as a deployment check
```

### Pattern 4: Layered Defense in C Main (gsh-main.c / jsh-main.c)

For the strongest protection, add checks in the C main before Chez even starts:

```c
#include <sys/ptrace.h>

extern int jerboa_antidebug_ptrace(void);
extern int jerboa_antidebug_check_tracer(void);
extern int jerboa_antidebug_check_ld_preload(void);
extern int jerboa_integrity_verify_hash(const unsigned char *, size_t);
extern int jerboa_seccomp_lock(void);

int main(int argc, char *argv[]) {
    // Phase 0: Before Chez init — C-level checks
    if (jerboa_antidebug_ptrace() != 0) _exit(1);
    if (jerboa_antidebug_check_tracer() != 0) _exit(1);
    if (jerboa_antidebug_check_ld_preload() != 0) _exit(1);

    // Phase 1: Chez init
    Sscheme_init(NULL);
    Sregister_boot_file_bytes(...);
    Sbuild_heap(NULL, NULL);

    // Phase 2: After all loading, lock syscalls
    jerboa_seccomp_lock();

    // Phase 3: Run the Scheme program
    return Sscheme_script(prog_path, argc, argv);
}
```

To link against `libjerboa_native.a` in the musl build:

```bash
# In build-jsh-musl.sh, add to the link step:
musl-gcc -static -o jsh-musl \
    jsh-main.o ffi-shim.o \
    -L ~/mine/jerboa/jerboa-native-rs/target/release \
    -ljerboa_native \
    -lkernel -llz4 -lz -lm -ldl -lpthread
```

### Pattern 5: Sandboxing with Landlock After Init

Combine hardening with Landlock to restrict filesystem access:

```scheme
(import (std os landlock-native)
        (std os antidebug)
        (std os seccomp))

(define (full-lockdown! home-dir)
  ;; 1. Anti-debug
  (guard (e [#t (void)]) (antidebug-ptrace!))
  (when (antidebug-traced?) (exit 1))

  ;; 2. Filesystem sandbox via Landlock
  (when (landlock-available?)
    (landlock-enforce!
      ;; Read-only paths
      (list "/etc" home-dir)
      ;; Read-write paths
      (list (string-append home-dir "/.jsh_history")
            "/tmp")
      ;; Executable paths
      (list "/usr/bin" "/bin")))

  ;; 3. Syscall lockdown (LAST — after all setup)
  (when (seccomp-available?)
    (seccomp-lock!)))
```

### Pattern 6: Watchdog Thread

For ongoing protection, spawn a background thread that periodically re-checks:

```scheme
(import (chezscheme)
        (std os antidebug))

(define (start-watchdog!)
  (fork-thread
    (lambda ()
      (let loop ()
        (sleep (make-time 'time-duration 0 5))  ; every 5 seconds
        (when (antidebug-traced?)
          (exit 1))
        (loop)))))
```

---

## Error Handling

All three modules define condition types for structured error handling:

```scheme
;; Antidebug errors
(guard (e [(antidebug-error? e)
           (printf "antidebug: ~a~%" (antidebug-error-reason e))])
  (antidebug-ptrace!))

;; Seccomp errors
(guard (e [(seccomp-error? e)
           (printf "seccomp: ~a~%" (seccomp-error-reason e))])
  (seccomp-lock!))

;; Integrity errors
(guard (e [(integrity-error? e)
           (printf "integrity: ~a~%" (integrity-error-reason e))])
  (integrity-hash-self))
```

For the Rust-side error detail, `(std os integrity)` exposes `native-last-error` internally, and integrity errors include it in the message condition.

---

## Security Notes

**Order matters.** The recommended sequence is:

1. `antidebug-ptrace!` — must be first (blocks debugger attach)
2. `antidebug-check-all` — detect existing tracers/injection
3. `integrity-verify-hash` or `integrity-verify-signature` — verify binary
4. Load all shared libraries and open all files
5. `landlock-enforce!` — filesystem restrictions (blocks new .so loading)
6. `seccomp-lock!` — syscall restrictions (must be LAST)

Reversing steps 5 and 6 is fine. But `seccomp-lock!` must come after all library loading and file opening, because the BPF filter is permanent.

**Don't leak detection details.** Use the same generic error message for all failures. Don't tell an attacker which check caught them:

```scheme
;; Good: generic message
(when (antidebug-traced?) (exit 1))

;; Bad: tells attacker what to bypass
(when (antidebug-traced?)
  (display "TracerPid check failed\n")
  (exit 1))
```

**Dev mode escape hatch.** Always provide a way to disable hardening for development and testing. An environment variable (`JSH_DEV=1`) is the simplest approach. Never ship with the escape hatch enabled.
