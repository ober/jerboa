# Jerboa: Remaining Gaps for Bulletproof Claude Code Generation

Status as of 2026-03-21. The safety gap implementations (commit 9879d86) addressed
resource RAII, contracts, error hierarchy, safe FASL, timeouts, immutable defaults,
and error context. This document covers what's still NOT covered.

## Critical: Safe-by-Default Prelude

**Problem**: Claude won't use the safe modules unless told to. The unsafe APIs
(`sqlite-open`, `tcp-connect`, raw `fasl-write`) are still there and still the
default imports. Claude reaches for `(import (std db sqlite-native))` not
`(import (std safe))` because training data and existing code use the raw APIs.
No compiler warning when using the unsafe version.

**Fix**: Either make `(std safe)` the default prelude, or add a lint pass that
warns on direct use of raw FFI modules when `(std safe)` equivalents exist.

**Implementation sketch**:
```scheme
;; Option A: Safe prelude replaces raw APIs
;; (import (jerboa prelude)) should re-export safe-sqlite-open as sqlite-open, etc.

;; Option B: Lint rule
;; jerboa-lint detects (import (std db sqlite-native)) and suggests (std safe)
```

## Critical: Compile-Time Type Checking

**Problem**: Contracts are runtime-only. `(safe-sqlite-exec "not-a-handle" 42)`
compiles fine — only fails when executed. A real type checker would reject it at
compile time.

**Fix**: Wire the `(std typed)` gradual type system into the contract-checked
APIs so that `define/t` annotated code gets checked at compile time.

**Implementation sketch**:
```scheme
;; Annotate safe APIs with types
(define/t (safe-sqlite-exec [db : Fixnum] [sql : String]) : Fixnum
  ...)

;; At call sites, type inference catches mismatches before runtime
```

## Critical: No Memory Safety for New FFI

**Problem**: If Claude writes new `c-lambda` / `foreign-procedure` bindings,
there's no protection against buffer overflows, use-after-free, null pointer
dereference, or type mismatches. The Rust native backend covers existing
bindings, but new FFI code is still unsafe.

**Fix**: Forbid raw `foreign-procedure` in the safe prelude. Require all FFI to
go through the Rust native library or a validated shim layer.

**Implementation sketch**:
```scheme
;; Safe prelude does NOT export foreign-procedure, c-lambda, etc.
;; New FFI must go through:
(define-safe-ffi my-function
  (rust-module "my_module")
  (signature (string int) -> int)
  (null-check #t)
  (timeout 30))
```

## High: Resource Cleanup is Opt-In

**Problem**: Claude can still write `(let ([db (sqlite-open "x.db")]) ...)`
without cleanup. Nothing forces use of `with-resource`. In Rust, `Drop` is
automatic — you can't forget it.

**Fix options**:
1. Make resource-acquiring functions return a wrapper that *must* be consumed by
   `with-resource` (linear type enforcement via `(std typed linear)`)
2. Use Chez's guardian/finalizer system as a safety net that logs warnings when
   resources are GC'd without being closed
3. Both

**Implementation sketch**:
```scheme
;; Option 1: Linear resource wrapper
(define (safe-sqlite-open path)
  (make-linear-resource (raw-sqlite-open path) sqlite-close))
;; Using the resource without with-resource raises at runtime

;; Option 2: Finalizer safety net
(define (safe-sqlite-open path)
  (let ([handle (raw-sqlite-open path)]
        [closed? #f])
    (register-guardian! handle
      (lambda ()
        (unless closed?
          (log-warning "sqlite handle ~a GC'd without close!" handle)
          (raw-sqlite-close handle))))
    handle))
```

## High: No Sandbox for Claude-Generated Code by Default

**Problem**: The `(std security restrict)` sandbox exists but isn't applied
automatically. Claude-generated code runs with full privileges — file system,
network, process spawning, everything.

**Fix**: A `run-safe` entry point that wraps Claude-generated code in the
restricted environment + Landlock + seccomp by default.

```scheme
(run-safe
  (capabilities: (fs-read "/data") (net-connect "api.example.com" 443))
  (timeout: 60)
  (body
    ;; Claude-generated code runs here with only the declared capabilities
    ...))
```

## High: No Input Validation on Network-Facing Code

**Problem**: The sanitization module exists (`std/security/sanitize`) but Claude
won't import it unless told. SQL injection, path traversal, and header injection
are still possible if Claude writes a web handler using the raw APIs.

**Fix**: The safe prelude's database wrappers should auto-parameterize queries.
The HTTP handler scaffold should auto-apply sanitization middleware.

```scheme
;; safe-sqlite-query should reject string interpolation patterns
;; and require parameterized queries:
(safe-sqlite-query db "SELECT * FROM users WHERE id = ?" user-id)  ;; OK
(safe-sqlite-query db (string-append "SELECT * FROM users WHERE id = " user-id))
;; ^ Should warn or reject at lint time
```

## Medium: Concurrency Bugs

**Problem**: STM and structured concurrency exist but are opt-in. Claude can
still write raw `fork-thread` + shared mutable state with no synchronization.
No race detector.

**Fix**: Safe prelude should not export `fork-thread`. Only expose
`with-task-scope` / `scope-spawn` from `(std concur structured)`.

## Medium: Bare `error` Still Works

**Problem**: Any module can still call bare `(error 'who "msg")` instead of
using the structured conditions from `(std error conditions)`. The condition
hierarchy exists but isn't enforced.

**Fix**: Lint rule that warns on bare `(error ...)` calls and suggests the
appropriate structured condition.

## Priority Order

| Priority | Fix | Effort | Impact |
|----------|-----|--------|--------|
| P0 | Safe-by-default prelude | ~200 lines | Prevents all "forgot to use safe API" bugs |
| P0 | Finalizer safety net for resources | ~100 lines | Catches resource leaks at GC time |
| P1 | Lint rules for unsafe patterns | ~300 lines | Catches unsafe code at development time |
| P1 | Compile-time type checking for top APIs | ~400 lines | Catches type errors before runtime |
| P2 | Forbid raw FFI in safe prelude | ~50 lines | Prevents new unsafe FFI |
| P2 | Auto-parameterized SQL | ~100 lines | Prevents SQL injection |
| P2 | Sandbox entry point | ~200 lines | Isolates Claude-generated code |
| P3 | Race detector | ~500 lines | Catches concurrency bugs |
| P3 | Lint for bare `error` calls | ~100 lines | Enforces structured errors |

## Current Safety Grade

| Category | Grade | Blocker |
|----------|:---:|---------|
| Security architecture | A | — |
| Safety (if using safe APIs) | A- | — |
| Safety (if using raw APIs) | C | Safe prelude not default |
| Claude-friendliness | B | Claude doesn't know to use safe APIs |
| Resource management | B | Opt-in, no finalizer net |
| Error diagnostics | B+ | — |
| Type safety | C+ | Runtime-only checks |

**The single highest-impact change**: Make `(jerboa prelude)` re-export the safe
APIs as the default names. This one change moves Claude-friendliness from B to A
because Claude will use the safe versions without being asked.
