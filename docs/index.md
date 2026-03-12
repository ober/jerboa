# Jerboa Documentation Index

Jerboa is a systems programming language built on Chez Scheme, providing Gerbil Scheme
compatibility with additional features: algebraic effects, gradual typing, native binary
compilation, and a full actor/distributed system.

**Current state**: 173 modules, ~35,000 lines, 2,898 tests (Phases 1–3 + Phase 4 complete).

## New Feature Documentation (Phases 1–13)

| Document | Features | Libraries |
|----------|----------|-----------|
| [effects.md](effects.md) | Algebraic effects, one-shot continuations | `(std effect)` |
| [async.md](async.md) | Async I/O, promises, channels | `(std async)` |
| [typing.md](typing.md) | Gradual typing, occurrence types, row polymorphism | `(std typed)`, `(std typed advanced)` |
| [stm.md](stm.md) | Software transactional memory | `(std stm)` |
| [pattern-matching.md](pattern-matching.md) | Sealed hierarchies, active patterns, exhaustive match | `(std match2)` |
| [staging.md](staging.md) | Compile-time computation, code generation | `(std staging)` |
| [actor-model.md](actor-model.md) | Local + distributed actors, supervision, registry | `(std actor)` and sub-libraries |
| [distributed.md](distributed.md) | Transport, cluster, CRDTs | `(std actor transport)`, `(std actor cluster)`, `(std actor crdt)` |
| [ffi.md](ffi.md) | Safe C interop, foreign structs, thread pools | `(std foreign)`, `(std foreign bind)` |
| [devex.md](devex.md) | Time-travel debugger, profiler, hot reload | `(std dev debug)`, `(std dev profile)`, `(std dev reload)` |
| [packages.md](packages.md) | Semver package manager, dependency resolution | `(jerboa pkg)` |
| [capability.md](capability.md) | Object-capability security, sandboxing | `(std capability)` |
| [sequences.md](sequences.md) | Lazy sequences, transducers, parallel collections, data tables | `(std seq)`, `(std table)` |
| [build.md](build.md) | Incremental/parallel build, cross-compilation, static linking | `(jerboa build)`, `(jerboa cache)` |
| [concurrency.md](concurrency.md) | Thread-safety annotations, deadlock detection, resource leaks | `(std concur)` |

## Phase 2 Libraries (2026-03-11)

### Phase 2a: Foundations
- `(std pvec)` — persistent vectors (Clojure-style 32-way HAMT trie)
- `(std pmap)` — persistent hash maps
- `(std select)` — channel select with priority, timeout, and default
- `(std errors)` — structured error hierarchy with typed conditions
- `(std derive)` — automatic derivation of `equal?`, `hash`, `show`, `compare`
- `(std repl)` — interactive REPL with command dispatch and tab completion

### Phase 2b: Performance
- `(std dev partial-eval)` — compile-time partial evaluation (`define-ct`, `ct`, `ct/try`)
- `(std dev pgo)` — profile-guided optimization with type feedback
- `(std dev cont-mark-opt)` — linear handler analysis and optimized `with-linear-handler`
- `(std dev devirt)` — whole-program devirtualization (`defmethod/tracked`, `devirt-call`)
- `(std regex-ct-impl)` — NFA→DFA subset construction pipeline
- `(std regex-ct)` — compile-time regex with `define-regex` and runtime fallback

### Phase 2c: Type System
- `(std typed gadt)` — GADTs as tagged vectors with `define-gadt` and `gadt-match`
- `(std typed typeclass)` — Haskell-style type classes (`define-class`, `define-instance`, `with-class`)
- `(std typed linear)` — linear types with use-once enforcement
- `(std typed effect-typing)` — effect signatures with `typed-with-handler`

### Phase 2d: Systems & Distributed
- `(std sched)` — M:N cooperative scheduler with work queue and OS worker threads
- `(std stream async)` — lazy async streams with backpressure over channels
- `(std raft)` — full Raft consensus (follower/candidate/leader, log replication, heartbeats)
- `(std net zero-copy)` — buffer pool with slice views and reference counting
- `(std proc supervisor)` — OTP-style supervisor (one-for-one, one-for-all, rest-for-one)
- `(std net pool)` — generic connection pool with health checking and timeout

### Phase 2e: Ecosystem
- `(std test framework)` — QuickCheck-style property testing with shrinking and test suites
- `(std doc generator)` — documentation generator producing markdown and HTML
- `(std config)` — S-expression config with schema validation and env variable overrides
- `(std ds sorted-map)` — persistent sorted map (Okasaki red-black tree), O(log n)
- `(std net grpc)` — gRPC-style RPC over TCP with S-expression framing

## Phase 3 Libraries (2026-03-11)

### Phase 3a: Observability
- `(std log)` — structured logging with levels (debug/info/warn/error/fatal), pluggable sinks (console, file, JSON), dynamic `current-logger`, and key/value fields
- `(std metrics)` — Prometheus-compatible metrics: counters, gauges, histograms with configurable buckets, registry, text exposition format
- `(std span)` — distributed tracing with random 64-bit trace/span IDs, parent/child spans, tag/log attachment, `with-span`, HTTP header context propagation
- `(std health)` — health check framework: named checks returning ok/degraded/failing, duration tracking, `run-checks`, `health-status` aggregation, timeout wrapping
- `(std circuit)` — circuit breaker: closed/open/half-open state machine, configurable failure/success thresholds and reset timeout, call stats

### Phase 3b: Advanced Networking
- `(std net websocket)` — RFC 6455 WebSocket: frame encode/decode, FIN/opcodes, 7/16/64-bit payload lengths, XOR masking, handshake accept key
- `(std net http2)` — HTTP/2 framing: 9-byte frame header, all standard frame types, HPACK static table (61 entries), literal header encoding, dynamic context
- `(std net dns)` — DNS wire format (RFC 1035): query encoding, response decoding, label encode/decode, compression pointers, A/AAAA/CNAME/TXT records
- `(std net rate)` — rate limiting: token bucket (refills at rate/sec), sliding window (prunes old timestamps), fixed window (epoch-aligned), thread-safe rate limiter
- `(std net router)` — HTTP request routing: `:param` captures, `*` wildcard, static/parameterized/wildcard priority, method matching, per-route and global middleware

### Phase 3c: Build & Package Tooling
- `(jerboa pkg)` — semantic versioning (`major.minor.patch`), constraint checking (`>=`, `^`, `~`, `=`, `*`), dependency resolution with cycle detection, package manifests
- `(jerboa lock)` — lockfile management: S-expression format, lock entries with content hash, read/write, merge (right-wins), diff (added/removed/changed)
- `(jerboa hot)` — hot code reload: mtime-based file watching, `reloader-check!`, `reloader-reload!`, on-reload/on-error callbacks, `with-reloader` macro
- `(jerboa embed)` — sandboxed evaluation environment: `sandbox-eval`, `sandbox-define!`, `sandbox-ref`, `sandbox-call`, safe exception wrapping, `with-sandbox`
- `(jerboa cross)` — cross-compilation config: OS/arch detection from `(machine-type)`, CC flags (`--target=`, `--sysroot=`), ABI naming, endianness/pointer-size lookup

### Phase 3d: Language Extensions
- `(std query)` — SQL-like query DSL over in-memory collections: `from`, `where`, `select`, `order-by`, `group-by`, `limit`, `offset`, `join`, predicate constructors (`q:=`, `q:like`, `q:between`, etc.)
- `(std schema)` — data schema validation: type validators, combinators (`s:list`, `s:hash`, `s:optional`, `s:enum`, `s:union`, `s:pattern`, `s:min`/`s:max`), path-annotated errors
- `(std pipeline)` — data pipeline DSL: `make-pipeline`, `make-stage`, `pipeline-run`, `pipeline-run-parallel`, `pipe` composition, tap/catch/filter/reduce/timeout stages, per-stage stats
- `(std rewrite)` — term rewriting: pattern variables (`?x`), `pattern-match`, `substitute`, `rewrite-once`, `rewrite` (innermost-first), `rewrite-fixed-point`, `normalize`
- `(std lint)` — source code linting: 9 built-in rules (empty-begin, missing-else, deep-nesting, redefine-builtin, magic-number, etc.), `lint-string`/`lint-form`/`lint-file`, severity levels

### Phase 3e: WASM Target
- `(jerboa wasm format)` — WebAssembly binary format: LEB128 (unsigned/signed), IEEE 754 (f32/f64), string encoding, section/opcode constants, bytevector builder
- `(jerboa wasm codegen)` — Scheme→WASM compiler: compiles pure i32 Scheme subset (define, lambda, let, if, begin, arithmetic, comparisons) to valid WASM binary
- `(jerboa wasm runtime)` — stack-based WASM interpreter: executes i32 arithmetic, comparisons, local.get/set/tee, if/else, function calls, memory, globals, traps

## Phase 4 Libraries (2026-03-11)

### Phase 4a: Core Runtime
- `(std effect deep)` — deep algebraic effect handlers that re-install after each resume, enabling stateful and multi-shot effect semantics
- `(std actor engine)` — engine-pool preemptive actor scheduler using Chez `make-engine`; `make-engine-pool`, `spawn-engine-actor`, `engine-pool-submit!`
- `(std transducer)` — composable, source-independent transducers: `mapping`, `filtering`, `taking`, `dropping`, `flat-mapping`, `deduplicate`, `windowing`; `transduce`, `into`, `sequence`, `rf-cons`, `rf-sum`
- `(std typed env)` — lexically-scoped type environment for static type checker, `type-env-extend`, `type-env-lookup`
- `(std typed infer)` — bidirectional type inference: `infer-type`, `check-type`, `unify-types`, `subtype?`, `with-type-errors-collected`
- `(std error-advice)` — error messages with fix suggestions: `advise-error`, `define-error-advice`, `with-error-advice`

### Phase 4b: Type System and Safety
- `(std typed hkt)` — higher-kinded types: `defprotocol-hkt`, `implement-hkt`, `do/m`, Option/Result/List functor instances
- `(std typed monad)` — State/Reader/Writer monads, `run-state`, `state-get`, `state-put`, `monad-sequence`
- `(std typed refine)` — refinement types: `make-refinement`, `NonNeg`, `Positive`, `NonNull`, `define/r`
- `(std typed solver)` — lightweight constraint solver returning `'satisfied`/`'violated`/`'unknown`
- `(std typed row2)` — open records with `record-extend`, `record-restrict`, `record-merge`, `Row` macro
- `(std typed effects)` — effect typing with `Eff`/`Pure` types, `define/te`, `effect-set-union`
- `(std taint)` — taint tracking: `taint`, `tainted?`, `define-sink`, `html-escape`, `sql-escape`
- `(std capability sandbox)` — capability sandbox: `make-sandbox-policy`, `sandbox-run`, `sandbox-run/timeout`

### Phase 4c: Systems and Performance
- `(std arena)` — bump-pointer arena allocator: `make-arena`, `arena-alloc`, `arena-reset!`, `with-arena`, `arena-checkpoint`
- `(std binary)` — packed binary structs: `define-binary-struct`, `binary-pack`, `binary-unpack`; field types u8/u16/u32/u64/f32/f64/bytes/cstring
- `(std mmap-btree)` — file-backed B+ tree: `open-btree`, `btree-get`, `btree-put!`, `btree-delete!`, `btree-fold`, `btree-range`
- `(std effect multishot)` — nondeterminism via choice-sequence backtracking: `choose`, `all-solutions`, `one-solution`, `amb`
- `(std concur deadlock)` — runtime deadlock detection via wait-for graph: `register-waiting!`, `detect-deadlock`, `deadlock-condition?`
- `(std concur util)` — semaphores, barriers, reader-writer locks, thread pools, futures, latches

### Phase 4d: Developer Experience
- `(std debug timetravel)` — event recorder with replay: `make-recorder`, `record-event!`, `trace-fn`, `with-recording`, `replay-to-step`
- `(std debug flamegraph)` — manual enter/exit profiler: `profiler-enter!`, `profiler-exit!`, `profiler->flamegraph-text`, `profiler-timing-stats`
- `(std proptest)` — property-based testing with shrinking: `gen-integer`, `gen-list`, `defproperty`, `check-property`
- `(std staging2)` — multi-stage programming: `quote-stage`, `define-staged`, `specialize`, `partial-eval`, `constant-fold`, `inline-calls`
- `(std match-syntax)` — AST pattern matching: `syntax-match`, `stx-*` predicates, `walk-syntax`, `fold-syntax`, `free-identifiers`, `build-*` constructors

### Phase 4e: Data and Distribution
- `(std dataframe)` — column-oriented dataframes: `make-dataframe`, `dataframe-filter`, `dataframe-group-by`, `dataframe-summarize`, `dataframe-join`, `col-sum/mean/min/max`, CSV I/O
- `(std stream window)` — tumbling, sliding, session, and time windows: `window-add!`, `window-flush!`, `window-map`, `window-reduce`
- `(std actor distributed)` — location-transparent `dsend`, `dsend/ask`, `cluster-register!`, `cluster-whereis`, `make-process-group`, `process-group-broadcast!`
- `(std wasm wasi)` — WASI snapshot_preview1 host: `make-wasi-env`, `make-wasi-imports`, `wasi-fd-write`, `wasi-clock-time-get`, `wasi-proc-exit`
- `(std actor checkpoint)` — value/mailbox serialization: `checkpoint-value`, `restore-value`, `checkpoint-serializable?`, `make-checkpoint-manager`

### Phase 4f: Toolchain and Interop
- `(std lsp)` — LSP 2.0 server: JSON-RPC/stdio with Content-Length framing, document store, `analyze-document`, `find-completions`, `find-definition`
- `(std python)` — Python subprocess interop: embedded helper script, `start-python`, `stop-python`, `python-eval`, `python-exec`, `python-call`, `python-import`
- `(std build watch)` — file watcher with incremental builds: `make-watcher`, `make-dep-graph`, `dep-graph-topo-sort`, `make-build-system`, `build-system-build!`
- `(std build cross)` — cross-compilation pipeline: 5 built-in platforms, `current-platform`, `find-cross-compiler`, `run-build-matrix`
- `(std build reproducible)` — reproducible builds: FNV-1a content hash, `make-artifact-store`, `make-manifest`, `make-build-cache`, `normalize-artifact`

## Existing Documentation

| Document | Description |
|----------|-------------|
| [goals.md](goals.md) | Project goals and design philosophy |
| [implement.md](implement.md) | Full 13-phase implementation plan (reference) |
| [actor-model.md](actor-model.md) | Deep-dive into the actor system architecture |
| [single-binary.md](single-binary.md) | Producing single static binaries |
| [optimization.md](optimization.md) | Performance optimization guide |
| [compiling-gerbil-projects.md](compiling-gerbil-projects.md) | Gerbil compatibility notes |
| [lsp-conversion.md](lsp-conversion.md) | LSP integration notes |

## Quick Start

### Run a file
```bash
scheme --libdirs lib --script myapp.ss
```

### Use a library
```scheme
#!chezscheme
(import (chezscheme)
        (std effect)      ; algebraic effects
        (std async)       ; async I/O
        (std actor))      ; actor system
```

### Build a native binary
```bash
# Development build
scheme --libdirs lib --script -e '(import (jerboa build)) (build-binary "myapp.ss" "myapp")'

# Release build (WPO, tree-shaking)
scheme --libdirs lib --script -e '(import (jerboa build)) (build-release (list "myapp.ss") "myapp")'

# Static binary (zero runtime deps)
scheme --libdirs lib --script -e '(import (jerboa build)) (build-static-binary "myapp.ss" "myapp")'

# Cross-compile for aarch64
scheme --libdirs lib --script -e '
  (import (jerboa build))
  (build-binary "myapp.ss" "myapp-arm64" (quote target:) target-linux-aarch64)'
```

### Run the test suite
```bash
make test           # core tests
make test-features  # Phase 2 + Phase 3 feature tests
make test-phase4a   # Core Runtime
make test-phase4b   # Type System and Safety
make test-phase4c   # Systems and Performance
make test-phase4d   # Developer Experience
make test-phase4e   # Data and Distribution
make test-phase4f   # Toolchain and Interop
make test-all       # everything
```

## Standard Library Overview

### Core
- `(jerboa core)` — `def`, `defstruct`, `defclass`, `match`, `try/catch`, `while`, hash literals
- `(jerboa prelude)` — imports everything at once
- `(jerboa runtime)` — method dispatch, hash tables, keywords

### Concurrency
- `(std effect)` — algebraic effects with one-shot continuations
- `(std effect deep)` — deep effect handlers with automatic re-installation *(Phase 4a)*
- `(std effect multishot)` — nondeterminism via `choose`/`all-solutions`/`amb` *(Phase 4c)*
- `(std async)` — async/await, promises, channels
- `(std stm)` — software transactional memory (TVars, `atomically`, `retry`)
- `(std actor)` — full actor system (local + distributed)
- `(std actor engine)` — engine-pool preemptive actor scheduler *(Phase 4a)*
- `(std actor distributed)` — location-transparent `dsend`/`dsend/ask`, process groups *(Phase 4e)*
- `(std actor checkpoint)` — actor mailbox and value serialization/restore *(Phase 4e)*
- `(std concur)` — thread-safety annotations, deadlock detection, resource tracking
- `(std concur deadlock)` — runtime wait-for graph deadlock detection *(Phase 4c)*
- `(std concur util)` — semaphores, barriers, rwlocks, thread pools, latches *(Phase 4c)*
- `(std task)` — task groups and structured concurrency
- `(std misc channel)` — typed channels
- `(std sched)` — M:N scheduler with OS worker threads *(Phase 2d)*
- `(std stream async)` — lazy async streams with backpressure *(Phase 2d)*
- `(std raft)` — Raft consensus protocol *(Phase 2d)*
- `(std proc supervisor)` — OTP-style process supervisor *(Phase 2d)*

### Type System
- `(std typed)` — gradual typing with zero-overhead release mode
- `(std typed advanced)` — occurrence typing, row polymorphism, refinement types
- `(std typed env)` — lexically-scoped type environment *(Phase 4a)*
- `(std typed infer)` — bidirectional type inference with unification *(Phase 4a)*
- `(std typed hkt)` — higher-kinded types, `defprotocol-hkt`, `do/m` *(Phase 4b)*
- `(std typed monad)` — State/Reader/Writer monads *(Phase 4b)*
- `(std typed refine)` — refinement types (`NonNeg`, `Positive`, `NonNull`) *(Phase 4b)*
- `(std typed solver)` — lightweight constraint solver *(Phase 4b)*
- `(std typed row2)` — open records with `record-extend`/`record-restrict` *(Phase 4b)*
- `(std typed effects)` — effect typing with `Eff`/`Pure` types *(Phase 4b)*
- `(std typed gadt)` — GADTs with `define-gadt` / `gadt-match` *(Phase 2c)*
- `(std typed typeclass)` — Haskell-style type classes *(Phase 2c)*
- `(std typed linear)` — linear types with use-once enforcement *(Phase 2c)*
- `(std typed effect-typing)` — effect signatures and `typed-with-handler` *(Phase 2c)*
- `(std match2)` — pattern matching with sealed hierarchies and active patterns
- `(std match-syntax)` — AST pattern matching with `syntax-match` and `walk-syntax` *(Phase 4d)*
- `(std staging)` — compile-time computation and code generation
- `(std staging2)` — multi-stage programming with `define-staged` and `specialize` *(Phase 4d)*
- `(std taint)` — taint tracking with `define-sink`, `html-escape`, `sql-escape` *(Phase 4b)*

### Data Structures
- `(std seq)` — lazy sequences, transducers, parallel collections
- `(std transducer)` — composable transducers (`mapping`, `filtering`, `flat-mapping`, `windowing`) *(Phase 4a)*
- `(std table)` — columnar in-memory data tables with SQL-like operations
- `(std dataframe)` — column-oriented dataframes with group-by, summarize, join, CSV I/O *(Phase 4e)*
- `(std stream window)` — tumbling, sliding, session, time windows over event streams *(Phase 4e)*
- `(std arena)` — bump-pointer arena allocator with checkpoints *(Phase 4c)*
- `(std binary)` — packed binary struct encode/decode (u8–u64, f32/f64, cstring) *(Phase 4c)*
- `(std mmap-btree)` — file-backed B+ tree for persistent sorted key-value data *(Phase 4c)*
- `(std pvec)` — persistent vectors (HAMT trie, O(log₃₂ n)) *(Phase 2a)*
- `(std pmap)` — persistent hash maps *(Phase 2a)*
- `(std ds sorted-map)` — persistent sorted map (red-black tree) *(Phase 2e)*
- `(std misc queue)` — mutable FIFO queue
- `(std misc bytes)` — bytevector utilities
- `(std misc list)` — list utilities
- `(std misc string)` — string utilities
- `(std misc alist)` — association list utilities

### Networking & I/O
- `(std net request)` — HTTP client
- `(std net httpd)` — HTTP server
- `(std net ssl)` — TLS/TCP sockets
- `(std net zero-copy)` — buffer pool with slice views, zero-copy I/O *(Phase 2d)*
- `(std net pool)` — generic connection pool with health checking *(Phase 2d)*
- `(std net grpc)` — gRPC-style RPC over TCP *(Phase 2e)*
- `(std net websocket)` — RFC 6455 WebSocket framing and handshake *(Phase 3b)*
- `(std net http2)` — HTTP/2 framing + HPACK header compression *(Phase 3b)*
- `(std net dns)` — DNS wire format, query/response encode/decode *(Phase 3b)*
- `(std net rate)` — token bucket, sliding/fixed window rate limiters *(Phase 3b)*
- `(std net router)` — HTTP request routing with parameter capture and middleware *(Phase 3b)*
- `(std os fdio)` — file descriptor I/O (POSIX read/write)
- `(std os path)` — path manipulation
- `(std os signal)` — Unix signal handling

### Data Formats
- `(std text json)` — JSON read/write
- `(std text csv)` — CSV parsing/writing
- `(std text xml)` — SXML → XML
- `(std text yaml)` — YAML load/dump
- `(std text base64)` — Base64 encoding
- `(std text hex)` — Hex encoding
- `(std text utf8)` — UTF-8 utilities

### Security
- `(std capability)` — object-capability model (unforgeable tokens, sandboxing)
- `(std capability sandbox)` — capability-constrained sandbox with timeout *(Phase 4b)*
- `(std taint)` — taint tracking to enforce parse-before-use at sinks *(Phase 4b)*
- `(std crypto digest)` — SHA-256, MD5, SHA-512
- `(std foreign)` — safe C FFI with memory management

### Databases
- `(std db sqlite)` — SQLite
- `(std db postgresql)` — PostgreSQL
- `(std db leveldb)` — LevelDB key-value store

### Developer Tools
- `(std dev debug)` — time-travel debugger, execution recording
- `(std debug timetravel)` — event recorder with `trace-fn` and `replay-to-step` *(Phase 4d)*
- `(std debug flamegraph)` — manual enter/exit profiler → flamegraph text output *(Phase 4d)*
- `(std dev profile)` — deterministic + sampling profiler
- `(std dev reload)` — hot code reload
- `(std dev partial-eval)` — compile-time partial evaluation (`define-ct`, `ct`) *(Phase 2b)*
- `(std dev pgo)` — profile-guided optimization with type feedback *(Phase 2b)*
- `(std dev cont-mark-opt)` — linear handler analysis *(Phase 2b)*
- `(std dev devirt)` — whole-program devirtualization *(Phase 2b)*
- `(std test)` — test framework (`test-suite`, `check`, `run-tests!`)
- `(std test framework)` — QuickCheck property testing and test suites *(Phase 2e)*
- `(std proptest)` — property-based testing with `defproperty`, `check-property`, shrinking *(Phase 4d)*
- `(std error-advice)` — error messages with context-aware fix suggestions *(Phase 4a)*
- `(std doc generator)` — doc generator (markdown + HTML) *(Phase 2e)*
- `(std logger)` — structured logging with level filtering
- `(std log)` — structured logging with pluggable sinks and dynamic context *(Phase 3a)*
- `(std metrics)` — Prometheus metrics: counters, gauges, histograms, registry *(Phase 3a)*
- `(std span)` — distributed tracing spans with HTTP context propagation *(Phase 3a)*
- `(std health)` — health check framework with status aggregation *(Phase 3a)*
- `(std circuit)` — circuit breaker pattern (closed/open/half-open) *(Phase 3a)*

### Build & Package
- `(jerboa build)` — native binary toolchain (incremental, parallel, cross-compile, static)
- `(jerboa cache)` — content-addressed compilation cache
- `(jerboa pkg)` — semver package manager with constraint solving and manifests *(Phase 3c)*
- `(jerboa lock)` — lockfile management with S-expr format, merge, diff *(Phase 3c)*
- `(jerboa hot)` — hot code reload via mtime polling and callbacks *(Phase 3c)*
- `(jerboa embed)` — sandboxed evaluation environments *(Phase 3c)*
- `(jerboa cross)` — cross-compilation config, ABI naming, CC flags *(Phase 3c)*
- `(jerboa wasm format)` — WebAssembly binary format primitives *(Phase 3e)*
- `(jerboa wasm codegen)` — Scheme→WASM compiler (pure i32 subset) *(Phase 3e)*
- `(jerboa wasm runtime)` — stack-based WASM interpreter *(Phase 3e)*
- `(std build watch)` — file watcher with dependency graph and incremental builds *(Phase 4f)*
- `(std build cross)` — cross-compilation pipeline for 5 platforms with build matrix runner *(Phase 4f)*
- `(std build reproducible)` — FNV-1a content-addressed artifact store and build cache *(Phase 4f)*
- `(std lsp)` — LSP 2.0 server (JSON-RPC/stdio, completions, go-to-definition) *(Phase 4f)*
- `(std python)` — Python subprocess interop via JSON bridge *(Phase 4f)*
- `(std wasm wasi)` — WASI snapshot_preview1 host implementation *(Phase 4e)*

### Utilities
- `(std format)` — `format`, `printf`, `fprintf`
- `(std sort)` — `sort`, `stable-sort`
- `(std config)` — S-expression config with env overrides and schema validation *(Phase 2e)*
- `(std pregexp)` — Perl-compatible regular expressions
- `(std pcre2)` — PCRE2 bindings
- `(std regex-ct)` — compile-time regex → DFA state machine (`define-regex`) *(Phase 2b)*
- `(std select)` — channel select with priority, timeout, default *(Phase 2a)*
- `(std errors)` — structured error hierarchy *(Phase 2a)*
- `(std derive)` — auto-derive `equal?`, `hash`, `show`, `compare` *(Phase 2a)*
- `(std srfi srfi-13)` — string operations (SRFI-13)
- `(std srfi srfi-19)` — date/time (SRFI-19)
- `(std misc uuid)` — UUID v4 generation
- `(std misc completion)` — async completion tokens
- `(std compress zlib)` — gzip/deflate compression
- `(std query)` — SQL-like query DSL over in-memory collections *(Phase 3d)*
- `(std schema)` — data schema validation with type/combinator validators *(Phase 3d)*
- `(std pipeline)` — data pipeline DSL with threading, parallel stages, tap/catch *(Phase 3d)*
- `(std rewrite)` — term rewriting system with pattern variables and fixed-point *(Phase 3d)*
- `(std lint)` — source code static analysis with 9 built-in rules *(Phase 3d)*
