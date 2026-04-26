# Jerboa

A Gerbil-syntax, Clojure-compatible Scheme dialect for production
concurrent systems, running on stock [Chez Scheme](https://cisco.github.io/ChezScheme/).

Jerboa implements Gerbil's user-facing language (`def`, `defstruct`,
`match`, hash tables, `:std/*` libraries) **and** a substantial Clojure
compatibility layer (atoms, refs/STM, agents, persistent collections,
core.async, transducers, protocols, multimethods) as Chez Scheme
macros and native libraries. No Gerbil expander, no Gambit
compatibility layer, no patched Chez. The standard Chez compiler
produces the binaries.

## Why Chez Scheme

Jerboa picks Chez Scheme as its host because its concurrency model is
the rare combination that real production systems need:

- **Real OS threads, no GIL.** Chez Scheme's threaded build
  (`--threads`) gives you native OS threads with a thread-safe
  generational GC. CPU-bound work scales linearly across cores; you
  do not pay for parallelism with a global interpreter lock.
- **First-class synchronization primitives.** `make-mutex`,
  `make-condition`, `with-mutex`, `condition-wait`,
  `condition-broadcast`, and atomic CAS on tc-mutex slots are
  exposed in the language. Jerboa's higher-level concurrency
  abstractions (`(std atom)`, `(std stm)`, `(std csp)`,
  `(std net io)` fibers) are built directly on these.
- **Cheap closures, fast call paths.** Chez compiles to machine code
  through the nanopass framework — its closure allocation and
  call-through-pointer costs are competitive with what Go achieves
  via its runtime. That gives Jerboa room to express tens of
  thousands of fibers as plain procedures over a small worker pool
  without the cost dominating the workload.
- **Fixnum-tagged arithmetic and unboxed bytevectors.** Hot paths in
  protocol handling (HTTP/2, WebSocket framing, base64, SHA) stay
  in fixnums and unboxed bytes, so a Scheme implementation of a
  protocol can sit within a small constant factor of a hand-written
  C version.
- **A stable, fast FFI.** `foreign-procedure` and `foreign-callable`
  let Jerboa drop into a Rust shared library (`libjerboa_native`)
  for everything that genuinely needs sharp edges — ring for
  crypto, rustls for TLS, regex for ReDoS-immune matching,
  rusqlite/postgres/duckdb for storage. The Scheme side stays
  high-level; the Rust side stays memory-safe.
- **A self-hosting compiler.** When Jerboa needs a primitive that
  Chez does not ship (e.g. `bytevector-slice`, `bytevector-append`,
  `base64-encode`/`base64-decode`, `sha1-bytevector`,
  `sha256-bytevector`), we add it to our Chez fork in pure Scheme
  with full backwards compatibility. No patched bootstrap, no
  vendored compiler — just additional primitives in `(chezscheme)`.
- **Apache 2.0**, no license entanglements.

The result: a single language where green threads (fibers), OS
threads, atomic state, software-transactional memory, and CSP
channels all coexist on top of the same scheduler primitives, with
predictable performance and no runtime to fight.

## Quick Start

```scheme
(import (jerboa prelude))

(def (main)
  (defstruct point (x y))
  (let ([p (make-point 3 4)])
    (displayln (point-x p))                 ;; 3
    (displayln (sort < [5 1 3]))            ;; (1 3 5)
    (displayln (string-join ["a" "b"] ","))  ;; a,b
    (displayln (json-object->string [1 2 3]))))  ;; [1,2,3]

(main)
```

Run with:
```bash
scheme --libdirs lib --script your-file.ss
```

## Architecture

```
┌──────────────────────────────────────────────┐
│            User's Gerbil-like code           │
│  (def (main) (displayln (sort < [3 1 2])))  │
└──────────────┬───────────────────────────────┘
               │
┌──────────────▼───────────────────────────────┐
│  Reader: [...] = (...), {...} → (~ ..)       │
│  :std/sort → (std sort), keyword:, heredocs  │
│  Optional Clojure mode (#!cloj)              │
├──────────────────────────────────────────────┤
│  Core Macros: def, defstruct, match, try     │
│  All expand to standard Chez Scheme          │
├──────────────────────────────────────────────┤
│  Runtime: hash tables, method dispatch,      │
│           persistent collections, transients │
├──────────────────────────────────────────────┤
│  Concurrency: fibers, CSP, STM, atoms,       │
│  agents, futures, work-stealing scheduler    │
├──────────────────────────────────────────────┤
│  Standard Library: 229 (std *) modules       │
├──────────────────────────────────────────────┤
│  Native FFI: libjerboa_native.so (Rust)      │
│   ring · flate2 · regex · sqlite ·           │
│   postgres · rustls · landlock · ed25519     │
├──────────────────────────────────────────────┤
│  Stock Chez Scheme — additive primitives,    │
│  no fork, no patches                         │
└──────────────────────────────────────────────┘
```

## What's Landed in the Last Month

The recent push has expanded Jerboa from "Gerbil syntax on Chez" into
a full production stack. The additions group into seven themes.

### 1. Fiber-aware concurrency stack

A green-thread system layered on Chez OS threads with epoll-integrated
I/O. The eight-phase rollout (`docs/green-wins.md`) is now complete.

| Module | Provides |
|---|---|
| `(std net io)` | epoll-integrated I/O core for fibers |
| `(std net fiber-httpd)` | Fiber-native HTTP/1.1 server with URL-param routing |
| `(std net fiber-ws)` | Fiber-aware WebSocket server, integrates with httpd |
| `(std workpool)` | Bounded worker pool for blocking syscalls |
| `(std net dns)` | Fiber-friendly resolver with caching |
| `(std net filepool)` | File-descriptor pool offloading slow disk I/O |
| `(std net sendfile)` | Zero-copy `sendfile(2)` paths for static content |
| `(std net connpool)` | Fiber-aware connection pooling for outbound TCP |
| `(std net rate)` | Token bucket, sliding/fixed-window limiters |
| `(std net router)` | HTTP routing with `:param` captures + middleware |
| `(std semaphore)` / `(std net admission)` | Production hardening: admission control + circuit metrics |
| `(std fiber)` | Cancellation, fiber-locals, join, link, select, timeouts, groups |

Internally, the scheduler now uses **per-worker work-stealing deques**
instead of a shared run-queue, and the completion / wait API was
re-wired through fibers so that ports and channels block fibers
without parking the OS thread.

### 2. Clojure compatibility layer — `(std clojure)`

A substantial Clojure-on-Scheme port: sequences, atoms, agents, refs,
multimethods, protocols, transducers, persistent collections, lazy
sequences, core.async, EDN, specter, zippers, and the rest of the
common idiom.

**Persistent collections** (HAMT- and RRB-backed):

| Module | Provides |
|---|---|
| `(std pmap)` | Persistent hash-array-mapped trie map + `transient-map` for fast bulk build |
| `(std pvec)` | Persistent RRB vector |
| `(std pset)` | Persistent set on top of `pmap` |
| `(std sorted-set)` | Sorted persistent set |
| `(std sorted-map)` | Sorted persistent map |
| `(std pqueue)` | Persistent FIFO queue (SRFI-134-backed) |

All persistent collections participate in Chez's `equal?` /
`equal-hash` / `display`, integrate with the `for/collect` / `for/fold`
iterator protocol, and are destructurable via `match`. They use
nongenerative RTDs so equality survives separate compilation.

**Concurrency primitives** (Clojure-style names, Chez-thread-safe):

| Module | Provides |
|---|---|
| `(std atom)` | `atom`, `swap!`, `reset!`, `compare-and-set!`, `add-watch!`, `volatile!` family |
| `(std agent)` | Async state cells with bounded send queues |
| `(std stm)` | `ref`, `dosync`, `alter`, `commute`, `ensure` on top of TVars |
| `(std multi)` | `defmulti` / `defmethod` with `:hierarchy` and `derive!` |
| `(std protocol)` | Open-world protocols (`defprotocol`, `extend-type`, `extend!`) |
| `(std meta)` | Metadata wrappers (`with-meta`, `meta`) |
| `(std component)` | Stuart Sierra-style lifecycle (`start`, `stop`, dependency graph) |

**core.async-style CSP** — `(std csp)`:

- `(chan n xform)` — transducer-backed channels
- Sliding / dropping / blocking buffers
- `alts!` / `alts!!` non-deterministic select
- `pipe`, `mult`, `mix` (with `'block` / `'drop` / `'timeout` policies)
- `pub` / `sub` topic filtering
- `split` / `chan-classify-by` n-way split
- `async-reduce`, `onto-chan!`, `onto-chan!!`
- `put!` / `take!` non-blocking callback variants
- Timer wheel for scalable timeouts (`JERBOA_CSP_TIMER_WHEEL=1`)
- `(std csp fiber-chan)` integrates channels with fibers

**Sequence / data manipulation**:

| Module | Provides |
|---|---|
| `(std clojure)` | Umbrella with `delay`, `future`, `promise`, polymorphic `deref` |
| `(std clojure walk)` | `prewalk`, `postwalk`, `keywordize-keys`, etc. |
| `(std clojure data)` | `diff` |
| `(std clojure zip)` | Tree zippers |
| `(std clojure seq)` | Lazy sequences: `range`, `iterate`, `repeat`, `cycle`, `take-while`, `drop-while` |
| `(std clojure reducers)` | Reducible/transducible adapters |
| `(std specter)` | Composable path navigation for nested data |
| `(std zipper)` | Functional tree zippers |
| `(std text edn)` | EDN reader/writer (#inst, #uuid, tagged literals) |
| `(std misc nested)` | `get-in`, `assoc-in`, `update-in` |
| `(std injest)` | Smart thread-last with transducer fusion |

The `(std clojure)` module also lands `ex-info`, `condp =>`,
`reduce-kv`, set relational ops (`select`, `project`, `rename`,
`index`, `join`), and full destructuring.

`(std test check)` is a property-based testing library with
shrinking, in the style of `test.check`.

### 3. Slang + WebAssembly backend

Slang is a secure language compiler that targets WebAssembly, with
two execution backends.

- Full WASM MVP plus post-MVP features: saturating conversions, bulk
  memory operations, reference types, tables, tail calls, exception
  handling, GC, host imports.
- `(jerboa wasm format)` — binary format primitives (LEB128, IEEE 754).
- `(jerboa wasm codegen)` — Scheme→WASM compiler for an i32 subset
  (closures, tail calls, exceptions, variadic lambdas).
- `(jerboa wasm runtime)` — stack-based interpreter for testing.
- **wasmi backend** — Rust embedding with fuel metering and bounded
  memory; security-hardened (bounds checks, exception boundary,
  import validation, module-size limits).
- **SpiderMonkey backend** via the `mozjs` crate — production JIT for
  benchmarks where wasmi is the bottleneck.
- Argon2id key derivation, message HMAC, sandbox limits, taint checks
  baked in.
- `wasm-sandbox-instantiate-hosted` provides a Scheme FFI binding for
  hosting third-party WASM modules with capability-based imports.

### 4. Native Rust backend — `libjerboa_native.so`

A unified Rust shared library replaces the previous C-FFI surface
with memory-safe implementations behind a small extern-"C" facade.

| Module | Crate(s) | Provides |
|---|---|---|
| `(std crypto native-rust)` | ring | SHA-1/256/384/512, HMAC, AES-256-GCM, PBKDF2, CSPRNG, ed25519 sign/verify |
| `(std crypto secure-mem)` | libc (mmap/mlock) | Guard-paged, mlocked memory outside GC |
| `(std compress native-rust)` | flate2 | `deflate`/`inflate`/`gzip`/`gunzip` with size limits |
| `(std regex-native)` | regex (NFA) | Compile / match / find / replace — ReDoS-immune |
| `(std db sqlite-native)` | rusqlite (bundled) | Open / exec / prepare with parameterized queries |
| `(std db postgresql-native)` | rust-postgres | Connect / exec / query |
| `(std db duckdb-native)` | duckdb-rs | Native DuckDB integration |
| `(std os epoll-native)` | libc | epoll create / ctl / wait |
| `(std os inotify-native)` | libc | inotify init / add_watch / read_events |
| `(std os landlock-native)` | libc | Landlock LSM ABI v1–v7 (FS + network confinement) |
| `(std net tls-rustls)` | rustls | HTTPS / `wss://` with pinned cert verification |
| `(std net request)` | rustls | HTTPS via the Rust TLS path |
| `(std pcap)` | rscap | Live packet capture |

`panic.rs` wraps every extern "C" entry point in `catch_unwind` so a
Rust panic never crosses the FFI boundary as undefined behavior.

### 5. Cross-platform ports

Jerboa now runs on Linux (glibc + musl), FreeBSD, macOS (Intel + Apple
Silicon), and Android (Termux).

- **FreeBSD**: full Capsicum support in `(std security cage)`,
  `__error` errno binding, correct platform constants for O_* flags,
  `struct stat`, `sockaddr_in`, signals (SIGTSTP/SIGCHLD/SIGCONT and
  six others were hardcoded to Linux values), and integrity check via
  `sysctl` instead of `/proc/curproc/file`.
- **macOS**: BPF live capture activation via `BIOCSETF` + `BIOCIMMEDIATE`
  (replacing `BIOCSETFNR` which doesn't exist on macOS), portable
  libc/libm names, dylib path fallback, AArch64 seccomp.
- **Android**: bionic libc errno symbol support in TCP layer.

`(std security cage)` provides pledge/unveil-style process
confinement that maps to the strongest mechanism available on each
platform: Landlock + seccomp on Linux, Capsicum on FreeBSD, sandbox-exec
on macOS.

### 6. Security hardening

- `(std security)` — `audit`, `auth`, `cage`, `capability`,
  `flow`, `import-audit`, `io-intercept`, `landlock`,
  `metrics`, `privsep`, `restrict`, `sandbox`, `sanitize`,
  `seatbelt`, `seccomp`, `secret`, `taint`, `capsicum`,
  `capability-typed`, `errors`.
- mTLS with **pinned cert verifier** (replacing
  `WebPkiClientVerifier`); in-memory cert/key APIs.
- Argon2id, TOCTOU-safe path handling, message HMAC.
- Binary-hardening flags wired into the musl static build (PIE,
  RELRO, stack-canaries, NX) — see `docs/secure-binary.md`.
- aarch64 seccomp filter.

### 7. Performance work — phases 4–22

A multi-phase optimization push, each with a benchmark gate to detect
regressions. The scaffolding lives in `(std bench)` and runs in CI.

| Phase | Optimization |
|---|---|
| 4 | Memoize regex compilation for literal reuse |
| 5 | Fuse `for` / `for/collect` / `for/fold` over `in-range` / `in-vector` / `in-string` |
| 6 | Single-pass keyword-arg extraction in `def` expansion |
| 7 | Build the prelude aggregator to produce WPO for `std/*` |
| 8 | Bench-suite harness + regression gate |
| 12 | Arity-specialized method dispatch in `(~ obj 'name ...)` |
| 13 | Fuse `in-hash-keys` / `in-hash-values` in `for/collect` |
| 14 | Fuse runs of `(list 'TAG p ...)` clauses in `match` |
| 17 | Method dispatch cost vs direct call (baseline) |
| 18 | Kwarg call overhead (baseline) |
| 22 | `string-append` adjacent-literal fold (Chez-side) |
| — | `defstruct` / `defrecord` / `ok` / `err` seal by default |
| — | `str` expand-time constant folding for literal args |
| — | Persistent-collection nongenerative UIDs |
| — | Iter fusion: `for/or` / `for/and` over known iterator heads |
| — | Match2 fast-path `(: Type)` with fused RTD dispatch |

### 8. Reader & build infrastructure

- **Clojure reader compatibility mode** (`#!cloj`) — switch a file or
  REPL session into Clojure surface syntax (`#"regex"`, `#{}` sets,
  `#_form` discard, etc.).
- **Regex tier 1–3** — raw strings, unified `(re ...)` API across the
  pure-Scheme and Rust backends, `rx` macros, full PEG grammar
  system in `(std peg)`.
- **Single-file packages** — `jerboa exec` reads a self-contained
  `.ss` file with header metadata and runs it without project
  scaffolding.
- **jerbuild** improvements — per-project feature gating so a
  static-musl build only links the dependencies the project
  actually uses.
- **Docker base image** for static musl binary builds; CI workflow
  for macOS Rust libraries; jemacs static build TUI deps included.
- **nREPL** — `(std nrepl)` is the canonical source; full CIDER /
  Calva middleware plus Jerboa extensions.
- **AI compatibility aliases** — `(jerboa prelude)` exports common
  names from Racket / Gambit / Common Lisp that LLMs frequently
  hallucinate (`hash-has-key?` → `hash-key?`,
  `directory-exists?` → `file-directory?`, `random-integer` →
  `random`, `eql?` → `eqv?`, etc.).

### 9. Documentation push

`docs/` is now ~90 files. Highlights:

- `docs/anti-cookbook.md` — common Scheme/Clojure mistakes and how
  Jerboa makes them explicit.
- `docs/api-index.md` — comprehensive API reference (~700KB,
  generated).
- `docs/clojure-vs-jerboa.md` — feature scorecard with status
  markers.
- `docs/clojure-left.md` — gap analysis driving the parity work.
- `docs/green-wins.md` — fiber roadmap (now complete).
- `docs/jerboa-edge.md` — edge-computing roadmap.
- `docs/jerboa-db.md` — database integration tracking.
- `docs/native-rust.md` — Rust backend architecture and migration.
- `docs/regex-rx-peg.md` — unified regex/SRE/PEG reference.

## What's Included

### Core Macros (`(jerboa core)`)
- `def`, `def*` — functions with optional / multi-arity / rest args
- `defstruct` — sealed Chez records with auto-generated accessors
- `defclass` — records with single inheritance
- `defmethod`, `defmulti` — method dispatch and multimethods
- `match`, `match2` — pattern matching (lists, predicates,
  `and`/`or`/`not`, cons, type patterns, persistent-collection
  destructuring, wildcards)
- `try`/`catch`/`finally`, `errdefer`, `defvariant` (Zig-inspired)
- `defrule`/`defrules` — syntax-rules shortcuts
- `while`/`until`, `for` family
- `hash-literal`/`let-hash`
- Threading macros: `chain`, `chain-and`, `->`, `->>`, `as->`,
  `some->`, `cond->`

### Runtime (`(jerboa runtime)`)
- Full Gerbil hash table API
- Method dispatch: `~`, `bind-method!`, `call-method`
- Keywords, ports, displayln, `iota`, `1+`, `1-`
- `(jerboa pkg)`, `(jerboa lock)` — semver, dep resolution,
  manifests, lockfile management
- `(jerboa hot)` — hot code reload via mtime polling
- `(jerboa embed)` — sandboxed evaluation environments
- `(jerboa cross)` — cross-compilation config and ABI naming

### Standard Library — 229 modules under `lib/std/`

Major areas:

- **Concurrency**: `(std atom)`, `(std agent)`, `(std stm)`,
  `(std csp)`, `(std multi)`, `(std protocol)`, `(std meta)`,
  `(std component)`, `(std clojure)`, `(std fiber)`, `(std raft)`,
  `(std actor)`, `(std concur hash)`, `(std concur stm)`,
  `(std concur structured)`.
- **Networking**: 35+ `(std net *)` modules — `request`, `httpd`,
  `fiber-httpd`, `fiber-ws`, `websocket`, `http2`, `dns`,
  `sendfile`, `connpool`, `workpool`, `tcp`, `udp`, `tls`,
  `tls-rustls`, `ssh`, `s3`, `smtp`, `socks5-server`, `9p`,
  `grpc`, `json-rpc`, `router`, `rate`, `uri`.
- **Data**: `(std pmap)`, `(std pvec)`, `(std pset)`,
  `(std sorted-set)`, `(std sorted-map)`, `(std pqueue)`,
  `(std specter)`, `(std zipper)`, `(std injest)`,
  `(std clojure data/walk/zip)`, `(std misc nested)`.
- **Persistence / DB**: `(std db sqlite/postgresql/duckdb/leveldb)`,
  native-Rust variants, `(std db dbi)`, `(std db query-compile)`,
  `(std db conpool)`.
- **Text**: `(std text json/edn/csv/xml/yaml/base64/hex/utf8)`,
  `(std regex-native)`, `(std rx)`, `(std peg)`.
- **OS / runtime**: `(std os env/path/temporaries/signal/fdio)`,
  native epoll/inotify/landlock, `(std os capsicum)`,
  `(std misc process)`, `(std misc thread)`, `(std misc cpu)`.
- **Crypto**: `(std crypto digest/cipher/hmac/pkey/kdf)`,
  `(std crypto native-rust)` (ring), `(std crypto secure-mem)`.
- **Production infra**: `(std log)`, `(std metrics)`, `(std span)`,
  `(std health)`, `(std circuit)`, `(std semaphore)`, `(std lint)`,
  `(std test)`, `(std test check)`, `(std bench)`.
- **Security**: 21 `(std security *)` modules — pledge/unveil,
  Landlock, Capsicum, seccomp, capability-typed I/O, taint, sandbox.

### FFI (`(jerboa ffi)`)
- `c-lambda` → `foreign-procedure` with automatic type translation
- `define-c-lambda`, `begin-ffi`, `c-declare`
- Full Gambit-to-Chez type mapping
- `native-available?` guards for build-time platform feature gating

### Reader (`(jerboa reader)`)
- `[...]` = `(...)` (same as Gerbil and Chez)
- `{method obj}` → `(~ obj 'method)`
- `keyword:` → keyword objects
- `:std/sort` → `(std sort)` module paths
- Heredoc strings, datum comments, block comments
- Optional Clojure surface syntax under `#!cloj`

### Prelude (`(jerboa prelude)`)
One import for everything:
```scheme
(import (jerboa prelude))
```

## Examples

### Fiber-based HTTP server
```scheme
(import (jerboa prelude)
        (std net fiber-httpd))

(define (handler req)
  (let-values ([(method path) (request-method+path req)])
    (case method
      [(GET)  (respond-text 200 "hello\n")]
      [else   (respond-text 405 "method not allowed\n")])))

(fiber-httpd-serve port: 8080 handler: handler workers: 4)
```

### CSP pipeline
```scheme
(import (jerboa prelude)
        (std csp) (std csp ops))

(let ([in  (chan 100)]
      [out (chan 100 (map (lambda (x) (* x x))))])
  (pipe in out)
  (go (let loop ([i 0])
        (when (< i 1000) (put! in i) (loop (+ i 1)))))
  (let consume ([n 0])
    (when (< n 1000)
      (displayln (take! out)) (consume (+ n 1)))))
```

### STM (Clojure refs)
```scheme
(import (jerboa prelude) (std stm))

(define account-a (ref 100))
(define account-b (ref 50))

(define (transfer! from to amount)
  (dosync
    (alter from - amount)
    (alter to   + amount)))

(transfer! account-a account-b 25)
```

### Persistent map
```scheme
(import (jerboa prelude) (std pmap))

(define m1 (pmap 'a 1 'b 2 'c 3))
(define m2 (pmap-assoc m1 'd 4))
(displayln (pmap-ref m2 'b))      ;; 2
(displayln (pmap-ref m1 'd #f))   ;; #f  (m1 unchanged)
```

## Testing

```bash
make test           # Core tests (289 tests)
make test-features  # Phase 2+3 feature tests (637 tests)
make test-native    # Rust native backend tests
make test-wrappers  # Legacy chez-* C library wrappers (27 tests)
make test-clojure   # Clojure compatibility layer tests
make test-fiber     # Fiber + CSP + STM tests
make test-wasm      # Slang/WASM backend tests
make test-all       # Everything (1500+ tests)
```

Property-based testing is available via `(std test check)`:

```scheme
(import (std test) (std test check))

(check 'sort-is-idempotent
       (lambda (xs) (equal? (sort < xs) (sort < (sort < xs))))
       (gen-list (gen-integer)))
```

## Requirements

- [Chez Scheme](https://cisco.github.io/ChezScheme/) 10.x (stock,
  unmodified — though we maintain an additive fork at
  [github.com/ober/ChezScheme](https://github.com/ober/ChezScheme)
  with a handful of pure-Scheme primitives that the standard
  library uses). Both work.
- Optional: [Rust toolchain](https://rustup.rs/) for building
  `libjerboa_native.so` (crypto, compression, regex, databases,
  TLS, OS integration, ed25519).
- Optional (legacy): [chez-*](https://github.com/ober) libraries for
  the older C-FFI shims (still functional, being superseded by the
  Rust backend).

### Supported platforms

| OS | Architecture | Notes |
|---|---|---|
| Linux | x86_64, aarch64 | glibc + musl static both supported |
| FreeBSD | x86_64 | Capsicum enabled by default |
| macOS | x86_64, aarch64 | Apple Silicon native; sandbox-exec for `(std security cage)` |
| Android | aarch64 | Termux; bionic libc compat |

## Project Structure

```
lib/
  jerboa/         # Reader, core macros, runtime, FFI, prelude
                  # + pkg, lock, hot, embed, cross, wasm, build
  std/            # 229 modules — see "Standard Library" above
jerboa-native-rs/ # Unified Rust shared library
  src/
    lib.rs              # module declarations, init
    crypto.rs           # ring digests, hmac, aead, csprng, ed25519
    compress.rs         # flate2: deflate, inflate, gzip
    regex_native.rs     # regex crate
    sqlite.rs           # rusqlite
    postgres_native.rs  # rust-postgres
    duckdb.rs           # duckdb-rs
    epoll.rs / inotify_native.rs / landlock.rs
    secure_mem.rs       # mlock + guard pages + explicit_bzero
    tls_rustls.rs       # rustls-based TLS
    panic.rs            # catch_unwind wrapper for FFI
slang/            # Slang language compiler
  src/            # IR, lowering, codegen
  wasm/           # WASM backend (wasmi + SpiderMonkey)
docs/             # ~90 files — green-wins, clojure-vs-jerboa, native-rust, …
tests/            # Test suite (1500+ tests)
benchmarks/       # Bench harness with regression gate
support/          # Static-build artifacts, Docker base image
```

## What Gerbil Code Works

Most user-level Gerbil code works unchanged:

```scheme
(import :std/sugar :std/sort :std/format)

(def (run-command cmd env)
  (try
    (let* ([tokens (tokenize cmd)]
           [expanded (expand-aliases tokens env)])
      (match expanded
        ([prog . args] (exec-pipeline prog args env))
        (else (displayln "empty command"))))
    (catch (e) (displayln "error: " (error-message e)))))
```

## What Won't Work

1. **Gerbil expander API** (`:gerbil/expander`) — not applicable
2. **Gambit `##` primitives** — provided case-by-case
3. **`(export #t)`** — re-export-everything needs explicit exports
4. **Gerbil-specific `syntax-case` binding semantics** — uses Chez R6RS
5. **Gambit thread API** is wrapped (`(std misc thread)`); some
   Gambit-specific primitives (e.g. `thread-yield!` quirks) are not
   1:1 — see `docs/concurrency-extended.md`.

## License

Apache 2.0
