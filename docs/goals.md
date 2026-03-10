# Jerboa: Making Gerbil-on-Chez Superior to Other Schemes/Lisps

## Current State

- 51 stdlib modules across crypto, db, networking, OS, text processing
- 11 chez-* FFI libraries (ssl, https, zlib, pcre2, yaml, leveldb, epoll, inotify, crypto, sqlite, postgresql)
- Gerbil reader, compiler, MOP, and runtime on stock Chez Scheme
- Full Gambit thread API shim (`lib/std/misc/thread.sls`) with SMP-safe thread-locals
- Channel-based concurrency (`lib/std/misc/channel.sls`)
- FFI translation macros (`lib/jerboa/ffi.sls`) mapping Gambit types to Chez types
- 338 tests passing (289 core + 49 wrapper)

---

## Feature 1: SMP Actors + Work-Stealing Scheduler

**Status**: Foundation exists (thread.sls, channel.sls use real OS threads)

**Gap**: Channels use `append` for enqueue (O(n)), no bounded channels, no `select` across multiple channels, no work-stealing. `spawn` is just `fork-thread` -- one OS thread per task, which doesn't scale past ~1000 concurrent tasks.

### Implementation Plan

**Module**: `lib/std/actor.sls`

**Phase 1 — Bounded channels + select**
```scheme
;; Bounded channel with backpressure
(make-channel 100)  ;; buffer size 100; channel-put blocks when full

;; Select across multiple channels (like Go select)
(channel-select
  ((ch1 msg) (handle-request msg))
  ((ch2 msg) (handle-event msg))
  (timeout: 5.0 (display "timed out")))
```

- Rewrite channel queue as a ring buffer (vector + head/tail indices) -- O(1) put/get
- Add `channel-select` macro using Chez `condition-wait` on a shared condition variable
- Add optional buffer size to `make-channel`

**Phase 2 — Lightweight tasks with work-stealing**
```scheme
;; spawn creates a lightweight task, NOT an OS thread
(spawn (lambda () (channel-put ch (heavy-computation))))

;; M:N scheduling: M tasks on N OS threads (N = CPU count)
(spawn-pool 8)  ;; 8 worker threads
```

- Fixed-size thread pool (default: `(cpu-count)` workers)
- Lock-free work-stealing deque per worker (Chase-Lev algorithm)
- `spawn` enqueues a thunk to the local deque; idle workers steal from others
- Task = continuation + state, not a full OS thread
- Chez's `make-thread-parameter` for worker-local deque access (already SMP-safe)

**Phase 3 — Actor mailboxes**
```scheme
(define actor (spawn-actor
  (lambda (msg)
    (match msg
      ['ping (reply 'pong)]
      [('compute n) (reply (fib n))]))))

(ask actor 'ping)  ;; => 'pong
(tell actor '(compute 40))  ;; fire-and-forget
```

- Each actor has an unbounded mailbox (MPSC queue)
- Actors are scheduled as tasks on the work-stealing pool
- `ask` = send + create a one-shot reply channel + wait
- `tell` = send, don't wait
- Dead letter handling for messages to dead actors

**Chez primitives used**: `fork-thread`, `make-mutex`, `make-condition`, `condition-wait`, `condition-signal`, `make-thread-parameter`, `cas` (for lock-free deque)

**Files**:
- `lib/std/actor.sls` — spawn, actors, work-stealing scheduler
- `lib/std/actor/scheduler.sls` — thread pool, deque, stealing logic
- `lib/std/actor/mailbox.sls` — MPSC queue for actor messages
- Modify `lib/std/misc/channel.sls` — ring buffer, bounded, select

**Tests**: `tests/test-actor.ss`

---

## Feature 2: Zero-Overhead FFI DSL

**Status**: `lib/jerboa/ffi.sls` has `c-lambda`/`define-c-lambda` mapping Gambit types to Chez. 11 chez-* libraries demonstrate the C shim + `foreign-procedure` pattern.

**Gap**: No declarative library loading, no automatic cleanup, no callback support, no struct accessors. Each chez-* library manually writes ~150 lines of boilerplate.

### Implementation Plan

**Module**: `lib/std/foreign.sls`

**Phase 1 — Declarative extern blocks**
```scheme
(define-ffi-library libsqlite3 "libsqlite3.so"

  ;; Constants
  (define-const SQLITE_OK int)
  (define-const SQLITE_ROW int)

  ;; Functions: (name (arg-types ...) -> ret-type)
  (define-foreign sqlite3-open
    "sqlite3_open" (string void*) -> int)

  (define-foreign sqlite3-close
    "sqlite3_close" (void*) -> int)

  ;; With automatic error checking
  (define-foreign/check sqlite3-exec
    "sqlite3_exec" (void* string void* void* void*) -> int
    (check: (lambda (rc) (= rc SQLITE_OK))
     error: (lambda (rc) (error 'sqlite3-exec "failed" rc)))))
```

- `define-ffi-library` macro expands to `load-shared-object` + multiple `foreign-procedure` bindings
- `define-foreign` generates a wrapper with type-mapped `foreign-procedure`
- `define-foreign/check` adds automatic error checking after the call
- `define-const` calls a zero-arg foreign-procedure to fetch C constants at load time

**Phase 2 — Resource management**
```scheme
;; Pointers with automatic cleanup via guardians
(define-foreign-type sqlite3-db void*
  (destructor: sqlite3-close))

(with-foreign-resource (db (sqlite3-open "test.db"))
  (sqlite3-exec db "CREATE TABLE ..."))
;; db automatically closed on scope exit or GC
```

- `define-foreign-type` creates a wrapper with a Chez guardian for GC-triggered cleanup
- `with-foreign-resource` uses `dynamic-wind` for deterministic cleanup
- Guardian thread periodically checks for collected pointers and calls destructors

**Phase 3 — Callbacks and struct access**
```scheme
;; Scheme -> C callbacks
(define-callback my-handler (int string -> void)
  (lambda (code msg)
    (printf "callback: ~a ~a~%" code msg)))

;; C struct field access (requires knowing offsets)
(define-foreign-struct stat
  (st_size  unsigned-64 offset: 48)
  (st_mtime unsigned-64 offset: 88))
```

- `define-callback` wraps `foreign-callable` + `lock-object` for GC safety
- `define-foreign-struct` generates `foreign-ref`/`foreign-set!` accessors with computed offsets

**Chez primitives used**: `foreign-procedure`, `foreign-callable`, `load-shared-object`, `foreign-alloc`, `foreign-free`, `foreign-ref`, `foreign-set!`, `lock-object`, `unlock-object`, `make-guardian`

**Files**:
- `lib/std/foreign.sls` — `define-ffi-library`, `define-foreign`, resource management
- `lib/std/foreign/types.sls` — type mapping, struct accessors
- `lib/std/foreign/callback.sls` — `define-callback`, GC-safe callable wrappers

**Tests**: `tests/test-foreign.ss`

---

## Feature 3: Static Native Binaries with Tree Shaking

**Status**: Proven in jerboa-shell (6.5 MB ELF, see `docs/single-binary.md`). The technique works: boot file embedding + memfd program loading + custom C main.

**Gap**: No automated tooling. Building a binary requires manually writing `build-binary.ss`, knowing boot file dependency order, and hand-crafting C main files.

### Implementation Plan

**Module**: `lib/jerboa/build.sls` + `bin/jerboa-build` script

**Phase 1 — `jerboa build` command**
```bash
$ jerboa build myapp.ss -o myapp
# Produces: ./myapp (~3-6 MB self-contained ELF)
```

The build command:
1. Traces imports from `myapp.ss` to build the dependency graph
2. Compiles all libraries (`compile-imported-libraries`)
3. Creates a boot file with `make-boot-file` (libraries only, dependency-ordered)
4. Compiles the program separately (`compile-program`)
5. Serializes boot files + program .so as C byte arrays
6. Generates `jerboa-main.c` from a template
7. Links with `gcc -rdynamic -o output main.o -lkernel -llz4 -lz -lm -ldl -lpthread`

**Phase 2 — Tree shaking via WPO**
```bash
$ jerboa build --release myapp.ss -o myapp
# optimize-level 3 + whole-program optimization + no inspector info
```

- `--release` enables `optimize-level 3`, `cp0-effort-limit 500`, `generate-inspector-information #f`
- Generate `.wpo` files and run `compile-whole-program` for dead code elimination
- Skip WPO for modules with mutable exports (auto-detected via `identifier-syntax` scan)
- Expected: +10% performance, -8% binary size (per optimization.md benchmarks)

**Phase 3 — Static linking**
```bash
$ jerboa build --static myapp.ss -o myapp
$ ldd myapp
  not a dynamic executable
```

- Link against Chez's `libkernel.a` (static) instead of dynamic
- Bundle FFI shared objects into the binary as additional C byte arrays
- Load via `memfd_create` at runtime (same technique as the program .so)

**Chez primitives used**: `compile-program`, `compile-file`, `make-boot-file`, `compile-whole-program`, `generate-wpo-files`, `library-directories`, `library-exports`

**Files**:
- `lib/jerboa/build.sls` — dependency tracing, boot file creation, C code generation
- `lib/jerboa/build/embed.sls` — `file->c-header` serialization
- `lib/jerboa/build/link.sls` — gcc invocation, linker flag detection
- `support/jerboa-main.c` — C main template with `Sregister_boot_file_bytes` + `memfd_create`
- `bin/jerboa-build` — CLI entry point

**Tests**: `tests/test-build.ss` (builds a minimal program, runs it, verifies output)

---

## Feature 4: Structured Concurrency

**Status**: No implementation. Thread.sls provides fire-and-forget threads.

**Gap**: No scoped task lifetime. Spawned threads can outlive their parent, leak resources, or fail silently.

### Implementation Plan

**Module**: `lib/std/task.sls`

**Phase 1 — Task groups (nurseries)**
```scheme
(with-task-group (lambda (tg)
  (task-group-spawn tg (lambda () (fetch url1)))
  (task-group-spawn tg (lambda () (fetch url2)))
  ;; Blocks until ALL tasks complete
  ;; If any task throws, all others are cancelled
  ))
```

- `with-task-group` creates a scope; no task can outlive it
- Tasks are scheduled on the work-stealing pool (Feature 1)
- On exception: set a cancellation flag, wake all waiting tasks
- On scope exit: wait for all tasks, then clean up

**Phase 2 — Cancellation via tokens**
```scheme
(with-task-group (lambda (tg)
  (task-group-spawn tg (lambda (cancel-token)
    (let loop ()
      (when (not (cancelled? cancel-token))
        (do-work)
        (loop)))))
  (task-group-cancel! tg)  ;; cancel all tasks
  ))
```

- Each task receives an immutable cancel token
- `cancelled?` checks a shared atomic flag (no lock needed)
- Cooperative cancellation — tasks must check the token at safe points
- `task-group-cancel!` sets the flag and broadcasts to all waiting conditions

**Phase 3 — Structured results**
```scheme
(let-values ([(r1 r2) (with-task-group (lambda (tg)
  (values
    (task-group-async tg (lambda () (compute-a)))
    (task-group-async tg (lambda () (compute-b))))))])
  (process r1 r2))
```

- `task-group-async` returns a future/promise
- The future blocks on `force` until the task completes
- All futures are invalidated if the task group is cancelled

**Chez primitives used**: `fork-thread`, `make-mutex`, `make-condition`, `condition-broadcast`, `dynamic-wind`, `make-thread-parameter`

**Files**:
- `lib/std/task.sls` — `with-task-group`, `task-group-spawn`, `task-group-async`, `task-group-cancel!`
- `lib/std/task/cancel.sls` — cancellation tokens
- `lib/std/task/future.sls` — future/promise for async results

**Tests**: `tests/test-task.ss`

---

## Feature 5: Hermetic Build Cache

**Status**: No caching. Chez's `--compile-imported-libraries` recompiles if `.so` is older than `.sls`.

**Gap**: Timestamp-based, not content-based. No sharing across machines. No parallel compilation.

### Implementation Plan

**Module**: `lib/jerboa/cache.sls`

**Phase 1 — Content-addressed local cache**
```
~/.jerboa/cache/
  abc123def456.so  ← SHA-256(source + dep-hashes + chez-version)
```

- Before compiling a module, hash its source + the hashes of all its dependencies
- If the hash exists in cache, copy the `.so` instead of recompiling
- Cache key includes Chez version and optimize-level (different settings = different artifacts)
- Use Chez's `sha256sum` via FFI (already have chez-crypto) or pure Scheme

**Phase 2 — Parallel compilation**
```scheme
;; Compile independent modules in parallel
(parallel-compile '("std/sort" "std/text/json" "std/text/csv"))
```

- Build the dependency DAG from import analysis
- Compile independent modules in parallel using the thread pool (Feature 1)
- Chez's `compile-file` is thread-safe when writing to different output files
- Topological sort ensures dependencies are compiled before dependents

**Phase 3 — Remote cache**
```bash
$ JERBOA_CACHE=s3://my-bucket/jerboa-cache jerboa build myapp.ss
# Fetches pre-compiled artifacts from S3 if available
```

- Upload compiled `.so` files keyed by content hash
- Download before local compilation; upload after
- HTTP/S3 transport using existing chez-https library

**Files**:
- `lib/jerboa/cache.sls` — hash computation, local cache lookup/store
- `lib/jerboa/cache/parallel.sls` — DAG-based parallel compilation
- `lib/jerboa/cache/remote.sls` — S3/HTTP cache transport

**Tests**: `tests/test-cache.ss`

---

## Feature 6: Gradual Typing

**Status**: No type system. Pure dynamic Scheme.

**Gap**: No way to express types, no compile-time checking, no specialized code generation.

### Implementation Plan

**Module**: `lib/std/typed.sls`

**Phase 1 — Type annotations as assertions**
```scheme
(import (std typed))

(define/t (fibonacci [n : fixnum]) : fixnum
  (if (fx< n 2) n
      (fx+ (fibonacci (fx- n 1)) (fibonacci (fx- n 2)))))

;; In debug mode, expands to:
(define (fibonacci n)
  (assert (fixnum? n))
  (let ([result (if (fx< n 2) n ...)])
    (assert (fixnum? result))
    result))

;; In release mode, expands to:
(define (fibonacci n)
  (if (fx< n 2) n ...))
```

- `define/t` macro parses type annotations from `[arg : type]` syntax
- In debug mode: emit `assert` checks at entry and exit
- In release mode: strip assertions, emit specialized ops (`fx+` for fixnum, `fl+` for flonum)
- Type predicates: `fixnum?`, `flonum?`, `string?`, `pair?`, `vector?`, `bytevector?`, custom record types

**Phase 2 — Parametric types + inference**
```scheme
(define/t (map/t [f : (-> A B)] [lst : (listof A)]) : (listof B)
  ...)

(define/t (hash-get/t [ht : (hashof string fixnum)] [key : string]) : fixnum
  ...)
```

- Type constructors: `(listof T)`, `(vectorof T)`, `(hashof K V)`, `(-> A B)` (function)
- Local type inference within function bodies (flow-sensitive)
- No boundary contracts — types are erased at module boundaries

**Phase 3 — Chez optimizer integration**
```scheme
;; When type is known, emit primitive-level ops
(define/t (dot [v1 : (vectorof flonum)] [v2 : (vectorof flonum)]) : flonum
  ;; Compiler emits fl+ and flvector-ref instead of generic + and vector-ref
  (let loop ([i 0] [sum 0.0])
    (if (= i (vector-length v1)) sum
        (loop (+ i 1) (+ sum (* (vector-ref v1 i) (vector-ref v2 i)))))))
```

- Replace generic ops with typed variants in the macro expansion
- Use Chez's `optimize-level 3` semantics selectively for typed code
- Profile-guided: record types seen at call sites, specialize hot paths

**Files**:
- `lib/std/typed.sls` — `define/t`, `lambda/t`, type assertion macros
- `lib/std/typed/predicates.sls` — type predicate registry, parametric types
- `lib/std/typed/specialize.sls` — op specialization (generic → fixnum/flonum)

**Tests**: `tests/test-typed.ss`

---

## Feature 7: Embeddable Runtime

**Status**: Chez provides `scheme.h` with `Sscheme_init`, `Sbuild_heap`, `Scall`, etc.

**Gap**: Raw Chez embedding API is low-level. No Jerboa-specific wrapper. No multi-instance support docs.

### Implementation Plan

**Module**: `support/jerboa-embed.h` + `support/jerboa-embed.c`

**Phase 1 — Simple C API**
```c
#include "jerboa-embed.h"

jerboa_t *j = jerboa_new(NULL);  // NULL = default config
jerboa_eval(j, "(define x 42)");
int64_t val = jerboa_get_int(j, "x");  // 42
jerboa_eval(j, "(define (greet name) (string-append \"hello \" name))");
const char *s = jerboa_call_string(j, "greet", 1, jerboa_string("world"));
// s = "hello world"
jerboa_destroy(j);
```

- `jerboa_new` calls `Sscheme_init` + `Sbuild_heap` with embedded boot files
- `jerboa_eval` calls `Sscheme_script` or eval via the interaction environment
- Type-safe getters: `jerboa_get_int`, `jerboa_get_string`, `jerboa_get_double`, `jerboa_get_bool`
- `jerboa_call` invokes a named procedure with marshaled arguments
- `jerboa_destroy` calls `Sscheme_deinit`

**Phase 2 — Error handling + multi-instance**
```c
jerboa_error_t err;
if (!jerboa_eval_safe(j, "(/ 1 0)", &err)) {
    printf("Error: %s\n", err.message);
    jerboa_error_free(&err);
}

// Multiple independent instances
jerboa_t *j1 = jerboa_new(NULL);
jerboa_t *j2 = jerboa_new(NULL);
// Each has its own heap, no shared state
```

- Error capture: `guard` in Scheme catches exceptions, marshals to C struct
- Thread safety: each instance has its own Chez heap (requires Chez 10.x)
- Config struct for boot file paths, heap size, library directories

**Phase 3 — Rust/Python bindings**
```rust
let j = Jerboa::new()?;
let result: i64 = j.eval("(+ 1 2)")?;
let greeting: String = j.call("greet", &["world"])?;
```

- Rust: `jerboa-sys` crate wrapping the C API + safe `Jerboa` wrapper
- Python: `ctypes` or `cffi` wrapper around the C shared library

**Files**:
- `support/jerboa-embed.h` — C API header
- `support/jerboa-embed.c` — C implementation wrapping Chez's `scheme.h`
- `support/Makefile` — builds `libjerboa.so` and `libjerboa.a`

**Tests**: `support/test-embed.c`

---

## Feature 8: LSP Server

**Status**: jerboa-lsp exists as a separate project (53 modules ported from gerbil-lsp, see `docs/lsp-conversion.md`). 13/15 e2e tests pass. 5.6 MB binary.

**Gap**: Lives in a separate repo. Needs integration with jerboa's module system for go-to-definition and completion of jerboa stdlib symbols.

### Implementation Plan

**Phase 1 — Integrate jerboa-lsp as a subproject**
- Move core LSP protocol handling into `lib/std/net/lsp.sls`
- Index jerboa's `lib/` tree for completion and go-to-definition
- Use `library-exports` to enumerate available symbols per module

**Phase 2 — Semantic features**
- Go-to-definition: parse import chains, locate `.sls` source files
- Hover: show function arity, type (from Feature 6 annotations), and docstrings
- Diagnostics: run `compile-file` in check mode, report errors with file/line/col
- Completion: scope-aware symbol completion from imported modules

**Phase 3 — Debugger integration (DAP)**
- Debug Adapter Protocol support for step-through debugging
- Use Chez's inspector and `debug` facilities
- Breakpoints via `(trace)` + thread suspension

**Files**:
- `lib/std/net/lsp.sls` — LSP protocol types, JSON-RPC transport
- `lib/std/net/lsp/server.sls` — request handlers, workspace state
- `lib/std/net/lsp/analysis.sls` — go-to-definition, completion, diagnostics
- `bin/jerboa-lsp` — standalone LSP binary

---

## Implementation Priority

Based on dependencies between features and impact:

```
Phase A (Foundation):
  Feature 2: FFI DSL         ← abstracts the chez-* pattern, unlocks everything
  Feature 1: Channels+Select ← bounded channels, ring buffer, select

Phase B (Concurrency):
  Feature 1: Work-stealing   ← M:N task scheduler
  Feature 4: Task groups     ← structured concurrency on top of scheduler
  Feature 1: Actors          ← actor mailboxes on top of scheduler

Phase C (Deployment):
  Feature 3: jerboa build    ← automated static binary generation
  Feature 5: Build cache     ← content-addressed compilation cache

Phase D (Developer Experience):
  Feature 6: Gradual typing  ← type annotations, specialized codegen
  Feature 8: LSP server      ← IDE integration
  Feature 7: Embedding       ← C/Rust/Python bindings
```

Feature 2 (FFI DSL) is the critical path. It reduces the boilerplate in all 11 chez-* libraries and establishes the pattern for users to bind their own C libraries. Feature 1 Phase 1 (better channels) is low-hanging fruit that improves the existing API.

---

## What We Already Have That Others Don't

- **Gerbil's syntax on Chez's runtime** -- nobody else has this combination
- **Self-hosting compiler in ~1100 lines** -- Racket CS's equivalent is 50K+
- **51 stdlib modules** -- crypto, db, networking, OS, text processing
- **11 chez-* FFI libraries** -- ssl, https, zlib, pcre2, yaml, leveldb, epoll, inotify, crypto, sqlite, postgresql
- **Real OS threads** with Gambit-compatible API + channels
- **Proven single-binary technique** -- 6.5 MB ELF with embedded boot files (jerboa-shell)
- **338 tests** -- 289 core + 49 wrapper
