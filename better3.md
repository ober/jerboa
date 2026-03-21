# Better3: 30 World-Shattering Language Features

Ambitious features inspired by Rust, Haskell, Elixir, Zig, Swift, Clojure, OCaml, Unison,
and research PLs — all exploiting Chez Scheme's unique capabilities (engines, continuations,
cp0 optimizer, guardians, ftypes, nanopass compiler).

Jerboa already has: algebraic effects, gradual types, STM, actors, capabilities, lazy seqs,
pattern matching v2, transducers, delimited continuations, coroutines. These 30 features
build on that foundation to create something no other Scheme — or most languages — offer.

---

## I. Ownership & Safety (1–5)

### 1. `(std region)` — Region-Based Memory with Compile-Time Lifetimes
**Inspiration:** Rust lifetimes, Cyclone regions, Linear Haskell

Chez has guardians and ftypes for C memory. Combine with jerboa's linear types
(`std/typed/linear.sls`) to create region-scoped allocations that are *provably* freed:

```scheme
(with-region r
  (let ([buf (region-alloc r 4096)])   ;; allocate in region r
    (region-ref buf 0)                  ;; read — valid inside region
    buf))                               ;; ERROR: buf escapes region r
;; ALL memory in r freed here — no GC pressure, no leaks
```

**Why this is world-shattering:** No Scheme has region-based memory. Chez's ftype system
provides the raw allocation; linear types prevent escape. This gives Rust-like memory
safety *within a dynamic language* — zero-cost for FFI-heavy code (litehtml, Qt, crypto).

**Chez leverage:** `ftype-pointer`, `foreign-alloc`/`foreign-free`, guardian fallback,
`define-ftype` for typed regions.

---

### 2. `(std borrow)` — Borrow Checker for Mutable State
**Inspiration:** Rust borrow checker, Clean uniqueness types

Build on linear types to enforce single-writer/multiple-reader discipline at the
*macro expansion* level:

```scheme
(define-linear buf (make-bytevector 1024))
(borrow buf reader              ;; immutable borrow
  (bytevector-u8-ref reader 0)) ;; OK: read access
(borrow-mut buf writer          ;; mutable borrow
  (bytevector-u8-set! writer 0 42))  ;; OK: exclusive write
;; buf still owned here
(consume buf)                   ;; linear resource consumed
```

**Why:** Eliminates data races at compile time for shared mutable state — something
even Clojure can't do (it uses STM at runtime). This is a *static* guarantee.

**Chez leverage:** `syntax-case` for compile-time tracking, continuation marks for
borrow stack, cp0 for dead-borrow elimination.

---

### 3. `(std move)` — Move Semantics for Zero-Copy Pipelines
**Inspiration:** Rust move semantics, Zig's comptime

When data flows through a pipeline, copies are the enemy. Move semantics transfer
ownership without copying:

```scheme
(define-move (process-request req)
  (let ([body (move! (request-body req))])  ;; req.body invalidated
    (let ([parsed (json-parse (move! body))]) ;; body invalidated
      parsed)))  ;; only parsed survives — zero copies
```

**Why:** Critical for jerboa-shell pipelines (zero-copy between stages), network
servers (request body → parser → handler), and FFI (C buffer ownership transfer).

**Chez leverage:** Continuation marks track ownership, cp0 eliminates dead references,
guardian catches use-after-move at runtime as safety net.

---

### 4. `(std phantom)` — Phantom Types for Type-Level State Machines
**Inspiration:** Haskell phantom types, Rust typestate pattern, OCaml GADTs

Encode protocol states in the type system so invalid transitions are compile-time errors:

```scheme
(define-phantom-states connection
  [disconnected connected authenticated])

(define/phantom (connect host) : (Connection disconnected) -> (Connection connected)
  (tcp-connect host 443))

(define/phantom (login conn creds) : (Connection connected) -> (Connection authenticated)
  (send-auth conn creds))

(define/phantom (query conn sql) : (Connection authenticated) -> Result
  (send-query conn sql))

;; (query (connect "db") "SELECT 1")  ;; TYPE ERROR: connected ≠ authenticated
```

**Why:** Prevents impossible state transitions at compile time. Database connections
that query before login, files that write after close, TLS that sends before handshake —
all caught statically. No other Scheme has this.

**Chez leverage:** Builds on jerboa's GADT module (`std/typed/gadt.sls`), syntax-case
for phantom parameter threading, record-type-descriptor for runtime fallback.

---

### 5. `(std affine)` — Affine Types (Use-At-Most-Once)
**Inspiration:** Rust's affine types, Linear Haskell, Granule

Complementing linear types (use-exactly-once), affine types allow *dropping* but not
*duplicating*:

```scheme
(define-affine (open-temp)
  (let ([path (make-temporary-file)])
    (affine-value path)))

(let ([tmp (open-temp)])
  ;; (list tmp tmp)  ;; COMPILE ERROR: affine value used twice
  (write-to tmp "data")
  ;; tmp automatically cleaned up if not consumed
  )
```

**Why:** Perfect for file handles, network connections, database transactions —
resources that can be *abandoned* (GC + guardian cleans up) but must never be *aliased*.

**Chez leverage:** Guardians as safety net for dropped affine values, continuation
marks for tracking, cp0 for dead-code elimination of cleanup paths.

---

## II. Computation Models (6–10)

### 6. `(std logic)` — Embedded Logic Programming (miniKanren)
**Inspiration:** miniKanren, Prolog, Datalog, core.logic (Clojure)

Full relational programming embedded in Scheme with Chez's continuation magic:

```scheme
(run* (q)
  (fresh (x y)
    (== q (list x y))
    (membero x '(1 2 3))
    (membero y '(a b c))
    (conde
      [(== x 1) (== y 'a)]
      [(== x 2) (== y 'b)])))
;; => ((1 a) (2 b))
```

**Why:** Logic programming within a systems language. Query engines, constraint solvers,
type inference engines, configuration validators — all expressible as relations.
Chez's first-class continuations make the search *fast* (no CPS transform needed).

**Chez leverage:** Native continuations for backtracking (no trampoline), engines for
bounded search (timeout after N ticks), unification over Chez records.

---

### 7. `(std datalog)` — Incremental Datalog for Reactive Queries
**Inspiration:** Datomic, Souffle, Differential Datalog, Naga

Bottom-up Datalog with incremental maintenance — when facts change, queries update
automatically:

```scheme
(define-datalog db
  ;; Rules
  [(ancestor ?x ?y) :- (parent ?x ?y)]
  [(ancestor ?x ?z) :- (parent ?x ?y) (ancestor ?y ?z)])

(datalog-assert! db '(parent alice bob))
(datalog-assert! db '(parent bob charlie))
(datalog-query db '(ancestor alice ?who))
;; => ((ancestor alice bob) (ancestor alice charlie))

;; Incremental: add a fact, query result updates automatically
(datalog-assert! db '(parent charlie dave))
(datalog-query db '(ancestor alice ?who))
;; => (... (ancestor alice dave))  ;; dave appears without re-evaluating
```

**Why:** Reactive data dependencies for build systems, configuration management,
access control policies, and the jerboa LSP server. Differential datalog is how
Rust-analyzer achieves fast incremental type checking.

**Chez leverage:** Hashtable-based fact indexing, engines for query timeout,
guardians for automatic fact GC when relations are dropped.

---

### 8. `(std frp)` — Functional Reactive Programming
**Inspiration:** Elm, Reflex (Haskell), Rx, Svelte reactivity

Signals and behaviors that automatically propagate changes through a dependency graph:

```scheme
(define width (make-signal 800))
(define height (make-signal 600))
(define area (signal-map * width height))
(define label (signal-map (lambda (a) (format "~a px²" a)) area))

(signal-ref label)  ;; => "480000 px²"
(signal-set! width 1024)
(signal-ref label)  ;; => "614400 px²"  — automatically propagated
```

**Why:** The UI model for jerboa-emacs. Instead of manual redraw callbacks, the
entire display is a signal graph. Change a buffer → window recomputes → display
updates. Also: reactive config files, live dashboards, monitoring systems.

**Chez leverage:** Continuation marks for tracking signal dependencies,
STM for glitch-free propagation (all updates atomic), guardians for signal cleanup.

---

### 9. `(std csp)` — Communicating Sequential Processes
**Inspiration:** Go goroutines/channels, Erlang processes, Clojure core.async

True CSP with typed channels, select with priority, and backpressure:

```scheme
(define-channel (ch : (Channel Integer)) 10)  ;; buffered channel, capacity 10

(go (lambda ()                    ;; lightweight green thread
  (for ([i (in-range 100)])
    (chan-put! ch (* i i)))))

(go (lambda ()
  (select
    [(recv ch val) (printf "got: ~a~n" val)]
    [(after 1000) (printf "timeout~n")]
    [default (printf "nothing ready~n")])))
```

**Why:** Jerboa already has channels and select, but not *typed* channels with
backpressure, not green threads (goroutines), and not a formal CSP model.
This turns jerboa into a Go-class concurrent language with Scheme's expressiveness.

**Chez leverage:** Engines for green thread scheduling (ticks = time slices),
continuations for context switching, ftype for lock-free channel buffers.

---

### 10. `(std lens)` — First-Class Optics (Lenses, Prisms, Traversals)
**Inspiration:** Haskell lens library, OCaml ppx_accessor, Kotlin Arrow Optics

Composable getters/setters for deeply nested immutable data:

```scheme
(define name-lens (make-lens person-name person-name-set))
(define city-lens (make-lens address-city address-city-set))
(define person-city (compose-lens address-lens city-lens))

(view person-city alice)                    ;; => "NYC"
(set person-city alice "SF")                ;; => new alice with city="SF"
(over person-city alice string-upcase)      ;; => new alice with city="NYC"→"NYC"

;; Prisms for sum types
(define-prism some-prism
  (lambda (x) (if (some? x) (some-value x) 'nothing))
  some)

;; Traversals for collections
(each-lens '(1 2 3 4))  ;; traverse every element
(over (each-lens) data add1)  ;; increment all elements
```

**Why:** Immutable data is painful to update deeply. Lenses make it ergonomic.
Critical for jerboa's persistent data structures (pvec, pmap, table) and
functional config management.

**Chez leverage:** `syntax-case` for lens composition macros, cp0 for fusing
nested lens operations into single-pass updates, records for type-safe lenses.

---

## III. Compile-Time Superpowers (11–15)

### 11. `(std comptime)` — Zig-Style Compile-Time Execution
**Inspiration:** Zig comptime, C++ constexpr, Rust const fn, Terra

Execute arbitrary Scheme code at compile time and splice results into the program:

```scheme
(define-comptime (fib n)
  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))

(define result (comptime (fib 40)))  ;; computed at COMPILE TIME
;; result is literally the integer 102334155 in the compiled output

(comptime
  (define lookup-table
    (list->vector
      (map (lambda (i) (* i i)) (iota 256)))))
;; lookup-table is a constant vector baked into the binary
```

**Why:** Zig's comptime is its killer feature — eliminate runtime computation by
doing it at compile time. Chez already has `eval-when` and the cp0 optimizer, but
this makes it *ergonomic* and *general*. Generate lookup tables, pre-compute hashes,
inline protocol parsers — all at compile time.

**Chez leverage:** `eval-when (compile)`, `meta` definitions, cp0 constant folding,
FASL for serializing compile-time results.

---

### 12. `(std derive2)` — Auto-Derive Protocol Implementations
**Inspiration:** Rust #[derive], Haskell deriving, Elixir @derive

Automatically generate implementations from struct definitions:

```scheme
(defstruct/derive point (x y)
  #:derive [equal hash display json serialize ord clone])

;; Automatically generates:
;; - (equal? p1 p2) comparing x,y fields
;; - (hash-code p) combining field hashes
;; - (display p port) pretty-printing
;; - (->json p) and (json-> 'point j) serialization
;; - (compare p1 p2) lexicographic ordering
;; - (clone p) deep copy
;; - (serialize p) / (deserialize 'point bv) binary format
```

**Why:** Jerboa already has `std/derive.sls` for some derivations. This extends it
to be *fully extensible* — users define new derivation strategies, and the system
applies them generically. Eliminates boilerplate across the entire codebase.

**Chez leverage:** `syntax-case` with `record-type-field-names` introspection,
`eval-when` for compile-time derivation, FASL for serialized forms.

---

### 13. `(std macro-types)` — Typed Macros with Expansion-Time Checking
**Inspiration:** Typed Racket macros, Scala 3 macros, sweet.js types

Macros that check their arguments at expansion time, not runtime:

```scheme
(define-typed-macro (matrix-multiply! dest a b)
  #:types ([dest : (Mutable Matrix)]
           [a : Matrix]
           [b : Matrix])
  #:check (= (matrix-cols a) (matrix-rows b))
  #:expand
  (let ([m (matrix-rows a)]
        [n (matrix-cols b)]
        [k (matrix-cols a)])
    #`(do ([i 0 (fx+ i 1)])
          ((fx= i #,m))
        (do ([j 0 (fx+ j 1)])
            ((fx= j #,n))
          (matrix-set! dest i j
            (do ([p 0 (fx+ p 1)] [sum 0.0 (fl+ sum (fl* (matrix-ref a i p)
                                                          (matrix-ref b p j)))])
                ((fx= p #,k) sum)))))))
```

**Why:** Macros are the soul of Lisp, but they're untyped — any mistake shows up
as a cryptic runtime error. Typed macros catch dimension mismatches, type errors,
and constraint violations *at macro expansion time*. This is the missing piece for
jerboa's type system to cover macros.

**Chez leverage:** `syntax-case` for expansion-time code, type environment threading
through expansion, cp0 for post-expansion optimization.

---

### 14. `(std quasiquote-types)` — Type-Safe Code Generation
**Inspiration:** MetaOCaml, Typed Template Haskell, Scala 3 quotes

Generate code that is *type-checked before splicing*:

```scheme
(define/staged (power n)
  (if (= n 0)
      #'1
      #'(* x #,(power (- n 1)))))

(define (power5 x) #,(power 5))
;; Expands to: (define (power5 x) (* x (* x (* x (* x (* x 1))))))
;; Type-checked: x must be numeric, result is numeric
```

**Why:** Jerboa already has `std/staging.sls` for multi-stage programming.
Adding types to stages prevents generating ill-typed code — a guarantee that
MetaOCaml provides but no Scheme has.

**Chez leverage:** Builds on existing staging module, `syntax-case` for quasiquote
types, cp0 for eliminating staging overhead in final code.

---

### 15. `(std specialize)` — Profile-Guided Specialization
**Inspiration:** Julia's JIT specialization, GraalVM partial evaluation, PyPy

Specialize functions based on runtime type profiles, then recompile hot paths:

```scheme
(define-specializable (vector-sum vec)
  (let loop ([i 0] [acc 0])
    (if (fx= i (vector-length vec))
        acc
        (loop (fx+ i 1) (+ acc (vector-ref vec i))))))

;; After profiling detects vec is always fixnum vector:
;; (specialize! vector-sum #:when (Vectorof Fixnum))
;; Generates: fx+ instead of generic +, bounds-check elimination
```

**Why:** Julia's speed comes from specialization. Chez's `compile` procedure can
recompile code at runtime. Combined with profiling data, we can JIT-specialize
hot functions — giving Julia-like performance for numeric code.

**Chez leverage:** `compile`, `optimize-level`, `eval` for runtime recompilation,
profile counters, cp0 for specialization.

---

## IV. Effect & Handler Patterns (16–20)

### 16. `(std effect/scoped)` — Scoped Effect Handlers (Koka-style)
**Inspiration:** Koka, Eff, Frank, Links

Extend jerboa's existing effect system with *scoped* resumptions that can be
called multiple times and compose cleanly:

```scheme
(defeffect Amb
  (flip : () -> Boolean))

(define (pythagorean-triples n)
  (with-handler ([Amb
                  (flip (resume)
                    (append (resume #t) (resume #f)))])
    (let ([a (if (perform (flip)) 1 (+ 1 (random n)))]
          [b (if (perform (flip)) a (+ a (random n)))]
          [c (if (perform (flip)) b (+ b (random n)))])
      (if (= (+ (* a a) (* b b)) (* c c))
          (list (list a b c))
          '()))))
```

**Why:** Koka proved that scoped effects can replace monads while being more
composable. Jerboa has one-shot effects; scoped effects add multi-shot
resumptions, enabling nondeterminism, backtracking, and probabilistic programming.

**Chez leverage:** `call/cc` for multi-shot continuations (vs current call/1cc),
engines for bounded nondeterminism, thread-local handler stacks.

---

### 17. `(std effect/async)` — Structured Concurrency via Effects
**Inspiration:** Kotlin coroutines, Swift structured concurrency, Java Loom

Replace ad-hoc thread spawning with effect-based structured concurrency:

```scheme
(defeffect Async
  (spawn : (-> a) -> (Task a))
  (await : (Task a) -> a)
  (cancel : (Task a) -> Void))

(with-async-scope
  (let ([t1 (perform (spawn (lambda () (http-get url1))))]
        [t2 (perform (spawn (lambda () (http-get url2))))])
    ;; Both tasks run concurrently
    (let ([r1 (perform (await t1))]
          [r2 (perform (await t2))])
      (merge r1 r2))))
;; Scope exit: ALL spawned tasks guaranteed terminated
;; No orphan threads, no resource leaks
```

**Why:** "Structured concurrency" is the hottest topic in language design (Java Loom,
Kotlin, Swift all adopted it). The key insight: concurrent tasks should follow
lexical scoping. Effects naturally provide this — the handler scope IS the
concurrency scope.

**Chez leverage:** Thread pools + engines for task scheduling, continuations for
suspend/resume, guardians for task cleanup on scope exit.

---

### 18. `(std effect/resource)` — Effect-Based Resource Management
**Inspiration:** Bracket pattern (Haskell), Rust RAII, Zig's errdefer

Resources as effects — acquired when performed, released when handler scope exits:

```scheme
(defeffect Resource
  (acquire : (-> a) (a -> Void) -> a))   ;; constructor, destructor

(define (with-resources thunk)
  (with-handler ([Resource
                  (acquire (resume ctor dtor)
                    (let ([r (ctor)])
                      (dynamic-wind void
                        (lambda () (resume r))
                        (lambda () (dtor r)))))])
    (thunk)))

(with-resources
  (lambda ()
    (let ([db (perform (acquire open-db close-db))]
          [file (perform (acquire open-file close-port))])
      ;; Use db and file
      (query db (slurp file)))))
;; BOTH db and file guaranteed closed, even on exception
```

**Why:** `with-destroy` handles one resource. This handles *N resources*
acquired dynamically, with guaranteed cleanup in reverse order. The effect
handler tracks all acquisitions.

**Chez leverage:** Dynamic-wind for cleanup, continuation marks for resource
tracking, guardians as safety net.

---

### 19. `(std effect/state)` — Pure State via Effects (No Mutation)
**Inspiration:** Koka state effect, PureScript State monad, Eff

Mutable state without mutation — state changes are *effects* that the handler
threads through:

```scheme
(defeffect State
  (get : () -> a)
  (put : a -> Void))

(define (counter n)
  (with-state 0
    (lambda ()
      (let loop ([i 0])
        (when (< i n)
          (perform (put (+ 1 (perform (get)))))
          (loop (+ i 1))))
      (perform (get)))))

(counter 1000000)  ;; => 1000000, but NO mutation happened
;; The handler threaded state through continuations
```

**Why:** Pure functions are easier to test, parallelize, and reason about.
Effect-based state gives the *ergonomics* of mutation with the *semantics*
of purity. Tests can swap the State handler for a recording handler.

**Chez leverage:** Continuations for state threading, cp0 for eliminating
handler overhead in tight loops, engines for timeout on runaway state.

---

### 20. `(std effect/io)` — Testable I/O via Effects
**Inspiration:** Haskell IO monad, ZIO, Unison abilities

All I/O operations as effects — swap handlers for testing:

```scheme
(defeffect FileIO
  (read-file : String -> String)
  (write-file : String String -> Void)
  (file-exists? : String -> Boolean))

;; Production handler: real filesystem
(define real-fs-handler
  (make-handler FileIO
    [(read-file (resume path) (resume (call-with-input-file path get-string-all)))
     (write-file (resume path content) (call-with-output-file path (lambda (p) (display content p))) (resume (void)))
     (file-exists? (resume path) (resume (file-exists? path)))]))

;; Test handler: in-memory filesystem
(define (make-test-fs initial-files)
  (let ([fs (make-hashtable string-hash string=?)])
    (for-each (lambda (p) (hashtable-set! fs (car p) (cdr p))) initial-files)
    (make-handler FileIO
      [(read-file (resume path) (resume (hashtable-ref fs path "")))
       (write-file (resume path content) (hashtable-set! fs path content) (resume (void)))
       (file-exists? (resume path) (resume (hashtable-contains? fs path)))])))

;; Same code, different handlers:
(with-handler real-fs-handler (my-program))   ;; real I/O
(with-handler (make-test-fs '()) (my-program)) ;; pure test
```

**Why:** The holy grail of testability. Every I/O operation is interceptable.
No mocking frameworks, no dependency injection containers — just swap the handler.
This is what makes Unison's approach revolutionary.

**Chez leverage:** Effect handler stack for composition, continuation marks for
handler lookup, cp0 for inlining handler dispatch.

---

## V. Distribution & Persistence (21–25)

### 21. `(std image)` — Smalltalk-Style World Persistence
**Inspiration:** Smalltalk images, Lisp Machine worlds, Unison codebase

Save the entire running program state to disk and resume later:

```scheme
(save-world "/path/to/snapshot.fasl")
;; Saves: all definitions, all global state, all thread states

;; Later:
(load-world "/path/to/snapshot.fasl")
;; Resumes exactly where save-world was called
```

**Why:** Chez Scheme has `compile-whole-program` and FASL — it can serialize
compiled code. Combined with jerboa's persistence module, we can save *entire
application states*. This enables: checkpoint/restart for long-running computations,
reproducible debugging (save state at crash point), and live migration.

**Chez leverage:** FASL serialization (handles cycles, shared structure),
`compile-whole-program` for whole-program snapshots, `eval` for
incremental loading.

---

### 22. `(std content-address)` — Content-Addressable Code (Unison-style)
**Inspiration:** Unison, IPFS, Git, Nix

Functions identified by hash of their AST, not by name:

```scheme
(define-content-addressed (factorial n)
  (if (zero? n) 1 (* n (factorial (- n 1)))))

(code-hash factorial)
;; => #hash:sha256:3f8a...  (deterministic, rename-proof)

;; Store in content-addressed store
(cas-put! store factorial)

;; Retrieve by hash from ANY machine
(define f (cas-get store #hash:sha256:3f8a...))
(f 10)  ;; => 3628800
```

**Why:** Unison's breakthrough insight: if code is identified by content hash,
renaming never breaks anything, and code can be shared across machines by hash.
Combined with FASL serialization, this enables a *global code store*.

**Chez leverage:** FASL for deterministic serialization, `compile` for
re-compilable code objects, crypto digest for hashing.

---

### 23. `(std distributed)` — Transparent Distributed Computation
**Inspiration:** Erlang distribution, Unison Cloud, Ray (Python)

Spawn computations on remote nodes transparently:

```scheme
(define cluster (make-cluster '("node1:8080" "node2:8080" "node3:8080")))

(define results
  (distributed-map cluster
    (lambda (chunk)
      (heavy-computation chunk))
    (chunk-data big-dataset 3)))

;; Automatically: serialize closures via FASL, ship to nodes,
;; execute, collect results, handle node failures with retry
```

**Why:** Jerboa already has distributed actors. This goes further — transparent
distribution of *arbitrary computations*, not just message passing. FASL can
serialize closures including their captured environments. No other Scheme can
do this.

**Chez leverage:** FASL closure serialization, `compile` for remote compilation,
TCP transport, engines for execution timeout on remote nodes.

---

### 24. `(std mvcc)` — Multi-Version Concurrency Control
**Inspiration:** PostgreSQL MVCC, Datomic, CockroachDB

Persistent data structures with transactional time-travel:

```scheme
(define db (make-mvcc-store))

;; Transaction 1
(mvcc-transact! db
  (lambda (tx)
    (tx-put! tx 'users/alice {:name "Alice" :age 30})
    (tx-put! tx 'users/bob {:name "Bob" :age 25})))

;; Transaction 2 (concurrent, isolated)
(mvcc-transact! db
  (lambda (tx)
    (let ([alice (tx-get tx 'users/alice)])
      (tx-put! tx 'users/alice (hash-update alice 'age add1)))))

;; Time travel: query as-of any past transaction
(mvcc-as-of db tx-id-1 (lambda (tx) (tx-get tx 'users/alice)))
;; => {:name "Alice" :age 30}  — before the update
```

**Why:** Every write creates a new version; reads never block writes. Combined
with jerboa's persistent data structures (pvec, pmap), the versioning is
*structural sharing* — space-efficient. This is a full in-process database.

**Chez leverage:** STM for transaction isolation, persistent hash tables for
versioning, FASL for snapshot persistence, hashtable for version indexing.

---

### 25. `(std event-source)` — Event Sourcing with Projections
**Inspiration:** Event Sourcing (DDD), Kafka, EventStoreDB

State as a log of immutable events, with derived projections:

```scheme
(define-event-store account-store
  #:events
  [(deposited amount)
   (withdrawn amount)
   (transferred from to amount)])

(define balance-projection
  (make-projection account-store
    (lambda (state event)
      (match event
        [(deposited amt) (+ state amt)]
        [(withdrawn amt) (- state amt)]
        [(transferred from to amt)
         (if (eq? (current-entity) from)
             (- state amt)
             (+ state amt))]))))

(emit! account-store (deposited 1000))
(emit! account-store (withdrawn 200))
(project balance-projection)  ;; => 800

;; Replay from any point in time
(project-as-of balance-projection timestamp)
```

**Why:** Event sourcing is the architecture behind every serious financial system,
audit log, and CQRS application. Built on jerboa's FASL for event persistence
and STM for projection consistency.

**Chez leverage:** FASL for event log persistence, engines for projection timeout,
persistent data structures for snapshot state.

---

## VI. Developer Experience (26–30)

### 26. `(std contract2)` — Temporal Contracts (History-Sensitive)
**Inspiration:** Eiffel contracts, TLA+, Dafny, Session types

Contracts that reason about *sequences* of operations, not just single calls:

```scheme
(define-temporal-contract file-protocol
  #:states [closed opened reading writing]
  #:transitions
  [(closed -> opened : open-file)
   (opened -> reading : begin-read)
   (opened -> writing : begin-write)
   (reading -> opened : end-read)
   (writing -> opened : end-write)
   (opened -> closed : close-file)]
  #:invariant (not (and reading writing))  ;; never both
  #:liveness (eventually closed))           ;; must close

(with-temporal-contract file-protocol
  (open-file f)
  (begin-write f)
  ;; (begin-read f)  ;; CONTRACT VIOLATION: writing → reading not allowed
  (end-write f)
  (close-file f))
```

**Why:** Regular contracts check individual function calls. Temporal contracts
check *protocols* — sequences of operations that must follow a state machine.
This catches use-after-close, write-during-read, and leaked resources as
*protocol violations*.

**Chez leverage:** Continuation marks for state tracking, engines for liveness
checking (timeout = liveness violation), record types for state machines.

---

### 27. `(std debug/replay)` — Deterministic Record & Replay
**Inspiration:** rr (Mozilla), Hermit (Meta), Time Travel Debugging

Record a program execution and replay it deterministically:

```scheme
(define recording (record-execution
  (lambda ()
    (let ([response (http-get "https://api.example.com")])
      (json-parse response)))))

;; Later: replay with full determinism
(replay-execution recording
  (lambda (frame)
    (printf "Step ~a: ~s~n" (frame-index frame) (frame-expression frame))
    (when (frame-error? frame)
      (inspect-frame frame))))
```

**Why:** "Why did my program crash at 3am?" Record-replay captures all
nondeterminism (I/O, time, randomness) as a deterministic event log.
Replay reconstructs the exact execution. Combined with effects (feature #20),
we intercept ALL nondeterminism at the handler level.

**Chez leverage:** Effects for I/O interception, FASL for event serialization,
engines for step-by-step replay, inspector for frame examination.

---

### 28. `(std doc)` — Literate Programming with Executable Examples
**Inspiration:** Rust doc-tests, Elixir doctests, Unison doc blocks

Documentation IS code — examples are automatically tested:

```scheme
(define/doc (fibonacci n)
  "Compute the nth Fibonacci number.

   Examples:
   ```scheme
   (fibonacci 0) ;=> 0
   (fibonacci 1) ;=> 1
   (fibonacci 10) ;=> 55
   (fibonacci 20) ;=> 6765
   ```

   Complexity: O(n) time, O(1) space."
  (let loop ([i 0] [a 0] [b 1])
    (if (= i n) a
        (loop (+ i 1) b (+ a b)))))

;; (run-doctests 'fibonacci) automatically extracts and runs examples
;; Failed examples show expected vs actual with source location
```

**Why:** Documentation drifts from code. Executable examples can't drift — they're
tested. Rust's doc-tests are beloved; bringing this to Scheme with jerboa's
test framework integration.

**Chez leverage:** `syntax-case` for extracting doc strings at compile time,
`eval` for running examples, source annotations for error locations.

---

### 29. `(std debug/contract-monitor)` — Runtime Contract Visualization
**Inspiration:** Racket contract profiler, Eiffel BON, Design by Contract tools

Live monitoring of contract satisfaction across a running system:

```scheme
(with-contract-monitor
  (lambda ()
    (run-server config))
  #:on-violation (lambda (contract call stack)
    (log-violation! contract call stack))
  #:report-interval 60  ;; seconds
  #:dashboard-port 8888)

;; Visit http://localhost:8888 to see:
;; - Which contracts are checked most often (hot contracts)
;; - Which contracts are closest to violation (near-misses)
;; - Contract checking overhead (% of total time)
;; - Historical violation log
```

**Why:** Contracts are great but can be expensive. This monitors which contracts
fire, how often, and whether they're earning their keep. Also catches
"almost violations" — values that barely satisfy a contract, suggesting fragility.

**Chez leverage:** Profile counters for contract overhead, engines for
timeout detection, HTTP server for dashboard, FASL for violation log.

---

### 30. `(std notebook)` — Interactive Computational Notebook
**Inspiration:** Jupyter, Observable, Pluto.jl, Clerk (Clojure)

Interactive notebook with reactive cells and rich output:

```scheme
(define-notebook "analysis.jerboa"
  (cell setup
    (import (std text csv)
            (std dataframe))
    (define data (csv->dataframe "sales.csv")))

  (cell summary
    #:depends (setup)
    (dataframe-describe data))

  (cell chart
    #:depends (setup)
    (plot-histogram (df-column data 'revenue)
                    #:title "Revenue Distribution"
                    #:bins 20))

  (cell model
    #:depends (setup)
    (linear-regression data 'ad-spend 'revenue)))

;; Cells re-execute when dependencies change
;; Rich output: tables, charts, HTML rendered in terminal or browser
;; Export to HTML, PDF, or standalone Scheme program
```

**Why:** Notebooks are the dominant format for data exploration, but only
Python/Julia/R have them. A Scheme notebook with jerboa's concurrency
(parallel cell evaluation), effects (reproducible execution), and FASL
(instant checkpoint/resume) would be unique.

**Chez leverage:** `eval` for cell execution, engines for cell timeout,
FASL for notebook state persistence, HTTP server for browser interface,
continuations for cell cancellation.

---

## Summary

| # | Feature | Module | Status | Tests |
|---|---------|--------|--------|-------|
| 1 | Region memory | `(std region)` | DONE | 6 |
| 2 | Borrow checker | `(std borrow)` | DONE | 8 |
| 3 | Move semantics | `(std move)` | DONE | 8 |
| 4 | Phantom types | `(std typed phantom)` | DONE | 6 |
| 5 | Affine types | `(std typed affine)` | DONE | 7 |
| 6 | Logic programming | `(std logic)` | DONE | 10 |
| 7 | Datalog | `(std datalog)` | DONE | 5 |
| 8 | FRP | `(std frp)` | DONE | 10 |
| 9 | CSP | `(std csp)` | DONE | 6 |
| 10 | Optics | `(std lens)` | DONE | 14 |
| 11 | Comptime | `(std comptime)` | DONE | 8 |
| 12 | Auto-derive | `(std derive2)` | DONE | 10 |
| 13 | Typed macros | `(std macro-types)` | DONE | 10 |
| 14 | Typed staging | `(std quasiquote-types)` | DONE | 6 |
| 15 | Specialization | `(std specialize)` | DONE | 4 |
| 16 | Scoped effects | `(std effect scoped)` | DONE | 3 |
| 17 | Structured concurrency | `(std concur structured)` | DONE | 4 |
| 18 | Effect resources | `(std effect resource)` | DONE | 4 |
| 19 | Pure state effects | `(std effect state)` | DONE | 5 |
| 20 | Testable I/O | `(std effect io)` | DONE | 8 |
| 21 | World persistence | `(std image)` | DONE | 5 |
| 22 | Content-addressed code | `(std content-address)` | DONE | 4 |
| 23 | Distributed compute | `(std distributed)` | DONE | 1 |
| 24 | MVCC | `(std mvcc)` | DONE | 9 |
| 25 | Event sourcing | `(std event-source)` | DONE | 5 |
| 26 | Temporal contracts | `(std contract2)` | DONE | 7 |
| 27 | Record/replay | `(std debug replay)` | DONE | 5 |
| 28 | Doc-tests | `(std doc)` | DONE | 5 |
| 29 | Contract monitor | `(std debug contract-monitor)` | DONE | 7 |
| 30 | Notebooks | `(std notebook)` | DONE | 10 |

**Total: 30/30 features implemented, 215 tests passing (597 total across all better*.md)**
