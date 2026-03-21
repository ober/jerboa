# Jerboa Safety Guide

Practical guide for writing secure Jerboa applications. Covers all safety
features as of 2026-03-21.

---

## 1. Quick Start: The Safe Prelude

The single most important line in any Jerboa application:

```scheme
(import (jerboa prelude safe))
```

This gives you the full Jerboa standard library with safety turned on by
default. Specifically, you get:

- **Contract-checked stdlib** — SQLite, TCP, file I/O, and JSON functions
  validate arguments before FFI calls and return structured error conditions
- **Resource management** — `with-resource` for RAII-style cleanup
- **Structured concurrency** — `with-task-scope` instead of raw `fork-thread`
- **Timeouts** — `with-timeout` and a configurable `*default-timeout*`
- **Safe serialization** — `safe-fasl-read`/`safe-fasl-write` that reject
  procedures and enforce size limits
- **Sandbox entry point** — `run-safe` and `run-safe-eval` for untrusted code
- **Error conditions** — structured hierarchy instead of bare `(error ...)`

What you do NOT get (intentionally):

- `foreign-procedure`, `c-lambda`, `begin-foreign` — no raw FFI
- `fork-thread` — use `with-task-scope` and `scope-spawn` instead
- `eval` — use `run-safe-eval` for untrusted input

If you need raw FFI or unscoped threads, import `(jerboa prelude)` instead.
But the safe prelude is the recommended default for application code.

---

## 2. The `run-safe` Sandbox

`run-safe` is the one-call entry point for running untrusted code with all
protections applied. It forks a child process, applies irreversible kernel
protections, runs your code, and returns the result to the parent.

### Basic Usage

```scheme
(import (jerboa prelude safe))

;; Run a thunk with default protections:
;; - 30 second timeout
;; - compute-only seccomp filter (blocks network, filesystem writes)
;; - No Landlock rules (add your own for filesystem restriction)
(run-safe (lambda () (+ 1 2)))  ;; => 3

;; Evaluate a string in a restricted environment (113-binding allowlist):
(run-safe-eval "(map (lambda (x) (* x x)) '(1 2 3))")  ;; => (1 4 9)
```

### Custom Configuration

```scheme
;; Allow I/O but restrict to 10 seconds:
(run-safe (lambda () (process-data input))
  (make-sandbox-config
    'timeout 10
    'seccomp 'io-only))

;; Filesystem sandbox: read-only access to specific directories:
(run-safe (lambda () (read-config))
  (make-sandbox-config
    'landlock (make-readonly-ruleset "/etc" "/usr/lib")
    'seccomp 'io-only
    'timeout 5))

;; No timeout (for trusted but resource-limited code):
(run-safe (lambda () (long-computation))
  (make-sandbox-config 'timeout #f 'seccomp 'compute-only))
```

### Config Options

| Key | Values | Default | Effect |
|-----|--------|---------|--------|
| `timeout` | seconds or `#f` | 30 | Engine-based preemptive timeout |
| `seccomp` | `'compute-only`, `'io-only`, `'network-server`, filter, `#f` | `'compute-only` | Syscall filter (irreversible) |
| `landlock` | ruleset or `#f` | `#f` | Filesystem access restriction (irreversible) |
| `capabilities` | list or `'()` | `'()` | Runtime capability tokens |

### Default Parameters

You can set global defaults instead of passing config every time:

```scheme
(parameterize ([*sandbox-timeout* 10]
               [*sandbox-seccomp* 'io-only])
  (run-safe (lambda () (do-work))))
```

### What It Protects Against

- **Code injection**: `run-safe-eval` uses a 113-binding allowlist. `system`,
  `eval`, `load`, `foreign-procedure` are not in the allowlist. No amount of
  clever input can summon them.
- **Filesystem escape**: Landlock restricts filesystem access at the kernel
  level. Once installed, it cannot be undone from Scheme or C.
- **Syscall abuse**: Seccomp BPF filters are kernel-enforced. Even arbitrary
  code execution inside the sandbox cannot bypass them.
- **Infinite loops**: Engine-based timeout preempts runaway Scheme code.
- **Parent compromise**: All protections are applied in a forked child. The
  parent process remains unrestricted.

### What It Does NOT Protect Against

- **Memory exhaustion**: A `(make-bytevector 1000000000)` inside the sandbox
  can OOM the child before the timeout fires. There is no `setrlimit` yet.
  For DoS protection, run sandboxed code in a resource-limited container.
- **Blocked FFI calls**: The engine timeout preempts Scheme code but cannot
  interrupt a blocking C/Rust FFI call. Use socket-level timeouts
  (`SO_RCVTIMEO`) for network operations.
- **Temp file race**: The child communicates results via `/tmp/jerboa-sandbox-*`
  with a random suffix. A local attacker with `/tmp` access could potentially
  interfere. This is a known issue.

---

## 3. Resource Management

### `with-resource` — Guaranteed Cleanup

`with-resource` guarantees that resources are cleaned up even when exceptions
occur. It uses `dynamic-wind` for LIFO cleanup ordering.

```scheme
(import (jerboa prelude safe))

;; Multiple resources — cleaned up in reverse order on any exit:
(with-resource ([db (sqlite-open "app.db")]
                [sock (tcp-connect "api.example.com" 443)]
                [f (open-safe-input-file "config.txt")])
  (let ([config (read f)])
    (sqlite-exec db (format "INSERT INTO log(msg) VALUES('~a')" "started"))
    (tcp-write-string sock "GET / HTTP/1.1\r\n\r\n")))
;; db, sock, and f are ALL guaranteed closed here

;; Single resource shorthand:
(with-resource1 (db (sqlite-open "test.db"))
  (sqlite-query db "SELECT 1"))
```

### Auto-Detection

`with-resource` auto-detects cleanup procedures for common types:

- **Ports** (files, string ports) — calls `close-port` (flushes output first)
- **Registered types** — anything registered via `register-resource-cleanup!`

For other types, provide an explicit cleanup:

```scheme
(with-resource ([buf (make-bytevector 4096) (lambda (b) (bytevector-fill! b 0))])
  (fill-buffer buf))
```

### Guardian Safety Net

If you forget `with-resource`, the guardian-based finalizer in `(std safe)`
catches resource handles that are garbage collected without being closed. It
logs a warning to `current-error-port` and attempts best-effort cleanup.

This is a safety net, not a strategy. Always use `with-resource` explicitly.

To check for leaked resources at shutdown:

```scheme
(poll-resource-finalizers!)
```

---

## 4. Contract-Checked Standard Library

When you import `(jerboa prelude safe)`, the standard names (`sqlite-exec`,
`tcp-connect`, etc.) are transparently replaced with contract-checked
versions from `(std safe)`.

### What the Contracts Check

- **Type validation** before FFI calls — e.g., `sqlite-exec` verifies the
  database handle and SQL string before calling into C
- **Post-condition checks** on results
- **SQL injection heuristics** — multi-statement detection, comment injection,
  and other patterns are rejected at runtime

```scheme
(import (jerboa prelude safe))

;; This works — single statement, no injection patterns:
(sqlite-exec db "SELECT * FROM users WHERE id = ?")

;; This is rejected — multi-statement detected:
(sqlite-exec db "SELECT 1; DROP TABLE users")
;; => raises &db-query-error with SQL injection warning
```

### SQL Injection Detection Limits

The runtime SQL check is a heuristic speed bump, not a wall. It catches
common patterns (`;` statement separators, `--` comments, `/* */` blocks)
but a determined adversary can craft bypasses. **Always use parameterized
queries as your primary defense**:

```scheme
;; GOOD — parameterized:
(sqlite-query db "SELECT * FROM users WHERE id = ?" user-id)

;; BAD — string interpolation (the lint rule will also warn):
(sqlite-query db (string-append "SELECT * FROM users WHERE id = " user-id))
```

### Release Mode

For production code that has been tested, you can skip contract checks for
zero overhead:

```scheme
(parameterize ([*safe-mode* 'release])
  (sqlite-exec db "SELECT 1"))  ;; no pre/post-condition checks
```

Default is `'check`. Only use `'release` after thorough testing.

---

## 5. Structured Concurrency

The safe prelude exports structured concurrency primitives and intentionally
does NOT export `fork-thread`.

### `with-task-scope`

All spawned tasks are guaranteed terminated when the scope exits. No task
outlives its scope.

```scheme
(import (jerboa prelude safe))

;; Spawn parallel work — both tasks are cancelled if scope exits early:
(with-task-scope
  (let ([t1 (scope-spawn (lambda () (fetch-url "https://api.example.com/a")))]
        [t2 (scope-spawn (lambda () (query-db "SELECT count(*) FROM users")))])
    (values (task-await t1) (task-await t2))))

;; Named tasks (for debugging):
(with-task-scope
  (let ([t (scope-spawn-named "data-loader" (lambda () (load-data)))])
    (task-await t)))
```

### `parallel` and `race`

Convenience forms for common patterns:

```scheme
;; Run all, return all results:
(parallel
  (lambda () (fetch-users))
  (lambda () (fetch-orders))
  (lambda () (fetch-config)))

;; Run all, return first to complete, cancel the rest:
(race
  (lambda () (query-primary-db "SELECT 1"))
  (lambda () (query-replica-db "SELECT 1")))
```

### Task Control

```scheme
(with-task-scope
  (let ([t (scope-spawn (lambda () (slow-computation)))])
    ;; Check if done without blocking:
    (task-done? t)    ;; => #f

    ;; Cancel:
    (task-cancel t)

    ;; Block until result (or re-raise task exception):
    (task-await t)))
```

### Why Not `fork-thread`?

Raw `fork-thread` creates threads that outlive their calling context. This
leads to:

- Resource leaks when threads hold references to closed handles
- Uncatchable exceptions in threads that nobody joins
- Race conditions that are hard to reproduce

`with-task-scope` prevents all of these by construction. If you genuinely
need raw threads, import `(jerboa prelude)` instead — but you lose the
structured cleanup guarantees.

---

## 6. Timeouts

### `with-timeout`

Uses Chez Scheme's engine system for true preemptive timeout. Works even if
the code is stuck in a Scheme-level infinite loop.

```scheme
(import (jerboa prelude safe))

;; Timeout after 5 seconds:
(with-timeout 5
  (tcp-read sock 1024))

;; Raises &jerboa-timeout on expiry.
;; Handle it:
(guard (exn
        [(timeout-error? exn) (displayln "operation timed out")])
  (with-timeout 2
    (infinite-loop)))
```

### `*default-timeout*`

Controls the default timeout for safe-* operations. Default is 30 seconds.

```scheme
;; Set a 10-second default for this scope:
(parameterize ([*default-timeout* 10])
  ;; All safe operations in this dynamic extent use 10s timeout
  (tcp-read sock 1024))

;; Disable timeouts (not recommended for untrusted input):
(parameterize ([*default-timeout* #f])
  (long-trusted-computation))
```

### Limitations

The engine-based timeout cannot interrupt blocked foreign calls (C/Rust FFI).
If a C function blocks on a socket read, the engine timer has no effect until
control returns to Scheme. For network I/O, set socket-level timeouts
(`SO_RCVTIMEO`/`SO_SNDTIMEO`) as a complementary measure.

---

## 7. Type Checking

### `define/ct` — Compile-Time Checked Functions

```scheme
(import (std typed check))

(define/ct (add [x : integer] [y : integer]) : integer
  (+ x y))

(define/ct (greet [name : string]) : string
  (string-append "Hello, " name))
```

Type mismatches are caught at compile time (macro expansion time). By default
they are warnings. For strict enforcement:

```scheme
;; Make type mismatches fatal compilation errors:
(parameterize ([*type-errors-fatal* #t])
  (compile-file "my-module.ss"))
```

### `lambda/ct` — Typed Lambdas

```scheme
(define handler
  (lambda/ct ([request : string] [timeout : integer]) : string
    (process request timeout)))
```

### Checking Existing Code

```scheme
;; Type-check a file and get error reports:
(type-check-file "my-module.ss")
;; => list of type-error records

;; Type-check forms programmatically:
(check-program-types
  '((define (f x) (+ x "hello"))))  ;; => type mismatch: integer vs string
```

### Coverage Limitations

The type system is gradual and opt-in. Only functions annotated with
`define/ct` or `lambda/ct` are checked. Calls from checked code to unchecked
code cross an unchecked boundary — type confusion bugs can still occur there.
This is standard for gradual type systems.

---

## 8. Kernel Sandboxing

### Landlock — Filesystem Restriction

Landlock restricts filesystem access without root. Rules are irreversible.
Available on Linux 5.13+.

```scheme
(import (std security landlock))

;; Build a ruleset:
(let ([rules (make-landlock-ruleset)])
  ;; Grant read-only access to specific directories:
  (landlock-add-read-only! rules "/usr/lib")
  (landlock-add-read-only! rules "/etc")
  ;; Grant read-write to a working directory:
  (landlock-add-read-write! rules "/tmp/myapp")
  ;; Grant execute permission:
  (landlock-add-execute! rules "/usr/bin")
  ;; Install (IRREVERSIBLE — cannot undo):
  (landlock-install! rules))
;; All filesystem access outside these paths is now blocked

;; Convenience: scope-based Landlock
(with-landlock (make-readonly-ruleset "/usr/lib" "/etc")
  (read-config-files))

;; Pre-built rulesets:
(make-readonly-ruleset "/path1" "/path2" ...)
(make-tmpdir-ruleset "/tmp/myapp")

;; Check availability:
(landlock-available?)  ;; => #t on Linux 5.13+ x86_64
```

### Seccomp — Syscall Filtering

Seccomp BPF restricts which system calls a process can make. Filters are
irreversible and kernel-enforced. Available on Linux x86_64.

```scheme
(import (std security seccomp))

;; Pre-built filters:
(seccomp-install! (compute-only-filter))    ;; CPU-only: blocks network, FS writes
(seccomp-install! (io-only-filter))         ;; Allow file I/O, block network
(seccomp-install! (network-server-filter))  ;; Allow network, block exec

;; Custom filter:
(let ([filter (make-seccomp-filter
                'default-action (seccomp-errno 1)  ;; EPERM for unmatched
                'allowed '(read write exit-group brk mmap mprotect))])
  (seccomp-install! filter))

;; Check availability:
(seccomp-available?)  ;; => #t on Linux x86_64
```

### When to Use Directly vs. via `run-safe`

Use `run-safe` when:
- You want all protections applied together (timeout + seccomp + Landlock)
- You need fork-based isolation (protections apply only to child)
- You are running untrusted code

Use Landlock/seccomp directly when:
- You want to restrict the main process permanently (e.g., a server that
  drops privileges after startup)
- You need fine-grained control over the protection order
- You want irreversible self-restriction as a defense-in-depth measure

Remember: **both Landlock and seccomp are irreversible**. Once installed in a
process, they cannot be removed — only tightened further. `run-safe` handles
this by forking a child, so the parent stays unrestricted.

---

## 9. Error Handling

### Structured Condition Hierarchy

All Jerboa errors inherit from `&jerboa`, which inherits from R6RS `&serious`.
Use `guard` to catch specific error kinds:

```scheme
(import (jerboa prelude safe))

(guard (exn
        [(db-query-error? exn)
         (displayln "bad query")]
        [(connection-refused? exn)
         (displayln "server down")]
        [(timeout-error? exn)
         (displayln "timed out")]
        [(resource-leak? exn)
         (displayln "resource leaked")]
        [(jerboa-condition? exn)
         (displayln (format "jerboa error in ~a"
                            (jerboa-condition-subsystem exn)))])
  (do-work))
```

### Full Hierarchy

```
&jerboa (root)
  &jerboa-network
    &connection-refused
    &connection-timeout
    &dns-failure
    &tls-error
    &network-read-error
    &network-write-error
  &jerboa-db
    &db-connection-error
    &db-query-error
    &db-constraint-violation
    &db-timeout
  &jerboa-actor
    &actor-dead
    &mailbox-full
    &supervision-failure
    &actor-timeout
  &jerboa-resource
    &resource-leak
    &resource-already-closed
    &resource-exhausted
  &jerboa-timeout
  &jerboa-serialization
    &unsafe-deserialize
    &serialize-size-exceeded
  &jerboa-parse
    &parse-depth-exceeded
    &parse-size-exceeded
    &parse-invalid-input
```

### Error Context

`(std error context)` provides `with-context` for accumulating diagnostic
context through call chains:

```scheme
(import (std error context))

(with-context "loading user profile"
  (with-context (format "user-id: ~a" user-id)
    (load-profile user-id)))
;; If load-profile raises, the error includes both context strings
```

---

## 10. Safe Serialization

### `safe-fasl-read` / `safe-fasl-write`

Wraps Chez FASL with safety checks for untrusted data:

```scheme
(import (jerboa prelude safe))

;; Write (rejects procedures by default):
(call-with-output-file "data.fasl"
  (lambda (port) (safe-fasl-write '(1 2 3) port)))

;; Read (rejects procedures and unregistered record types):
(call-with-input-file "data.fasl"
  (lambda (port) (safe-fasl-read port)))

;; Bytevector convenience:
(let ([bytes (safe-fasl-write-bytevector '(1 2 3))])
  (safe-fasl-read-bytevector bytes))
```

### Configuration

```scheme
;; Allow procedures (for trusted local persistence only):
(parameterize ([*fasl-allow-procedures* #t])
  (safe-fasl-write my-closure port))

;; Size limits:
(parameterize ([*fasl-max-object-count* 10000]     ;; max 10K objects (default 1M)
               [*fasl-max-byte-size* (* 1 1024 1024)])  ;; max 1MB (default 100MB)
  (safe-fasl-read port))
```

### Record Type Registry

Only explicitly registered record types can be deserialized:

```scheme
(define-record-type user (fields name email))

;; Register for deserialization:
(register-safe-record-type! (record-type-descriptor user))

;; Now safe-fasl-read will accept user records.
;; Unregister when no longer needed:
(unregister-safe-record-type! (record-type-descriptor user))
```

### Decompression Bomb Limits

These limits apply across the safe APIs:

| Parser | Parameter | Default |
|--------|-----------|---------|
| JSON | `*json-max-depth*` | 512 |
| JSON | `*json-max-string-length*` | 10 MB |
| XML/SXML | `*sxml-max-depth*` | 512 |
| XML/SXML | `*sxml-max-output-size*` | 50 MB |
| FASL | `*fasl-max-object-count*` | 1,000,000 |
| FASL | `*fasl-max-byte-size*` | 100 MB |
| Zlib | (hardcoded in Rust backend) | 100 MB |

---

## 11. Linting

`(std lint)` provides 14 static analysis rules. Run them on your source files
to catch common issues before they become bugs.

### Usage

```scheme
(import (std lint))

;; Lint a file:
(let ([results (lint-file default-linter "my-module.ss")])
  (for-each
    (lambda (r)
      (displayln (format "[~a] ~a: ~a"
                         (lint-result-severity r)
                         (lint-result-rule r)
                         (lint-result-message r))))
    results))

;; Lint a string:
(lint-string default-linter "(import (std db sqlite-native)) (define car 42)")

;; Summary counts:
(lint-summary results)  ;; => ((error . 0) (warn . 2) (info . 1))
```

### The 14 Rules

**Safety rules** (severity: warn):

| Rule | Detects |
|------|---------|
| `unsafe-import` | Importing raw FFI modules when safe alternatives exist |
| `sql-interpolation` | Building SQL via `string-append`/`format` inside sqlite calls |
| `redefine-builtin` | Redefining `car`, `map`, `+`, etc. |
| `duplicate-import` | Importing the same module more than once |

**Safety rules** (severity: info):

| Rule | Detects |
|------|---------|
| `bare-error` | Using `(error ...)` instead of structured conditions |
| `unused-only-import` | Symbols imported via `(only ...)` that are never used |

**Hygiene rules** (severity: warn/info):

| Rule | Detects |
|------|---------|
| `shadowed-define` | Bindings that shadow outer bindings |
| `unused-define` | Top-level definitions never referenced in the same file |

**Style rules** (severity: info):

| Rule | Detects |
|------|---------|
| `empty-begin` | `(begin)` with no forms |
| `single-arm-cond` | `cond` with only one clause (use `if` instead) |
| `missing-else` | `if` without an else branch |
| `deep-nesting` | Expressions nested more than 10 levels |
| `long-lambda` | Lambda bodies with more than 20 forms |
| `magic-number` | Numeric literals > 100 (suggest named constants) |

### Custom Rules

```scheme
(let ([linter (make-linter)])
  ;; Add a custom rule:
  (add-rule! linter 'no-display
    (lambda (forms)
      (filter-map
        (lambda (f)
          (and (pair? f) (eq? (car f) 'display)
               (make-lint-result #f #f #f 'warn
                 "use displayln instead of display" 'no-display)))
        forms)))

  ;; Remove a built-in rule:
  (remove-rule! linter 'magic-number)

  (lint-file linter "my-module.ss"))
```

---

## 12. Known Limitations

Be honest about what Jerboa does NOT protect against:

### No Memory Limits in Sandbox

`run-safe` does not set `setrlimit(RLIMIT_AS)` in the child process. A
malicious thunk can exhaust memory before the timeout fires. If you run
untrusted code, use OS-level memory limits (cgroups, containers) as a
complementary measure.

### Kernel Protections Are Linux x86_64 Only

Landlock requires Linux 5.13+. Seccomp BPF uses x86_64-specific syscall
numbers. On other platforms (macOS, ARM Linux, BSDs), these protections
silently degrade — the code runs without kernel sandboxing. The Scheme-level
allowlist and timeout still apply.

### Temp File Race in `run-safe`

`run-safe` communicates results via `/tmp/jerboa-sandbox-<random>`. A local
attacker with `/tmp` access could create symlinks to redirect the result
file. This should use `mkstemp` or `O_TMPFILE` but does not yet.

### Engine Timeout Cannot Interrupt FFI

The Chez engine timeout preempts Scheme computation but not blocked foreign
calls. If your code calls a C function that blocks on a socket, the timeout
has no effect until that call returns. Set socket-level timeouts separately.

### Type System Is Gradual

Only `define/ct` and `lambda/ct` annotated functions are type-checked. Calls
from checked code into unchecked code cross an unchecked boundary. Type
confusion bugs can occur at these boundaries.

### No Race Detector

There is no dynamic race detection for concurrent code. Structured concurrency
via `with-task-scope` reduces risk but does not eliminate data races. Code
using raw `fork-thread` (from the non-safe prelude) has no race detection.

### Deadlock Detection Is Opt-In

`(std concur deadlock)` provides `make-checked-mutex` and
`with-checked-mutex` for runtime deadlock detection via wait-for graph
analysis. This is not automatic — you must explicitly use checked mutexes.
Regular `make-mutex` has no deadlock detection.

### SQL Injection Heuristic Is Bypassable

The runtime SQL injection check in `(std safe)` uses pattern matching. It
catches common attacks but a determined adversary with knowledge of the
heuristics can craft bypasses. Parameterized queries are the real defense.

### Import Conflict in Safe Prelude

The safe prelude has overlapping symbol exports between imported modules that
produce a "multiple definitions" warning. This is cosmetic but means symbol
resolution order could theoretically surprise you in edge cases. In practice,
the safe version always wins because it is bound last.

### Build Reproducibility Is Partial

`(std build reproducible)` provides content-addressed artifacts and SHA-256
hashing, but bit-identical reproducible builds end-to-end are not yet
verified. The SBOM detects Scheme, C, and Rust dependencies but full build
orchestration is not complete.

---

## Recommended Patterns

### Server That Drops Privileges

```scheme
(import (jerboa prelude safe))
(import (std security landlock))
(import (std security seccomp))

;; Phase 1: Start up with full privileges
(define config (read-config "/etc/myapp/config.scm"))
(define db (sqlite-open (config-db-path config)))
(define server (tcp-listen (config-port config)))

;; Phase 2: Drop privileges (irreversible)
(let ([rules (make-landlock-ruleset)])
  (landlock-add-read-only! rules "/etc/myapp")
  (landlock-add-read-write! rules "/var/lib/myapp")
  (landlock-install! rules))
(seccomp-install! (network-server-filter))

;; Phase 3: Serve requests with restricted privileges
(let loop ()
  (with-resource ([client (tcp-accept server)])
    (with-timeout 30
      (handle-request db client)))
  (loop))
```

### Processing Untrusted User Input

```scheme
(import (jerboa prelude safe))

(define (eval-user-expression user-input)
  ;; Fork a child, apply all protections, evaluate in 113-binding allowlist:
  (guard (exn
          [(sandbox-error? exn)
           (format "Error: ~a" (sandbox-error-detail exn))]
          [(timeout-error? exn)
           "Timed out"])
    (run-safe-eval user-input
      (make-sandbox-config 'timeout 5))))
```

### Robust Resource Handling

```scheme
(import (jerboa prelude safe))

(define (transfer-data source-path dest-path)
  (with-resource ([in (open-safe-input-file source-path)]
                  [out (open-safe-output-file dest-path)])
    (with-timeout 60
      (let loop ()
        (let ([line (get-line in)])
          (unless (eof-object? line)
            (put-string out line)
            (newline out)
            (loop)))))))
;; Both files guaranteed closed, even on timeout or exception
```

### Parallel Work with Cancellation

```scheme
(import (jerboa prelude safe))

(define (fetch-with-fallback primary-url fallback-url)
  ;; First to complete wins, other is cancelled:
  (race
    (lambda () (fetch-url primary-url))
    (lambda () (fetch-url fallback-url))))
```
