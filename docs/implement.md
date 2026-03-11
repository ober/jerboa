# Jerboa Implementation Plan: The Superior Scheme

## Vision

Jerboa is not another Scheme implementation. It is a **systems programming language** with Scheme's elegance, built on Chez Scheme's world-class compiler. Where Racket chose "batteries included but slow," where Gerbil chose "Gambit plus syntax," and where Guile chose "GNU's extension language," Jerboa chooses: **maximum performance, fearless concurrency, and zero-compromise developer experience.**

The goal: a language you'd choose over Rust for concurrent network services, over Go for systems tooling, over Erlang for distributed systems — because Jerboa gives you all three with less code and no garbage collector pauses that matter.

---

## Current State (Step 8 Complete)

| Component | Status | LOC |
|-----------|--------|-----|
| Core (reader, macros, runtime) | Complete | ~1,700 |
| Standard Library (51 modules) | Complete | ~3,500 |
| FFI (c-lambda, foreign wrappers) | Working | ~500 |
| Actor System (7 layers) | Complete | ~2,500 |
| Gradual Typing (Phase 2-3) | Working | ~320 |
| Build System + Cache | Prototype | ~350 |
| FFI DSL (define-foreign) | Prototype | ~350 |
| Tests | 338 passing | — |
| External Wrappers | 11 chez-* libs | — |
| LSP Server | Separate project, 13/15 e2e | — |

---

## Implementation Phases

### Phase 1: Effect System and Algebraic Effects
**Why this is transformative**: No production Scheme has algebraic effects. Racket has parameters and continuations. OCaml 5 just got effects. Jerboa can be the first Scheme with a typed, performant effect system — and Chez's first-class continuations make the implementation natural.

Algebraic effects subsume: exceptions, async/await, generators/iterators, coroutines, backtracking, nondeterminism, and state. One mechanism replaces six.

**Step 9: Core Effect Handlers**
- File: `lib/std/effect.sls`
- Implement `with-handler`, `perform`, `resume` using Chez's `call/1cc` (one-shot continuations for performance; no full `call/cc` overhead)
- One-shot continuations are critical: most effect handlers resume at most once, and `call/1cc` avoids the continuation-copying overhead of full `call/cc`

```scheme
;; Define effects as lightweight structs
(defeffect Async
  (await promise)     ; suspend until promise resolves
  (spawn thunk))      ; launch concurrent task

(defeffect State
  (get)               ; read current state
  (put val))          ; write new state

;; Handle effects — the handler chooses how to resume
(with-handler ([Async
                (await (p k) (on-resolve p (lambda (v) (resume k v))))
                (spawn (t k) (fork-thread t) (resume k (void)))]
               [State
                (get (k) (resume k current-state))
                (put (v k) (set! current-state v) (resume k (void)))])
  (let ([data (perform (Async await (fetch-url url)))])
    (perform (State put data))
    (process data)))
```

**What this enables**:
- Async/await without colored functions (any function can perform effects)
- Testable code: swap real I/O handler for mock handler
- Composable: stack multiple handlers (async + state + logging)
- Zero-cost when not used: no overhead if no handler is installed

**Step 10: Effect Typing Integration**
- Extend `std/typed.sls` with effect annotations
- `(def (fetch [url : String]) : (Effect Async String))` — the type tells you this function performs Async effects
- Effect inference: if a function calls `perform`, its effect type is inferred
- Effect polymorphism: `(def (map-effect [f : (-> A (Effect E B))] [xs : (List A)]) : (Effect E (List B)))`

**Implementation strategy**:
- `defeffect` macro generates: effect struct types, performer functions, pattern-match clauses
- `with-handler` macro generates: `call/1cc` capture point, dispatch table, resume continuation
- Compile-time effect tracking: accumulate effects through function calls, warn on unhandled effects
- Runtime: effect dispatch via eq-hashtable keyed on effect type descriptor (same pattern as method dispatch — O(1))

**Performance considerations**:
- One-shot continuations (`call/1cc`) avoid the heap allocation of multi-shot `call/cc`
- Effect dispatch is a single hashtable probe (same as method dispatch)
- When the handler is statically known (common case), the macro can inline the handler body directly
- Chez's cp0 can inline small handlers across the `with-handler` boundary

**Lines**: ~400 for core, ~200 for typed integration

---

### Phase 2: Async I/O Runtime
**Why this matters**: Every serious systems language needs non-blocking I/O. Go has goroutines + netpoller, Erlang has the BEAM scheduler, Rust has tokio. Jerboa's actor system already has threads and mailboxes — add an event loop and you have a complete async runtime.

**Step 11: Event Loop on epoll**
- File: `lib/std/async.sls`
- Build on existing `std/os/epoll.sls` wrapper
- Single event loop per scheduler thread (no cross-thread wakeup overhead)
- Integrate with effect system: `(perform (Async await ...))` suspends the current task and registers it with the event loop

```scheme
;; The event loop is an effect handler
(define (run-async thunk)
  (let ([loop (make-event-loop)])
    (with-handler ([Async
                    (await (promise k)
                      (event-loop-register! loop promise k))
                    (spawn (thunk k)
                      (event-loop-submit! loop thunk)
                      (resume k (void)))
                    (sleep (ms k)
                      (event-loop-timer! loop ms k))])
      (thunk)
      (event-loop-run! loop))))  ; process events until all tasks done

;; TCP server with async effects — reads like synchronous code
(def (handle-client conn)
  (let loop ()
    (let ([data (perform (Async await (tcp-read conn 4096)))])
      (unless (eof-object? data)
        (perform (Async await (tcp-write conn (process data))))
        (loop)))))

(def (start-server port)
  (run-async
    (lambda ()
      (let ([listener (tcp-listen port)])
        (let accept-loop ()
          (let ([conn (perform (Async await (tcp-accept listener)))])
            (perform (Async spawn (lambda () (handle-client conn))))
            (accept-loop)))))))
```

**Step 12: Async-Aware Channels and Actors**
- Extend `std/misc/channel.sls`: channel-send/receive become effect-aware (suspend on full/empty instead of blocking OS thread)
- Extend actor mailbox: `receive` suspends via effect when mailbox empty, event loop reschedules when message arrives
- Result: millions of concurrent tasks on a handful of OS threads (like Go goroutines, but with algebraic effects instead of a special runtime)

**Step 13: io_uring Integration (Linux 5.1+)**
- File: `lib/std/os/iouring.sls`
- io_uring provides zero-copy, zero-syscall async I/O
- Submit batches of I/O operations (read, write, accept, connect) in a single syscall
- Completion queue maps directly to effect handler resume points
- This is the performance frontier: even Go and Rust/tokio are still migrating to io_uring

```scheme
(define-ffi-library liburing "liburing"
  (io_uring_queue_init (unsigned int pointer) -> int)
  (io_uring_get_sqe (pointer) -> pointer)
  (io_uring_submit (pointer) -> int)
  (io_uring_wait_cqe (pointer pointer) -> int))

;; Transparent to user code — same async effect, faster backend
(define (make-iouring-event-loop)
  (let ([ring (io-uring-init 256)])
    (make-event-loop
      #:backend 'io-uring
      #:submit (lambda (ops) (io-uring-submit-batch ring ops))
      #:poll (lambda () (io-uring-poll ring)))))
```

**Lines**: ~600 (event loop) + ~300 (io_uring) + ~200 (async channels)

---

### Phase 3: Advanced Type System
**Why this matters**: Typed Racket proved that gradual typing for Scheme is possible but showed it's painfully slow at type boundaries. Jerboa's approach is different: types are *compiler hints*, not runtime contracts. In debug mode, they're assertions. In release mode, they guide optimization. No boundary tax.

**Step 14: Occurrence Typing**
- Extend `std/typed.sls`
- After a type predicate, narrow the type in the consequent branch
- This is the feature that makes gradual typing actually useful in practice

```scheme
(def (process [x : (Union String Number)])
  (cond
    [(string? x)
     ;; Here the compiler knows x is String
     ;; Emits (string-length x) directly, no type check
     (string-length x)]
    [(number? x)
     ;; Here x is Number — emit (fx+ x 1) if fixnum range
     (+ x 1)]))
```

**Step 15: Row Polymorphism for Records**
- Allow functions to accept "any record with at least these fields"
- This gives structural subtyping without the complexity of full OOP

```scheme
;; This function works on any struct with 'name' and 'age' fields
(def (greet [person : (Row name: String age: Number)])
  (format "Hello ~a, you are ~a years old"
          (~ person name) (~ person age)))

(defstruct employee (name age department salary))
(defstruct student (name age university gpa))

;; Both work — row polymorphism checks structurally
(greet (make-employee "Alice" 30 "Engineering" 150000))
(greet (make-student "Bob" 22 "MIT" 3.9))
```

**Implementation**: At compile time, row types resolve to a set of required accessors. The macro emits a record-type-descriptor check + field access. Chez's cp0 can often inline the accessor if the concrete type is known.

**Step 16: Refinement Types**
- Types with predicates: `(Refine Number positive?)` means "a number that satisfies `positive?`"
- In debug mode: runtime assertion. In release mode: erased (you're asserting correctness).
- Killer feature for FFI: `(Refine Pointer nonnull?)` catches null pointer bugs at the boundary

```scheme
(def (sqrt [x : (Refine Number (lambda (n) (>= n 0)))]) : Number
  (fl-sqrt (inexact x)))

;; Port numbers, array indices, etc. — refinements catch logic bugs
(def (connect [host : String]
              [port : (Refine Fixnum (lambda (p) (<= 1 p 65535)))])
  ...)
```

**Step 17: Type-Directed Compilation**
- When the type system knows a value is a fixnum, emit `fx+` instead of generic `+`
- When it knows a value is a flonum, emit `fl*` instead of generic `*`
- When it knows a list is non-empty, skip the `null?` check
- This is where Jerboa's type system pays for itself in raw performance

**Lines**: ~500 (occurrence typing) + ~400 (row types) + ~300 (refinements) + ~300 (type-directed compilation)

---

### Phase 4: Software Transactional Memory
**Why this matters**: Locks don't compose. If module A takes lock 1 then lock 2, and module B takes lock 2 then lock 1, you get deadlocks. STM makes concurrent data access composable — and Chez's first-class continuations make the implementation elegant.

**Step 18: STM Core**
- File: `lib/std/stm.sls`
- Transactional variables (TVars) with optimistic read/write sets
- `atomically` block: run speculatively, validate read set, commit or retry

```scheme
(define balance-a (make-tvar 1000))
(define balance-b (make-tvar 2000))

;; Transfer is atomic — no locks, no deadlocks, composable
(def (transfer! from to amount)
  (atomically
    (let ([f (tvar-read from)]
          [t (tvar-read to)])
      (when (< f amount)
        (retry))  ;; block until balances change, then re-run
      (tvar-write! from (- f amount))
      (tvar-write! to (+ t amount)))))

;; STM composes — this is impossible with locks
(def (transfer-both! a b c amount)
  (atomically
    (transfer! a b amount)     ;; These two transfers are
    (transfer! b c amount)))   ;; a single atomic operation
```

**Implementation**:
- TVars: boxed values with version counters
- Transaction log: thread-local read-set (tvar + version-seen) and write-set (tvar + new-value)
- Commit: acquire global lock (or per-tvar locks with total ordering), validate read-set versions, apply write-set, bump versions, release
- Retry: register current thread on TVars' wait sets, sleep on condition variable, wake when any TVar changes
- Nested transactions: flatten into parent (no nested commit)

**Integration with effects**:
```scheme
(defeffect STM
  (read tvar)
  (write tvar val)
  (retry))
```

**Lines**: ~500

---

### Phase 5: Fearless FFI
**Why this matters**: The existing FFI works but it's manual. The goal is to make calling C as easy as calling Scheme — with safety guarantees that prevent use-after-free, buffer overflows, and null pointer dereferences.

**Step 19: Auto-Generated Bindings from C Headers**
- File: `lib/std/foreign/bind.sls`
- Parse C header files and generate Jerboa FFI bindings automatically
- Handle: functions, structs, enums, typedefs, #defines
- Use the existing `c-lambda` → `foreign-procedure` pipeline

```scheme
;; One line replaces hundreds of manual bindings
(define-c-library sqlite3
  (header "sqlite3.h")
  (link "-lsqlite3")
  (prefix sqlite3_)   ;; strip prefix from Scheme names
  (include-only       ;; only bind what you need
    sqlite3_open sqlite3_close sqlite3_prepare_v2
    sqlite3_step sqlite3_column_* sqlite3_finalize))

;; Auto-generated: (sqlite3-open path db) → int, etc.
;; Type-safe: pointer arguments checked, strings auto-converted
```

**Step 20: Ownership-Tracked Pointers**
- Wrap foreign pointers with ownership metadata
- Use Chez guardians for GC-triggered cleanup
- Prevent use-after-free at the type level

```scheme
(defstruct/foreign sqlite3-db
  (pointer nonnull)
  (destructor sqlite3-close)     ;; called by guardian or explicit free
  (owned #t))                    ;; this Scheme code owns the pointer

;; Use-after-free is a compile-time error when types are enabled
(def (bad-example)
  (let ([db (sqlite3-open ":memory:")])
    (sqlite3-db-free! db)
    (sqlite3-prepare db "SELECT 1")))  ;; Type error: db is freed
```

**Step 21: Async Foreign Calls**
- Problem: `foreign-procedure` blocks the OS thread
- Solution: run blocking FFI calls on a dedicated thread pool, suspend the calling task via effect system

```scheme
;; Transparent to caller — looks synchronous, runs async
(define-foreign/async curl-easy-perform
  (c-lambda (pointer) int "curl_easy_perform")
  #:blocking #t)    ;; runs on FFI thread pool

(def (fetch url)
  ;; This suspends the current task, not the OS thread
  (let ([handle (curl-easy-init)])
    (curl-easy-setopt handle CURLOPT_URL url)
    (curl-easy-perform handle)))  ;; non-blocking!
```

**Lines**: ~600 (header parsing) + ~300 (ownership) + ~300 (async FFI)

---

### Phase 6: Pattern Matching 2.0
**Why this matters**: Jerboa already has `match`. But the best pattern matching in any language is in Rust (exhaustiveness checking) and Scala 3 (extractors). Jerboa can have both, plus features neither has.

**Step 22: Exhaustiveness Checking**
- When matching on a defstruct hierarchy with `(sealed #t)`, the compiler knows all possible cases
- Warn on non-exhaustive patterns at compile time
- This catches bugs that would be runtime `match-error` in every other Scheme

```scheme
(defstruct shape () sealed: #t)
(defstruct circle shape (radius))
(defstruct rect shape (width height))
(defstruct triangle shape (a b c))

(def (area [s : shape])
  (match s
    ((circle r) (* pi r r))
    ((rect w h) (* w h))))
    ;; WARNING: non-exhaustive match — missing 'triangle' case
```

**Step 23: Active Patterns (Extractors)**
- User-defined pattern decomposition — patterns that run arbitrary code
- Like Scala extractors or F# active patterns

```scheme
;; Define an active pattern for parsing
(define-active-pattern (IPv4 s)
  (let ([parts (string-split s ".")])
    (and (= (length parts) 4)
         (let ([nums (map string->number parts)])
           (and (every (lambda (n) (and n (<= 0 n 255))) nums)
                (apply values nums))))))

(def (classify-ip ip)
  (match ip
    ((IPv4 10 _ _ _) 'private-class-a)
    ((IPv4 192 168 _ _) 'private-class-c)
    ((IPv4 127 _ _ _) 'loopback)
    ((IPv4 a b c d) (list 'public a b c d))))
```

**Step 24: Pattern Guards and View Patterns**
```scheme
(match request
  ((http-request method: 'GET path: (? string-prefix? "/api/" -> rest))
   (handle-api rest))
  ((http-request method: 'POST body: (json-parse -> data)
                 (where (hash-has-key? data 'action)))
   (handle-action data)))
```

**Lines**: ~500 (exhaustiveness) + ~300 (active patterns) + ~200 (guards/views)

---

### Phase 7: Metaprogramming and Staging
**Why this matters**: Chez Scheme has the most powerful macro system of any production language. Jerboa should exploit this to the fullest — not just with macros, but with *multi-stage programming* that lets you write code that writes optimized code.

**Step 25: Compile-Time Computation**
- File: `lib/std/staging.sls`
- `(at-compile-time expr)` evaluates at compile time and splices the result
- Build lookup tables, precompute constants, generate specialized code

```scheme
;; Compile-time regex → specialized matcher (no runtime parsing)
(define-syntax fast-match
  (lambda (stx)
    (syntax-case stx ()
      [(_ pattern input)
       (let ([dfa (at-compile-time (regex->dfa (syntax->datum #'pattern)))])
         (generate-dfa-matcher dfa #'input))])))

;; The generated code is a direct state machine — no regex engine at runtime
(fast-match "^[a-z]+@[a-z]+\\.[a-z]{2,}$" email)
```

**Step 26: Code Generation DSL**
- Multi-stage programming: write programs that generate programs
- Type-safe quasiquotation with guaranteed well-formedness
- Use case: domain-specific optimizers, JIT-like specialization

```scheme
;; Generate specialized serializer at compile time based on struct definition
(define-syntax derive-serializer
  (lambda (stx)
    (syntax-case stx ()
      [(_ struct-name)
       (let ([fields (struct-fields (syntax->datum #'struct-name))])
         #`(def (#,(format-id #'struct-name "serialize-~a" #'struct-name) obj port)
             #,@(map (lambda (f)
                       #`(write-field '#,f (#,(accessor-name #'struct-name f) obj) port))
                     fields)))])))

(derive-serializer point)
;; Expands to:
;; (def (serialize-point obj port)
;;   (write-field 'x (point-x obj) port)
;;   (write-field 'y (point-y obj) port))
```

**Step 27: Syntax-Rules Extensions**
- `defrule` already works; extend with:
  - Ellipsis depth tracking (nested `...`)
  - Template guards `(where ...)`
  - Recursive templates for tree transformations

**Lines**: ~400 (staging) + ~500 (codegen DSL) + ~200 (syntax extensions)

---

### Phase 8: Distributed Computing
**Why this matters**: The actor system (Steps 4-8) provides the foundation. Now build the distributed layer that makes Jerboa competitive with Erlang/OTP for building distributed systems.

**Step 28: Node Discovery and Clustering**
- File: `lib/std/actor/cluster.sls`
- Automatic node discovery via UDP multicast or explicit seed nodes
- Cluster membership with failure detection (phi accrual failure detector)
- Node-local actor registry automatically federated

```scheme
(define node (start-node!
  #:name "worker-1"
  #:cookie "my-secret-cookie"    ;; Erlang-style shared secret
  #:listen "tcp://0.0.0.0:9000"
  #:seeds '("tcp://192.168.1.10:9000")))

;; Actors on remote nodes are transparent
(let ([db (whereis 'database #:node "db-server")])
  (ask db (query:select "users" #:where '(active = #t))))
```

**Step 29: Distributed Supervision**
- Supervisors that manage actors across nodes
- If a node goes down, restart its actors on surviving nodes
- Configurable placement strategies: round-robin, least-loaded, affinity

**Step 30: CRDT-Based Distributed State**
- File: `lib/std/actor/crdt.sls`
- Conflict-free replicated data types for eventually-consistent shared state
- G-Counter, PN-Counter, OR-Set, LWW-Register, MV-Register
- Integrate with actor registry: distributed state that survives node failures

```scheme
;; Distributed counter — no coordination needed
(define visitors (make-distributed-counter 'site-visitors))

;; Each node increments locally
(crdt-increment! visitors)

;; Reads merge automatically — eventually consistent
(crdt-value visitors)  ;; => 14523 (merged from all nodes)
```

**Lines**: ~500 (clustering) + ~400 (distributed supervision) + ~600 (CRDTs)

---

### Phase 9: Developer Experience
**Why this matters**: The best language in the world fails if the tooling is painful. Jerboa should have the best REPL, the best debugger, and the best build system of any Scheme.

**Step 31: Hot Code Reloading**
- File: `lib/std/dev/reload.sls`
- Reload individual modules without restarting the process
- Actors receive a `'code-change` message and can migrate state to the new version
- Erlang's killer feature, now in Scheme

```scheme
;; In the REPL during development
(reload! 'my-app/handlers)  ;; recompiles and reloads

;; Actors automatically get new behavior
;; Old messages in flight are handled by old code
;; New messages use new code
```

**Step 32: Time-Travel Debugger**
- File: `lib/std/dev/debug.sls`
- Record execution trace (configurable: all, exceptions-only, or sampled)
- Step backwards through evaluation
- Built on Chez's inspector API + continuation capture

```scheme
(with-recording
  (lambda ()
    (my-complex-function input)))

;; After an error:
(debug-rewind 5)     ;; go back 5 steps
(debug-inspect 'x)   ;; see value of x at this point
(debug-forward 2)    ;; go forward 2 steps
(debug-locals)       ;; show all local bindings
```

**Step 33: Built-In Profiler**
- File: `lib/std/dev/profile.sls`
- Statistical profiler: periodic thread sampling (low overhead)
- Deterministic profiler: instrument specific functions (high detail)
- Allocation profiler: track where memory is allocated
- Output: flame graphs (SVG), call trees (text), hot-spot annotations

```scheme
(with-profiling (#:mode 'statistical #:output "profile.svg")
  (lambda ()
    (run-my-benchmark)))

;; Or instrument specific functions
(profile-functions (fetch parse transform emit)
  (compile-project "my-app"))
```

**Step 34: Package Manager**
- File: `lib/jerboa/pkg.sls`
- Content-addressed package store (like Nix, but simpler)
- Lock files for reproducible builds
- Source dependencies (Git URLs) and binary caches
- Workspace support for monorepos

```scheme
;; jerboa.pkg
(package
  (name "my-web-app")
  (version "1.2.0")
  (dependencies
    (jerboa-http "^0.3.0")
    (jerboa-json "^1.0.0")
    (my-utils (git "https://github.com/me/utils" #:tag "v2.1"))))
```

```
$ jerboa pkg install
$ jerboa pkg add jerboa-crypto
$ jerboa pkg lock     # generate lock file
$ jerboa pkg audit    # check for known vulnerabilities
```

**Step 35: `jerboa build` CLI**
- Complete the build system prototype in `jerboa/build.sls`
- Subcommands: `build`, `run`, `test`, `bench`, `repl`, `fmt`, `lint`
- Incremental compilation using content-addressed cache
- Cross-compilation targets (Linux, macOS, via Chez's cross-compiler support)

```
$ jerboa build my-app.ss -o my-app          # 5 MB static binary
$ jerboa build my-app.ss --target aarch64   # cross-compile
$ jerboa run my-app.ss                      # run without compiling
$ jerboa test                               # run all *-test.ss files
$ jerboa bench benchmarks/                  # run benchmarks
$ jerboa repl                               # REPL with project context
```

**Lines**: ~400 (reload) + ~500 (debugger) + ~400 (profiler) + ~600 (pkg manager) + ~500 (CLI)

---

### Phase 10: Capability-Based Security
**Why this matters**: No Scheme has a capability security model. Jerboa can be the first language where you can safely run untrusted code — useful for plugin systems, multi-tenant servers, and sandboxed scripting.

**Step 36: Object-Capability Model**
- File: `lib/std/capability.sls`
- All dangerous operations (I/O, FFI, network) require a capability token
- Capabilities can be attenuated (read-only view of a file, rate-limited network access)
- Unforgeable: capabilities are opaque objects, not strings or paths

```scheme
;; The main program has full capabilities
(define root-cap (make-root-capability))

;; Create attenuated capabilities for a plugin
(define plugin-fs (attenuate root-cap
  (fs #:read-only #t #:paths '("/data/plugins/myplugin/"))))
(define plugin-net (attenuate root-cap
  (net #:allow '("api.example.com") #:deny-all-others #t)))

;; Plugin receives only what it needs — can't access anything else
(load-plugin "myplugin.ss"
  #:capabilities (list plugin-fs plugin-net))
```

**Step 37: Sandboxed Evaluation**
```scheme
;; Run untrusted code in a sandbox
(define result
  (with-sandbox
    (#:timeout 5000              ;; 5 second time limit
     #:memory (* 64 1024 1024)  ;; 64 MB memory limit
     #:capabilities (list fs-cap net-cap))
    (lambda ()
      (load "untrusted-plugin.ss")
      (plugin-main input))))
```

**Lines**: ~600 (capabilities) + ~400 (sandbox)

---

### Phase 11: Data Processing Pipeline
**Why this matters**: Scheme's functional nature makes it ideal for data pipelines, but no Scheme has a competitive data processing story. Jerboa should have lazy sequences (like Clojure's), transducers, and parallel collection operations.

**Step 38: Lazy Sequences and Transducers**
- File: `lib/std/seq.sls`
- Lazy sequences: produce elements on demand, compose transformations without intermediate allocation
- Transducers: composable transformation steps, independent of data source

```scheme
;; Lazy — nothing computes until you consume
(define (primes)
  (let sieve ([s (range 2 +inf.0)])
    (lazy-cons (lazy-first s)
      (sieve (lazy-filter
               (lambda (n) (not (zero? (mod n (lazy-first s)))))
               (lazy-rest s))))))

(take 100 (primes))  ;; first 100 primes, computed lazily

;; Transducers — one pass, no intermediate lists
(define xform
  (compose-xf
    (filter-xf even?)
    (map-xf (lambda (x) (* x x)))
    (take-xf 10)))

(transduce xform + 0 (range 1 1000000))  ;; sum of first 10 even squares
```

**Step 39: Parallel Collections**
- `par-map`, `par-filter`, `par-reduce` — automatic work distribution across cores
- Built on the work-stealing scheduler from the actor system
- Chunk-based: partition input into cache-friendly chunks, process in parallel, merge results

```scheme
;; Process 10 million records across all cores
(par-map (lambda (record) (expensive-transform record))
         large-dataset
         #:chunk-size 1000)

;; Parallel fold with associative combiner
(par-reduce + 0 (par-map score documents))
```

**Step 40: Dataframe-Like Operations**
- File: `lib/std/table.sls`
- Columnar data tables with typed columns
- SQL-like operations: select, where, group-by, join, aggregate
- Integration with SQLite/PostgreSQL via existing wrappers for query results

```scheme
(define users (table-from-csv "users.csv"))

(-> users
    (table-where (lambda (row) (> (row 'age) 18)))
    (table-group-by 'country)
    (table-aggregate 'count count 'avg-age (mean 'age))
    (table-sort-by 'count #:descending #t)
    (table-take 10))
```

**Lines**: ~500 (lazy seq) + ~400 (parallel collections) + ~600 (tables)

---

### Phase 12: Native Binary Toolchain
**Why this matters**: The build system prototype works but needs to become production-grade. The goal: `jerboa build` produces a static binary as easily as `go build`.

**Step 41: Complete Build Pipeline**
- Finish `jerboa/build.sls` and `jerboa/cache.sls`
- Dependency resolution from `jerboa.pkg`
- Incremental compilation: only recompile changed modules (content-hash comparison)
- Parallel compilation: independent modules compile on separate threads

**Step 42: Tree Shaking and Dead Code Elimination**
- WPO integration: use Chez's `compile-whole-program` for release builds
- Module-level DCE: unused imports don't make it into the binary
- Function-level DCE: unreachable functions eliminated
- Record-level DCE: unused struct types eliminated (Jerboa advantage over Gherkin)

**Step 43: Cross-Compilation**
- Leverage Chez's cross-compiler support (already exists for multiple architectures)
- Target: Linux x86-64, Linux aarch64, macOS x86-64, macOS aarch64
- Cross-compile FFI C code via appropriate toolchain

**Step 44: Static Linking**
- Link against musl libc for truly static Linux binaries
- Embed all FFI libraries (SQLite, OpenSSL, etc.) as static archives
- Target: single-file binary with zero runtime dependencies

```
$ jerboa build --release --static my-server.ss -o my-server
$ ldd my-server
    not a dynamic executable
$ ls -la my-server
    -rwxr-xr-x 1 user user 4.2M my-server
```

**Lines**: ~800 (build pipeline) + ~400 (tree shaking) + ~300 (cross-compile) + ~200 (static linking)

---

### Phase 13: Concurrency Safety Toolkit
**Why this matters**: Fearless concurrency isn't just about having threads — it's about tools that prevent data races, deadlocks, and resource leaks. No Scheme implementation provides these guarantees.

**Step 45: Thread-Safety Annotations**
- Mark data structures as `thread-safe`, `thread-local`, or `immutable`
- Compile-time warnings when thread-local data escapes to another thread
- Integrate with the type system

```scheme
(defstruct/immutable config (host port database))  ;; safe to share
(defstruct/thread-local scratch-buffer (data pos))  ;; warn if shared

(def (handler [cfg : (Immutable config)] request)
  ;; cfg can be freely shared across threads
  ;; scratch-buffer is flagged if captured in a closure passed to spawn
  ...)
```

**Step 46: Deadlock Detection**
- Runtime deadlock detector for development mode
- Track mutex acquisition order per thread
- Detect cycles in the lock-order graph
- Report: which threads hold which locks, and the cycle

**Step 47: Resource Leak Detection**
- Track open resources (files, sockets, FFI pointers) per task/actor
- Warn when a task exits with unclosed resources
- Integrate with structured concurrency: task-group cleanup ensures all resources freed

**Lines**: ~300 (annotations) + ~400 (deadlock detection) + ~300 (leak detection)

---

## Implementation Priority and Dependencies

```
                    Phase 1: Effects
                    /              \
           Phase 2: Async I/O    Phase 3: Types
                |                    |
           Phase 4: STM         Phase 6: Match 2.0
                |                    |
           Phase 5: FFI         Phase 7: Staging
                |                    |
           Phase 8: Distributed    Phase 10: Capabilities
                \                  /
              Phase 9: DevEx Tools
                    |
              Phase 11: Data Processing
                    |
              Phase 12: Build Toolchain
                    |
              Phase 13: Concurrency Safety
```

**Critical path**: Phase 1 (Effects) → Phase 2 (Async) → Phase 8 (Distributed)

**Quick wins** (high impact, low effort):
- Step 22: Exhaustiveness checking for match (~500 lines)
- Step 25: Compile-time computation (~400 lines)
- Step 31: Hot code reload (~400 lines)
- Step 38: Lazy sequences (~500 lines)

**High effort, transformative**:
- Steps 9-10: Effect system (~600 lines, unlocks everything)
- Steps 11-13: Async I/O runtime (~1,100 lines, makes Jerboa competitive for servers)
- Steps 28-30: Distributed computing (~1,500 lines, Erlang competitor)

---

## Competitive Analysis After Full Implementation

| Feature | Jerboa | Racket | Gerbil | Guile | Chez | Erlang | Go | Rust |
|---------|--------|--------|--------|-------|------|--------|-----|------|
| Algebraic effects | **Yes** | No | No | No | No | No | No | No |
| Async I/O (io_uring) | **Yes** | No | No | No | No | Yes* | Yes | Yes |
| Gradual typing | **Yes** | Yes | No | No | No | Yes | Yes | N/A |
| Occurrence typing | **Yes** | Yes | No | No | No | No | No | N/A |
| Row polymorphism | **Yes** | No | No | No | No | No | No | No |
| STM | **Yes** | No | No | No | No | No | No | No |
| Actor supervision | **Yes** | No | Yes | No | No | Yes | No | No |
| Distributed actors | **Yes** | No | Yes | No | No | Yes | No | No |
| CRDTs | **Yes** | No | No | No | No | No | No | No |
| Hot code reload | **Yes** | No | No | No | No | Yes | No | No |
| Static binaries | **Yes** | Yes | Yes | No | No | Yes | Yes | Yes |
| Tree shaking | **Yes** | No | No | No | Yes | No | N/A | Yes |
| Capability security | **Yes** | No | No | No | No | No | No | No |
| Pattern exhaustive | **Yes** | Yes | No | No | No | Yes | No | Yes |
| Active patterns | **Yes** | No | No | No | No | No | No | No |
| Transducers | **Yes** | No | No | No | No | No | No | Yes* |
| Parallel collections | **Yes** | Yes | No | No | No | Yes | Yes | Yes |
| Time-travel debug | **Yes** | No | No | No | No | No | No | No |
| Zero-copy FFI | **Yes** | No | Yes | No | Yes | No | Yes | Yes |
| Auto FFI bindings | **Yes** | Yes | No | No | No | No | No | Yes |
| Content-addressed builds | **Yes** | No | No | No | No | No | No | No |
| Cross-compilation | **Yes** | No | No | Yes | Yes | Yes | Yes | Yes |

\* Erlang uses `epoll`, not `io_uring`. Rust iterators are similar to transducers.

---

## Estimated Total New Code

| Phase | Lines | Modules |
|-------|-------|---------|
| 1. Effects | 600 | 2 |
| 2. Async I/O | 1,100 | 3 |
| 3. Types | 1,500 | 4 |
| 4. STM | 500 | 1 |
| 5. FFI | 1,200 | 3 |
| 6. Pattern Matching | 1,000 | 3 |
| 7. Staging | 1,100 | 3 |
| 8. Distributed | 1,500 | 3 |
| 9. DevEx | 2,400 | 5 |
| 10. Capabilities | 1,000 | 2 |
| 11. Data Processing | 1,500 | 3 |
| 12. Build Toolchain | 1,700 | 4 |
| 13. Concurrency Safety | 1,000 | 3 |
| **Total** | **~16,100** | **39** |

Combined with existing ~9,000 lines, Jerboa would be ~25,000 lines — still half the size of Gherkin's 20,400 lines which provides far less functionality.

---

## The Jerboa Thesis

Most language implementations add features by piling layers on top of their runtime. Jerboa does the opposite: it exposes Chez Scheme's existing power through ergonomic syntax and composable abstractions.

- Effects use Chez's native continuations
- STM uses Chez's native threads and atomic operations
- Types guide Chez's native optimizer
- Records map to Chez's native record system
- FFI maps to Chez's native foreign-procedure
- Binaries use Chez's native boot files and WPO

Every feature compiles down to what Chez already does well. No shim layers, no compatibility wrappers, no runtime tax. The macro system is the optimizer — compile-time code generation replaces runtime dispatch.

This is why Jerboa can be the superior Scheme: it doesn't fight its foundation. It *is* Chez Scheme, with the UX of a modern language.
