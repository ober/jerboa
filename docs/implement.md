# Jerboa Implementation Plan: Phase 3 — Production Excellence

## Status: COMPLETE ✓

All Phase 3 sub-phases have been implemented and pushed (2026-03-11):

| Phase | Libraries | Tests | Commit |
|-------|-----------|-------|--------|
| 3a: Observability | 5 | 131 | `cf41c35` |
| 3b: Advanced Networking | 5 | 129 | `197ba30` |
| 3c: Build & Package Tooling | 5 | 119 | `4e513a9` |
| 3d: Language Extensions | 5 | 158 | `644a501` |
| 3e: WASM Target | 3 | 100 | `9b8b16a` |
| **Total** | **23** | **637** | |

---

## Phase 2 (Previous) — The Superior Scheme: COMPLETE ✓

All Phase 2 sub-phases were implemented and pushed (2026-03-11):

| Phase | Libraries | Tests | Commit |
|-------|-----------|-------|--------|
| 2a: Foundations | 7 | 111 | `316cb5e` |
| 2b: Performance | 6 | 101 | `691e709` |
| 2c: Type System | 4 | 111 | `4e99988` |
| 2d: Systems & Distributed | 6 | 105 | `53794bb` |
| 2e: Ecosystem | 5 | 113 | `e1a0a5e` |
| **Total** | **28** | **541** | |

---

## Where We Are (After Phase 3)

Jerboa now has 110+ modules, 1,178+ tests, and covers:

**Phase 2 additions**: PGO, devirtualization, compile-time regex, continuation mark optimization, GADTs, type classes, linear types, effect typing, M:N scheduler, async streams, Raft consensus, zero-copy networking, process supervision, connection pooling, property-based testing, doc generator, S-Expr config, gRPC, sorted maps, persistent vectors, persistent hash maps, channel select, error messages, derive system, memory-mapped I/O, REPL enhancements.

**Phase 3 additions**:
- **Observability**: structured logging, Prometheus metrics, distributed tracing, health checks, circuit breakers
- **Advanced Networking**: WebSocket (RFC 6455), HTTP/2 framing + HPACK, DNS wire format, rate limiting, HTTP router
- **Build & Package**: semantic versioning + dep resolver, lockfiles, hot code reload, sandboxed eval, cross-compilation config
- **Language Extensions**: SQL-like query DSL, data schema validation, data pipeline DSL, term rewriting, source linting
- **WASM Target**: binary format (LEB128, IEEE 754), Scheme→WASM compiler (i32 subset), stack-based interpreter

The original Phase 2 plan identified 25 additions; those are now complete. Phase 3 added 23 more libraries to cover the "production excellence" gap — the tooling, observability, and interoperability needed to deploy Jerboa in real systems.

---

## Phase 2 Plan Details

The following tracks were the Phase 2 design document (now fully implemented):

---

## Track 1: Compiler Infrastructure — The Performance Moat

Chez Scheme has the best optimizing compiler in the Lisp world. Jerboa should be the language that gives users direct access to that power. No other Scheme exposes compile-time optimization hooks this way.

### 1.1 Profile-Guided Optimization (PGO)

Record type feedback from production runs, feed it back to the compiler.

**What Chez gives us**: `cp0` (copy propagation pass 0) already does aggressive inlining and constant folding. With type profiles, we can tell it which branches to favor.

```scheme
;; Instrument: record which types flow through each call site
(jerboa build myapp.ss --profile)
./myapp --workload production < data.txt
;; Produces myapp.profile — type histograms per call site

;; Optimize: use the profile to specialize
(jerboa build myapp.ss --pgo myapp.profile -o myapp-fast)
;; Now (+ x y) at line 47 emits fx+ because the profile shows x,y are always fixnums
```

**Implementation**:
- `lib/std/dev/pgo.sls` — instrumentation macros that wrap call sites with type counters
- A `define-syntax` transformer that reads profile data at compile time and emits specialized code paths
- Integration with `(jerboa build)`: `--profile` flag instruments, `--pgo` flag applies
- Store profiles as FASL files (native Chez serialization, fast to read)

**Why this is unique**: No Scheme, no Lisp, no ML has PGO. Only C/C++ (GCC/LLVM), Go, and Rust (via LLVM) have it. Jerboa would be the first functional language with PGO.

**LOC**: ~500

### 1.2 Whole-Program Devirtualization

When the compiler can see all implementations of a method, replace dynamic dispatch with a `cond` on the type.

```scheme
;; Before: runtime hashtable lookup
({area} shape)  ;; → find-method → eq-hashtable-ref → call

;; After (when only circle, rect, triangle implement area):
(cond
  [(circle? shape) (circle-area shape)]    ;; native record predicate, inlineable
  [(rect? shape) (rect-area shape)]
  [(triangle? shape) (triangle-area shape)]
  [else (error 'area "no method" shape)])
```

**Implementation**:
- Collect all `bind-method!` calls during WPO's whole-program analysis
- For each method, if the set of implementing types is closed, emit a `cond` dispatch
- Chez's cp0 can then inline the accessor bodies if they're small
- Result: method call → record predicate check → inlined body. Two instructions.

**Why this matters**: This is the optimization that makes Java's HotSpot fast (speculative devirtualization). Jerboa can do it statically at compile time because WPO sees the whole program.

**LOC**: ~400

### 1.3 Compile-Time Partial Evaluation

Go beyond macros — let the compiler evaluate any pure expression at compile time.

```scheme
(define-ct (fib n)
  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))

(define answer (fib 30))
;; At compile time: evaluates to 832040
;; At runtime: (define answer 832040) — zero-cost constant
```

**Implementation**:
- Extend `(std staging)` with a binding-time analysis: classify expressions as static (known at compile time) or dynamic
- Static expressions are evaluated by the macro expander via `eval`
- Hybrid: partially evaluate a function, leaving dynamic parts as residual code
- Guard: pure functions only (no mutation, no I/O)

**What this enables**:
- Compile-time regex → DFA conversion (specialized matcher, no regex engine at runtime)
- Compile-time JSON schema → specialized parser
- Compile-time SQL query → optimized access plan
- Compile-time protocol buffer → serializer/deserializer

**LOC**: ~600

### 1.4 Continuation Mark Optimization

Chez's `call/1cc` is fast but not free. For the common case where an effect handler resumes exactly once (async/await, state, exceptions), eliminate the continuation capture entirely.

**Implementation**:
- Extend `with-handler` with a static analysis: if the handler's `resume` is called exactly once and is in tail position, the handler is "linear"
- Linear handlers compile to a direct call (no continuation capture)
- This makes algebraic effects zero-cost for the 90% case

```scheme
;; The State effect handler is linear — get/put always resume once
(with-handler ([State
                (get (k) (resume k current-state))
                (put (v k) (set! current-state v) (resume k (void)))])
  body)

;; Compiles to (approximately):
(let ([current-state init])
  (fluid-let ([*state-get* (lambda () current-state)]
              [*state-put* (lambda (v) (set! current-state v))])
    body))
;; No call/1cc at all!
```

**LOC**: ~350

---

## Track 2: Type System — From Gradual to Powerful

The existing type system is annotations-as-assertions. That's step 1. Step 2 is making the type system powerful enough that typed Jerboa code runs measurably faster than untyped code.

### 2.1 Algebraic Data Types with GADT Patterns

Combine sealed struct hierarchies with type-indexed pattern matching. This is the feature that makes Haskell, OCaml, and Rust's type systems so expressive.

```scheme
;; Typed expression language — the type parameter tracks the result type
(deftype (Expr a)
  (IntLit  [val : Fixnum]          : (Expr Fixnum))
  (BoolLit [val : Boolean]         : (Expr Boolean))
  (Add     [l : (Expr Fixnum)]
           [r : (Expr Fixnum)]     : (Expr Fixnum))
  (If      [test : (Expr Boolean)]
           [then : (Expr a)]
           [else : (Expr a)]       : (Expr a))
  (Equal   [l : (Expr Fixnum)]
           [r : (Expr Fixnum)]     : (Expr Boolean)))

;; Type-safe evaluator — the return type matches the GADT index
(define/t (eval-expr [e : (Expr a)]) : a
  (match-type e
    [(IntLit v)      v]              ;; v : Fixnum, return : Fixnum ✓
    [(BoolLit v)     v]              ;; v : Boolean, return : Boolean ✓
    [(Add l r)       (fx+ (eval-expr l) (eval-expr r))]
    [(If test then else)
     (if (eval-expr test) (eval-expr then) (eval-expr else))]
    [(Equal l r)     (fx= (eval-expr l) (eval-expr r))]))
```

**Implementation**:
- `deftype` macro generates sealed record types with an extra phantom type parameter tracked at compile time
- `match-type` refines the phantom type in each branch, enabling type-directed code generation
- Runtime representation: standard records (no type parameter at runtime — fully erased)
- This is *the* feature for writing interpreters, compilers, and DSLs in Jerboa

**LOC**: ~700

### 2.2 Type Classes / Protocols

Haskell's type classes, but simpler. Define a set of operations a type must support, then write generic code against the protocol.

```scheme
(defprotocol Printable
  (to-string [self] : String))

(defprotocol Hashable
  (hash-code [self] : Fixnum))

(defprotocol (Functor f)
  (fmap [fn : (-> a b)] [fa : (f a)] : (f b)))

;; Implement for specific types
(implement Printable point
  (to-string [self] (format "(~a, ~a)" (point-x self) (point-y self))))

(implement (Functor list)
  (fmap [fn lst] (map fn lst)))

;; Generic code — works for any Printable
(define/t (show-all [xs : (List (Printable a))]) : (List String)
  (map to-string xs))
```

**Implementation**:
- `defprotocol` generates a vtable struct per protocol
- `implement` registers a vtable instance in a compile-time registry
- At call sites where the concrete type is known → direct call (no vtable indirection)
- At call sites where the type is abstract → vtable dispatch (one pointer chase)
- Chez cp0 can inline the direct-call case entirely

**Why not just methods?** Methods dispatch on a single argument. Protocols can dispatch on multiple type parameters (`Functor f` abstracts over the container type). This is what makes generic programming work.

**LOC**: ~600

### 2.3 Linear Types for Resource Safety

Mark values that must be used exactly once. Prevents resource leaks at compile time.

```scheme
(define/t (open-file [path : String]) : (Linear Port)
  (open-input-file path))

(define/t (read-all [p : (Linear Port)]) : (Values String (Linear Port))
  ;; Must return the port — can't drop it
  (let ([data (get-string-all p)])
    (values data p)))

(define/t (close [p : (Linear Port)]) : Void
  ;; Consumes the port — type system ensures it's not used again
  (close-port p))

;; This is a compile-time error:
(define/t (leak [path : String]) : String
  (let ([p (open-file path)])
    (let-values ([(data _p) (read-all p)])
      data)))  ;; ERROR: linear value _p not consumed
```

**Implementation**:
- Linear types tracked at compile time via the macro expander's environment
- Each linear binding has a "consumed" flag; checked at scope exit
- `values` and `let-values` thread linear bindings through
- In release mode: checks erased (the type system proved correctness)

**LOC**: ~500

### 2.4 Effect Typing — Know What Your Code Does

Annotate functions with the effects they may perform. The compiler warns on unhandled effects.

```scheme
(define/t (fetch-user [id : Fixnum]) : (Eff [IO, Async] User)
  (let ([response (perform (Async await (http-get (format "/users/~a" id))))])
    (json->user (perform (IO read-body response)))))

;; Pure function — the type proves it
(define/t (validate [user : User]) : (Eff [] Boolean)
  (and (string? (user-name user))
       (> (user-age user) 0)))

;; Compiler warns: fetch-user performs IO, Async — but no handler installed
(define (main)
  (fetch-user 42))  ;; WARNING: unhandled effects [IO, Async]
```

**Implementation**:
- Extend the type syntax with `(Eff [effects...] result-type)`
- Effect inference: scan function bodies for `perform` calls, accumulate effect sets
- Handler checking: `with-handler` discharges effects from the body's effect set
- Polymorphic effects: `(define/t (map-eff [f : (-> a (Eff e b))] [xs : (List a)]) : (Eff e (List b)))`

**LOC**: ~500

---

## Track 3: Concurrency — Beyond Erlang

Jerboa already has actors, STM, and structured concurrency. Now make them industrial-strength.

### 3.1 M:N Runtime with Preemptive Scheduling

Currently actors run on OS threads. For 100,000+ concurrent actors, we need lightweight green threads multiplexed onto OS threads — but unlike Gerbil's approach, do it on top of Chez's native thread support.

```scheme
;; Spawn 1,000,000 actors on 8 OS threads
(define pool (make-scheduler #:workers 8))

(for-each
  (lambda (i)
    (spawn-actor pool
      (lambda (msg)
        (match msg
          [('ping sender) (send sender 'pong)]))))
  (iota 1000000))

;; Each actor is ~200 bytes (continuation + mailbox pointer)
;; Total: ~200 MB for 1M actors
```

**Implementation**:
- Extend `(std actor scheduler)` with a timer-interrupt based preemption mechanism
- Use Chez's `timer-interrupt-handler` to yield the current actor after a time slice
- Actor state = saved one-shot continuation (from `call/1cc`) + mailbox ref
- The scheduler dequeues the next ready actor and resumes its continuation
- Work-stealing between worker threads for load balancing

**Key Chez primitives**: `timer-interrupt-handler`, `set-timer`, `call/1cc`, `engine` (Chez's built-in coroutine mechanism — engines are preemptible computations!)

**Chez engines**: Chez has a built-in `make-engine` / `engine-return` / `engine-block` mechanism that provides preemptive, timed evaluation. Each engine gets a fuel count (ticks); when fuel runs out, the engine suspends and returns its continuation. This is *exactly* what we need for actor scheduling:

```scheme
(define (run-actor actor fuel)
  (let ([eng (make-engine (lambda () (actor-body actor)))])
    (eng fuel
      ;; Completed within fuel
      (lambda (remaining-fuel value) (actor-complete! actor value))
      ;; Ran out of fuel — preempted
      (lambda (remaining-engine) (reschedule! actor remaining-engine)))))
```

**Why this is better than goroutines**: Goroutines can't be inspected or migrated. Jerboa actors have typed mailboxes, supervision trees, and can be transparently distributed across nodes.

**LOC**: ~800

### 3.2 Channel Select with Priority and Default

Go's `select` is one of its best features. Jerboa should have it, but better.

```scheme
(select
  ;; Receive from channels with priority (first match wins on tie)
  [(recv ch1) => (lambda (msg) (handle-request msg))]
  [(recv ch2) => (lambda (msg) (handle-event msg))]
  ;; Send to a channel (blocks if full)
  [(send result-ch answer) => (lambda () (log "sent"))]
  ;; Timer
  [(after 5000) => (lambda () (log "timeout"))]
  ;; Default — non-blocking poll
  [default => (lambda () (log "nothing ready"))])
```

**Implementation**:
- `select` macro compiles to a wait on multiple condition variables with a shared "claimed" flag
- When any channel becomes ready, it signals the select's condition variable
- Priority: check channels in order; first ready one wins
- `default`: if no channel is ready, execute immediately (non-blocking)
- `after`: register a timer with the event loop; fires if no channel fires first

**Integration with actors**: `receive` in an actor body becomes syntactic sugar for `select` on the actor's mailbox.

**LOC**: ~400

### 3.3 Async Streams

Lazy sequences that produce values asynchronously. The marriage of `(std seq)` and `(std async)`.

```scheme
;; An async stream of lines from a network connection
(define (line-stream conn)
  (async-generate
    (lambda (yield)
      (let loop ()
        (let ([line (await (tcp-read-line conn))])
          (unless (eof-object? line)
            (yield line)
            (loop)))))))

;; Process with familiar sequence operations — but each step may suspend
(async-for-each
  (lambda (line)
    (await (process-line line)))
  (async-filter
    (lambda (line) (string-prefix? "DATA:" line))
    (line-stream connection)))
```

**Implementation**:
- `async-generate` creates a producer that yields values via one-shot continuation
- `async-for-each`, `async-map`, `async-filter` — standard operations that `await` between elements
- Back-pressure: the producer suspends when the consumer isn't ready
- Cancellation: dropping the stream reference triggers cleanup via guardian

**LOC**: ~450

### 3.4 Distributed Consensus (Raft)

CRDTs give eventual consistency. For strong consistency, implement Raft.

```scheme
(define cluster (raft-cluster
  #:nodes '("node1:9001" "node2:9001" "node3:9001")
  #:state-machine (lambda (state command)
                    (match command
                      [('set key val) (hash-set state key val)]
                      [('get key) (values state (hash-ref state key))]))))

;; Strongly consistent reads and writes
(raft-apply! cluster '(set "user:1" "Alice"))   ;; replicated to majority
(raft-query cluster '(get "user:1"))             ;; reads from leader → "Alice"
```

**Implementation**:
- Build on `(std actor transport)` for RPC and `(std actor cluster)` for node management
- Leader election, log replication, and safety per the Raft paper
- State machine interface: user provides a pure function `(state, command) → (state, response)`
- Snapshotting for log compaction
- Joint consensus for cluster membership changes

**LOC**: ~1200

---

## Track 4: Metaprogramming — The Unfair Advantage

Scheme's macro system is its superpower. Jerboa should push it further than any language has gone.

### 4.1 Syntax-Level Computation (Typed Macros)

Macros that carry type information through the expansion. The macro system becomes a type-level programming language.

```scheme
;; Type-level natural numbers
(define-type-syntax Zero)
(define-type-syntax (Succ n))

;; Type-safe heterogeneous list indexed by length
(define-syntax HList
  (syntax-rules ()
    [(_ ()) '()]
    [(_ (t . ts)) (cons t (HList ts))]))

;; Type-safe vector access — out-of-bounds is a compile-time error
(define-syntax vec-ref/safe
  (lambda (stx)
    (syntax-case stx ()
      [(_ vec idx)
       (let ([len (syntax-local-value #'vec 'vector-length)]
             [i (syntax->datum #'idx)])
         (when (>= i len)
           (syntax-error stx "index out of bounds"))
         #'(vector-ref vec idx))])))
```

**Implementation**:
- Extend the macro expander environment with compile-time value bindings
- `syntax-local-value` retrieves compile-time metadata for a binding
- `define-for-syntax` binds values available during macro expansion
- Type-level computation happens entirely at compile time — zero runtime cost

**LOC**: ~500

### 4.2 Declarative Derive System

Automatically generate implementations from struct definitions. Like Rust's `#[derive]` or Haskell's `deriving`.

```scheme
(defstruct point (x y)
  #:derive (equal hash print json serializable))

;; Auto-generates:
;; - (point=? a b) — structural equality
;; - (point-hash p) — consistent hash code
;; - Custom print method: #<point x: 3 y: 4>
;; - (point->json p) → {"x": 3, "y": 4}
;; - (json->point j) → (make-point 3 4)
;; - (point->bytes p) / (bytes->point bv) — binary serialization

;; Users can define custom derivations:
(define-derivation comparable
  (lambda (struct-info)
    (let ([fields (struct-info-fields struct-info)])
      #`(define (#,(format-id 'compare (symbol->string (struct-info-name struct-info)))
                 a b)
          (let loop ([fs '#,fields])
            (if (null? fs) 0
                (let ([cmp (compare (field-ref a (car fs))
                                    (field-ref b (car fs)))])
                  (if (zero? cmp) (loop (cdr fs)) cmp))))))))
```

**Implementation**:
- Extend `defstruct` to accept `#:derive` clause
- Each derivation is a macro that receives struct metadata (name, fields, types, parent) and produces definitions
- Built-in derivations: `equal`, `hash`, `print`, `json`, `serializable`, `comparable`, `copy`, `builder`
- User-extensible via `define-derivation`

**LOC**: ~700

### 4.3 Compile-Time Regular Expressions

Compile regex patterns to DFA state machines at compile time. No regex engine overhead at runtime.

```scheme
(define-regex email-pattern
  "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$")

;; At compile time: parses regex, builds NFA, converts to DFA, generates code
;; At runtime: a direct state machine — no interpretation

(email-pattern "user@example.com")   ;; => #t
(email-pattern "invalid")            ;; => #f

;; With capture groups
(define-regex url-pattern
  "^(https?)://([^/]+)(/.*)?$"
  #:captures (scheme host path))

(url-pattern "https://example.com/api")
;; => #<match scheme: "https" host: "example.com" path: "/api">
```

**Implementation**:
- Regex parser → NFA → DFA (subset construction) → code generator, all at compile time
- Code generator emits a `case`-based state machine that Chez compiles to a jump table
- Capture groups track start/end positions during the DFA walk
- Fallback to PCRE2 for features DFA can't handle (backreferences, lookahead)

**Why faster than PCRE2**: No function call overhead per character. The DFA is inlined code. For simple patterns, 5-10x faster than interpreted regex.

**LOC**: ~800

---

## Track 5: Data & Collections — The Clojure Playbook

Clojure proved that immutable persistent data structures can be the default for a practical language. Jerboa should have the best persistent data structures of any Scheme.

### 5.1 Persistent Vectors (HAMT-Based)

Immutable vectors with O(log32 n) ≈ O(1) access, update, and append. 32-way branching trie.

```scheme
(define v (persistent-vector 1 2 3 4 5))

(persistent-vector-ref v 2)        ;; => 3, O(~1)
(define v2 (persistent-vector-set v 2 99))   ;; => [1 2 99 4 5], O(~1)
(persistent-vector-ref v 2)        ;; => 3 (original unchanged)

(define v3 (persistent-vector-append v 6))   ;; => [1 2 3 4 5 6]

;; Transient for batch mutation (like Clojure)
(define v4 (persistent!
  (let ([t (transient v)])
    (transient-set! t 0 100)
    (transient-set! t 1 200)
    (transient-append! t 999)
    t)))
```

**Implementation**:
- 32-way branching trie (5 bits per level, max 7 levels for 2^35 elements)
- Path copying on update (structural sharing)
- Tail optimization: last chunk stored separately for O(1) append
- Transient mode: mutable operations on a thread-owned copy, then freeze

**Why this matters**: Persistent vectors are thread-safe by construction. No locks, no copying, no races. Combined with STM, this gives Clojure-style concurrency without the JVM.

**LOC**: ~600

### 5.2 Persistent Hash Maps (CHAMP)

Compressed Hash Array Mapped Trie — the state of the art for immutable hash maps.

```scheme
(define m (persistent-map 'a 1 'b 2 'c 3))

(persistent-map-ref m 'b)             ;; => 2
(define m2 (persistent-map-set m 'd 4))  ;; => {a:1 b:2 c:3 d:4}
(persistent-map-ref m 'd)             ;; => error (original unchanged)

;; Efficient merge
(persistent-map-merge m m2 (lambda (k v1 v2) v2))

;; Works with STM
(define state (make-tvar (persistent-map)))
(atomically
  (tvar-write! state
    (persistent-map-set (tvar-read state) 'counter
      (+ 1 (persistent-map-ref (tvar-read state) 'counter 0)))))
```

**Implementation**:
- CHAMP trie with bitmap-indexed nodes (Steindorfer & Vinju 2015)
- ~2x more memory-efficient than HAMT due to compressed node layout
- Equality checking in O(1) for identical tries (pointer equality)
- Efficient diff: `persistent-map-diff` walks only differing subtrees

**LOC**: ~700

### 5.3 Immutable Sorted Maps (Red-Black Trees)

For ordered data — range queries, min/max, ordered iteration.

```scheme
(define s (sorted-map < 3 "c" 1 "a" 5 "e" 2 "b"))

(sorted-map-min s)                    ;; => (1 . "a")
(sorted-map-max s)                    ;; => (5 . "e")
(sorted-map-range s 2 4)              ;; => ((2 . "b") (3 . "c"))
(sorted-map-ref s 3)                  ;; => "c"

;; Persistent — all operations return new trees
(define s2 (sorted-map-set s 4 "d"))
```

**Implementation**:
- Okasaki-style persistent red-black trees
- O(log n) insert, delete, lookup
- O(log n) split and join for efficient range operations
- Integration with `(std seq)`: `sorted-map->lazy-seq` for lazy ordered traversal

**LOC**: ~500

---

## Track 6: Systems Programming — The Rust Alternative

Make Jerboa the best Scheme for writing the kind of software people currently write in Rust or Go.

### 6.1 Memory-Mapped I/O

Direct access to file contents as bytevectors without copying.

```scheme
(define mapping (mmap "large-file.dat" #:mode 'read-only))

;; Access bytes directly — no read() syscall, no buffer copy
(bytevector-u64-ref mapping 0 (endianness little))

;; Memory-mapped writes
(define writable (mmap "output.dat" #:mode 'read-write #:size (* 1024 1024)))
(bytevector-u64-set! writable 0 42 (endianness little))
(msync writable)  ;; flush to disk

;; Auto-cleanup
(munmap mapping)
```

**Implementation**:
- FFI wrapper around `mmap`/`munmap`/`msync`/`madvise`
- Return a Chez bytevector backed by the mapped region (via `foreign-ref` on the mmap pointer)
- Guardian-based cleanup for GC safety
- `madvise` integration: `sequential`, `random`, `willneed`, `dontneed`

**LOC**: ~300

### 6.2 Zero-Copy Networking

Avoid copies between kernel and user space for high-throughput networking.

```scheme
;; sendfile — kernel-to-kernel copy, zero user-space involvement
(define (serve-static-file conn path)
  (let ([fd (open-fd path O_RDONLY)]
        [size (file-size path)])
    (sendfile (connection-fd conn) fd 0 size)
    (close-fd fd)))

;; splice — pipe data between fds without user-space copy
(define (proxy src-conn dst-conn)
  (let ([pipe-fds (pipe)])
    (let loop ()
      (let ([n (splice (connection-fd src-conn) (pipe-read pipe-fds) 65536)])
        (when (> n 0)
          (splice (pipe-write pipe-fds) (connection-fd dst-conn) n)
          (loop))))))

;; io_uring scatter-gather I/O
(define (batch-read ring fds buffers)
  (for-each
    (lambda (fd buf)
      (io-uring-prep-read ring fd buf (bytevector-length buf) 0))
    fds buffers)
  (io-uring-submit ring)
  (io-uring-wait ring (length fds)))
```

**Implementation**:
- FFI wrappers for `sendfile`, `splice`, `tee`, `vmsplice`
- Integration with `(std os iouring)` for batched scatter-gather
- Buffer pool for recycling bytevectors (avoid GC pressure)

**LOC**: ~400

### 6.3 Process Supervision and Signals

Production-grade process management.

```scheme
(define (main)
  (install-signal-handlers!
    [SIGTERM (lambda () (graceful-shutdown!))]
    [SIGHUP  (lambda () (reload-config!))]
    [SIGUSR1 (lambda () (dump-stats!))])

  ;; Supervised child processes
  (with-process-group
    (spawn-process "worker" "./worker" '("--port" "8001")
      #:restart 'on-failure
      #:max-restarts 5
      #:backoff 'exponential)
    (spawn-process "logger" "./logger" '()
      #:restart 'always)))
```

**Implementation**:
- Extend `(std os signal)` with proper signal handling (signalfd or self-pipe trick)
- Process group management via `setpgid`/`waitpid`
- Supervised processes with restart policies (like an OS-level supervisor tree)
- PID file management, daemon mode

**LOC**: ~500

### 6.4 Async DNS and Connection Pooling

Essential for any network service.

```scheme
;; Non-blocking DNS resolution
(define ips (await (dns-resolve "example.com" #:type 'A)))

;; Connection pool with health checks
(define pool (make-connection-pool
  #:create (lambda () (tcp-connect "db.internal" 5432))
  #:destroy close-port
  #:validate (lambda (conn) (db-ping conn))
  #:max-size 20
  #:max-idle-time 300))

(with-pooled-connection pool
  (lambda (conn)
    (db-query conn "SELECT * FROM users")))
```

**Implementation**:
- `c-ares` FFI wrapper for async DNS (or `getaddrinfo_a` on glibc)
- Generic connection pool with idle timeout, max size, health checks
- Integration with `(std async)` for non-blocking acquire/release
- Exponential backoff on connection failures

**LOC**: ~600

---

## Track 7: Developer Experience — What Makes People Stay

### 7.1 Interactive REPL with Rich Features

The REPL should be the best in any Scheme.

```
jerboa> (defstruct point (x y))
;; point, make-point, point?, point-x, point-y defined

jerboa> (make-point 3 4)
#<point x: 3 y: 4>          ;; auto-print with field names

jerboa> ,type (make-point 3 4)
(Struct point (x: Any) (y: Any))

jerboa> ,time (fib 35)
;; 9227465
;; 0.234s elapsed, 0.001s GC, 48 MB allocated

jerboa> ,doc hash-ref
;; (hash-ref ht key [default]) → any
;; Look up key in hash table. If not found and default given,
;; return default. Otherwise, raise an error.

jerboa> ,apropos channel
;; make-channel, channel-put, channel-get, channel-select,
;; channel-close, channel?, async-channel, ...

jerboa> ,trace (fibonacci 5)
;; (fibonacci 5)
;;   (fibonacci 4)
;;     (fibonacci 3)
;;       (fibonacci 2) → 1
;;       (fibonacci 1) → 1
;;     → 2
;;     (fibonacci 2) → 1
;;   → 3
;;   (fibonacci 3) ...
;; → 5

jerboa> ,profile (run-benchmark)
;; Top 5 hot functions:
;;   1. parse-json        34.2%  (1,234 calls)
;;   2. hash-ref          21.1%  (45,678 calls)
;;   3. string-split       8.3%  (2,345 calls)
;;   ...
```

**Implementation**:
- REPL commands (`,type`, `,time`, `,doc`, `,apropos`, `,trace`, `,profile`, `,expand`)
- Tab completion from imported modules
- Multi-line input with bracket balancing
- History with reverse search
- Colored output (types, values, errors)
- Auto-import: unknown identifier triggers `suggest-imports`

**LOC**: ~800

### 7.2 Error Messages That Don't Suck

The #1 complaint about every Scheme. Fix it.

```scheme
;; Before (stock Chez):
;; Exception: incorrect number of arguments to #<procedure fibonacci>

;; After (Jerboa):
;; error: fibonacci called with 2 arguments, but expects 1
;;
;;   12 | (fibonacci 10 20)
;;      |  ^^^^^^^^^
;;      |  defined at lib/math.ss:5
;;      |  signature: (fibonacci n : Fixnum) → Fixnum
;;
;;   hint: did you mean (fibonacci 10)?

;; Type error:
;; error: type mismatch in argument 1 of string-length
;;
;;   8 | (string-length 42)
;;     |                ^^
;;     |  expected: String
;;     |  got:      Fixnum (42)
;;
;;   hint: use (number->string 42) to convert

;; Unbound identifier:
;; error: unbound identifier 'hassh-ref'
;;
;;   15 | (hassh-ref table key)
;;      |  ^^^^^^^^^
;;      |  did you mean: hash-ref (from (std hash))?
```

**Implementation**:
- Wrap Chez's `condition` system with enhanced formatters
- Source location tracking: store file/line/col in syntax objects through macro expansion
- Levenshtein distance for "did you mean?" suggestions
- Type annotation integration: show expected vs. actual types
- Stack traces with source locations (not just procedure names)

**LOC**: ~600

### 7.3 Documentation Generator

Generate documentation from source code annotations.

```scheme
;; In source:
(def (hash-ref ht key (default (void)))
  "Look up KEY in hash table HT.
   If KEY is not found and DEFAULT is provided, return DEFAULT.
   Otherwise, raise an error.

   Examples:
     (hash-ref (hash (a 1) (b 2)) 'a) => 1
     (hash-ref (hash) 'missing 'default) => default

   See also: hash-set, hash-has-key?, hash-update"
  ...)

;; Generate:
;; $ jerboa doc --format html lib/
;; $ jerboa doc --format markdown lib/std/
```

**Implementation**:
- Parse docstrings from `def`, `defstruct`, `defprotocol` forms
- Extract type signatures from `define/t` annotations
- Cross-reference: hyperlink "See also" references
- Output formats: HTML, Markdown, man pages
- Searchable index with symbol categorization

**LOC**: ~700

### 7.4 Test Framework Enhancements

Make `(std test)` competitive with property-based testing frameworks.

```scheme
;; Property-based testing (QuickCheck-style)
(check-property
  "reverse is involutive"
  (forall ([xs (gen:list (gen:integer))])
    (equal? (reverse (reverse xs)) xs)))

(check-property
  "sort produces sorted output"
  (forall ([xs (gen:list (gen:integer))])
    (sorted? <= (sort xs <=))))

;; Generators compose
(define gen:point
  (gen:map make-point (gen:integer) (gen:integer)))

;; Shrinking — on failure, automatically find minimal counterexample
(check-property
  "all points have positive coordinates"  ;; intentionally wrong
  (forall ([p gen:point])
    (and (> (point-x p) 0) (> (point-y p) 0))))
;; FAIL: shrunk to (make-point 0 0)
```

**Implementation**:
- Generators: `gen:integer`, `gen:string`, `gen:list`, `gen:one-of`, `gen:map`, `gen:bind`
- Shrinking: binary search on failing inputs to find minimal counterexample
- Integration with `(std test)`: `check-property` as a new assertion type
- Coverage tracking: instrument tested code, report uncovered branches

**LOC**: ~700

---

## Track 8: Interoperability — Reach Beyond Scheme

### 8.1 WASM Compilation Target

Compile Jerboa programs to WebAssembly for browser and edge deployment.

```bash
$ jerboa build --target wasm myapp.ss -o myapp.wasm
```

**Implementation approach**:
- **Phase 1**: Compile a restricted subset of Jerboa (no continuations, no FFI) to WASM via Chez's code generator or a custom backend
- **Phase 2**: Implement a minimal runtime (GC, basic types) in WAT (WebAssembly text format)
- **Phase 3**: Support full Jerboa by compiling continuations to WASM's exception handling proposal

This is a major undertaking but transformative — Jerboa in the browser, Jerboa on Cloudflare Workers, Jerboa on Fastly Compute.

**LOC**: ~3000 (runtime) + ~2000 (compiler backend) — this is a multi-month project

### 8.2 S-Expression Configuration Language

A safe subset of Jerboa for configuration files. Like Dhall, but with Scheme syntax.

```scheme
;; config.jerboa — no I/O, no mutation, no side effects, terminates
{
  server: {
    host: "0.0.0.0"
    port: 8080
    workers: (* 2 (cpu-count))    ;; computed at load time
    tls: {
      cert: (env "TLS_CERT_PATH")
      key: (env "TLS_KEY_PATH")
    }
  }
  database: {
    url: (string-append "postgres://" (env "DB_HOST") ":5432/myapp")
    pool-size: (max 5 (quotient (cpu-count) 2))
  }
  features: (if (env? "PRODUCTION")
              '(caching rate-limiting metrics)
              '(debug-logging hot-reload))
}
```

**Implementation**:
- Subset of Jerboa: arithmetic, string ops, conditionals, `let`, `env`, `env?`, `cpu-count`
- No: mutation, I/O (except `env`), recursion (total language — always terminates)
- Evaluate using `(std capability)` sandbox with minimal capabilities
- Output: Scheme value (hash table, list, etc.)
- Type-check config against a schema: `(define-config-schema ...)`

**LOC**: ~500

### 8.3 gRPC / Protocol Buffers Support

First-class support for the dominant RPC framework.

```scheme
(define-proto user.proto
  (message User
    (string name  1)
    (int32  age   2)
    (string email 3))

  (service UserService
    (GetUser    (GetUserRequest)    → (User))
    (ListUsers  (ListUsersRequest)  → (stream User))))

;; Client
(define client (grpc-connect "localhost:50051"))
(define user (grpc-call client 'UserService/GetUser
               (make-GetUserRequest #:id 42)))

;; Server
(define-grpc-service UserServiceImpl
  (GetUser (req)
    (db-lookup-user (GetUserRequest-id req)))
  (ListUsers (req)
    (async-generate
      (lambda (yield)
        (for-each yield (db-list-users))))))

(grpc-serve UserServiceImpl #:port 50051)
```

**Implementation**:
- Proto3 parser (text format) → Jerboa struct definitions
- Wire format encoder/decoder (varint, length-delimited, etc.)
- HTTP/2 framing via existing TLS + custom frame parser
- Streaming via async generators from Track 3.3

**LOC**: ~1500

---

## Implementation Order

The tracks are mostly independent and can be worked in parallel. Within each track, items are ordered by dependency.

### Phase 2a: Foundations (High Impact, Moderate Effort)

| # | Item | Track | LOC | Dependencies |
|---|------|-------|-----|-------------|
| 1 | Persistent Vectors | 5.1 | 600 | None |
| 2 | Persistent Hash Maps | 5.2 | 700 | None |
| 3 | Channel Select | 3.2 | 400 | Existing channels |
| 4 | Error Messages | 7.2 | 600 | None |
| 5 | Derive System | 4.2 | 700 | Existing defstruct |
| 6 | Memory-Mapped I/O | 6.1 | 300 | Existing FFI |
| 7 | REPL Enhancements | 7.1 | 800 | None |

**Subtotal**: ~4,100 LOC

### Phase 2b: Performance (The Moat)

| # | Item | Track | LOC | Dependencies |
|---|------|-------|-----|-------------|
| 8 | Continuation Mark Opt | 1.4 | 350 | Existing effects |
| 9 | PGO | 1.1 | 500 | Existing build |
| 10 | Devirtualization | 1.2 | 400 | Existing methods |
| 11 | Compile-Time Regex | 4.3 | 800 | Existing staging |
| 12 | Compile-Time Partial Eval | 1.3 | 600 | Existing staging |

**Subtotal**: ~2,650 LOC

### Phase 2c: Type System (The Differentiator)

| # | Item | Track | LOC | Dependencies |
|---|------|-------|-----|-------------|
| 13 | GADTs | 2.1 | 700 | Existing typed |
| 14 | Type Classes | 2.2 | 600 | Existing typed |
| 15 | Linear Types | 2.3 | 500 | Existing typed |
| 16 | Effect Typing | 2.4 | 500 | Existing effects + typed |

**Subtotal**: ~2,300 LOC

### Phase 2d: Systems & Distributed (The Killer Apps)

| # | Item | Track | LOC | Dependencies |
|---|------|-------|-----|-------------|
| 17 | M:N Scheduler | 3.1 | 800 | Existing actors |
| 18 | Async Streams | 3.3 | 450 | Existing async + seq |
| 19 | Raft Consensus | 3.4 | 1200 | Existing transport |
| 20 | Zero-Copy Networking | 6.2 | 400 | Existing IO |
| 21 | Process Supervision | 6.3 | 500 | Existing signals |
| 22 | Connection Pooling | 6.4 | 600 | Existing async |

**Subtotal**: ~3,950 LOC

### Phase 2e: Ecosystem (Long-term)

| # | Item | Track | LOC | Dependencies |
|---|------|-------|-----|-------------|
| 23 | Test Framework | 7.4 | 700 | Existing test |
| 24 | Doc Generator | 7.3 | 700 | None |
| 25 | S-Expr Config | 8.2 | 500 | Existing capability |
| 26 | gRPC | 8.3 | 1500 | Existing async + FFI |
| 27 | Sorted Maps | 5.3 | 500 | None |
| 28 | WASM Target | 8.1 | 5000 | Everything |

**Subtotal**: ~8,900 LOC (WASM is optional/aspirational)

---

## Total Estimated Code

| Phase | LOC | Modules |
|-------|-----|---------|
| 2a: Foundations | 4,100 | ~10 |
| 2b: Performance | 2,650 | ~6 |
| 2c: Type System | 2,300 | ~5 |
| 2d: Systems | 3,950 | ~8 |
| 2e: Ecosystem | 3,900 (excl. WASM) | ~8 |
| **Total** | **~16,900** | **~37** |

Combined with existing 14,876 lines across 87 modules, Jerboa would be ~31,800 lines across ~124 modules. Still vastly more compact than Racket (~700K LOC), Guile (~300K), or even Gerbil (~80K with Gambit).

---

## Competitive Position After Phase 2

| Feature | Jerboa | Racket | Gerbil | OCaml | Haskell | Rust | Go | Erlang |
|---------|--------|--------|--------|-------|---------|------|----|--------|
| Algebraic effects | **Yes** | No | No | 5.x | Libs | No | No | No |
| GADTs | **Yes** | No | No | **Yes** | **Yes** | No | No | No |
| Type classes | **Yes** | No | No | Modules | **Yes** | Traits | No | No |
| Linear types | **Yes** | No | No | No | Linear H | **Yes** | No | No |
| Effect typing | **Yes** | No | No | 5.x | **Yes** | No | No | No |
| STM | **Yes** | No | No | No | **Yes** | No | No | No |
| Persistent data | **Yes** | No | No | **Yes** | **Yes** | Libs | No | No |
| PGO | **Yes** | No | No | No | No | **Yes** | **Yes** | No |
| Compile-time regex | **Yes** | No | No | No | No | **Yes** | No | No |
| M:N scheduling | **Yes** | No | No | 5.x | Green | No | **Yes** | **Yes** |
| Raft consensus | **Yes** | No | No | No | No | Libs | Libs | No |
| Property testing | **Yes** | No | No | QCheck | QC | proptest | gopter | PropEr |
| Distributed actors | **Yes** | No | Yes | No | Cloud H | No | No | **Yes** |
| Zero-copy FFI | **Yes** | No | Yes | **Yes** | No | **Yes** | CGo | NIF |
| Static binaries | **Yes** | Yes | Yes | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** |
| Macro system | **Yes** | **Yes** | **Yes** | No | TH | proc | No | No |
| Derive/deriving | **Yes** | No | No | ppx | **Yes** | **Yes** | No | No |
| WASM target | Planned | No | No | wasm_of | Asterius | **Yes** | **Yes** | No |

**Unique combination**: No other language has all of: algebraic effects + GADTs + type classes + linear types + STM + persistent data structures + distributed actors + Raft + property testing + PGO + compile-time regex + a macro system. Jerboa would.

---

## The Thesis

Phase 1 proved that Gerbil's ergonomics can run on Chez's compiler without compromise. Phase 2 proves that a macro-based language on a great compiler can rival purpose-built languages at their own game:

- **Haskell's type system**: GADTs, type classes, linear types, effect typing — but with gradual adoption, not all-or-nothing
- **Clojure's data model**: Persistent vectors, maps, sorted maps — but compiled, not JVM-interpreted
- **Erlang's distribution**: Actors, supervision, Raft, CRDTs — but with static binaries and zero-copy FFI
- **Rust's safety**: Linear types, capability security, ownership tracking — but with a GC for the 95% that doesn't need manual memory management
- **Go's tooling**: Fast builds, static binaries, good error messages, batteries included — but with macros and a real type system

The key insight: Chez Scheme's compiler is so good that macro-generated code performs like hand-written C. Every feature in this plan compiles down to efficient native code through Chez's cp0 optimizer, not through interpretation or bytecode. The macro system is the compiler — and it's extensible.

That's the unfair advantage no other approach can replicate.
