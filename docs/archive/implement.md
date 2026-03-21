# Jerboa Implementation Plan: Phase 5 — The World-Class Scheme

## Status: Phase 8 Complete

Phases 1-4 establish Jerboa as the most capable Scheme implementation ever built, with 200+ modules and 2,700+ tests. Phase 5 pushes Jerboa into uncharted territory by exploiting Chez Scheme's deepest capabilities — features that exist nowhere else in the Scheme ecosystem.

### Where We Stand

| Phase | Libraries | Tests | Status |
|-------|-----------|-------|--------|
| 1: Core | 51 | 289 | Complete |
| 2: Advanced | 28 | 541 | Complete |
| 3: Production | 23 | 637 | Complete |
| 4a: Core Runtime | 6 | 165 | Complete |
| 4b: Type System | 8 | 363 | Complete |
| 4c: Systems | 6 | 179 | Complete |
| 4d: Dev Experience | 5 | 220 | Complete |
| 4e: Data & Distribution | 5 | 247 | Complete |
| 4f: Toolchain & Interop | 5 | 257 | Complete |
| **Phase 4 Total** | **137** | **2,898** | **Complete** |
| **Phase 5 (Planned)** | **~65** | **~1,500** | **In Progress** |

---

# Phase 5: Chez Scheme's Magical Powers Unleashed

Phase 5 leverages Chez Scheme's unique capabilities that no other Scheme implementation has — features that Kent Dybvig spent 35+ years perfecting. These aren't just incremental improvements; they're architectural advantages that make certain classes of features possible that would be impossible or extremely difficult in other implementations.

## The Chez Scheme Advantage

Chez Scheme has capabilities that most developers don't even know exist:

1. **Native Code Compilation with cp0** — The most sophisticated Scheme optimizer ever built, with constant folding, inlining, dead code elimination, and type-based specialization
2. **Engines** — Preemptible computations with fuel-based scheduling (unique to Chez)
3. **First-Class Continuations** — Both one-shot (`call/1cc`) and multi-shot (`call/cc`) with serialization via `fasl-write`
4. **Native OS Threads** — True SMP with thread-local parameters, not green threads
5. **Fasl Serialization** — Binary serialization of ANY Scheme value including closures and continuations
6. **Foreign Procedure Interface** — Zero-copy FFI with automatic type marshaling
7. **Profile-Guided Optimization** — Runtime profiling that feeds back into compilation
8. **Inspector API** — Full runtime introspection of stack frames, closures, and records
9. **Compile-Time Computation** — Arbitrary Scheme code at macro-expansion time
10. **Whole-Program Optimization** — Cross-module inlining and dead code elimination

---

## Track 11: The Compiler as a Library — Self-Modifying Optimization

### 11.1 User-Defined cp0 Optimization Passes

Chez's cp0 optimizer is the crown jewel. Phase 5 exposes it as a library, letting users write custom optimization passes that run during compilation.

```scheme
(import (std compiler passes))

;; Define a custom optimization pass
(define-cp0-pass matrix-fusion
  "Fuse consecutive matrix operations to avoid intermediate allocations"
  #:pattern (matrix-* (matrix-* ?a ?b) ?c)
  #:transform (matrix-*-fused ?a ?b ?c))

;; Register it globally
(register-optimization-pass! matrix-fusion #:priority 50)

;; Now this code:
(define result (matrix-* (matrix-* A B) C))
;; Compiles to a single fused operation — no intermediate matrix

;; Domain-specific optimizations
(define-cp0-pass sql-query-fusion
  "Combine consecutive SQL operations into single query"
  #:pattern (sql-filter ?pred (sql-map ?fn ?table))
  #:transform (sql-filter-map ?pred ?fn ?table))
```

**Implementation**:
- Hook into Chez's nanopass framework (`(nanopass)` library)
- Expose `define-cp0-pass` macro that generates nanopass transformers
- Pattern language with `?var` for pattern variables, guards for predicates
- Pass composition with explicit ordering via `#:priority`
- Debug mode: dump intermediate representations between passes

**Why unique**: No other language lets users write optimizations that run inside the compiler. LLVM has passes, but they operate on IR, not source semantics. This lets domain experts (numerical computing, databases, graphics) write optimizations that understand their domain.

**Files**: `lib/std/compiler/passes.sls` (~600 LOC), `lib/std/compiler/pattern.sls` (~400 LOC)
**Tests**: 30 tests

### 11.2 Compile-Time Partial Evaluation

Go beyond macros to automatic partial evaluation — the compiler evaluates what it can at compile time.

```scheme
(import (std compiler partial-eval))

;; Mark a function for aggressive partial evaluation
(define/pe (power base n)
  (if (= n 0)
      1
      (* base (power base (- n 1)))))

;; At compile time, if n is known:
(define cube (lambda (x) (power x 3)))
;; Expands to: (define cube (lambda (x) (* x (* x (* x 1)))))
;; Then cp0 folds: (define cube (lambda (x) (* x x x)))

;; Specialize entire functions
(define-specialized power-5 (power _ 5))
;; Generates: (define power-5 (lambda (base) (* base base base base base)))

;; Automatic specialization based on call patterns
(define/auto-specialize matrix-multiply
  (lambda (A B)
    ...)) ;; Compiler generates specialized versions for common matrix sizes
```

**Implementation**:
- Binding-time analysis: classify expressions as static (compile-time) or dynamic (runtime)
- Unfold calls with static arguments, residualize calls with dynamic arguments
- Memoization table to avoid re-specializing identical configurations
- Integration with `compile-time-value` for forcing compile-time evaluation
- Specialization cache in `.jerboa/specializations/`

**Files**: `lib/std/compiler/partial-eval.sls` (~800 LOC)
**Tests**: 35 tests

### 11.3 Profile-Guided Optimization Integration

Use runtime profiling data to guide compilation decisions.

```scheme
(import (std compiler pgo))

;; Collect profile data during test runs
;; $ jerboa run --profile-collect myapp.ss
;; Generates: .jerboa/profile/myapp.prof

;; Rebuild with profile data
;; $ jerboa build --profile-use myapp.ss -o myapp

;; Or programmatically:
(define-pgo-module (myapp main)
  (import ...)
  
  ;; This hot function will be inlined aggressively
  (define (process-event event)
    (case (event-type event)
      [(click) (handle-click event)]      ;; 73% of calls
      [(scroll) (handle-scroll event)]    ;; 25% of calls
      [(keypress) (handle-key event)]))   ;; 2% of calls
  
  ;; PGO reorders branches by frequency, inlines hot paths
  )

;; Query profile data programmatically
(profile-hot-functions "myapp.prof" #:top 20)
;; => ((process-event 45000000) (handle-click 32850000) ...)
```

**Implementation**:
- Instrumentation pass: insert counters at basic block boundaries
- Profile file format: binary, maps code locations to execution counts
- Branch reordering: put most likely branch first for better prediction
- Inline decisions: lower threshold for frequently-called functions
- Dead code: functions never called in profile are candidates for removal

**Files**: `lib/std/compiler/pgo.sls` (~500 LOC), `lib/std/compiler/instrument.sls` (~400 LOC)
**Tests**: 25 tests

---

## Track 12: First-Class Continuations as a Superpower

### 12.1 Delimited Continuations with Efficient Implementation

Chez's continuation implementation is the fastest in any Scheme. Expose it with a cleaner API.

```scheme
(import (std control delimited))

;; Shift/reset — the classic delimited control operators
(reset
  (+ 1 (shift k (k (k 5)))))
;; => 7 (k applied twice: 1 + (1 + 5))

;; Control/prompt — abortive variant
(prompt
  (+ 1 (control k 5)))
;; => 5 (continuation k discarded)

;; Named prompts for nested handlers
(prompt 'outer
  (prompt 'inner
    (+ 1 (shift-at 'outer k (k 10)))))
;; => 11 (jumps past inner prompt to outer)

;; Efficient implementation: no stack copying for one-shot use
(define (generator->stream gen)
  (let ([resume #f])
    (reset
      (gen (lambda (value)
             (shift k
               (set! resume k)
               value)))
      'done)))
```

**Implementation**:
- `reset`/`shift` via Chez's `call/cc` with prompt markers
- One-shot optimization: use `call/1cc` when continuation used linearly
- Named prompts via hash table mapping tags to prompt continuations
- `control`/`prompt` as abortive variant (doesn't capture continuation)
- Integration with effect system from Phase 4

**Files**: `lib/std/control/delimited.sls` (~400 LOC)
**Tests**: 30 tests

### 12.2 Coroutine Library with Symmetric Coroutines

True symmetric coroutines where any coroutine can transfer to any other.

```scheme
(import (std control coroutine))

;; Create coroutines
(define co1
  (make-coroutine
    (lambda (yield)
      (displayln "co1: start")
      (yield 'to-co2 1)
      (displayln "co1: back with 2")
      (yield 'to-co2 3)
      'done)))

(define co2
  (make-coroutine
    (lambda (yield)
      (displayln "co2: received 1")
      (yield 'to-co1 2)
      (displayln "co2: received 3")
      'finished)))

;; Symmetric transfer
(coroutine-transfer co1)
;; Prints: co1: start, co2: received 1, co1: back with 2, co2: received 3

;; Use for cooperative multitasking
(define scheduler (make-round-robin-scheduler))
(scheduler-add! scheduler co1)
(scheduler-add! scheduler co2)
(scheduler-run! scheduler)
```

**Implementation**:
- Coroutine = one-shot continuation + state (ready, running, suspended, dead)
- `yield` captures current continuation, stores it, transfers to target
- Scheduler maintains run queue of ready coroutines
- Deadlock detection: all coroutines waiting, none ready

**Files**: `lib/std/control/coroutine.sls` (~350 LOC)
**Tests**: 25 tests

### 12.3 Continuation Marks for Dynamic Scoping

Continuation marks attach key-value pairs to stack frames, enabling stack inspection without explicit passing.

```scheme
(import (std control marks))

;; Attach a mark to the current continuation
(with-continuation-mark 'user-id 42
  (with-continuation-mark 'request-id "abc123"
    (handle-request)))

;; Inside handle-request, query marks:
(define (log-event event)
  (let ([user-id (current-continuation-marks 'user-id)]
        [request-id (current-continuation-marks 'request-id)])
    (format "~a: user=~a request=~a event=~a"
            (current-time) user-id request-id event)))

;; Get all marks for a key (stack trace of values)
(continuation-marks->list 'user-id)
;; => (42) — only one mark in this example

;; Use for:
;; - Logging context without threading through every function
;; - Security context (current user, permissions)
;; - Transaction context (current DB connection)
;; - Error context (source location breadcrumbs)
```

**Implementation**:
- Marks stored in a thread-local stack of (key . value) pairs
- `with-continuation-mark` pushes on entry, pops on exit (via `dynamic-wind`)
- `current-continuation-marks` walks the mark stack
- Efficient: marks are hash-consed for fast comparison

**Files**: `lib/std/control/marks.sls` (~300 LOC)
**Tests**: 20 tests

---

## Track 13: Fasl — The Universal Serializer

### 13.1 Persistent Closures and Hot Code Reload

Chez can serialize closures to disk and reload them. This enables features impossible in most languages.

```scheme
(import (std persist closure))

;; Serialize a closure to disk
(define my-handler
  (let ([config (load-config)])
    (lambda (request)
      (process request config))))

(closure-save my-handler "handler.fasl")

;; Later, in a different process:
(define restored-handler (closure-load "handler.fasl"))
(restored-handler some-request) ;; Works! Config is embedded

;; Hot code reload without losing state
(define (make-stateful-service initial-state)
  (let ([state initial-state])
    (lambda (msg)
      (case (car msg)
        [(get) state]
        [(set) (set! state (cadr msg))]
        [(upgrade code)
         ;; Replace this closure's code while keeping state!
         (let ([new-handler (eval code)])
           (set! state (new-handler 'migrate state)))]))))

;; Checkpoint long-running computations
(define (checkpoint-computation comp-state)
  (fasl-write comp-state "checkpoint.fasl"))

(define (resume-computation)
  (let ([state (fasl-read "checkpoint.fasl")])
    (continue-from state)))
```

**Implementation**:
- Wrap `fasl-write`/`fasl-read` with closure-aware preprocessing
- Strip non-serializable values (ports, FFI pointers) with replacement markers
- Versioning: include schema version in serialized data
- Hot reload: combine with `eval` to replace code while preserving heap

**Files**: `lib/std/persist/closure.sls` (~400 LOC)
**Tests**: 25 tests

### 13.2 Distributed Object Protocol

Share objects between processes using fasl serialization.

```scheme
(import (std persist distributed))

;; Create a distributed hash table
(define dht (make-distributed-hashtable
  #:nodes '("node1:9000" "node2:9000" "node3:9000")
  #:replication 2))

;; Store any Scheme value — including closures!
(dht-put! dht 'my-handler
  (lambda (x) (* x x)))

;; On another node:
(define handler (dht-get dht 'my-handler))
(handler 5) ;; => 25

;; Distributed actors with mobile code
(define (spawn-remote node code)
  (let ([serialized (fasl-write code)])
    (remote-eval node
      `(let ([thunk (fasl-read ',serialized)])
         (spawn-actor thunk)))))
```

**Implementation**:
- Consistent hashing for key distribution
- Fasl-based value serialization over TCP
- Replication with read-your-writes consistency
- Failure detection via heartbeat
- Mobile code: serialize lambdas, eval on remote

**Files**: `lib/std/persist/distributed.sls` (~600 LOC)
**Tests**: 30 tests

### 13.3 Image-Based Development (Like Smalltalk)

Save the entire program state to disk and resume later.

```scheme
(import (std persist image))

;; Develop interactively in the REPL
> (define counter 0)
> (define (inc!) (set! counter (+ counter 1)))
> (inc!) (inc!) (inc!)
> counter
3

;; Save the entire image
> (save-image "myapp.image")

;; Later, in a fresh process:
$ jerboa --image myapp.image
> counter
3  ;; State preserved!

;; Create deployable images
(define (main args)
  (start-server 8080))

(save-executable-image "server" main)
;; Produces a single-file executable with all code and data baked in
```

**Implementation**:
- Walk all reachable objects from roots (globals, threads, parameters)
- Fasl-serialize the entire heap to a single file
- On load: restore heap, reconnect ports, restart threads
- Executable image: embed boot file + heap dump in single binary

**Files**: `lib/std/persist/image.sls` (~500 LOC)
**Tests**: 20 tests

---

## Track 14: The Inspector — Runtime Introspection

### 14.1 Stack Frame Inspection and Modification

Chez's inspector can examine and modify live stack frames.

```scheme
(import (std debug inspector))

;; In an error handler, inspect the call stack
(with-exception-handler
  (lambda (exn)
    (let ([frames (current-stack-frames)])
      (for-each
        (lambda (frame i)
          (format #t "~a: ~a~%" i (frame-procedure-name frame))
          (for-each
            (lambda (var)
              (format #t "    ~a = ~s~%" (car var) (cdr var)))
            (frame-local-variables frame)))
        frames
        (iota (length frames)))))
  dangerous-computation)

;; Programmatic debugging: set values and continue
(define (debug-repl frame)
  (let loop ()
    (display "debug> ")
    (let ([cmd (read)])
      (case (car cmd)
        [(inspect) (pp (frame-local-ref frame (cadr cmd)))]
        [(set!) (frame-local-set! frame (cadr cmd) (caddr cmd))]
        [(continue) (frame-continue frame)]
        [(up) (debug-repl (frame-parent frame))]
        [(down) (debug-repl (frame-child frame))]
        [else (loop)]))))
```

**Implementation**:
- Use Chez's `inspect` API to access stack frames
- `continuation->frames` decomposes a continuation into frame objects
- Frame introspection: procedure, locals, source location
- Frame modification: write back changed values before resuming
- Integration with condition system for automatic debugging on error

**Files**: `lib/std/debug/inspector.sls` (~500 LOC)
**Tests**: 25 tests

### 14.2 Closure Inspection and Mutation

Examine and modify the captured environment of closures.

```scheme
(import (std debug closure-inspect))

(define (make-counter start)
  (let ([n start])
    (lambda () (set! n (+ n 1)) n)))

(define counter (make-counter 10))

;; Inspect the closure's free variables
(closure-free-variables counter)
;; => ((n . 10))

;; Modify a captured variable
(closure-set-free-variable! counter 'n 100)
(counter) ;; => 101

;; Clone a closure with modified environment
(define counter2 (closure-with counter '((n . 500))))
(counter2) ;; => 501
(counter)  ;; => 102 (original unchanged)

;; Use for: debugging, hot-patching, dependency injection
```

**Implementation**:
- `closure-code` and `closure-env` extract components
- `closure-free-variables` walks the environment, associates names via debug info
- `closure-set-free-variable!` mutates the environment vector
- `closure-with` creates new closure with same code, different env

**Files**: `lib/std/debug/closure-inspect.sls` (~300 LOC)
**Tests**: 20 tests

### 14.3 Record/Struct Introspection

Full reflection on record types at runtime.

```scheme
(import (std debug record-inspect))

(defstruct point (x y z))

(define p (make-point 1 2 3))

;; Introspect the record type
(record-type-name (record-rtd p))  ;; => point
(record-type-field-names (record-rtd p))  ;; => (x y z)
(record-type-parent (record-rtd p))  ;; => #f

;; Generic field access by name
(record-ref p 'x)  ;; => 1
(record-set! p 'y 20)

;; Iterate over all fields
(record->alist p)  ;; => ((x . 1) (y . 20) (z . 3))

;; Create records dynamically
(define rtd (make-record-type-descriptor 'dynamic-point #f #f #f #f
              '#((mutable x) (mutable y))))
(define maker (record-constructor (make-record-constructor-descriptor rtd #f #f)))
(define dyn-point (maker 10 20))
```

**Implementation**:
- Expose Chez's `record-rtd`, `record-type-name`, `record-type-field-names`
- Build field-name → index mapping for named access
- `record->alist` / `alist->record` for serialization-friendly formats
- Dynamic record creation via `make-record-type-descriptor`

**Files**: `lib/std/debug/record-inspect.sls` (~350 LOC)
**Tests**: 25 tests

---

## Track 15: Zero-Cost Abstractions via cp0

### 15.1 Compile-Time Regex

Regex patterns compiled to native code, not interpreted at runtime.

```scheme
(import (std text regex-compile))

;; This regex is compiled to a state machine at compile time
(define-regex email-pattern
  #rx"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}")

;; At runtime, email-pattern is a native procedure — no regex engine involved
(email-pattern "test@example.com")  ;; => #t
(email-pattern "invalid")           ;; => #f

;; Extract matches
(define-regex url-pattern
  #rx"(https?)://([^/]+)(/.*)?")

(url-pattern-match "https://example.com/path")
;; => #("https://example.com/path" "https" "example.com" "/path")

;; Compile-time regex operations
(define-regex combined
  (regex-or email-pattern url-pattern))  ;; Combined at compile time
```

**Implementation**:
- Parse regex at macro-expansion time
- Generate DFA state machine as Scheme code
- cp0 optimizes the generated state machine (dead states, redundant checks)
- Result: regex matching as fast as hand-written character loops
- No runtime regex library linked in

**Files**: `lib/std/text/regex-compile.sls` (~700 LOC)
**Tests**: 35 tests

### 15.2 Compile-Time JSON Schema Validation

Generate validators from JSON schemas at compile time.

```scheme
(import (std text json-schema))

(define-json-schema user-schema
  '{"type": "object"
    "properties": {
      "name": {"type": "string" "minLength": 1}
      "age": {"type": "integer" "minimum": 0}
      "email": {"type": "string" "format": "email"}}
    "required": ["name" "email"]})

;; At compile time, this generates:
;; (define (validate-user obj)
;;   (and (hashtable? obj)
;;        (let ([name (hashtable-ref obj "name" #f)])
;;          (and name (string? name) (>= (string-length name) 1)))
;;        (let ([age (hashtable-ref obj "age" #f)])
;;          (or (not age) (and (fixnum? age) (>= age 0))))
;;        (let ([email (hashtable-ref obj "email" #f)])
;;          (and email (string? email) (email-format? email)))))

;; Zero runtime overhead — just field checks
(validate-user (json-parse input))
```

**Implementation**:
- Parse JSON schema at macro-expansion time
- Generate Scheme validation code from schema structure
- Inline format validators (email, uri, date-time)
- Error messages include JSON path to invalid field

**Files**: `lib/std/text/json-schema.sls` (~500 LOC)
**Tests**: 30 tests

### 15.3 Compile-Time Query Planning

SQL queries analyzed and optimized at compile time.

```scheme
(import (std db query-compile))

;; Query is analyzed at compile time
(define-query get-user-orders
  (select (u.name o.total o.date)
    (from (users u) (orders o))
    (where (and (= u.id o.user_id)
                (= u.id ?user-id)
                (> o.total ?min-total)))
    (order-by o.date desc)
    (limit 10)))

;; At compile time:
;; - Validates column names against schema (if available)
;; - Generates optimal join order
;; - Creates prepared statement with parameter slots
;; - Generates result row destructuring code

;; At runtime: just parameter binding and execution
(get-user-orders db #:user-id 42 #:min-total 100.0)
;; => ((name: "Alice" total: 250.0 date: ...) ...)
```

**Implementation**:
- Query AST built at macro-expansion time
- Schema information loaded from `.jerboa/db-schema.json`
- Join ordering heuristics (small tables first)
- Prepared statement caching
- Row destructuring code generated per-query

**Files**: `lib/std/db/query-compile.sls` (~600 LOC)
**Tests**: 25 tests

---

## Track 16: Advanced Effect Handlers

### 16.1 Effect Fusion and Optimization

Combine multiple effect handlers into a single optimized handler.

```scheme
(import (std effect fusion))

;; Separate handlers
(defeffect Log (log message))
(defeffect State (get) (put value))
(defeffect Async (await promise))

;; Naively, three handlers = three layers of continuation capture
;; Effect fusion combines them:

(with-fused-handlers
  ([Log (log (k msg) (displayln msg) (resume k (void)))]
   [State (get (k) (resume k state))
          (put (k v) (set! state v) (resume k (void)))]
   [Async (await (k p) (promise-then p (lambda (v) (resume k v))))])
  (begin
    (perform (Log log "Starting"))
    (let ([x (perform (State get))])
      (perform (State put (+ x 1)))
      (perform (Async await (fetch-data))))))

;; Fused handler: single continuation capture covers all effects
;; ~3x faster than nested handlers
```

**Implementation**:
- Analyze effect handler composition at compile time
- Generate unified dispatch table for all effects
- Single continuation capture point for the fused handler
- Escape analysis: effects that don't escape can be inlined completely

**Files**: `lib/std/effect/fusion.sls` (~450 LOC)
**Tests**: 25 tests

### 16.2 Scoped Effects with Regions

Effects that are statically scoped, ensuring resources are properly released.

```scheme
(import (std effect scoped))

(defeffect-scoped File
  (open path mode)
  (read handle n)
  (write handle data)
  (close handle))

;; The 'close' effect is automatically called at scope exit
(with-scoped-effect File
  ([open (path mode) (let ([h (posix-open path mode)])
                       (values h (lambda () (posix-close h))))]
   [read (h n) (posix-read h n)]
   [write (h data) (posix-write h data)])
  (let ([h (perform (File open "/tmp/test" 'write))])
    (perform (File write h "Hello"))
    ;; At scope exit, close is called automatically
    ;; Even if an exception is raised!
    ))
```

**Implementation**:
- Track opened resources in a scope-local list
- `dynamic-wind` ensures cleanup on any exit (normal, exception, continuation)
- Linear type checking (optional): resources used exactly once
- Integration with capability system for resource access control

**Files**: `lib/std/effect/scoped.sls` (~400 LOC)
**Tests**: 25 tests

### 16.3 Algebraic Effect Inference

Automatically infer which effects a function may perform.

```scheme
(import (std effect infer))

;; No annotations needed — effects inferred from usage
(define (process-with-logging data)
  (perform (Log log "Processing"))
  (let ([result (transform data)])
    (perform (Log log "Done"))
    result))

;; Compiler infers: process-with-logging : (-> any (Eff (Log) any))

;; Effect polymorphism
(define (map-eff f xs)
  (if (null? xs)
      '()
      (cons (f (car xs)) (map-eff f (cdr xs)))))

;; Inferred: map-eff : (forall (e) (-> (-> a (Eff e b)) (list a) (Eff e (list b))))

;; Effect inference errors
(define (bad-function)
  (perform (State get)))  ;; Unhandled effect!

;; WARNING: unhandled effect (State) in bad-function at line 10
```

**Implementation**:
- Effect type variables for polymorphism
- Unification-based inference algorithm
- Warning (not error) for unhandled effects — gradual adoption
- Effect annotations optional: `(define/e (f x) : (Eff (Log State) number) ...)`

**Files**: `lib/std/effect/infer.sls` (~600 LOC)
**Tests**: 30 tests

---

## Track 17: Advanced Concurrency Patterns

### 17.1 Software Transactional Memory with Nested Transactions

Full STM with support for nested transactions and retry.

```scheme
(import (std concur stm))

(define balance-a (make-tvar 1000))
(define balance-b (make-tvar 500))

;; Atomic transfer
(define (transfer! from to amount)
  (atomically
    (let ([from-bal (tvar-get from)]
          [to-bal (tvar-get to)])
      (when (< from-bal amount)
        (retry))  ;; Block until condition might change
      (tvar-set! from (- from-bal amount))
      (tvar-set! to (+ to-bal amount)))))

;; Nested transactions
(define (batch-transfers! transfers)
  (atomically
    (for-each
      (lambda (t)
        (atomically  ;; Nested — commits with outer
          (transfer! (car t) (cadr t) (caddr t))))
      transfers)))

;; Or-else: try first transaction, if it retries, try second
(atomically
  (or-else
    (transfer! account-a account-b 100)
    (transfer! account-c account-b 100)))
```

**Implementation**:
- TVars: versioned mutable cells with read/write sets
- Optimistic concurrency: read without locking, validate at commit
- Conflict detection: version mismatch triggers rollback and retry
- `retry`: block until any read TVar changes
- `or-else`: composable transaction alternatives
- Nested transactions: inner commits are provisional until outer commits

**Files**: `lib/std/concur/stm.sls` (~600 LOC)
**Tests**: 35 tests

### 17.2 Lock-Free Data Structures

Concurrent data structures using compare-and-swap.

```scheme
(import (std concur lockfree))

;; Lock-free queue (Michael-Scott)
(define q (make-lockfree-queue))
(lockfree-enqueue! q 'item)
(lockfree-dequeue! q)  ;; => 'item

;; Lock-free stack (Treiber)
(define s (make-lockfree-stack))
(lockfree-push! s 'a)
(lockfree-push! s 'b)
(lockfree-pop! s)  ;; => 'b

;; Lock-free hash table (split-ordered list)
(define h (make-lockfree-hashtable))
(lockfree-put! h 'key 'value)
(lockfree-get h 'key)  ;; => 'value

;; Hazard pointers for safe memory reclamation
(with-hazard-pointer hp
  (let ([node (lockfree-dequeue! q)])
    (hp-protect! hp node)
    (process node)))
;; Node won't be reclaimed while protected
```

**Implementation**:
- FFI to `__atomic_compare_exchange` for CAS operations
- Michael-Scott queue: two-pointer with CAS
- Treiber stack: single-pointer with CAS
- Split-ordered list hashtable: O(1) amortized operations
- Hazard pointers: safe deferred reclamation
- ABA problem prevention via tagged pointers or hazard pointers

**Files**: `lib/std/concur/lockfree.sls` (~800 LOC), `support/atomic.c` (~100 LOC)
**Tests**: 40 tests

### 17.3 Async/Await with Structured Concurrency

Async/await syntax backed by structured concurrency guarantees.

```scheme
(import (std concur async-await))

;; Async function returns a promise
(define-async (fetch-user id)
  (let ([response (await (http-get (format "/users/~a" id)))])
    (json-parse (response-body response))))

;; Awaiting in async context
(define-async (get-user-with-orders id)
  (let ([user (await (fetch-user id))]
        [orders (await (fetch-orders id))])
    (user-with-orders user orders)))

;; Parallel await
(define-async (get-dashboard user-id)
  (let-values ([(user orders notifications)
                (await-all (fetch-user user-id)
                           (fetch-orders user-id)
                           (fetch-notifications user-id))])
    (make-dashboard user orders notifications)))

;; Cancellation propagates
(define cts (make-cancellation-token-source))
(define dashboard-promise (get-dashboard 42 #:cancellation (cts-token cts)))
(cts-cancel! cts)  ;; Cancels fetch-user, fetch-orders, fetch-notifications
```

**Implementation**:
- `define-async` transforms to CPS with promise return
- `await` captures continuation, resumes when promise resolves
- `await-all`: spawn parallel tasks, collect results
- Cancellation tokens: cooperative cancellation via check points
- Structured concurrency: child tasks cancelled when parent completes

**Files**: `lib/std/concur/async-await.sls` (~500 LOC)
**Tests**: 30 tests

---

## Track 18: Systems Integration

### 18.1 eBPF Program Generation

Write eBPF programs in Scheme, compile to eBPF bytecode.

```scheme
(import (std os ebpf))

;; Define an eBPF program that traces system calls
(define-ebpf syscall-tracer
  (tracepoint sys_enter_open
    (let ([filename (bpf-probe-read-str (pt-regs-arg1 ctx) 256)])
      (bpf-trace-printk "open: %s" filename))))

;; Load and attach
(define prog (ebpf-load syscall-tracer))
(ebpf-attach prog 'tracepoint "syscalls" "sys_enter_open")

;; Read trace output
(with-input-from-file "/sys/kernel/debug/tracing/trace_pipe"
  (lambda ()
    (let loop ()
      (displayln (read-line))
      (loop))))
```

**Implementation**:
- eBPF bytecode generation from Scheme AST
- Restricted subset of Scheme (no recursion, limited loops)
- BPF helpers: `bpf-map-lookup`, `bpf-probe-read`, `bpf-trace-printk`
- Map types: hash, array, perf event, ring buffer
- Verifier integration: check program before loading

**Files**: `lib/std/os/ebpf.sls` (~800 LOC), `lib/std/os/ebpf-codegen.sls` (~600 LOC)
**Tests**: 25 tests

### 18.2 Seccomp Sandboxing

Generate seccomp-bpf filters from high-level policy.

```scheme
(import (std os seccomp))

;; Define a security policy
(define-seccomp-policy web-server-policy
  (allow read write close fstat mmap munmap)
  (allow-if (= (syscall) SYS_open)
            (or (path-prefix "/var/www/")
                (path-prefix "/etc/ssl/")))
  (allow socket bind listen accept
         #:when (= (sock-domain) AF_INET))
  (deny-all #:action 'kill))

;; Apply to current process
(seccomp-apply! web-server-policy)

;; Now any disallowed syscall kills the process
```

**Implementation**:
- Parse policy to BPF filter program
- Syscall argument inspection via BPF
- Path prefix checking for file operations
- Socket family/type restrictions
- Action modes: kill, trap, errno, log

**Files**: `lib/std/os/seccomp.sls` (~500 LOC)
**Tests**: 20 tests

### 18.3 Namespaces and Containers

Create isolated execution environments.

```scheme
(import (std os namespace))

;; Create a new namespace
(define ns (make-namespace
  #:unshare '(mount pid net user)
  #:uid-map '((0 1000 1))    ;; Map root to uid 1000
  #:gid-map '((0 1000 1))))

;; Run code in the namespace
(in-namespace ns
  (lambda ()
    ;; We're now in an isolated environment
    ;; PID 1, separate mount tree, separate network
    (mount "none" "/" "none" '(MS_REC MS_PRIVATE))
    (mount "/path/to/rootfs" "/newroot" "none" '(MS_BIND))
    (pivot-root "/newroot" "/newroot/old")
    (exec "/bin/sh")))

;; Container-like isolation
(define (run-container image cmd)
  (let ([ns (make-namespace #:unshare '(mount pid net user ipc uts))])
    (in-namespace ns
      (lambda ()
        (setup-rootfs image)
        (setup-cgroups)
        (drop-capabilities)
        (exec cmd)))))
```

**Implementation**:
- FFI to `clone`, `unshare`, `setns`
- UID/GID mapping via `/proc/self/uid_map`
- Mount namespace manipulation
- `pivot_root` for filesystem isolation
- Cgroup integration for resource limits

**Files**: `lib/std/os/namespace.sls` (~600 LOC)
**Tests**: 20 tests

---

## Track 19: Developer Tools

### 19.1 Structural Code Editor Support

Expose AST structure for paredit-like editing.

```scheme
(import (std dev structural))

;; Parse code to navigable AST
(define ast (parse-to-ast "(define (f x) (+ x 1))"))

;; Structural navigation
(ast-node-type ast)  ;; => 'define
(ast-children ast)   ;; => (#<ast (f x)> #<ast (+ x 1)>)
(ast-parent (car (ast-children ast)))  ;; => ast

;; Structural editing operations
(ast-wrap ast 'let '([y 2]))
;; => (let ([y 2]) (define (f x) (+ x 1)))

(ast-splice (cadr (ast-children ast)))
;; => (define (f x) x 1)  ;; unwrapped the +

;; Generate edit commands for editors
(structural-edit->lsp-edits
  (ast-wrap ast 'when '#t)
  "file.ss")
;; => LSP TextEdit objects
```

**Implementation**:
- Full Scheme reader with position tracking
- AST nodes with parent links for navigation
- Structural operations: wrap, splice, raise, slurp, barf
- LSP integration: generate TextEdit commands
- Preserve comments and formatting where possible

**Files**: `lib/std/dev/structural.sls` (~500 LOC)
**Tests**: 30 tests

### 19.2 Live Documentation Generator

Generate documentation from code with live examples.

```scheme
(import (std dev docgen))

;;; @doc
;;; Reverses a list.
;;; 
;;; @example
;;; (reverse '(1 2 3)) => (3 2 1)
;;; (reverse '()) => ()
;;; 
;;; @complexity O(n)
;;; @see append, list-reverse
(define (reverse lst)
  (fold-left (lambda (acc x) (cons x acc)) '() lst))

;; Generate documentation
(generate-docs "lib/" "docs/api/"
  #:format 'markdown
  #:run-examples #t      ;; Actually run examples and verify output
  #:include-source #t    ;; Include source code in docs
  #:cross-reference #t)  ;; Link @see references

;; Produces:
;; docs/api/
;;   index.md
;;   std/
;;     list.md    (with reverse documented, examples tested)
```

**Implementation**:
- Parse `@doc` comments with Markdown support
- Extract `@example` blocks and run them
- Verify example output matches specification
- Cross-reference generation from `@see` tags
- Multiple output formats: Markdown, HTML, man pages

**Files**: `lib/std/dev/docgen.sls` (~600 LOC)
**Tests**: 25 tests

### 19.3 Benchmark Framework with Statistical Analysis

Rigorous benchmarking with statistical significance testing.

```scheme
(import (std dev benchmark))

(define-benchmark-suite sorting-benchmarks
  
  (define-benchmark quicksort-random
    #:setup (lambda () (random-list 10000))
    #:run (lambda (lst) (quicksort lst))
    #:teardown (lambda (result) (assert (sorted? result))))
  
  (define-benchmark mergesort-random
    #:setup (lambda () (random-list 10000))
    #:run (lambda (lst) (mergesort lst)))
  
  #:warmup 100        ;; Warmup iterations
  #:iterations 1000   ;; Measured iterations
  #:gc-between #t)    ;; Force GC between iterations

;; Run and analyze
(define results (run-benchmark-suite sorting-benchmarks))

(benchmark-report results)
;; quicksort-random: 1.23ms ± 0.15ms (95% CI)
;; mergesort-random: 1.45ms ± 0.12ms (95% CI)
;; Difference: quicksort 15% faster (p < 0.001)

;; Compare against baseline
(benchmark-compare results "baseline.json")
;; quicksort-random: 5% regression (was 1.17ms)
;;                   SIGNIFICANT (p = 0.003)
```

**Implementation**:
- Warmup phase to stabilize JIT/caches
- Statistical analysis: mean, median, std dev, confidence intervals
- Significance testing: t-test for comparing benchmarks
- GC tracking: separate GC time from computation time
- Baseline comparison with regression detection
- JSON output for CI integration

**Files**: `lib/std/dev/benchmark.sls` (~500 LOC)
**Tests**: 25 tests

---

## Phase 5 Implementation Summary

### Phase 5a: Compiler as Library (Highest Impact)

| # | Item | Track | Est. LOC | Priority |
|---|------|-------|----------|----------|
| 1 | User-defined cp0 passes | 11.1 | 1,000 | Critical |
| 2 | Compile-time partial evaluation | 11.2 | 800 | High |
| 3 | Compile-time regex | 15.1 | 700 | High |
| 4 | Delimited continuations | 12.1 | 400 | High |
| 5 | PGO integration | 11.3 | 900 | Medium |
| **Subtotal** | | | **~3,800** | |

### Phase 5b: Persistence and Distribution

| # | Item | Track | Est. LOC | Priority |
|---|------|-------|----------|----------|
| 6 | Persistent closures | 13.1 | 400 | High |
| 7 | Distributed object protocol | 13.2 | 600 | High |
| 8 | Image-based development | 13.3 | 500 | Medium |
| 9 | Continuation marks | 12.3 | 300 | Medium |
| 10 | Coroutines | 12.2 | 350 | Medium |
| **Subtotal** | | | **~2,150** | |

### Phase 5c: Inspector and Debugging

| # | Item | Track | Est. LOC | Priority |
|---|------|-------|----------|----------|
| 11 | Stack frame inspection | 14.1 | 500 | High |
| 12 | Closure inspection | 14.2 | 300 | Medium |
| 13 | Record introspection | 14.3 | 350 | Medium |
| 14 | Structural editor support | 19.1 | 500 | Medium |
| 15 | Live documentation | 19.2 | 600 | Medium |
| **Subtotal** | | | **~2,250** | |

### Phase 5d: Advanced Effects and Concurrency

| # | Item | Track | Est. LOC | Priority |
|---|------|-------|----------|----------|
| 16 | Effect fusion | 16.1 | 450 | High |
| 17 | Scoped effects | 16.2 | 400 | High |
| 18 | Effect inference | 16.3 | 600 | Medium |
| 19 | STM with nesting | 17.1 | 600 | High |
| 20 | Lock-free structures | 17.2 | 900 | Medium |
| 21 | Async/await | 17.3 | 500 | High |
| **Subtotal** | | | **~3,450** | |

### Phase 5e: Systems and Zero-Cost

| # | Item | Track | Est. LOC | Priority |
|---|------|-------|----------|----------|
| 22 | JSON schema compile | 15.2 | 500 | Medium |
| 23 | Query compile | 15.3 | 600 | Medium |
| 24 | eBPF generation | 18.1 | 1,400 | Low |
| 25 | Seccomp policies | 18.2 | 500 | Low |
| 26 | Namespaces | 18.3 | 600 | Low |
| 27 | Benchmark framework | 19.3 | 500 | High |
| **Subtotal** | | | **~4,100** | |

---

## Phase 5 Total

| Phase | LOC | New Modules | New Tests |
|-------|-----|-------------|-----------|
| 5a: Compiler | 3,800 | ~8 | ~155 |
| 5b: Persistence | 2,150 | ~5 | ~105 |
| 5c: Inspector | 2,250 | ~5 | ~125 |
| 5d: Effects/Concurrency | 3,450 | ~6 | ~165 |
| 5e: Systems/Tools | 4,100 | ~7 | ~115 |
| **Total Phase 5** | **~15,750** | **~31** | **~665** |

Combined with Phase 4's ~73,000 lines across ~190 modules with ~2,550 tests, Phase 5 brings Jerboa to **~89,000 lines** across **~220 modules** with **~3,200 tests**.

---

## The World-Class Thesis

Phase 5 exploits what makes Chez Scheme unique in the programming language landscape:

1. **The compiler is a library** — Users can write optimization passes that run during compilation, something impossible in most languages
2. **First-class continuations are fast** — Enables control flow abstractions (effects, coroutines, backtracking) that would be slow or impossible elsewhere  
3. **Everything is serializable** — Closures, continuations, even entire program states can be saved and restored
4. **The inspector is exposed** — Full runtime introspection for debugging, profiling, and metaprogramming
5. **Compile-time computation is unlimited** — Any Scheme code can run at compile time, enabling zero-cost abstractions

No other language has all of these. Combined with Phase 4's type system, effect handlers, and systems programming features, Jerboa becomes not just the best Scheme — but a serious contender against Rust, Haskell, and OCaml for systems programming, against Erlang for distributed computing, and against Clojure for data processing.

**The unfair advantage**: Jerboa users can extend the compiler, serialize their programs, inspect running code, and compute at compile time — using the same language they write their applications in. No FFI to C, no separate metalanguage, no build system plugins. Just Scheme, all the way down.

---

## Design Philosophy

Jerboa's architectural advantage is that `defstruct` maps to native Chez records, methods dispatch via `eq-hashtable`, and macros compile to idiomatic Chez code that cp0 can fully optimize. Phase 4 leverages this foundation to build features no other Scheme has, drawing from the best ideas across programming languages:

- **From Rust**: ownership tracking, borrow checking (via linear types), fearless concurrency
- **From Haskell**: type classes with coherence, kind system, deriving via generics
- **From OCaml 5**: direct-style effects with deep handlers, multicore domains
- **From Erlang/BEAM**: hot code swapping, distribution, process isolation
- **From Go**: channels with select, fast compilation, single-binary deployment
- **From Clojure**: persistent data structures, transducers, spec/schema
- **From Zig**: comptime execution, no hidden allocations in systems code
- **From Unison**: content-addressed code, structural editing

The key insight: Chez Scheme's cp0 optimizer is so good that macro-generated code performs like hand-written C. Every feature compiles down through macros to native Chez — the macro system *is* the compiler, and it's user-extensible.

---

## Track 1: Multicore Runtime — Beyond Erlang, Beyond Go

Jerboa already has actors, channels, STM, and a work-stealing scheduler. Phase 4 makes this the most sophisticated concurrency runtime in any Scheme.

### 1.1 Engine-Based Preemptive Actor Scheduling

Chez Scheme has a built-in `make-engine` mechanism — preemptible computations with fuel-based scheduling. No other Scheme exposes this. Use it to build a true preemptive actor runtime where no actor can monopolize a worker thread.

```scheme
;; Spawn 1,000,000 actors — each gets fair CPU time slices
(define pool (make-actor-pool #:workers (cpu-count) #:fuel 10000))

(for-each
  (lambda (i)
    (spawn-actor pool
      (lambda (self)
        (actor-receive self
          [('ping sender) (actor-send sender 'pong)]
          [('compute n) (fib n)]))))  ;; even long-running fib gets preempted
  (iota 1000000))
```

**Implementation**:
- Wrap each actor's message handler in `make-engine` with a configurable fuel count
- When fuel exhausts, engine suspends → actor goes back on the run queue
- Worker threads pop actors from work-stealing deques, run engine for one quantum
- Actor state = engine continuation + mailbox ref (~200 bytes per actor)
- Use Chez's `set-timer` + `timer-interrupt-handler` as the fuel mechanism

**Why unique**: Go's goroutines aren't preemptible (they yield at function calls). Erlang's reduction counting is similar but tied to BEAM. Jerboa gets preemption via Chez engines on native threads — the best of both worlds.

**Files**: `lib/std/actor/engine.sls` (~400 LOC)
**Tests**: 20 tests (preemption fairness, fuel exhaustion, million-actor spawn)

### 1.2 Affinity-Based Scheduling and NUMA Awareness

For high-performance servers, schedule actors to the same core that owns their data.

```scheme
(define-actor-group db-actors
  #:affinity 'core-pinned
  #:workers 4)

(define-actor-group compute-actors
  #:affinity 'numa-local    ;; keep on same NUMA node
  #:workers (numa-node-count))

;; Actor-to-actor messages within same group avoid cross-core cache invalidation
(spawn-in-group db-actors (lambda (self) ...))
```

**Implementation**:
- FFI to `sched_setaffinity` / `pthread_setaffinity_np` for core pinning
- NUMA topology discovery via `/sys/devices/system/node/`
- Per-group work-stealing deques — stealing prefers same NUMA node
- Thread-local allocator hints for NUMA-aware memory placement

**Files**: `lib/std/actor/affinity.sls` (~300 LOC), `lib/std/os/numa.sls` (~200 LOC)
**Tests**: 15 tests

### 1.3 Continuations as Serializable Values

Chez's one-shot continuations (`call/1cc`) can be serialized to bytevectors via `fasl-write`. This enables actor migration, distributed checkpointing, and time-travel debugging.

```scheme
;; Checkpoint an actor's state
(define (checkpoint-actor actor)
  (let ([cont (actor-continuation actor)]
        [mailbox (actor-mailbox-snapshot actor)])
    (fasl-write (list cont mailbox) "actor-checkpoint.fasl")))

;; Restore on a different machine
(define (restore-actor path)
  (let ([state (fasl-read path)])
    (spawn-actor-from-checkpoint (car state) (cadr state))))
```

**Implementation**:
- Use `fasl-write` / `fasl-read` for continuation serialization
- Strip non-serializable closures (FFI pointers, ports) with a pre-serialization walk
- Integration with `(std actor transport)` for live actor migration

**Files**: `lib/std/actor/checkpoint.sls` (~250 LOC)
**Tests**: 15 tests

### 1.4 Structured Concurrency with Deadlock Detection

Extend `with-task-group` with automatic deadlock detection using a wait-for graph.

```scheme
(with-task-group (lambda (tg)
  (let ([ch1 (make-channel 0)]
        [ch2 (make-channel 0)])
    ;; Deadlock: task A waits on ch2, task B waits on ch1
    (task-group-spawn tg (lambda () (channel-get ch2) (channel-put ch1 'a)))
    (task-group-spawn tg (lambda () (channel-get ch1) (channel-put ch2 'b)))
    ;; Runtime detects the cycle and raises &deadlock with the wait-for graph
    )))
```

**Implementation**:
- Global wait-for graph (hash table: thread-id → waiting-on-resource)
- Updated at every blocking operation (channel-get, mutex-lock, condition-wait)
- Background detector thread runs DFS cycle detection periodically
- On cycle detection: raise `&deadlock` condition with the cycle path
- Opt-in via `(parameterize ([*detect-deadlocks* #t]) ...)`

**Files**: `lib/std/concur/deadlock.sls` (~300 LOC)
**Tests**: 15 tests

---

## Track 2: Type System — Toward Dependent Types

Phase 2 gave us gradual typing, GADTs, type classes, and linear types. Phase 4 pushes toward a type system competitive with Haskell, Scala 3, and Idris — but always optional.

### 2.1 Compile-Time Type Checking (Not Just Runtime Assertions)

Currently `define/t` emits runtime assertions. Phase 4 adds a static checker that runs at macro-expansion time, reporting errors before the program runs.

```scheme
(define/t (add [x : fixnum] [y : fixnum]) : fixnum
  (string-append x y))
;; COMPILE ERROR: string-append expects (string, string), got (fixnum, fixnum)
;; at lib/myapp.sls:5:3
```

**Implementation**:
- Type environment threaded through macro expansion via syntax properties
- Bidirectional type checking: annotations flow down, inferred types flow up
- Constraint-based local inference within function bodies
- Error messages with source location, expected vs actual, and suggestions
- `define/t` becomes dual-mode: static check at expand time + optional runtime assert

**Why this matters**: Typed Racket proved that a Scheme can have serious static typing. But TR's approach (separate #lang) fractures the ecosystem. Jerboa's approach (opt-in per-function via `define/t`) is gradual without fragmentation.

**Files**: `lib/std/typed/check.sls` (~800 LOC), `lib/std/typed/infer.sls` (~600 LOC), `lib/std/typed/env.sls` (~300 LOC)
**Tests**: 40 tests

### 2.2 Higher-Kinded Types and Functor/Monad/Applicative

Type classes that abstract over type constructors, not just types.

```scheme
(defprotocol (Functor f)
  (fmap [fn : (-> a b)] [fa : (f a)] : (f b)))

(defprotocol (Monad m) #:extends (Functor m)
  (return [a] : (m a))
  (bind [ma : (m a)] [f : (-> a (m b))] : (m b)))

;; Implement for Option type
(deftype (Option a) (Some [val : a]) (None))

(implement (Functor Option)
  (fmap [fn fa]
    (match fa
      [(Some v) (Some (fn v))]
      [(None) (None)])))

(implement (Monad Option)
  (return [a] (Some a))
  (bind [ma f]
    (match ma
      [(Some v) (f v)]
      [(None) (None)])))

;; do-notation via macro
(do/m Option
  [x <- (Some 3)]
  [y <- (Some 4)]
  (return (+ x y)))
;; => (Some 7)
```

**Implementation**:
- Extend `defprotocol` to accept type-constructor parameters `(f)`, `(m)`
- `#:extends` clause for protocol inheritance
- `do/m` macro desugars to nested `bind` calls
- Instance resolution at macro-expansion time when concrete type is known
- Fallback to vtable dispatch when type is abstract

**Files**: `lib/std/typed/hkt.sls` (~500 LOC), `lib/std/typed/monad.sls` (~400 LOC)
**Tests**: 30 tests

### 2.3 Refinement Types with SMT-Backed Verification

Go beyond runtime `assert-refined` — verify refinements statically using an embedded decision procedure.

```scheme
(define/t (safe-divide [n : number] [d : (Refine number (not zero?))]) : number
  (/ n d))

(safe-divide 10 0)
;; COMPILE ERROR: refinement violation
;;   d must satisfy (not zero?)
;;   but literal 0 is always zero
;;   at lib/math.sls:3:18

;; Flow-sensitive refinement
(define/t (safe-head [lst : (Refine list (not null?))]) : any
  (car lst))

(define/t (process [xs : list])
  (if (null? xs)
    'empty
    (safe-head xs)))  ;; OK — refinement satisfied by the (not null?) branch
```

**Implementation**:
- Lightweight constraint solver for linear arithmetic and boolean predicates
- Integration with occurrence typing — branch conditions refine types
- Only checks what it can prove; unresolvable refinements fall back to runtime checks
- Special rules for `null?`, `zero?`, `negative?`, `positive?`, comparison operators

**Files**: `lib/std/typed/refine.sls` (~500 LOC), `lib/std/typed/solver.sls` (~400 LOC)
**Tests**: 30 tests

### 2.4 Type-Safe Extensible Records (Row Polymorphism Done Right)

Go beyond structural row checks to full row-polymorphic record operations.

```scheme
;; Function works on any record with at least 'name' and 'age' fields
(define/t (greet [person : (Row name: string age: fixnum | r)]) : string
  (format "Hello ~a, age ~a" (name person) (age person)))

;; Works with any record that has those fields
(defstruct employee (name age department salary))
(defstruct student (name age university gpa))

(greet (make-employee "Alice" 30 "Engineering" 100000))  ;; OK
(greet (make-student "Bob" 20 "MIT" 3.9))                ;; OK

;; Record extension
(define/t (with-id [rec : (Row | r)] [id : fixnum]) : (Row id: fixnum | r)
  (record-extend rec 'id id))
```

**Implementation**:
- Row type variables (`| r`) represent "and possibly more fields"
- Unification of row types during type checking
- `record-extend` / `record-restrict` as primitive operations
- Compiles to Chez `define-record-type` with dynamic field tables for open rows

**Files**: `lib/std/typed/row.sls` (~500 LOC)
**Tests**: 25 tests

---

## Track 3: Effects System — Deep Handlers and Multishot

Phase 2's effects use one-shot continuations. Phase 4 adds deep handlers (that re-install themselves) and limited multishot support for backtracking.

### 3.1 Deep Effect Handlers

Currently handlers are shallow — after resuming, the handler is no longer installed. Deep handlers automatically re-install for the remainder of the computation.

```scheme
;; Shallow (current): must manually re-install
(with-handler ([State (get (k) (resume k cell))])
  (State get)    ;; handled
  (State get))   ;; NOT handled — handler consumed by first resume

;; Deep (new): handler persists
(with-deep-handler ([State (get (k) (resume k cell))])
  (State get)    ;; handled
  (State get)    ;; also handled — handler re-installed after resume
  (State get))   ;; still handled
```

**Implementation**:
- `with-deep-handler` wraps each `resume` call to re-install the handler frame before continuing
- Uses `dynamic-wind` to ensure handler is on the stack during the resumed computation
- Negligible overhead: one parameter mutation per resume

**Files**: `lib/std/effect/deep.sls` (~200 LOC)
**Tests**: 20 tests

### 3.2 Multishot Continuations via Delimited Prompts

For backtracking search, nondeterminism, and probabilistic programming, support continuations that can be invoked more than once.

```scheme
(defeffect Choose (choose options))

;; Backtracking search — explore all choices
(define (all-solutions thunk)
  (let ([results '()])
    (with-multishot-handler
      ([Choose
        (choose (k options)
          (for-each (lambda (opt)
                      (let ([r (resume k opt)])  ;; k invoked multiple times!
                        (set! results (cons r results))))
                    options))])
      (thunk))
    (reverse results)))

(all-solutions (lambda ()
  (let ([x (Choose choose '(1 2 3))]
        [y (Choose choose '(a b))])
    (list x y))))
;; => ((1 a) (1 b) (2 a) (2 b) (3 a) (3 b))
```

**Implementation**:
- Use Chez's full `call/cc` (not `call/1cc`) for multishot handlers
- Stack copying cost is real — document performance implications
- `with-multishot-handler` as explicit opt-in (don't slow down one-shot handlers)
- Useful for: SAT solvers, probabilistic programming, parser combinators, logic programming

**Files**: `lib/std/effect/multishot.sls` (~350 LOC)
**Tests**: 20 tests

### 3.3 Effect Polymorphism in the Type System

Connect the effect system to the type system so the compiler knows which effects a function may perform.

```scheme
(define/te (pure-add [x : fixnum] [y : fixnum]) : (Eff [] fixnum)
  (fx+ x y))

(define/te (stateful-add [x : fixnum]) : (Eff [State] fixnum)
  (let ([current (perform (State get))])
    (perform (State put (fx+ current x)))
    (perform (State get))))

;; Compiler ensures all effects are handled
(run-state 0 (lambda () (stateful-add 5)))  ;; OK — State handled

(stateful-add 5)
;; WARNING: unhandled effect [State] at lib/app.sls:10
```

**Implementation**:
- Extend `define/te` with effect set inference
- `with-handler` discharges named effects from the inferred set
- Effect polymorphism: `(define/te (map-eff [f : (-> a (Eff e b))] [xs : list]) : (Eff e list) ...)`
- Warning (not error) for unhandled effects — gradual adoption

**Files**: `lib/std/typed/effects.sls` (~400 LOC)
**Tests**: 25 tests

---

## Track 4: Metaprogramming — The Unfair Advantage

### 4.1 Multi-Stage Programming (Staging à la MetaOCaml)

Go beyond `define-ct` to proper staged computation with code quotation and splicing.

```scheme
;; Stage 0: generate optimized code at compile time
(define-staged (make-power n)
  (lambda/staged (x)
    (let loop ([i n])
      (if (= i 0)
        (quote-stage 1)
        (quote-stage (* x ~(loop (- i 1))))))))

;; At compile time: (make-power 5) generates:
;; (lambda (x) (* x (* x (* x (* x (* x 1))))))
;; Chez cp0 then folds the (* ... 1) away

(define power5 (make-power 5))
(power5 3)  ;; => 243, computed with 4 multiplications, no loop
```

**Implementation**:
- `quote-stage` / `~` (splice) for code quotation and antiquotation
- Type-safe: spliced expressions must have the right type
- Cross-stage persistence for values that survive from stage 0 to stage 1
- Integration with Chez's `eval` for compile-time evaluation

**Why unique**: MetaOCaml has this. BER MetaScheme has a prototype. Nobody has it integrated with a macro system AND algebraic effects.

**Files**: `lib/std/staging/multi.sls` (~500 LOC)
**Tests**: 25 tests

### 4.2 Syntax-Level Pattern Matching (Match on AST)

Pattern matching on syntax objects for writing macros more naturally.

```scheme
(define-syntax my-let
  (syntax-match ()
    [(_ ([var expr] ...) body ...)
     #'((lambda (var ...) body ...) expr ...)]
    [(_ loop ([var init] ...) body ...)
     #'(letrec ([loop (lambda (var ...) body ...)])
         (loop init ...))]))
```

**Implementation**:
- `syntax-match` — pattern matching on syntax objects with template output
- Integrates with `match2` patterns (guards, nested patterns, `or` patterns)
- Syntax patterns: `...` for repetition, `_` for wildcard, `#:keyword` for keywords
- Much more readable than nested `syntax-case` with `with-syntax`

**Files**: `lib/std/staging/syntax-match.sls` (~350 LOC)
**Tests**: 20 tests

### 4.3 Compile-Time Code Contracts

Verify properties of generated code at macro-expansion time.

```scheme
(define-syntax/contract (safe-vector-ref vec idx)
  #:pre (and (identifier? #'vec) (integer? (syntax->datum #'idx)))
  #:post (lambda (expanded) (not (contains-unsafe? expanded)))
  #'(let ([v vec] [i idx])
      (assert (< i (vector-length v)))
      (vector-ref v i)))
```

**Implementation**:
- `define-syntax/contract` wraps a transformer with pre/post checks
- Pre-conditions: validated on the input syntax
- Post-conditions: validated on the expanded output
- Violations are compile-time errors with source locations
- Useful for macro libraries that must guarantee safety properties

**Files**: `lib/std/staging/contract.sls` (~250 LOC)
**Tests**: 15 tests

---

## Track 5: Systems Programming — The Rust Alternative

### 5.1 Async I/O Runtime with io_uring Backend

Build a proper async runtime that uses Linux io_uring for zero-copy, zero-syscall I/O.

```scheme
(define runtime (make-io-runtime #:backend 'io-uring #:workers (cpu-count)))

(run-io runtime (lambda ()
  ;; All I/O is non-blocking, submitted to io_uring in batches
  (let ([listener (tcp-listen "0.0.0.0" 8080)])
    (let loop ()
      (let ([conn (await (tcp-accept listener))])
        (spawn-task (lambda ()
          (let ([request (await (read-http-request conn))])
            (let ([response (handle-request request)])
              (await (write-http-response conn response))
              (await (close conn))))))
        (loop))))))
```

**Implementation**:
- `(std os iouring)` already exists — extend with high-level async wrappers
- Submission queue batching: collect I/O requests, submit in one syscall
- Completion queue polling in a dedicated thread, dispatching to actor/task callbacks
- Fallback to epoll on older kernels (< 5.1)
- File I/O, socket I/O, timer, and fsync all via io_uring

**Files**: `lib/std/async/ioruntime.sls` (~600 LOC), `lib/std/async/iouring-ops.sls` (~400 LOC)
**Tests**: 25 tests

### 5.2 Arena Allocators for Zero-GC Hot Paths

For latency-sensitive code, allocate from a fixed arena that gets bulk-freed, avoiding GC pauses entirely.

```scheme
(define arena (make-arena (* 1024 1024)))  ;; 1 MB arena

(with-arena arena
  ;; All allocations in this scope use the arena
  (let ([buf (arena-alloc-bytevector 4096)])
    (read-into! fd buf)
    (process buf)))
;; Arena reset — all memory freed in O(1), no GC involvement

;; For request handlers:
(define (handle-request req)
  (with-arena (request-arena req)
    ;; Temporary allocations for parsing/serialization live in per-request arena
    ;; Arena freed when request completes
    (let ([body (parse-json (request-body req))])
      (json->bytevector (process body)))))
```

**Implementation**:
- `make-arena` allocates a contiguous block via `foreign-alloc`
- `arena-alloc-bytevector` returns bytevectors backed by arena memory
- `with-arena` resets the bump pointer on scope exit
- Guardian integration: arena itself is GC-managed, but contents are not
- Thread-local arena parameter for implicit arena selection

**Why this matters**: Java's ZGC and Go's GC still have tail latencies. Arena allocation gives deterministic latency for request-processing hot paths. Zig popularized this pattern; Jerboa brings it to a GC'd language.

**Files**: `lib/std/mem/arena.sls` (~350 LOC)
**Tests**: 20 tests

### 5.3 Structured Binary Data (Like Rust's `repr(C)`)

Define packed binary layouts that map directly to C structs, network packets, and file formats.

```scheme
(define-binary-struct ip-header
  #:endian 'big
  (version      uint4)
  (ihl          uint4)
  (dscp         uint6)
  (ecn          uint2)
  (total-length uint16)
  (id           uint16)
  (flags        uint3)
  (frag-offset  uint13)
  (ttl          uint8)
  (protocol     uint8)
  (checksum     uint16)
  (src-addr     uint32)
  (dst-addr     uint32))

;; Zero-copy parsing from a bytevector
(define header (bytevector->ip-header packet 0))
(ip-header-src-addr header)  ;; => #x0A000001

;; Zero-copy serialization
(define bv (ip-header->bytevector header))
```

**Implementation**:
- `define-binary-struct` generates `foreign-ref` / `foreign-set!` accessors at computed offsets
- Bit-field support via shift-and-mask operations
- Endianness specified per-struct or per-field
- Nested structs and fixed-size arrays
- Validation: field values checked against bit-width at write time

**Files**: `lib/std/binary.sls` (~500 LOC)
**Tests**: 25 tests

### 5.4 Safe Memory-Mapped Persistent Data Structures

Combine `(std os mmap)` with persistent data structures for databases and caches.

```scheme
;; Memory-mapped B+ tree
(define db (mmap-btree-open "data.db"
  #:key-type 'string
  #:value-type 'bytevector
  #:page-size 4096))

(mmap-btree-put! db "user:1" (string->utf8 "Alice"))
(mmap-btree-get db "user:1")  ;; => #vu8(65 108 105 99 101)

;; Crash-safe: uses write-ahead log + msync
(mmap-btree-transaction db
  (lambda (txn)
    (txn-put! txn "counter" (fixnum->bytevector (+ 1 (bytevector->fixnum (txn-get txn "counter")))))
    (txn-put! txn "updated" (fixnum->bytevector (current-time)))))
```

**Implementation**:
- B+ tree with 4K pages mapped via mmap
- Write-ahead log for crash recovery
- Copy-on-write pages for MVCC transactions
- `msync` for durability guarantees
- Compaction and defragmentation

**Files**: `lib/std/db/mmap-btree.sls` (~800 LOC)
**Tests**: 30 tests

---

## Track 6: Developer Experience — What Makes People Stay

### 6.1 Time-Travel Debugger with Replay

Record execution history and navigate backward through time.

```scheme
(with-time-travel
  (lambda ()
    (define x 1)       ;; frame 0
    (set! x (+ x 1))  ;; frame 1
    (set! x (* x 3))  ;; frame 2
    (error "bug!")))   ;; frame 3

;; After the error:
;; jerboa> ,rewind 1
;; frame 1: x = 2, at lib/app.sls:4
;; jerboa> ,rewind 0
;; frame 0: x = 1, at lib/app.sls:3
;; jerboa> ,inspect x
;; x = 1 : fixnum
```

**Implementation**:
- Instrumentation macro that records variable bindings in a circular buffer
- Each frame: source location + variable snapshot (name → value)
- Configurable buffer size (default 10,000 frames)
- Integration with REPL `,rewind` command
- Conditional recording: only record when a predicate is true (for production)

**Files**: `lib/std/dev/time-travel.sls` (~400 LOC)
**Tests**: 20 tests

### 6.2 Error Messages with Fix Suggestions

Go beyond "did you mean?" to actionable fix suggestions with auto-apply.

```scheme
;; Unbound identifier with fix
;; error: unbound identifier 'htable-ref'
;;   15 | (htable-ref config 'port)
;;      |  ^^^^^^^^^^
;;   fix: replace with 'hash-ref' (from (jerboa runtime))
;;   fix: replace with 'hashtable-ref' (from (chezscheme))

;; Wrong arity with signature
;; error: string-split called with 1 argument, expects 2
;;   8 | (string-split line)
;;     |  ^^^^^^^^^^^^
;;   signature: (string-split str delimiter) from (std misc string)
;;   fix: (string-split line " ")

;; Missing import with auto-add
;; error: unbound identifier 'json-object->string'
;;   3 | (json-object->string data)
;;     |  ^^^^^^^^^^^^^^^^^^^^
;;   fix: add (import (std text json))
;;   [press 'f' to apply fix]
```

**Implementation**:
- Wrap `compile-file` to capture all diagnostics
- Post-process error messages with Levenshtein matching against all visible bindings
- Arity database built from `library-exports` + procedure metadata
- Fix application: source file rewriting via `(std lint)` infrastructure
- REPL integration: `,fix` command applies the most recent suggestion

**Files**: `lib/std/dev/errors.sls` (~500 LOC), `lib/std/dev/suggest.sls` (~300 LOC)
**Tests**: 25 tests

### 6.3 Interactive Profiler with Flame Graphs

Beyond counters — generate flame graphs for visual performance analysis.

```scheme
(with-flame-profile "output.svg"
  (lambda ()
    (run-benchmark)))

;; Produces an interactive SVG flame graph
;; Each bar = function, width = CPU time, depth = call stack
;; Click to zoom into subtrees

;; Allocation profiling
(with-alloc-profile
  (lambda ()
    (process-data large-dataset))
  (lambda (report)
    ;; report: per-function allocation counts, sizes, GC pressure
    (display-allocation-report report)))
```

**Implementation**:
- Stack sampling via `timer-interrupt-handler` at 1000 Hz
- Call stack capture via Chez inspector API
- Folded stack format → SVG flame graph generation
- Allocation tracking via Chez's `statistics` + per-function instrumentation
- HTML output with interactive zoom, search, and annotation

**Files**: `lib/std/dev/flame.sls` (~500 LOC), `lib/std/dev/alloc-profile.sls` (~300 LOC)
**Tests**: 15 tests

### 6.4 Property-Based Testing with Integrated Shrinking

QuickCheck-style testing with smart shrinking and stateful model checking.

```scheme
(import (std test prop))

;; Basic property
(check-property "reverse is involutive"
  (forall ([xs (gen:list-of (gen:integer))])
    (equal? (reverse (reverse xs)) xs)))

;; Stateful model checking (like Erlang PropEr)
(define-model counter-model
  #:state 0
  #:commands
  [(increment () (lambda (state) (+ state 1)))
   (decrement () (lambda (state) (max 0 (- state 1))))
   (reset     () (lambda (state) 0))]
  #:invariant (lambda (state) (>= state 0)))

(check-model counter-model
  #:commands-per-test 50
  #:num-tests 1000)
;; Tests random command sequences against the model
;; On failure: shrinks to minimal failing command sequence
```

**Implementation**:
- Generators: `gen:integer`, `gen:string`, `gen:list-of`, `gen:one-of`, `gen:frequency`, `gen:such-that`
- Integrated shrinking: each generator knows how to make values smaller
- Stateful testing: generate command sequences, check invariants after each step
- On failure: shrink the command sequence to minimal reproducer
- Parallel property testing: run test cases across worker threads

**Files**: `lib/std/test/prop.sls` (~600 LOC), `lib/std/test/gen.sls` (~400 LOC), `lib/std/test/shrink.sls` (~300 LOC), `lib/std/test/model.sls` (~400 LOC)
**Tests**: 30 tests

---

## Track 7: Data Processing — The Clojure+ Playbook

### 7.1 Transducers with Parallel Execution

Composable data transformations that work on any sequential or parallel data source.

```scheme
(import (std xform))

;; Define a transducer pipeline
(define process-pipeline
  (compose-xf
    (xf:filter even?)
    (xf:map (lambda (x) (* x x)))
    (xf:take 10)
    (xf:partition-by (lambda (x) (> x 100)))))

;; Apply to different data sources — same pipeline
(transduce process-pipeline conj '() (range 1 1000))           ;; list
(transduce process-pipeline conj '() (file-lines "data.txt"))  ;; lazy file
(transduce process-pipeline + 0 (channel->seq ch))              ;; channel

;; Parallel execution — split data, apply independently, combine
(parallel-transduce process-pipeline + 0
  (range 1 10000000)
  #:workers (cpu-count))
```

**Implementation**:
- Transducer = `(reducing-fn -> reducing-fn)` — composable via function composition
- Standard transducers: `xf:map`, `xf:filter`, `xf:take`, `xf:drop`, `xf:partition-by`, `xf:dedupe`, `xf:interpose`, `xf:mapcat`
- Early termination via `reduced` wrapper (like Clojure)
- Parallel mode: partition input, apply transducer per partition, combine results
- Works with lists, vectors, channels, generators, files

**Files**: `lib/std/xform.sls` (~500 LOC)
**Tests**: 30 tests

### 7.2 Dataframes for Tabular Data

SQL-like operations on in-memory columnar data, optimized for analytics.

```scheme
(import (std dataframe))

(define df (make-dataframe
  '((name   "Alice" "Bob" "Carol" "Dave")
    (age    30      25    35      28)
    (salary 90000   60000 120000  75000)
    (dept   "eng"   "eng" "mgmt"  "sales"))))

;; SQL-like operations chain naturally
(-> df
  (df:filter (lambda (row) (> (row 'age) 26)))
  (df:group-by 'dept)
  (df:aggregate 'salary mean)
  (df:sort-by 'salary >)
  (df:to-csv "report.csv"))

;; Column-wise operations (vectorized)
(df:mutate! df 'bonus (lambda (row) (* 0.1 (row 'salary))))
(df:select df '(name salary bonus))
```

**Implementation**:
- Columnar storage: each column is a vector (fixnum, flonum, or string)
- Vectorized operations on columns (map over raw vectors, not row-by-row)
- Group-by with hash-based partitioning
- Join operations: inner, left, right, cross
- CSV/JSON serialization/deserialization
- Integration with `(std query)` for SQL-like syntax

**Files**: `lib/std/dataframe.sls` (~700 LOC)
**Tests**: 30 tests

### 7.3 Stream Processing with Windowing

Real-time event processing with tumbling, sliding, and session windows.

```scheme
(import (std stream window))

(define event-stream (channel->async-stream events-channel))

;; Tumbling window: count events per 5-second window
(async-for-each
  (lambda (window)
    (log-metric "events-per-5s" (length window)))
  (stream:tumbling-window event-stream (seconds 5)))

;; Sliding window: moving average of last 100 events
(async-for-each
  (lambda (window)
    (log-metric "avg-latency" (mean (map event-latency window))))
  (stream:sliding-window event-stream 100))

;; Session window: group events by user with 30s gap
(async-for-each
  (lambda (session)
    (process-user-session (session-key session) (session-events session)))
  (stream:session-window event-stream
    #:key event-user-id
    #:gap (seconds 30)))
```

**Implementation**:
- Window types: tumbling (fixed-size, non-overlapping), sliding (fixed-size, overlapping), session (gap-based)
- Watermark-based event-time processing (not just wall-clock)
- Late event handling: configurable allowed lateness
- State management: window state in STM tvars for thread-safe access
- Integration with `(std async)` and `(std stream async)`

**Files**: `lib/std/stream/window.sls` (~500 LOC)
**Tests**: 25 tests

---

## Track 8: Distribution and Interop

### 8.1 Actor Distribution with Location Transparency

Send messages to actors on remote nodes with the same syntax as local actors.

```scheme
;; Node A
(define registry (make-distributed-registry
  #:transport 'tcp
  #:bind "0.0.0.0:9000"
  #:cluster '("node-b:9000" "node-c:9000")))

(define counter (spawn-actor registry 'counter
  (lambda (self)
    (let ([n 0])
      (actor-receive self
        [('increment) (set! n (+ n 1))]
        [('get sender) (actor-send sender n)])))))

;; Node B — same send syntax, but message goes over the network
(define remote-counter (actor-ref registry "node-a:9000" 'counter))
(actor-send remote-counter 'increment)
(actor-ask remote-counter '(get ,self))  ;; => 1
```

**Implementation**:
- Extend `(std actor transport)` with actor discovery via distributed registry
- Serialization of messages via `fasl-write` (fast, handles all Scheme values)
- Connection pooling between nodes with heartbeat
- Failure detection via phi accrual failure detector
- Transparent retry with configurable at-least-once / at-most-once semantics

**Files**: `lib/std/actor/distributed.sls` (~500 LOC), `lib/std/actor/discovery.sls` (~300 LOC)
**Tests**: 20 tests

### 8.2 WASM System Interface (WASI) Support

Extend the WASM target to support WASI for running Jerboa programs outside the browser.

```scheme
;; Compile to WASM+WASI
;; $ jerboa build --target wasi myapp.ss -o myapp.wasm
;; $ wasmtime myapp.wasm

;; WASI capabilities
(import (jerboa wasm wasi))

(define (main args)
  (let ([contents (wasi:read-file (cadr args))])
    (wasi:write-stdout (process contents))
    0))  ;; exit code
```

**Implementation**:
- Extend `(jerboa wasm codegen)` with WASI import declarations
- System calls: fd_read, fd_write, args_get, environ_get, clock_time_get
- String encoding: UTF-8 memory layout for WASI string passing
- Linear memory management for the WASM heap

**Files**: `lib/jerboa/wasm/wasi.sls` (~400 LOC)
**Tests**: 20 tests

### 8.3 Language Server Protocol 2.0

Full LSP with semantic tokens, inlay hints, and code actions.

```scheme
;; Features:
;; - Semantic highlighting (distinguish macros, types, effects, variables)
;; - Inlay hints: show inferred types inline
;; - Code actions: auto-import, extract function, inline function
;; - Workspace diagnostics: type errors, unused imports, missing exports
;; - Go to definition across modules
;; - Find all references
;; - Rename symbol with preview
```

**Implementation**:
- Semantic token provider using `(std lint)` + type information
- Incremental document sync for responsive editing
- Workspace-wide symbol index built from `library-exports`
- Code action engine for automated refactorings
- Integration with type checker for diagnostic overlays

**Files**: `lib/std/lsp/server.sls` (~600 LOC), `lib/std/lsp/semantic.sls` (~300 LOC), `lib/std/lsp/actions.sls` (~400 LOC), `lib/std/lsp/diagnostics.sls` (~300 LOC)
**Tests**: 25 tests

### 8.4 Python Interop via Shared Memory

Call Python libraries (numpy, pandas, ML frameworks) from Jerboa without serialization overhead.

```scheme
(import (std interop python))

(define py (python-init))

;; Call numpy
(python-exec py "import numpy as np")
(define arr (python-eval py "np.array([1, 2, 3, 4, 5])"))

;; Zero-copy: share memory between Chez bytevector and numpy array
(define bv (python-array->bytevector arr))  ;; shared memory, no copy
(bytevector-ieee-double-ref bv 0 (endianness native))  ;; => 1.0

;; Call ML model
(python-exec py "import torch")
(define model (python-eval py "torch.load('model.pt')"))
(define input (python-eval py "torch.tensor([[1.0, 2.0, 3.0]])"))
(define output (python-call py model "forward" input))
```

**Implementation**:
- Embed CPython via `libpython3.so` FFI
- `Py_Initialize` / `PyRun_SimpleString` / `PyObject_CallObject` wrappers
- Shared memory for bytevectors ↔ numpy arrays (via Python buffer protocol)
- Reference counting bridge: Chez guardian releases PyObject references
- Thread safety: GIL acquisition around Python calls

**Files**: `lib/std/interop/python.sls` (~600 LOC)
**Tests**: 15 tests

---

## Track 9: Security and Sandboxing

### 9.1 Capability-Based Module System

Extend `(std capability)` to control what imported modules can do.

```scheme
;; Load a plugin with restricted capabilities
(define plugin-env (make-sandbox
  #:allow '(read-file "config/*")           ;; only config files
  #:allow '(network "api.example.com" 443)  ;; only one host
  #:deny  '(exec)                           ;; no subprocess execution
  #:deny  '(ffi)                            ;; no foreign functions
  #:memory-limit (* 50 1024 1024)           ;; 50 MB heap
  #:time-limit 30))                         ;; 30 seconds

(sandbox-eval plugin-env '(import (plugin main)))
(sandbox-call plugin-env 'plugin-entry-point config)
```

**Implementation**:
- Extend `(jerboa embed)` with fine-grained capability tokens
- Intercept `foreign-procedure`, `open-file-input-port`, `process` at the sandbox boundary
- Resource limits via Chez's engines (fuel = time limit) and heap tracking
- Capability attenuation: plugins can grant sub-capabilities to their own sub-plugins
- Audit log: record all capability exercises for security analysis

**Files**: `lib/std/capability/sandbox.sls` (~500 LOC), `lib/std/capability/audit.sls` (~200 LOC)
**Tests**: 25 tests

### 9.2 Taint Tracking for Input Validation

Track which values came from untrusted sources and prevent them from reaching sensitive sinks.

```scheme
(define user-input (taint (read-line) 'user-input))

;; Tainted values propagate through operations
(define query-part (string-append "SELECT * FROM users WHERE name = '" user-input "'"))
;; query-part is tainted with 'user-input

;; Sensitive sinks reject tainted values
(sql-execute db query-part)
;; ERROR: tainted value ('user-input) reached sql-execute
;; fix: use parameterized query: (sql-execute db "SELECT ... WHERE name = ?" user-input)

;; Sanitization removes taint
(define safe-input (untaint (sql-escape user-input) 'user-input))
(sql-execute db (string-append "..." safe-input))  ;; OK
```

**Implementation**:
- `taint` wraps a value in a record with a taint label set
- Taint propagates through string operations, list operations, hash operations
- `untaint` removes a specific label after sanitization
- Sensitive sinks (`sql-execute`, `eval`, `system`, `open-file`) check for taint
- Compile-time mode: macro-expansion-time taint analysis for known patterns

**Files**: `lib/std/security/taint.sls` (~400 LOC)
**Tests**: 25 tests

---

## Track 10: Build System and Toolchain

### 10.1 Incremental Compilation with File Watching

`jerboa watch` recompiles only changed modules and re-runs affected tests.

```scheme
;; $ jerboa watch lib/ tests/
;; Watching 138 modules, 92 test files...
;; [12:00:01] lib/std/json.sls changed
;; [12:00:01] Compiling (std text json)... OK (0.3s)
;; [12:00:01] Running tests/test-json.ss... 15/15 passed (0.5s)
;; [12:00:15] lib/std/actor/core.sls changed
;; [12:00:15] Compiling (std actor core)... OK
;; [12:00:15] Recompiling dependents: (std actor), (std actor supervisor)...
;; [12:00:16] Running tests/test-actor-core.ss... 20/20 passed
```

**Implementation**:
- Module dependency graph built from import analysis
- `inotify` (already have `(std os inotify)`) for file change detection
- Topological sort of changed modules + dependents for minimal recompilation
- Parallel compilation of independent modules
- Test selection: only run tests that import changed modules

**Files**: `lib/jerboa/watch.sls` (~400 LOC)
**Tests**: 15 tests

### 10.2 Cross-Compilation for ARM64 and RISC-V

Build binaries for different architectures from a single host.

```scheme
;; $ jerboa build --target aarch64-linux myapp.ss -o myapp-arm64
;; $ jerboa build --target riscv64-linux myapp.ss -o myapp-riscv64
```

**Implementation**:
- Extend `(jerboa cross)` with full cross-compilation pipeline
- Boot file generation for target architecture via `make-boot-file`
- Cross-gcc invocation for C shim compilation
- FFI library compilation for target (via pkg-config cross queries)
- Testing via QEMU user-mode emulation

**Files**: `lib/jerboa/cross/pipeline.sls` (~400 LOC)
**Tests**: 10 tests

### 10.3 Reproducible Builds with Content-Addressed Everything

Every build artifact is identified by the hash of its inputs. Same inputs → same outputs, always.

```scheme
;; Build produces a content-addressed artifact
;; $ jerboa build --reproducible myapp.ss
;; artifact: sha256:a1b2c3... (3.2 MB)
;; deps: sha256:d4e5f6... (std text json)
;;       sha256:789abc... (std actor core)
;;       ...

;; Verify a build
;; $ jerboa verify myapp sha256:a1b2c3...
;; OK: build is reproducible
```

**Implementation**:
- Strip timestamps, temp paths, and nondeterministic data from compiled output
- Hash chain: artifact hash = H(source + H(dep1) + H(dep2) + ... + chez-version + flags)
- Build manifest: JSON file listing all inputs and their hashes
- Verification: rebuild and compare hashes

**Files**: `lib/jerboa/build/reproducible.sls` (~350 LOC)
**Tests**: 15 tests

### 10.4 Static Binary Delivery with musl libc

Build fully static executables with zero runtime dependencies using musl libc. These binaries run on any Linux system regardless of glibc version — ideal for deployment to containers, embedded systems, and legacy servers.

```scheme
;; Build a fully static binary with musl
;; $ jerboa build --static --musl myapp.ss -o myapp-static
;; Linking with musl-gcc...
;; Built: myapp-static (4.2 MB, statically linked)

;; Verify it has no dynamic dependencies
;; $ ldd myapp-static
;; => not a dynamic executable

;; Programmatic API
(import (jerboa build))

(build-binary "src/server.sls" "dist/server"
  'static: #t
  'musl: #t)

;; Cross-compile static ARM64 binary
(build-binary "src/server.sls" "dist/server-arm64"
  'static: #t
  'musl: #t
  'target: target-linux-aarch64)
```

**Implementation**:
- Detect musl toolchain: `musl-gcc` (wrapper) or `x86_64-linux-musl-gcc` (cross)
- Compile Chez Scheme runtime with musl: requires rebuilding `libkernel.a` against musl headers
- Link flags: `-static -nostdlib` + musl's `crt1.o`, `crti.o`, `crtn.o`, `libc.a`
- Handle musl-specific differences:
  - No `dlopen` in static builds — all FFI must be linked at build time
  - Thread-local storage via `__thread` instead of `pthread_key_create`
  - Signal handling works identically (POSIX compliant)
- Alpine Linux compatibility: musl is the native libc, so binaries work unmodified
- Size optimization: musl binaries are typically 20-30% smaller than glibc static builds

**Toolchain Setup**:
```bash
# Debian/Ubuntu: install musl toolchain
apt install musl-tools

# Or build musl-cross-make for cross-compilation
git clone https://github.com/richfelker/musl-cross-make
cd musl-cross-make
make TARGET=aarch64-linux-musl install

# Set path for cross builds
export PATH=$HOME/musl-cross/bin:$PATH
```

**Limitations**:
- No runtime `dlopen` (dynamic library loading) — all native extensions must be statically linked
- Name resolution: musl's `getaddrinfo` doesn't read `/etc/nsswitch.conf` (uses `/etc/resolv.conf` directly)
- Locale: musl has minimal locale support (C/POSIX only by default)
- Thread stack size: musl defaults to 80KB (vs glibc's 8MB) — may need `pthread_attr_setstacksize`

**Files**: `lib/jerboa/build/musl.sls` (~300 LOC), `support/musl-chez-build.sh` (~150 LOC)
**Tests**: 12 tests

---

## Implementation Order

### Phase 4a: Core Runtime (Highest Impact)

| # | Item | Track | Est. LOC | Priority |
|---|------|-------|----------|----------|
| 1 | Engine-based actor scheduling | 1.1 | 400 | Critical |
| 2 | Deep effect handlers | 3.1 | 200 | High |
| 3 | Static type checking | 2.1 | 1,700 | Critical |
| 4 | Transducers | 7.1 | 500 | High |
| 5 | Async I/O runtime (io_uring) | 5.1 | 1,000 | High |
| 6 | Error messages with fixes | 6.2 | 800 | High |
| **Subtotal** | | | **~4,600** | |

### Phase 4b: Type System and Safety

| # | Item | Track | Est. LOC | Priority |
|---|------|-------|----------|----------|
| 7 | Higher-kinded types | 2.2 | 900 | High |
| 8 | Refinement types + solver | 2.3 | 900 | Medium |
| 9 | Row polymorphism v2 | 2.4 | 500 | Medium |
| 10 | Effect polymorphism | 3.3 | 400 | Medium |
| 11 | Taint tracking | 9.2 | 400 | Medium |
| 12 | Capability sandbox | 9.1 | 700 | High |
| **Subtotal** | | | **~3,800** | |

### Phase 4c: Systems and Performance

| # | Item | Track | Est. LOC | Priority |
|---|------|-------|----------|----------|
| 13 | Arena allocators | 5.2 | 350 | High |
| 14 | Binary struct definitions | 5.3 | 500 | High |
| 15 | Mmap B+ tree | 5.4 | 800 | Medium |
| 16 | Multishot continuations | 3.2 | 350 | Medium |
| 17 | NUMA-aware scheduling | 1.2 | 500 | Low |
| 18 | Deadlock detection | 1.4 | 300 | Medium |
| **Subtotal** | | | **~2,800** | |

### Phase 4d: Developer Experience

| #            | Item                    | Track | Est. LOC   | Priority |
|--------------|-------------------------|-------|------------|----------|
| 19           | Time-travel debugger    | 6.1   | 400        | Medium   |
| 20           | Flame graph profiler    | 6.3   | 800        | High     |
| 21           | Property-based testing  | 6.4   | 1,700      | High     |
| 22           | Multi-stage programming | 4.1   | 500        | Medium   |
| 23           | Syntax-level match      | 4.2   | 350        | Medium   |
| 24           | Compile-time contracts  | 4.3   | 250        | Low      |
| **Subtotal** |                         |       | **~4,000** |          |

### Phase 4e: Data and Distribution

| #            | Item                       | Track | Est. LOC   | Priority |
|--------------|----------------------------|-------|------------|----------|
| 25           | Dataframes                 | 7.2   | 700        | Medium   |
| 26           | Stream windowing           | 7.3   | 500        | Medium   |
| 27           | Distributed actors         | 8.1   | 800        | High     |
| 28           | WASI support               | 8.2   | 400        | Medium   |
| 29           | Continuation serialization | 1.3   | 250        | Low      |
| **Subtotal** |                            |       | **~2,650** |          |

### Phase 4f: Toolchain and Interop

| #            | Item                              | Track | Est. LOC   | Priority |
|--------------|-----------------------------------|-------|------------|----------|
| 30           | LSP 2.0                           | 8.3   | 1,600      | High     |
| 31           | Python interop                    | 8.4   | 600        | Medium   |
| 32           | File watching + incremental build | 10.1  | 400        | High     |
| 33           | Cross-compilation pipeline        | 10.2  | 400        | Medium   |
| 34           | Reproducible builds               | 10.3  | 350        | Medium   |
| 35           | Static musl builds                | 10.4  | 450        | High     |
| **Subtotal** |                                   |       | **~3,800** |          |

---

## Total Estimated Code

| Phase                    | LOC         | New Modules | New Tests  |
|--------------------------|-------------|-------------|------------|
| 4a: Core Runtime         | 4,600       | ~10         | ~200       |
| 4b: Type System          | 3,800       | ~8          | ~180       |
| 4c: Systems              | 2,800       | ~8          | ~150       |
| 4d: Developer Experience | 4,000       | ~10         | ~200       |
| 4e: Data & Distribution  | 2,650       | ~7          | ~150       |
| 4f: Toolchain & Interop  | 3,800       | ~9          | ~162       |
| **Total Phase 4**        | **~21,650** | **~52**     | **~1,042** |

Combined with existing ~52,000 lines across 138+ modules, Jerboa would be ~73,000 lines across ~190 modules with ~2,550 tests. Still dramatically more compact than Racket (~700K), Guile (~300K), or Gerbil+Gambit (~80K).

---

## Competitive Position After Phase 4

| Feature | Jerboa | Racket | Gerbil | OCaml 5 | Haskell | Rust | Go | Erlang | Zig |
|---------|--------|--------|--------|---------|---------|------|----|--------|-----|
| Algebraic effects (deep) | **Yes** | No | No | **Yes** | Libs | No | No | No | No |
| Multishot continuations | **Yes** | **Yes** | No | No | No | No | No | No | No |
| Static type checking | **Yes** | TR | No | **Yes** | **Yes** | **Yes** | **Yes** | Dialyzer | **Yes** |
| GADTs | **Yes** | No | No | **Yes** | **Yes** | No | No | No | No |
| Higher-kinded types | **Yes** | No | No | Functors | **Yes** | No | No | No | No |
| Type classes | **Yes** | No | No | Modules | **Yes** | Traits | No | No | No |
| Linear types | **Yes** | No | No | No | Linear | **Yes** | No | No | No |
| Refinement types | **Yes** | No | No | No | LH | No | No | No | No |
| Effect typing | **Yes** | No | No | **Yes** | **Yes** | No | No | No | No |
| STM | **Yes** | No | No | No | **Yes** | No | No | No | No |
| Persistent data | **Yes** | No | No | **Yes** | **Yes** | Libs | No | No | No |
| PGO | **Yes** | No | No | No | No | **Yes** | **Yes** | No | No |
| Compile-time regex | **Yes** | No | No | No | No | **Yes** | No | No | **Yes** |
| Engine-based scheduling | **Yes** | No | No | Domains | Green | No | Goroutine | Reduction | No |
| Preemptive actors | **Yes** | No | No | No | No | No | No | **Yes** | No |
| Distributed actors | **Yes** | No | Yes | No | Cloud H | No | No | **Yes** | No |
| Raft consensus | **Yes** | No | No | No | No | Libs | Libs | No | No |
| CRDTs | **Yes** | No | No | No | No | Libs | Libs | No | No |
| Arena allocators | **Yes** | No | No | No | No | No | No | No | **Yes** |
| Zero-copy FFI | **Yes** | No | Yes | **Yes** | No | **Yes** | CGo | NIF | **Yes** |
| io_uring | **Yes** | No | No | Libs | No | **Yes** | Libs | No | **Yes** |
| Binary struct defs | **Yes** | No | No | cstruct | No | `repr(C)` | No | No | packed |
| Mmap databases | **Yes** | No | No | No | No | Libs | Libs | No | No |
| Static binaries | **Yes** | Yes | Yes | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** |
| WASM+WASI | **Yes** | No | No | wasm_of | No | **Yes** | **Yes** | No | **Yes** |
| Macro system | **Yes** | **Yes** | **Yes** | ppx | TH | proc | No | No | comptime |
| Multi-stage programming | **Yes** | No | No | MetaOCaml | No | No | No | No | **Yes** |
| Derive/deriving | **Yes** | No | No | ppx | **Yes** | **Yes** | No | No | No |
| Property testing | **Yes** | No | No | QCheck | QC | proptest | gopter | PropEr | No |
| Stateful model testing | **Yes** | No | No | No | No | No | No | PropEr | No |
| Time-travel debugging | **Yes** | No | No | No | No | No | Delve | No | No |
| Flame graph profiling | **Yes** | No | No | perf | No | cargo-flame | pprof | No | No |
| Taint tracking | **Yes** | No | No | No | No | No | No | No | No |
| Capability sandbox | **Yes** | Sandbox | No | No | No | No | No | No | No |
| Python interop | **Yes** | No | No | No | No | PyO3 | No | No | No |
| Dataframes | **Yes** | No | No | No | No | polars | No | No | No |
| Stream windowing | **Yes** | No | No | No | conduit | No | No | No | No |
| Content-addressed builds | **Yes** | No | No | No | Nix | No | No | No | **Yes** |
| LSP with semantic tokens | **Yes** | **Yes** | No | **Yes** | HLS | r-a | gopls | No | ZLS |

**The unique combination**: No other language has ALL of: algebraic effects (deep + multishot) + GADTs + higher-kinded types + type classes + linear types + refinement types + effect typing + STM + persistent data + distributed actors + Raft + CRDTs + preemptive engine-based scheduling + arena allocators + io_uring + binary struct definitions + multi-stage programming + property-based testing with model checking + a full macro system. Jerboa would be the first.

---

## The Thesis

Phases 1-3 proved that Gerbil's ergonomics run on Chez's compiler without compromise, and that a macro-based approach produces a comprehensive standard library in ~52K lines.

Phase 4 proves that the right foundation — a great optimizing compiler, a powerful macro system, and native OS threads — can support every advanced feature found across the landscape of modern programming languages, without the complexity explosion that a VM-based approach (JVM, BEAM, CLR) requires.

The insight is architectural: **macros are the universal language extension mechanism**. Every feature in this plan — effects, types, actors, arenas, transducers, binary structs, staging — compiles through macros into idiomatic Chez Scheme that cp0 optimizes to native code. There is no runtime interpreter, no bytecode, no JIT warmup, no hidden overhead.

This is the unfair advantage: **the macro system is the compiler, and it's user-extensible**. Users can add new optimization passes, new type system features, new concurrency primitives — using the same mechanism the standard library uses. No other language architecture makes this possible.

Jerboa: the Scheme that took the best ideas from every language and made them compose.


---

# Phase 6: Making Real Programs Easier to Build

Phase 5 gave Jerboa sophisticated language features — effects, actors, arenas, binary structs, staging. Phase 6 asks a different question: **what makes real programs hard to build on Chez Scheme, and how do we fix it?**

The answer comes from jerboa-shell (jsh), a 45,000-line POSIX shell built entirely on Jerboa. Building jsh exposed every rough edge in the Chez Scheme ecosystem: a 570-line C FFI shim for basic POSIX operations, an 838-line compatibility layer for Gambit APIs, a 7-step sequential build taking 30-60 seconds, signal handling race conditions, UTF-8 mangling of raw bytes, Linux-only binary loading hacks, and a completely stubbed sandbox. These aren't theoretical problems — they're the actual barriers that make systems programming in Scheme painful.

Phase 6 eliminates these barriers. Every feature is grounded in a specific pain point from real code, with concrete before/after examples showing the improvement.

### Where We Stand

| Metric | Value |
|--------|-------|
| Modules | ~204 |
| Lines of code | ~37,500 |
| Test cases | ~3,196 |
| jerboa-shell modules | 33 |
| jerboa-shell LOC | ~45,000 |
| C FFI shim lines to eliminate | 570 |
| Gambit compat lines to eliminate | 838 |
| Build time target | 30-60s → 2-5s |

### Chez Primitives Exploited

| Primitive | Tracks Using It |
|-----------|----------------|
| `foreign-procedure` / `foreign-entry` | 20, 24, 25, 26, 29 |
| `fasl-write` / `fasl-read` | 22, 23 |
| `compile-whole-library` | 22 |
| `eval` / `interaction-environment` | 23 |
| `make-thread-parameter` | 24, 25, 27 |
| `mutex` / `condition` | 25, 27 |
| `inspect/object` | 28 |
| `continuation-condition` | 28 |
| `load-shared-object` | 29 |

---

## Track 20: Declarative POSIX FFI — Eliminate the C Shim

**Pain point**: jerboa-shell maintains a 570-line C file (`ffi-shim.c`) and a 261-line Chez wrapper (`ffi.sls`) just to call standard POSIX functions. Every new system call requires editing C code, recompiling the shim, and keeping the Scheme wrapper in sync.

**Solution**: A `define-posix` macro that generates direct `foreign-procedure` calls to libc, with automatic errno checking, flag constants, and struct accessors — no C compilation required.

### Before (current jerboa-shell)

```scheme
;; ffi-shim.c (C code that must be compiled separately)
static int ffi_waitpid_status;
int ffi_do_waitpid(int pid, int options) {
    int s;
    int result = waitpid(pid, &s, options);
    ffi_waitpid_status = s;
    return result;
}
int ffi_get_waitpid_status(void) { return ffi_waitpid_status; }

;; ffi.sls (Scheme wrapper)
(define-foreign c-ffi-do-waitpid "ffi_do_waitpid" (int int) -> int)
(define-foreign c-ffi-get-waitpid-status "ffi_get_waitpid_status" () -> int)
(define (ffi-waitpid-pid pid options) (c-ffi-do-waitpid pid options))
(define (ffi-waitpid-status) (c-ffi-get-waitpid-status))
```

### After (with Track 20)

```scheme
(import (std os posix))

(define-values (pid status) (posix-waitpid child-pid WNOHANG))
(when (WIFEXITED status)
  (printf "exited with ~a~n" (WEXITSTATUS status)))
```

### What Gets Built

**Module: `(std os posix)`** — Declarative POSIX bindings

The macro `define-posix` wraps `foreign-procedure` with:
- **Errno checking**: Automatically calls `foreign-entry "errno"` after each call, raises `&posix-error` condition on failure
- **Flag constants**: `WNOHANG`, `O_RDONLY`, `O_NONBLOCK`, etc. as Chez constants (no C header parsing)
- **Multi-return via out-pointers**: Uses Chez `foreign-alloc` + `foreign-ref` for functions that return values through pointer parameters (like `waitpid`'s status, `pipe`'s fd pair)
- **Struct accessors**: `define-posix-struct` for `termios`, `stat`, `winsize` using `foreign-ref`/`foreign-set!` with field offsets

**Covered syscall families** (replacing ffi-shim.c):
1. **Process**: `fork`, `execve`, `waitpid`, `_exit`, `getpid`, `getppid`, `setpgid`, `getpgid`, `tcsetpgrp`, `tcgetpgrp`, `setsid`
2. **File descriptors**: `open`, `close`, `read`, `write`, `dup`, `dup2`, `fcntl`, `pipe`, `lseek`, `mkfifo`, `unlink`
3. **Signals**: `sigaction`, `sigprocmask`, `kill`, `sigpending`
4. **Terminal**: `tcgetattr`, `tcsetattr`, `ioctl` (TIOCGWINSZ)
5. **User/permissions**: `umask`, `getuid`, `geteuid`, `getegid`, `access`, `isatty`
6. **Environment**: `setenv`, `unsetenv`
7. **Resources**: `getrlimit`, `setrlimit`
8. **Stat**: `stat`, `fstat`, `lstat`
9. **Time**: `strftime`, `localtime`

### Implementation Strategy

1. **Define `define-posix` macro** that expands to `foreign-procedure` + errno wrapper
2. **Define `define-posix-struct`** using `foreign-alloc`/`foreign-ref` for C struct access
3. **Enumerate POSIX constants** from POSIX spec (platform-specific values via `foreign-procedure` to query at load time, or compile-time C snippets using `(machine-type)`)
4. **Test against jerboa-shell** by replacing ffi-shim.c calls one family at a time

### Tests (~40)

- Each syscall wrapper: correct return values, errno propagation
- Multi-return functions (waitpid, pipe): correct value extraction
- Struct accessors (termios, stat): field read/write roundtrip
- Error conditions: ENOENT, EACCES, EINTR handling
- Platform flag values match system headers

### Estimated Effort

~800 lines of Scheme (macro + syscall definitions). Zero lines of C.

---

## Track 21: Portable OS Abstraction Layer

**Pain point**: jerboa-shell's `jsh-main.c` uses `memfd_create`, `/proc/self/exe`, and `/proc/self/fd` — all Linux-only. The build script hardcodes ELF assumptions. The shell can't run on macOS or BSDs without major rewrites.

**Solution**: An OS abstraction module that detects the platform at load time and provides portable APIs for process execution, filesystem introspection, and binary loading.

### Before (current jerboa-shell)

```c
// jsh-main.c — Linux-only program loading
int memfd = memfd_create("jsh-boot", MFD_CLOEXEC);
write(memfd, program_text, program_len);
char path[64];
snprintf(path, sizeof(path), "/proc/self/fd/%d", memfd);
Sscheme_script(path, argc, argv);
```

### After (with Track 21)

```scheme
(import (std os platform))

;; Works on Linux, macOS, FreeBSD
(platform-load-program program-text)
;; Uses memfd_create on Linux, shm_open on macOS, tmpfile on fallback

(define exe-path (platform-executable-path))
;; Uses /proc/self/exe on Linux, _NSGetExecutablePath on macOS,
;; sysctl KERN_PROC_PATHNAME on FreeBSD
```

### What Gets Built

**Module: `(std os platform)`**

- **`(machine-type)` dispatch**: Uses Chez's built-in `(machine-type)` to select platform-specific implementations at expansion time
- **Portable executable path**: `/proc/self/exe` (Linux), `_NSGetExecutablePath` (macOS), `sysctl` (FreeBSD)
- **Portable memory-backed execution**: `memfd_create` (Linux), `shm_open` + `shm_unlink` (macOS/BSD), `tmpfile` fallback
- **Portable terminal detection**: abstracts differences in `ioctl` constants across platforms
- **Build system integration**: `(std os platform build)` sub-module for cross-platform compilation flags

### Implementation Strategy

1. **Use `(machine-type)` for compile-time dispatch** — Chez already knows the target platform
2. **Runtime fallback chain** for operations that need runtime detection (e.g., container environments where `/proc` may not exist)
3. **Conditional `foreign-procedure`** using Track 20's `define-posix` with platform guards
4. **Test on CI** with Linux (primary) and macOS (secondary) targets

### Tests (~25)

- Executable path resolution on each platform
- Memory-backed file creation and execution
- Terminal size detection portability
- Platform detection accuracy
- Graceful fallback when preferred API unavailable

### Estimated Effort

~500 lines. Mostly platform-specific `foreign-procedure` wrappers with a dispatch layer.

---

## Track 22: Incremental Parallel Build System

**Pain point**: jerboa-shell's build takes 30-60 seconds because it compiles 50+ modules sequentially, with manual dependency ordering in a 216-line build script. Adding a module requires figuring out where it fits in the dependency chain. Rebuilding after a one-line change recompiles everything.

**Solution**: A build system that automatically discovers module dependencies, compiles independent modules in parallel using native threads, and skips unchanged modules using file modification timestamps and content hashes.

### Before (current jerboa-shell)

```scheme
;; build-binary-jsh.ss — 216 lines of manual ordering
(define compile-order
  '("std/error" "std/sugar" "std/misc/string" "std/misc/list"
    "std/misc/alist" "std/format" "std/sort" "std/pregexp"
    "std/hash" "std/os/path" "std/os/signal" "std/text/json"
    "runtime/mop" "runtime/util" "compat/gambit"
    "jsh/util" "jsh/ffi" "jsh/variables" "jsh/signals"
    ;; ... 30+ more modules in precise order ...
    "jsh/main"))
(for-each compile-one! compile-order)  ;; sequential!
```

### After (with Track 22)

```scheme
(import (std build))

;; Discovers deps, parallelizes, caches — one call
(build-project "src/"
  #:parallel #t
  #:incremental #t
  #:output "jsh")
```

### What Gets Built

**Module: `(std build)`**

1. **Dependency discovery**: Parse `(import ...)` forms to build a DAG. Topological sort determines compilation order.
2. **Parallel compilation**: Independent modules (no dependency relationship) compile on separate Chez threads using `fork-thread`. Thread count defaults to `(cpu-count)` or `(std os platform)` CPU detection.
3. **Incremental caching**: Store content hashes (SHA-256 via `(std crypto digest)` from Phase 3) alongside `.so` outputs. Skip recompilation when source hash matches cache.
4. **Change propagation**: When module A changes, recompile A and all modules that transitively depend on A — but not unrelated modules.
5. **`compile-whole-library` integration**: Use Chez's `compile-whole-library` for release builds that inline across module boundaries.

### Implementation Strategy

1. **Parse imports** using `read` on source files to extract `(library ... (import ...) ...)` forms
2. **Build DAG** using adjacency lists, topological sort from `(std algo sort)` or custom implementation
3. **Thread pool** using `fork-thread` + `mutex` + `condition` for work-stealing
4. **Hash cache** stored as a fasl file (`.build-cache.fasl`) using `fasl-write`/`fasl-read`
5. **Compile worker** calls `compile-library` or `compile-whole-library` per module

### Tests (~30)

- Dependency graph construction from import forms
- Topological sort correctness (including cycle detection)
- Parallel compilation produces same results as sequential
- Incremental: unchanged modules not recompiled
- Change propagation: downstream modules recompiled
- Cache invalidation on source edit
- `compile-whole-library` integration

### Estimated Effort

~600 lines. DAG + thread pool + cache + compile dispatch.

---

## Track 23: Safe Program Loading Without Threading Hacks

**Pain point**: Chez Scheme boot files can't create threads (the thread system isn't initialized yet). jerboa-shell works around this with a C `main()` that uses `memfd_create` to load the program after boot completes — a Linux-only, fragile hack. The `JSH_ARGC`/`JSH_ARG0` environment variables exist because Chez steals the `-c` flag.

**Solution**: A proper program loading protocol that separates boot-time initialization from runtime startup, with clean argument passing.

### Before (current jerboa-shell)

```c
// jsh-main.c — 92 lines of C workaround
int main(int argc, char *argv[]) {
    Sscheme_init(NULL);
    Sregister_boot_file(boot_file);
    Sbuild_heap(NULL, NULL);
    // Can't just call Scheme here — threads won't work!
    // Must use memfd_create trick:
    int memfd = memfd_create("jsh-boot", MFD_CLOEXEC);
    write(memfd, program_text, strlen(program_text));
    snprintf(path, sizeof(path), "/proc/self/fd/%d", memfd);
    // Pass args through env vars because Chez steals -c
    setenv("JSH_ARGC", argc_str, 1);
    Sscheme_script(path, 0, NULL);
}
```

### After (with Track 23)

```scheme
;; boot-main.ss — loaded during boot, sets up deferred start
(import (std app))

(define-application "jsh"
  #:init (lambda () (setup-default-signal-handlers!))
  #:main (lambda (args) (jsh-main args))  ;; runs after boot, threads OK
  #:args (command-line))  ;; clean argument access
```

### What Gets Built

**Module: `(std app)`**

1. **`define-application` macro**: Separates init (runs during boot, no threads) from main (runs after boot, full runtime available)
2. **Deferred main**: Uses `eval` in `interaction-environment` after boot completes — same mechanism as `Sscheme_script` but without the memfd hack
3. **Argument passing**: Wraps `(command-line)` with proper parsing, avoiding Chez's `-c` flag conflict
4. **Boot file generation**: Helper to create boot files that include the deferred-start protocol
5. **Static binary support**: Integrates with `compile-whole-program` for single-binary output

### Implementation Strategy

1. **Boot-time registration**: `define-application` stores init/main thunks in a module-level parameter
2. **Post-boot dispatch**: A `scheme-start` handler (via `scheme-start` parameter) that runs the registered main after full initialization
3. **Argument isolation**: Capture `(command-line)` before Chez processes arguments, expose through `(app-arguments)`
4. **Integration with Track 22**: Build system knows how to generate boot files with deferred-start protocol

### Tests (~15)

- Application boots and runs main with threads available
- Command-line arguments passed correctly
- Init phase runs before main phase
- Thread creation works in main phase
- Static binary generation works
- Graceful error handling if main throws

### Estimated Effort

~300 lines. Mostly `scheme-start` integration and boot file helpers.

---

## Track 24: Structured FD and Process Lifecycle Manager

**Pain point**: jerboa-shell manually tracks file descriptors, leaks them on error paths, and has intricate `dup2`/`close` sequences scattered across 6+ modules. Process group management (setpgid, tcsetpgrp) is similarly ad-hoc. Every pipeline implementation risks fd leaks.

**Solution**: A structured resource manager for file descriptors and child processes that guarantees cleanup via `dynamic-wind` and provides composable pipeline construction.

### Before (current jerboa-shell)

```scheme
;; Scattered across multiple modules
(let ([rfd (ffi-dup fd)])
  ;; ... lots of code ...
  ;; hope nobody forgets:
  (ffi-close-fd rfd))  ;; leaked on exception!

;; Pipeline construction — manual fd juggling
(let-values ([(r1 w1) (ffi-pipe-raw)]
             [(r2 w2) (ffi-pipe-raw)])
  (ffi-dup2 w1 1) (ffi-close-fd w1) (ffi-close-fd r1)
  ;; ... more dup2/close ...
  ;; if anything throws, fds leak
  )
```

### After (with Track 24)

```scheme
(import (std os fd))

(with-fds ([rfd (fd-dup source-fd)]
           [pipe (fd-pipe)])
  ;; rfd and pipe automatically closed on exit or exception
  (fd-redirect! (pipe-write pipe) STDOUT_FILENO)
  (spawn-process cmd #:stdin (pipe-read pipe)))

;; Or with pipeline combinator:
(run-pipeline '("grep" "pattern") '("sort") '("uniq" "-c")
  #:input input-fd
  #:output output-fd)
```

### What Gets Built

**Module: `(std os fd)`**

1. **`with-fds` macro**: Like `with-exception-handler` but for fd cleanup. Uses `dynamic-wind` to guarantee `close()` on all exit paths.
2. **FD objects**: Thin wrappers around integer fds that track ownership and prevent double-close
3. **`fd-pipe`**: Returns a pipe object with `pipe-read`/`pipe-write` accessors
4. **`fd-redirect!`**: Combines `dup2` + `close` atomically
5. **Process spawning**: `spawn-process` that manages fd inheritance, process groups, and foreground control
6. **Pipeline combinator**: `run-pipeline` that wires up N processes with pipes, managing all intermediate fds

**Module: `(std os process)`**

1. **Process objects**: Track PID, process group, status
2. **`with-process-group`**: Manage foreground process group via `dynamic-wind`
3. **`process-wait`**: Wraps `waitpid` with status decoding (using Track 20's POSIX bindings)

### Implementation Strategy

1. **FD wrapper type**: `define-record-type` with finalizer via guardian (Chez's `make-guardian`)
2. **Ownership tracking**: Each FD object knows if it owns the underlying fd (vs. borrowed reference)
3. **`dynamic-wind` cleanup**: `with-fds` expands to nested `dynamic-wind` with close-on-exit
4. **Pipeline**: Fork N children, wire pipes, manage process group, wait for all

### Tests (~35)

- `with-fds` closes on normal exit
- `with-fds` closes on exception
- No double-close when fd explicitly closed before exit
- Pipeline: 2-stage, 3-stage, N-stage
- Pipeline with failing middle process
- Process group management (setpgid/tcsetpgrp)
- FD leak detection (count open fds before/after)

### Estimated Effort

~700 lines. FD manager + process spawning + pipeline combinator.

---

## Track 25: Safe Signal Delivery via Channels

**Pain point**: jerboa-shell uses two incompatible signal mechanisms simultaneously: Gerbil's `add-signal-handler!` (which runs closures asynchronously) and a C-level flag array polled by `pending-signals!`. There are race conditions between signal arrival and flag checking. The `*pending-signals*` list is mutated from multiple contexts without synchronization.

**Solution**: A channel-based signal delivery system using Chez's native `mutex`/`condition` primitives, where signals are delivered as messages to typed channels that can be `select`-ed alongside other event sources.

### Before (current jerboa-shell)

```scheme
;; signals.sls — two incompatible mechanisms
;; Mechanism 1: async closures (Gerbil-style)
(add-signal-handler! SIGINT
  (lambda ()
    ;; Race: this mutates a shared list from signal context!
    (set! *pending-signals* (cons "INT" *pending-signals*))))

;; Mechanism 2: C flag polling
(ffi-signal-flag-install SIGXFSZ)
(define (pending-signals!)
  (hash-for-each
    (lambda (name signum)
      (when (= 1 (ffi-signal-flag-check signum))
        ;; Race: flag can be set between check and clear!
        (set! *pending-signals* (cons name *pending-signals*))))
    *flag-trapped-signals*))
```

### After (with Track 25)

```scheme
(import (std os signal-channel))

(define sig-ch (make-signal-channel SIGINT SIGTERM SIGCHLD SIGWINCH))

;; In the main loop — type-safe, no races
(let loop ()
  (select
    [(recv sig-ch) => (lambda (sig)
      (case (signal-name sig)
        [("INT") (handle-interrupt)]
        [("CHLD") (reap-children)]
        [("WINCH") (update-terminal-size)]))]
    [(ready? input-port) => handle-input]
    [(timeout 100) => check-background-jobs])
  (loop))
```

### What Gets Built

**Module: `(std os signal-channel)`**

1. **Signal channel**: A mutex-protected queue that receives signal notifications
2. **Signal thread**: A dedicated Chez thread that blocks on `sigwait()` (via Track 20's POSIX bindings) and enqueues signals to channels
3. **`select` integration**: Signal channels implement the selectable protocol from `(std event)` (Phase 4)
4. **`make-signal-channel`**: Register interest in specific signals, returns a channel
5. **Signal masking**: Automatically calls `sigprocmask` to block registered signals in all threads except the signal thread

### Implementation Strategy

1. **Signal thread**: One dedicated thread calls `sigwait()` in a loop
2. **Channel dispatch**: Signal thread looks up registered channels by signal number, enqueues
3. **Mutex-protected queue**: Standard producer-consumer with `mutex-acquire`/`mutex-release` and `condition-signal`
4. **`select` protocol**: Channels expose `ready?` and `recv` that integrate with the event system
5. **Backward compat**: `add-signal-handler!` still works for simple cases, but signal-channel is preferred

### Tests (~25)

- Signal delivery to channel (send signal, recv matches)
- Multiple signals to same channel
- Select between signal channel and I/O
- Signal masking (only signal thread receives)
- Channel cleanup on close
- No lost signals under rapid delivery
- Backward compatibility with existing handler API

### Estimated Effort

~500 lines. Signal thread + channel type + select integration.

---

## Track 26: Raw Byte I/O Ports

**Pain point**: Chez Scheme's ports assume UTF-8 text. jerboa-shell needs raw byte access for shell I/O (binary data in pipes, locale-independent byte processing). Currently uses a 1MB C buffer (`ffi_read_buf`) and Latin-1 decoding hack to preserve raw bytes — each byte 0x00-0xFF becomes char U+0000-U+00FF.

**Solution**: First-class binary port operations that bypass Chez's UTF-8 codec, using `bytevector` as the natural currency for raw I/O.

### Before (current jerboa-shell)

```scheme
;; ffi.sls — C buffer + Latin-1 hack
(define (ffi-read-all-from-fd fd)
  ;; Read into C buffer, copy to bytevector, decode as Latin-1
  (let* ((len (c-ffi-do-read-all fd))
         (bv (make-bytevector len))
         (_ (c-ffi-copy-read-buf bv len))
         (result (make-string len)))
    (let loop ((i 0))
      (if (>= i len) result
        (begin
          (string-set! result i (integer->char (bytevector-u8-ref bv i)))
          (loop (+ i 1)))))))  ;; O(n) char-by-char copy!
```

### After (with Track 26)

```scheme
(import (std io raw))

;; Direct byte I/O — no codec, no C buffer, no copying
(define bv (fd-read-bytes fd 4096))
(fd-write-bytes fd bv)

;; Or wrap fd as a binary port
(define bp (fd->binary-port fd))
(get-bytevector-some bp)  ;; standard R6RS binary port ops
```

### What Gets Built

**Module: `(std io raw)`**

1. **`fd-read-bytes`**: Direct `read()` syscall via `foreign-procedure`, returns bytevector. No codec, no intermediate buffer.
2. **`fd-write-bytes`**: Direct `write()` syscall, accepts bytevector.
3. **`fd->binary-port`**: Creates a Chez binary port backed by an fd, using `make-custom-binary-input-port` / `make-custom-binary-output-port` (R6RS standard)
4. **`fd->textual-port`**: Creates a textual port with selectable codec (UTF-8, Latin-1, raw) backed by an fd
5. **Buffered variants**: Optional userspace buffering for small reads

### Implementation Strategy

1. **`fd-read-bytes`**: Uses `foreign-procedure "read"` with a pre-allocated bytevector. `foreign-procedure` can operate directly on bytevectors via Chez's C-callable interface.
2. **`fd->binary-port`**: Uses R6RS `make-custom-binary-input-port` with read/close handlers that call POSIX `read()`/`close()`
3. **`fd->textual-port`**: Uses `make-custom-textual-input-port` with a transcoder parameter
4. **No C shim needed**: All operations use `foreign-procedure` to call libc directly

### Tests (~20)

- Read/write roundtrip with binary data (including null bytes)
- Binary port operations: `get-u8`, `get-bytevector-n`, `get-bytevector-some`
- No UTF-8 mangling of bytes > 127
- Pipe I/O with binary ports
- Large read (>1MB) without intermediate buffer
- Port close properly closes underlying fd

### Estimated Effort

~300 lines. Mostly port constructor wrappers around R6RS custom port API.

---

## Track 27: Copy-on-Write Environment for Subshells

**Pain point**: Shell subshells (`(cmd)`, `$(cmd)`, command substitution) need a copy of the entire shell environment (variables, traps, options, aliases) without modifying the parent. Currently, jerboa-shell deep-copies hash tables on every subshell fork — expensive for the common case where most variables are never modified.

**Solution**: A persistent map (using the functional red-black tree or hash-array-mapped trie from Phase 3) that supports O(1) snapshots and copy-on-write updates.

### Before (current jerboa-shell)

```scheme
;; Deep copy on every subshell — copies entire variable table
(define (make-subshell-env parent-env)
  (let ([new-vars (make-hash-table)])
    (hash-for-each
      (lambda (k v) (hash-put! new-vars k v))
      (env-variables parent-env))
    ;; ... copy traps, aliases, options, functions ...
    (make-env new-vars ...)))
```

### After (with Track 27)

```scheme
(import (std data pmap))  ;; persistent map from Phase 3

;; O(1) snapshot — shares structure with parent
(define (make-subshell-env parent-env)
  (make-env
    (pmap-snapshot (env-variables parent-env))  ;; instant
    (pmap-snapshot (env-traps parent-env))       ;; instant
    (pmap-snapshot (env-aliases parent-env))     ;; instant
    ...))

;; Writes in subshell don't affect parent (copy-on-write)
(pmap-set! subshell-vars "PATH" "/usr/bin")  ;; only modifies subshell's tree
```

### What Gets Built

This track primarily integrates Phase 3's `(std data pmap)` (persistent map) with the shell environment. The work is:

1. **Shell environment adapter**: Replace mutable hash tables in jsh's environment with persistent maps
2. **Snapshot protocol**: `env-snapshot` that captures the entire environment in O(1)
3. **Thread-safe access**: Persistent maps are inherently thread-safe for reads; writes create new versions
4. **Migration path**: Adapter that presents pmap with hash-table-compatible API (`pmap-ref`, `pmap-set!`, `pmap-for-each`)

### Implementation Strategy

1. **Wrap pmap with mutable cell**: Each environment holds a `(box pmap)`. Reads go through the pmap. Writes create a new pmap and `set-box!`.
2. **Snapshot = read the box**: `env-snapshot` just reads the current pmap — it's already persistent.
3. **Benchmark**: Measure subshell creation time with hash-copy vs pmap-snapshot to validate the speedup.

### Tests (~15)

- Subshell snapshot doesn't affect parent
- Parent changes after snapshot don't affect subshell
- Variable lookup performance (pmap vs hash-table baseline)
- Large environment snapshot (1000+ variables)
- Nested subshells (grandchild doesn't see parent's post-fork changes)

### Estimated Effort

~200 lines. Mostly integration code — the pmap itself already exists in Phase 3.

---

## Track 28: Error Recovery and Diagnostics

**Pain point**: When a Chez Scheme program crashes, you get a bare condition with no context. jerboa-shell wraps most operations in `guard` clauses that swallow errors, making debugging nearly impossible. There's no equivalent of Python's traceback or Rust's `RUST_BACKTRACE=1`.

**Solution**: A structured error system that captures continuation marks (Chez's `inspect/object`), formats readable diagnostics, and supports error recovery strategies.

### Before (current jerboa-shell)

```scheme
;; Error handling — catch everything, hope for the best
(guard (__exn [#t ((lambda (e) (%%void)) __exn)])
  (remove-signal-handler! signum))
;; If this fails, we have no idea why
```

### After (with Track 28)

```scheme
(import (std error diagnostics))

(with-diagnostics
  (lambda ()
    (remove-signal-handler! signum))
  #:on-error (lambda (err context)
    (display-diagnostic err context (current-error-port))
    ;; Prints:
    ;; Error: invalid signal number 99
    ;;   at (std os signal):remove-signal-handler! line 42
    ;;   at (jsh signals):trap-set! line 178
    ;;   at (jsh main):process-trap-command line 523
    ;;   Context: signum = 99, handler = #<procedure>
    ))
```

### What Gets Built

**Module: `(std error diagnostics)`**

1. **`with-diagnostics`**: Like `guard` but captures the continuation and extracts a stack trace using Chez's `inspect/object`
2. **`display-diagnostic`**: Formats error with stack trace, source locations, and local variable values
3. **`continuation->frames`**: Walks the continuation chain using `inspect/object` to extract procedure names and source locations
4. **`&diagnostic-condition`**: Condition type that carries structured trace information
5. **`current-diagnostic-handler`**: Parameter for global error formatting policy

**Module: `(std error recovery)`**

1. **`with-retry`**: Retry with backoff on transient errors (useful for I/O operations)
2. **`with-fallback`**: Try primary, fall back to alternative on error
3. **`with-cleanup`**: Like `dynamic-wind` but only runs cleanup on error (lighter than always-run)

### Implementation Strategy

1. **`inspect/object`**: Chez's inspector API can walk continuations and extract procedure names, source file/line info (when compiled with debug info)
2. **Source location**: Use `annotation-source` from compile-time annotations when available
3. **Frame formatting**: Map each continuation frame to a readable "module:procedure line N" format
4. **Condition wrapping**: Wrap any caught condition in `&diagnostic-condition` with the trace attached

### Tests (~20)

- Stack trace captures correct procedure names
- Source locations present when debug info compiled in
- Nested error contexts compose correctly
- `with-retry` retries specified number of times
- `with-fallback` uses fallback on error
- `display-diagnostic` output is human-readable
- Performance: diagnostic capture adds <1ms overhead

### Estimated Effort

~500 lines. Stack trace extraction + formatting + recovery combinators.

---

## Track 29: Capability-Aware Static Binaries

**Pain point**: jerboa-shell's sandbox module is completely stubbed — it prints "Warning: sandbox not available in static binary" and runs the command unsandboxed. Static binaries can't use `load-shared-object`, so dynamic plugin loading is impossible. There's no way to restrict what a shell script can do.

**Solution**: A capability-based security model where programs declare required capabilities (filesystem, network, process, environment) and the runtime enforces them, with special support for static binaries that can't load external code.

### Before (current jerboa-shell)

```scheme
;; sandbox.sls — completely stubbed
(define (jsh-sandbox-run opts thunk)
  (display "Warning: sandbox not available in static binary\n")
  (thunk))  ;; runs completely unsandboxed!
```

### After (with Track 29)

```scheme
(import (std security capability))

(with-capabilities
  '((filesystem read "/home" "/tmp")
    (filesystem write "/tmp")
    (process spawn)
    (network none))
  (lambda ()
    (run-untrusted-script "user-script.sh")))
;; Script can read /home and /tmp, write only /tmp,
;; spawn processes, but cannot access network.
;; Violations raise &capability-violation condition.
```

### What Gets Built

**Module: `(std security capability)`**

1. **Capability types**: `filesystem` (read/write/execute, with path restrictions), `network` (connect/listen/none), `process` (spawn/signal/none), `environment` (read/write/restrict)
2. **`with-capabilities`**: Establishes a capability context. All system calls within check against the granted capabilities.
3. **Enforcement layer**: Wraps Track 20's POSIX bindings with capability checks. `posix-open` checks filesystem capabilities before calling `open()`.
4. **Static binary support**: Capabilities are enforced in Scheme (no kernel sandbox needed), so they work in statically-linked musl binaries.
5. **Capability attenuation**: Child contexts can only restrict capabilities, never add new ones (monotonic security).

**Module: `(std security restrict)`**

1. **`restricted-eval`**: Evaluate code in an environment with limited bindings (no `foreign-procedure`, no `load`, no `system`)
2. **`make-restricted-environment`**: Creates an interaction-environment with only safe bindings

### Implementation Strategy

1. **Thread parameter**: `current-capabilities` is a `make-thread-parameter` holding the active capability set
2. **Interposition**: Track 20's POSIX wrappers check `current-capabilities` before each syscall
3. **Path canonicalization**: Capability paths are resolved to absolute paths to prevent path traversal (`../../../etc/passwd`)
4. **No kernel dependency**: This is pure Scheme enforcement — works on any OS, any binary format
5. **Granularity trade-off**: Start with coarse capabilities (filesystem/network/process), refine based on usage patterns

### Tests (~30)

- Filesystem read capability: allowed path succeeds, disallowed fails
- Filesystem write capability: write to allowed dir succeeds, disallowed raises
- Network capability: connect blocked when `network none`
- Process capability: spawn blocked when `process none`
- Capability attenuation: child can't escalate
- Path traversal prevention
- Static binary: capabilities work without dlopen
- `restricted-eval`: no access to FFI or file system
- Nested `with-capabilities`: inner restricts outer

### Estimated Effort

~600 lines. Capability types + enforcement wrappers + restricted eval.

---

## Summary: What Phase 6 Replaces

| What | Before (current) | After (Phase 6) |
|------|-------------------|------------------|
| POSIX calls | 570-line C shim + 261-line Scheme wrapper | Direct `foreign-procedure` via `define-posix` |
| Platform support | Linux-only (memfd, /proc) | Linux + macOS + FreeBSD |
| Build time | 30-60s sequential, 216-line manual script | 2-5s parallel, automatic dep discovery |
| Program loading | C main() with memfd hack | `define-application` macro |
| FD management | Manual dup2/close, leak on exception | `with-fds`, guaranteed cleanup |
| Signal handling | Two incompatible mechanisms with races | Channel-based, select-able |
| Binary I/O | 1MB C buffer + Latin-1 hack | Direct bytevector I/O |
| Subshell env | O(n) deep copy | O(1) persistent map snapshot |
| Error diagnostics | Bare conditions, swallowed errors | Stack traces, source locations |
| Sandbox | Completely stubbed | Capability-based enforcement |

### Lines of Code Eliminated in jerboa-shell

| Component | Current LOC | After Phase 6 |
|-----------|-------------|---------------|
| ffi-shim.c | 570 | 0 (replaced by Track 20) |
| ffi.sls wrappers | 261 | ~50 (thin import layer) |
| jsh-main.c | 92 | 0 (replaced by Track 23) |
| build-binary-jsh.ss | 216 | ~10 (one `build-project` call) |
| compat/gambit.sls | 838 | ~200 (only non-POSIX Gambit idioms) |
| **Total eliminated** | **~1,977** | **~260** |

### Estimated Total Effort

| Track | Description | Lines | Tests |
|-------|-------------|-------|-------|
| 20 | Declarative POSIX FFI | ~800 | ~40 |
| 21 | Portable OS Abstraction | ~500 | ~25 |
| 22 | Incremental Parallel Build | ~600 | ~30 |
| 23 | Safe Program Loading | ~300 | ~15 |
| 24 | Structured FD & Process Manager | ~700 | ~35 |
| 25 | Signal Channels | ~500 | ~25 |
| 26 | Raw Byte I/O Ports | ~300 | ~20 |
| 27 | Copy-on-Write Environment | ~200 | ~15 |
| 28 | Error Recovery & Diagnostics | ~500 | ~20 |
| 29 | Capability-Aware Static Binaries | ~600 | ~30 |
| **Total** | | **~5,000** | **~255** |

### Dependency Order

```
Track 20 (POSIX FFI) ← foundation for everything
  ├── Track 21 (Platform Abstraction) ← uses define-posix
  ├── Track 24 (FD Manager) ← uses POSIX fd operations
  ├── Track 25 (Signal Channels) ← uses sigwait, sigprocmask
  ├── Track 26 (Raw Byte I/O) ← uses POSIX read/write
  └── Track 29 (Capabilities) ← wraps POSIX calls with checks

Track 22 (Build System) ← independent, uses only Chez primitives
Track 23 (Program Loading) ← independent, uses scheme-start

Track 27 (CoW Environment) ← uses Phase 3 pmap
Track 28 (Error Diagnostics) ← uses inspect/object, independent
```

Build order: 20 → (21, 22, 23, 27, 28 in parallel) → (24, 25, 26) → 29

Phase 6 turns Jerboa from a language that *can* build systems programs (with enough C glue and platform hacks) into a language that makes systems programming *natural*. The difference: 1,977 lines of workarounds become 260 lines of clean imports.

---

# Phase 7: Gerbil Application Porting — The Missing Pieces

## Motivation

Jerboa already has extensive Gerbil API compatibility: hash tables (`hash-put!`/`hash-get`), `defstruct`, `defclass`, `defmethod`, `match`, `try`/`catch`/`finally`, channels, threads (Gambit API), and most of `:std/sugar`. However, porting real Gerbil applications (like gerbil-emacs, ~88K lines) reveals specific gaps that cause friction across nearly every source file.

### What Already Works

| Feature | Module | Status |
|---------|--------|--------|
| Hash tables (Gerbil API) | `(jerboa runtime)` | Complete — `hash-put!`, `hash-get`, `hash-ref`, `hash->list`, etc. |
| `defstruct` / `defclass` | `(jerboa core)` | Complete — with inheritance support |
| `defmethod` | `(jerboa core)` | Complete — runtime method dispatch |
| `match` | `(jerboa core)` | Complete — pattern matching |
| `try`/`catch`/`finally` | `(std sugar)` | Complete |
| `while`/`until` | `(std sugar)` | Complete |
| `unwind-protect` | `(std sugar)` | Complete |
| Channels | `(std misc channel)` | Complete — O(1) ring buffer with `channel-select` |
| Threads (Gambit API) | `(std misc thread)` | Complete — `make-thread`, `thread-start!`, `thread-join!` |
| Mutexes/Condvars | `(std misc thread)` | Complete — Gambit-compatible API |
| Thread mailboxes | `(std misc thread)` | Complete — `thread-send`, `thread-receive` |
| JSON | `(std text json)` | Complete |
| Format/printf | `(std format)` | Complete |
| SRFI-13 | `(std srfi srfi-13)` | Complete |
| SRFI-19 | `(std srfi srfi-19)` | Complete |
| Process execution | `(std misc process)` | Partial — `run-process` returns string, no port access |
| POSIX FFI | `(std os posix)` | Complete — pipe, fork, open, stat, etc. |
| FD management | `(std os fd)` | Complete — `spawn-process`, `fd-pipe`, `with-fds` |

### What's Missing (This Phase)

| Track | Feature | Impact | Est. Lines |
|-------|---------|--------|-----------|
| 30 | `spawn` / `spawn/name` / `spawn/group` | Every background task | ~30 |
| 31 | Atoms (`atom`, `atom-deref`, `atom-reset!`, `atom-swap!`) | Thread-safe state | ~40 |
| 32 | Read-Write Locks (`make-rwlock`, `with-read-lock`, `with-write-lock`) | Shared state | ~60 |
| 33 | TCP Server (`tcp-listen`, `tcp-accept`, `tcp-connect`) | Networking/IPC | ~200 |
| 34 | Process Ports (`open-input-process`, `open-output-process`, `process-port-pid`) | Shell/REPL/linter | ~120 |
| 35 | `with-lock` macro and `unwind-protect` enhancements | Cleanup patterns | ~20 |
| **Total** | | | **~470** |

---

## Track 30: `spawn` / `spawn/name` / `spawn/group`

**Module**: `(std misc thread)` — extend existing

**What**: Gerbil's `spawn` is the primary way to create background threads. It's used ~50 times in gerbil-emacs alone.

```scheme
(spawn thunk)                    ;; → thread (started immediately)
(spawn/name "worker" thunk)      ;; → thread with name
(spawn/group "pool" thunk)       ;; → thread in named group
```

**Implementation**: Thin wrappers around existing `make-thread` + `thread-start!`.

```scheme
(define (spawn thunk)
  (thread-start! (make-thread thunk)))

(define (spawn/name name thunk)
  (thread-start! (make-thread thunk name)))

(define (spawn/group group thunk)
  (thread-start! (make-thread thunk group)))
```

---

## Track 31: Atoms — Thread-Safe Mutable References

**Module**: `(std misc atom)` — new

**What**: Gerbil's `atom` is a mutable cell with optional mutex protection, used for background thread state (file indices, caches). Used ~20 times in gerbil-emacs.

```scheme
(define counter (atom 0))
(atom-deref counter)            ;; → 0
(atom-reset! counter 42)        ;; set to 42
(atom-swap! counter add1)       ;; atomically apply function
(atom-update! counter + 10)     ;; atomically apply with extra args
```

**Implementation**: Record type + mutex for thread safety.

---

## Track 32: Read-Write Locks

**Module**: `(std misc rwlock)` — new

**What**: Gerbil's `:std/misc/rwlock` provides concurrent-read / exclusive-write locking. Used for shared data structures accessed from multiple threads.

```scheme
(define lock (make-rwlock))
(with-read-lock lock (lambda () (read-shared-data)))
(with-write-lock lock (lambda () (update-shared-data!)))
```

**Implementation**: Classic readers-writer lock via Chez mutex + condition variables.

---

## Track 33: TCP Server — Socket Networking

**Module**: `(std net tcp)` — new

**What**: Gerbil applications use `open-tcp-server` for IPC (emacsclient-like remote control), HTTP servers, and service networking. This is a hard requirement for any networked application.

```scheme
;; Server
(define server (tcp-listen "127.0.0.1" 8080))
(let-values ([(in out) (tcp-accept server)])
  (display "hello\n" out)
  (flush-output-port out)
  (close-port in)
  (close-port out))
(tcp-close server)

;; Client
(let-values ([(in out) (tcp-connect "127.0.0.1" 8080)])
  (display (read-line in))
  (close-port in)
  (close-port out))
```

**Implementation**: POSIX socket FFI (`socket`, `bind`, `listen`, `accept`, `connect`) wrapped into Scheme ports via `make-custom-binary-input/output-port` or Chez's transcoded ports.

---

## Track 34: Process Ports — Subprocess I/O as Ports

**Module**: `(std misc process)` — extend existing

**What**: Gerbil's `open-process` returns a bidirectional port connected to a subprocess. Used for interactive shells, REPLs, and linters that need to send input and read output incrementally (not batch).

```scheme
;; Open a subprocess with port-based I/O
(let ([proc (open-input-process '("ls" "-la"))])
  (let loop ()
    (let ([line (read-line proc)])
      (unless (eof-object? line)
        (displayln line)
        (loop))))
  (close-input-port proc))

;; Bidirectional
(let ([proc (open-process '("python3" "-i"))])
  (display "print(1+2)\n" proc)
  (flush-output-port proc)
  (displayln (read-line proc))
  (close-port proc))
```

**Implementation**: Uses POSIX `pipe` + `fork` + `execvp` to create subprocess, then wraps the pipe FDs as Chez Scheme ports. Builds on existing `(std os posix)` and `(std io raw)`.

---

## Track 35: `with-lock` Macro

**Module**: `(std sugar)` — extend existing

**What**: Common Gerbil pattern for mutex-protected critical sections. Cleaner than manual `mutex-lock!`/`unwind-protect`/`mutex-unlock!`.

```scheme
(with-lock my-mutex
  (modify-shared-state!))
```

**Implementation**: Syntax-rules macro expanding to `dynamic-wind` or `unwind-protect`.

---

## Dependency Order

```
Track 30 (spawn) ← extends (std misc thread), no deps
Track 31 (atoms) ← uses Chez mutexes, no deps
Track 32 (rwlock) ← uses Chez mutexes + conditions, no deps
Track 33 (TCP) ← uses (std os posix) for socket FFI
Track 34 (process ports) ← uses (std os posix) + (std io raw)
Track 35 (with-lock) ← extends (std sugar), no deps
```

Build order: (30, 31, 32, 35 in parallel) → (33, 34)

## Porting Effort After Phase 7

With these ~470 lines implemented, porting gerbil-emacs becomes mechanical translation:
- **100% of import lines** map to jerboa modules
- **100% of concurrency patterns** have direct equivalents
- **100% of data structures** have compatible APIs
- Remaining work is Gambit→Chez FFI translation (`begin-ffi` → `foreign-procedure`) which is module-specific, not pervasive

---

# Phase 8: Deep Gerbil Compatibility — Closing the Porting Gap

**Goal:** Eliminate the remaining API gaps that would require manual rewriting when porting gerbil-emacs (~88K lines, 147 files). Phase 7 gave us the infrastructure; Phase 8 makes the translation mechanical.

**Analysis basis:** Searched all 147 `.ss` files in gerbil-emacs for Gerbil-specific APIs and cross-referenced against jerboa's existing modules. These 10 tracks cover features used across 85+ files with 5,500+ combined occurrences.

### What Already Works (no changes needed)

| Feature | Jerboa Module | Status |
|---------|--------------|--------|
| `def` with optional positional args | `(jerboa core)` | ✅ Works |
| `defstruct`, `defclass`, `defmethod` | `(jerboa core)` | ✅ Works |
| `match` | `(jerboa core)` | ✅ Works |
| `try`/`catch`/`finally` | `(std sugar)` | ✅ Works |
| `when`/`unless`/`while`/`until` | `(std sugar)` | ✅ Works |
| `defrule`/`defrules` | `(jerboa core)` | ✅ Works |
| `chain`/`chain-and` | `(std sugar)` | ✅ Works |
| `hash-get`, `hash-put!`, `hash->list`, etc. | `(jerboa runtime)` | ✅ Works |
| `hash-copy`, `hash-merge`, `hash-fold` | `(jerboa runtime)` | ✅ Works |
| `hash-literal` (as `hash-literal`) | `(jerboa core)` | ✅ Renamed |
| `string-split`, `string-join`, `string-trim` | `(std misc string)` | ✅ Works |
| `string-prefix?`, `string-suffix?` | `(std misc string)` | ✅ Works |
| `read-file-string`, `write-file-string` | `(std misc ports)` | ✅ Works |
| `path-expand`, `path-join`, `path-normalize` | `(std os path)` | ✅ Works |
| `pregexp-match`, `pregexp-replace`, etc. | `(std pregexp)` | ✅ Works |
| `read-json`, `write-json` | `(std text json)` | ✅ Works |
| `displayln`, `format`, `printf` | `(jerboa runtime)`, `(std format)` | ✅ Works |
| `spawn`, `thread-join!`, `thread-sleep!` | `(std misc thread)` | ✅ Works |
| `atom`, `atom-swap!`, `atom-deref` | `(std misc atom)` | ✅ Works |
| `with-lock` | `(std sugar)` | ✅ Works |
| `make-mutex`, `with-mutex` | `(chezscheme)` | ✅ Native |
| `getenv`, `setenv` | `(std os env)` | ✅ Works |
| `current-directory` | `(chezscheme)` | ✅ Native |
| `parameterize`, `make-parameter` | `(chezscheme)` | ✅ Native |
| `values`, `call-with-values` | `(chezscheme)` | ✅ Native |
| `dynamic-wind` | `(chezscheme)` | ✅ Native |
| `define-syntax`, `syntax-rules` | `(chezscheme)` | ✅ Native |
| `string-downcase`, `string-upcase` | `(chezscheme)` | ✅ Native |
| `void` | `(chezscheme)` | ✅ Native |

### What's Missing — The 10 Tracks

## Track 36: `def` with Keyword Arguments

**Used in:** 19+ files, core editor infrastructure
**Occurrences:** ~50 keyword-arg definitions, ~200 keyword-arg call sites

Gerbil's `def` supports keyword arguments with defaults:
```scheme
(def (defvar! name default docstring
              setter: (setter #f)
              type: (type 'sexp)
              group: (group 'misc))
  ...)

;; Called as:
(defvar! 'tab-width 8 "Tab width" type: 'integer group: 'editing)
```

**Current state:** jerboa's `def` handles optional positional args via `case-lambda` but not keyword args.

**Implementation:** Extend the `def` macro to detect `keyword:` patterns in the parameter list. Generate a body that parses a rest-arg list for keyword/value pairs, falling back to defaults.

```scheme
;; Desired expansion of keyword def:
(def (foo x y key1: (key1 default1) key2: (key2 default2)) body ...)
;; →
(define (foo x y . kwargs)
  (let ([key1 (keyword-arg kwargs key1: default1)]
        [key2 (keyword-arg kwargs key2: default2)])
    body ...))
```

**Depends on:** `(jerboa runtime)` keyword utilities (already has `keyword?`, `keyword->string`)

## Track 37: `with-catch` — Exception Handler Shorthand

**Used in:** 85 files, 621 occurrences
**The single most-used missing API in gerbil-emacs**

```scheme
;; Gerbil pattern:
(with-catch
  (lambda (e) #f)           ;; handler: return #f on error
  (lambda () (dangerous-op)))  ;; thunk: the guarded code

;; Also common:
(with-catch
  (lambda (e) (values 'error e))
  (lambda () (parse-json input)))
```

**Current state:** jerboa has `try`/`catch`/`finally` in `(std sugar)` but not the simpler two-argument `with-catch`.

**Implementation:** ~5 lines in `(std sugar)`:
```scheme
(define (with-catch handler thunk)
  (guard (e [#t (handler e)])
    (thunk)))
```

## Track 38: `hash` Constructor Macro (Rename)

**Used in:** 10+ files, 168 hash table constructions
**Critical for JSON-heavy code (AI integration, LSP client)**

Gerbil uses `(hash ...)` to construct hash tables:
```scheme
(hash ("model" "gpt-4")
      ("messages" [(hash ("role" "user")
                         ("content" prompt))]))
```

**Current state:** jerboa has `hash-literal` which does the same thing, but under a different name.

**Implementation:** Add `hash` as an alias for `hash-literal` and `hash-eq` for `hash-eq-literal`:
```scheme
(define-syntax hash
  (syntax-rules ()
    [(_ args ...) (hash-literal args ...)]))
```

**Also need:** Square bracket `[...]` syntax for list literals (Gerbil convention). Chez already supports `[...]` as equivalent to `(...)` in most contexts.

## Track 39: `struct-out` Export Helper

**Used in:** 33 files with `(export #t)`, 14 with selective exports, 8 struct-heavy modules

Gerbil's `(export (struct-out typename))` automatically exports the constructor, predicate, and all field accessors/mutators:
```scheme
(export (struct-out buffer))
;; Expands to: (export make-buffer buffer? buffer-name buffer-file-path ...)
```

**Current state:** Not implemented. Users must manually list every accessor.

**Implementation:** A macro that expands by looking up the registered struct type info:
```scheme
(define-syntax struct-out
  (lambda (stx)
    (syntax-case stx ()
      [(_ type-name)
       ;; Look up type in *struct-types* at expansion time
       ;; Generate export list: make-TYPE TYPE? TYPE-field1 TYPE-field1-set! ...
       ...])))
```

**Depends on:** `(jerboa core)` struct type registry (`*struct-types*`, `register-struct-type!`)

## Track 40: `cut` / `cute` — SRFI-26 Partial Application

**Used in:** 5+ files, lightweight but idiomatic
**Prevents verbose `lambda` wrappers**

```scheme
;; Gerbil:
(map (cut string-append "prefix-" <>) items)
;; Instead of:
(map (lambda (x) (string-append "prefix-" x)) items)

;; With multiple slots:
(cut string-append <> "-" <>)
;; → (lambda (a b) (string-append a "-" b))
```

**Current state:** Not implemented.

**Implementation:** ~20 lines as a `syntax-rules` macro:
```scheme
(define-syntax cut
  (syntax-rules (<> <...>)
    [(_ expr ...)
     (cut-helper () (expr ...))]))

(define-syntax cut-helper
  (syntax-rules (<> <...>)
    [(_ (args ...) ())
     (lambda (args ...) (orig ...))]
    [(_ (args ...) (<> rest ...))
     (cut-helper (args ... x) (rest ...))]
    ...))
```

## Track 41: Gerbil-Style Import/Export Translation Layer

**Used in:** All 147 files
**The biggest mechanical translation burden**

Every gerbil-emacs file starts with:
```scheme
(import :std/sugar
        :std/iter
        :std/sort
        :gerbil-scintilla/constants
        :gemacs/core)
```

Jerboa uses R6RS `(import (std sugar) (std iter) ...)`.

**Implementation:** A `gerbil-import` macro that translates `:std/foo` → `(std foo)` and `:pkg/mod` → `(pkg mod)`:
```scheme
(define-syntax gerbil-import
  (lambda (stx)
    (syntax-case stx ()
      [(_ spec ...)
       (with-syntax ([(translated ...) (map translate-import-spec #'(spec ...))])
         #'(import translated ...))])))
```

Also: `(export #t)` auto-export macro that re-exports all definitions.

**Note:** This is a convenience layer — files can always be converted manually, but automating it makes bulk porting feasible.

## Track 42: `for/fold` and `for/collect` — Iterator Macros

**Used in:** While gerbil-emacs uses `map`/`fold` directly (not `for/list`), the Gerbil `:std/iter` module is imported in 15+ files.

Common `:std/iter` patterns:
```scheme
(import :std/iter)

;; for-each with index
(for ((x items) (i (in-naturals)))
  (display (format "~a: ~a\n" i x)))

;; collect results
(for/collect ((x items))
  (string-upcase x))

;; fold with accumulator
(for/fold ((acc 0)) ((x items))
  (+ acc x))
```

**Current state:** jerboa has transducers and lazy sequences, but not Gerbil's `for` macro family.

**Implementation:** ~80 lines. Core `for` macro with `in-list`, `in-range`, `in-vector`, `in-hash-keys`, `in-hash-values` iterators:
```scheme
(define-syntax for
  (syntax-rules ()
    [(_ ((var iter-expr)) body ...)
     (iter-for-each (lambda (var) body ...) iter-expr)]))

(define (in-list lst) lst)
(define (in-range n) (iota n))
(define (in-naturals) ...)
```

## Track 43: `begin-ffi` / `begin-foreign` — FFI Block Macro

**Used in:** 5 files (pty.ss, terminal.ss, subprocess.ss, signal handling)
**Critical for porting native terminal/PTY code**

Gerbil's `begin-ffi` wraps Gambit's `c-declare`/`c-lambda`:
```scheme
(begin-ffi (ffi-pty-spawn ffi-pty-read ffi-pty-write ffi-pty-close)
  (c-declare "#include <pty.h>")
  (define ffi-pty-spawn
    (c-lambda (char-string) int "forkpty_spawn")))
```

**Current state:** jerboa has `(jerboa ffi)` with `begin-ffi` that uses `foreign-procedure`.

**Implementation:** The existing `begin-ffi` needs to handle the Gerbil calling convention. Map Gambit FFI types to Chez types:
- `char-string` → `string`
- `int` → `int`
- `void*` → `void*`
- `scheme-object` → `scheme-object`

## Track 44: `##` Gambit Primitives Compatibility

**Used in:** 5 files, ~10 occurrences
**Needed for:** debugging (`##object->string`), system info (`##cpu-count`)

```scheme
(gemacs-log! "async error: " (##object->string e))
(max 1 (quotient (##cpu-count) 2))
```

**Current state:** Not implemented.

**Implementation:** Provide compatibility bindings for the ~5 Gambit `##` primitives actually used:
```scheme
;; In (std compat gambit)
(define (##object->string obj)
  (call-with-string-output-port
    (lambda (p) (write obj p))))

(define (##cpu-count)
  (let ([n (foreign-procedure "sysconf" (long) long)])
    (n 84)))  ;; _SC_NPROCESSORS_ONLN = 84 on Linux
```

## Track 45: HTTP Client Implementation

**Used in:** 4 files, ~8 call sites
**Critical for:** AI/copilot integration, web features, LSP

```scheme
(http-get url)
(http-post url
  headers: [("Content-Type" . "application/json")]
  data: (json-object->string payload))
```

**Current state:** `(std net request)` exists as a stub — exports declared but no implementation.

**Implementation:** ~150 lines using the TCP module from Track 33 plus TLS via FFI:
```scheme
(define (http-get url . kwargs)
  (let-values ([(scheme host port path) (parse-url url)])
    (let-values ([(in out) (if (string=? scheme "https")
                             (tls-connect host port)
                             (tcp-connect host port))])
      (put-string out (format "GET ~a HTTP/1.1\r\nHost: ~a\r\n\r\n" path host))
      (flush-output-port out)
      (parse-http-response in))))
```

**Depends on:** Track 33 (TCP), OpenSSL FFI for HTTPS

## Dependency Order

```
Track 37 (with-catch)    ← no deps, ~5 lines
Track 38 (hash alias)    ← no deps, ~5 lines
Track 40 (cut/cute)      ← no deps, ~30 lines
Track 44 (## compat)     ← no deps, ~20 lines
Track 36 (keyword args)  ← extends (jerboa core), ~60 lines
Track 39 (struct-out)    ← uses struct registry, ~40 lines
Track 41 (import/export) ← translation layer, ~80 lines
Track 42 (for/collect)   ← iterator macros, ~80 lines
Track 43 (begin-ffi)     ← extends (jerboa ffi), ~50 lines
Track 45 (HTTP client)   ← uses Track 33 TCP, ~150 lines
```

Build order: (37, 38, 40, 44 in parallel) → (36, 39, 42) → (41, 43) → 45

## Phase 8 Total — IMPLEMENTED

~520 lines of implementation across 10 tracks, 90 tests passing. All gaps for mechanical gerbil-emacs porting are closed.

## Porting Effort After Phase 8

With Phases 7 + 8 complete (~990 lines total), porting gerbil-emacs becomes:
1. **Find-and-replace imports** — `:std/foo` → `(std foo)` (automated by Track 41)
2. **`#!chezscheme` header** — add to each file
3. **`begin-ffi` blocks** — translate `c-lambda` → `foreign-procedure` (Track 43 handles most)
4. **`##` primitives** — 5 substitutions total (Track 44)
5. **Everything else** — compatible as-is
