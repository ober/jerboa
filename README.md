# Jerboa

Gerbil Scheme's syntax and APIs, running on stock Chez Scheme.

Jerboa implements Gerbil's user-facing language — `def`, `defstruct`, `match`, hash tables, `:std/*` libraries — as Chez Scheme macros and native libraries. No Gerbil expander, no Gambit compatibility layer, no patched Chez.

## Quick Start

```scheme
(import (jerboa prelude))

(def (main)
  (defstruct point (x y))
  (let ([p (make-point 3 4)])
    (displayln (point-x p))           ;; 3
    (displayln (sort [5 1 3] <))      ;; (1 3 5)
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
│  (def (main) (displayln (sort [3 1 2] <)))  │
└──────────────┬───────────────────────────────┘
               │
┌──────────────▼───────────────────────────────┐
│  Reader: [...] → (list ...), {...} → (~ ..)  │
│  :std/sort → (std sort) module paths         │
├──────────────────────────────────────────────┤
│  Core Macros: def, defstruct, match, try     │
│  All expand to standard Chez Scheme          │
├──────────────────────────────────────────────┤
│  Runtime: hash tables, method dispatch       │
├──────────────────────────────────────────────┤
│  Standard Library: sort, JSON, paths, etc.   │
├──────────────────────────────────────────────┤
│  FFI: c-lambda → foreign-procedure           │
├──────────────────────────────────────────────┤
│  Stock Chez Scheme — no fork, no patches     │
└──────────────────────────────────────────────┘
```

## What's Included

### Core Macros (`(jerboa core)`)
- `def` — functions with optional args, rest args
- `def*` — case-lambda shorthand
- `defstruct` — native Chez records with auto-generated accessors
- `defclass` — records with inheritance
- `defmethod` — method dispatch via `bind-method!`
- `match` — pattern matching (lists, predicates, `and`/`or`/`not`, cons, wildcards)
- `try`/`catch`/`finally` — exception handling
- `defrule`/`defrules` — syntax-rules shortcuts
- `while`/`until` — loop macros
- `hash-literal`/`let-hash` — hash table construction and destructuring

### Runtime (`(jerboa runtime)`)
- Full Gerbil hash table API: `hash-ref`, `hash-put!`, `hash-get`, `hash-keys`, etc.
- Method dispatch: `~`, `bind-method!`, `call-method`
- Keywords: `string->keyword`, `keyword?`, `keyword->string`
- Utilities: `displayln`, `iota`, `1+`, `1-`

### Standard Library
| Module | Provides |
|--------|----------|
| `(std sort)` | `sort`, `stable-sort` |
| `(std format)` | `printf`, `fprintf`, `eprintf` |
| `(std error)` | `Error`, `ContractViolation` |
| `(std sugar)` | `chain`, `chain-and`, `assert!` |
| `(std text json)` | `read-json`, `write-json`, `string->json-object`, `json-object->string` |
| `(std os path)` | `path-join`, `path-directory`, `path-extension`, etc. |
| `(std misc string)` | `string-split`, `string-join`, `string-trim`, `string-contains`, etc. |
| `(std misc list)` | `flatten`, `unique`, `take`, `drop`, `every`, `any`, `filter-map`, `zip` |
| `(std misc alist)` | `agetq`, `pgetq`, `alist->hash-table` |
| `(std misc ports)` | `read-file-string`, `with-output-to-string`, etc. |
| `(std misc channel)` | Thread-safe channels (Chez mutex/condvar) |
| `(std misc thread)` | Gambit-compatible thread API on Chez threads |
| `(std misc process)` | `run-process`, `run-process/batch` |
| `(std misc queue)` | Mutable FIFO queue |
| `(std misc bytes)` | Bytevector bitwise operations |
| `(std misc uuid)` | UUID v4 generation |
| `(std misc repr)` | `repr`, `prn` object printing |
| `(std misc completion)` | Async completion tokens |
| `(std pregexp)` | Portable regex (pregexp) |
| `(std test)` | Test framework (`test-suite`, `test-case`, `check`) |
| `(std logger)` | Logging with levels (error/warn/info/debug) |
| `(std cli getopt)` | CLI argument parsing (options, flags, commands) |
| `(std text base64)` | Base64 encode/decode |
| `(std text hex)` | Hex encode/decode |
| `(std text utf8)` | UTF-8 utilities |
| `(std text csv)` | CSV read/write |
| `(std text xml)` | SXML → XML serialization |
| `(std text yaml)` | YAML load/dump with roundtrip support (pure Scheme, preserves comments/ordering/styles) |
| `(std os env)` | `getenv`, `setenv`, `unsetenv` |
| `(std os temporaries)` | Temporary file creation |
| `(std os signal)` | POSIX signal constants + handlers |
| `(std os fdio)` | File descriptor I/O |
| `(std crypto digest)` | MD5/SHA hashing via openssl |
| `(std srfi srfi-13)` | SRFI-13 string operations |
| `(std srfi srfi-19)` | Date/time handling |

### Phase 3 Libraries
| Module | Provides |
|--------|----------|
| `(std log)` | Structured logging with levels, pluggable sinks, `current-logger` |
| `(std metrics)` | Prometheus-compatible counters, gauges, histograms |
| `(std span)` | Distributed tracing spans with HTTP context propagation |
| `(std health)` | Health check framework with aggregated status |
| `(std circuit)` | Circuit breaker (closed/open/half-open) |
| `(std net websocket)` | RFC 6455 WebSocket frame encoding/decoding |
| `(std net http2)` | HTTP/2 framing + HPACK header compression |
| `(std net dns)` | DNS wire format (query/response encode/decode) |
| `(std net rate)` | Token bucket, sliding/fixed window rate limiters |
| `(std net router)` | HTTP routing with `:param` captures and middleware |
| `(std query)` | SQL-like query DSL over in-memory collections |
| `(std schema)` | Data schema validation with path-annotated errors |
| `(std pipeline)` | Data pipeline DSL with tap, catch, parallel stages |
| `(std rewrite)` | Term rewriting with pattern variables and fixed-point |
| `(std lint)` | Source code static analysis (9 built-in rules) |
| `(jerboa pkg)` | Semantic versioning, dep resolution, manifests |
| `(jerboa lock)` | Lockfile management with merge and diff |
| `(jerboa hot)` | Hot code reload via mtime polling |
| `(jerboa embed)` | Sandboxed evaluation environments |
| `(jerboa cross)` | Cross-compilation config and ABI naming |
| `(jerboa wasm format)` | WebAssembly binary format primitives (LEB128, IEEE 754) |
| `(jerboa wasm codegen)` | Scheme→WASM compiler (pure i32 subset) |
| `(jerboa wasm runtime)` | Stack-based WASM interpreter |

### Rust Native Backend (`libjerboa_native.so`)

Jerboa includes a unified Rust shared library that replaces most C dependencies with memory-safe implementations. Build with `make native` (requires Rust toolchain).

| Module | Rust Crate | Provides |
|--------|------------|----------|
| `(std crypto native-rust)` | ring | SHA-1/256/384/512, HMAC-SHA256, AES-256-GCM, PBKDF2, CSPRNG, constant-time compare |
| `(std crypto secure-mem)` | libc (mmap/mlock) | `secure-alloc`, `secure-free`, `secure-wipe` — guard-paged, mlock'd memory outside GC |
| `(std compress native-rust)` | flate2 | `deflate-bytevector`, `inflate-bytevector`, `gzip-bytevector`, `gunzip-bytevector` with size limits |
| `(std regex-native)` | regex (NFA) | `regex-compile`, `regex-match?`, `regex-find`, `regex-replace-all` — ReDoS-immune |
| `(std db sqlite-native)` | rusqlite (bundled) | `sqlite-open`, `sqlite-exec`, `sqlite-prepare`, parameterized queries |
| `(std db postgresql-native)` | rust-postgres | `pg-connect`, `pg-exec`, `pg-query`, parameterized queries |
| `(std os epoll-native)` | libc | `epoll-create`, `epoll-ctl`, `epoll-wait` |
| `(std os inotify-native)` | libc | `inotify-init`, `inotify-add-watch`, `inotify-read-events` |
| `(std os landlock-native)` | libc (syscalls) | Landlock LSM ABI v1-v7 — filesystem and network sandboxing |

See [docs/native-rust.md](docs/native-rust.md) for architecture, C ABI design, and migration details.

### Legacy C Library Wrappers (require [chez-*](https://github.com/ober) libraries)

These modules use external C libraries via chez-* FFI shims. They remain functional but are being superseded by the Rust native backend above.

| Module | Wraps | Provides |
|--------|-------|----------|
| `(std net request)` | [chez-https](https://github.com/ober/chez-https) | `http-get`, `http-post`, `http-put`, `http-delete`, `url-encode` |
| `(std net httpd)` | [chez-https](https://github.com/ober/chez-https) | `httpd-start`, `httpd-route`, `http-respond-json`, etc. |
| `(std net ssl)` | [chez-ssl](https://github.com/ober/chez-ssl) | `ssl-connect`, `tcp-connect`, `tcp-listen`, TLS/TCP networking |
| `(std compress zlib)` | [chez-zlib](https://github.com/ober/chez-zlib) | `gzip-bytevector`, `gunzip-bytevector`, `deflate-bytevector` |
| `(std db leveldb)` | [chez-leveldb](https://github.com/ober/chez-leveldb) | `leveldb-open`, `leveldb-put`, `leveldb-get`, iterators, batches |
| `(std db sqlite)` | [chez-sqlite](https://github.com/ober/chez-sqlite) | `sqlite-open`, `sqlite-query`, `sqlite-eval`, prepared statements |
| `(std db postgresql)` | [chez-postgresql](https://github.com/ober/chez-postgresql) | `pg-connect`, `pg-query`, `pg-eval`, parameterized queries |
| `(std pcre2)` | [chez-pcre2](https://github.com/ober/chez-pcre2) | `pcre2-compile`, `pcre2-search`, `pcre2-replace`, JIT regex |
| `(std os epoll)` | [chez-epoll](https://github.com/ober/chez-epoll) | `epoll-create`, `epoll-add!`, `epoll-wait`, edge-triggered I/O |
| `(std os inotify)` | [chez-inotify](https://github.com/ober/chez-inotify) | `inotify-init`, `inotify-add-watch!`, `inotify-read-events` |
| `(std crypto *)` | [chez-crypto](https://github.com/ober/chez-crypto) | `sha256`, `hmac-sha256`, `aes-encrypt`, `rsa-sign`, key derivation |

### FFI (`(jerboa ffi)`)
- `c-lambda` → `foreign-procedure` with automatic type translation
- `define-c-lambda` — named FFI bindings
- `begin-ffi`, `c-declare` — compatibility forms
- Full Gambit-to-Chez type mapping

### Reader (`(jerboa reader)`)
- `[1 2 3]` → `(list 1 2 3)`
- `{method obj}` → `(~ obj 'method)`
- `keyword:` → keyword objects
- `:std/sort` → `(std sort)` module paths
- Heredoc strings, datum comments, block comments

### Prelude (`(jerboa prelude)`)
One import for everything:
```scheme
(import (jerboa prelude))
```

## Testing

```bash
make test          # Core tests (289 tests)
make test-features # Phase 2+3 feature tests (637 tests)
make test-native   # Rust native backend tests (requires `make native` first)
make test-wrappers # Legacy chez-* library wrapper tests (27 tests)
make test-all      # Everything (953+ tests)
```

Runs 289 core tests across reader, core macros, runtime, standard library, FFI, module paths, and expanded stdlib. Feature tests add 637 more for Phase 2 and Phase 3 libraries. Native tests cover the Rust backend (crypto, compression, regex, databases, OS). Wrapper tests cover the legacy chez-* C library integrations.

## Requirements

- [Chez Scheme](https://cisco.github.io/ChezScheme/) 10.x (stock, unmodified)
- Optional: [Rust toolchain](https://rustup.rs/) for building `libjerboa_native.so` (crypto, compression, regex, databases, OS integration)
- Optional (legacy): [chez-*](https://github.com/ober) libraries for networking, compression, PCRE2, LevelDB, SQLite, PostgreSQL, epoll, inotify, crypto

## Project Structure

```
lib/
  jerboa/
    reader.sls      # Gerbil-compatible reader
    core.sls         # Core syntax macros
    runtime.sls      # Hash tables, method dispatch, keywords
    ffi.sls          # FFI translation macros
    prelude.sls      # All-in-one import
  std/
    sort.sls         # :std/sort
    format.sls       # :std/format
    error.sls        # :std/error
    sugar.sls        # :std/sugar
    text/json.sls    # :std/text/json
    os/path.sls      # :std/os/path
    misc/
      string.sls     # :std/misc/string
      list.sls        # :std/misc/list
      alist.sls       # :std/misc/alist
      ports.sls        # :std/misc/ports
      channel.sls      # :std/misc/channel
      thread.sls       # :std/misc/thread
      process.sls      # :std/misc/process
      queue.sls        # :std/misc/queue
      bytes.sls        # :std/misc/bytes
      uuid.sls         # :std/misc/uuid
      repr.sls         # :std/misc/repr
      completion.sls   # :std/misc/completion
    text/
      json.sls         # :std/text/json
      base64.sls       # :std/text/base64
      hex.sls          # :std/text/hex
      utf8.sls         # :std/text/utf8
      csv.sls          # :std/text/csv
      xml.sls          # :std/text/xml
      yaml.sls         # :std/text/yaml (pure Scheme, roundtrip)
      yaml/
        nodes.sls      # AST record types
        reader.sls     # YAML parser
        writer.sls     # YAML emitter
    os/
      path.sls         # :std/os/path
      env.sls          # :std/os/env
      temporaries.sls  # :std/os/temporaries
      signal.sls       # :std/os/signal
      fdio.sls         # :std/os/fdio
      epoll.sls        # :std/os/epoll (wraps chez-epoll — legacy)
      epoll-native.sls # :std/os/epoll-native (Rust via libjerboa_native.so)
      inotify.sls      # :std/os/inotify (wraps chez-inotify — legacy)
      inotify-native.sls # :std/os/inotify-native (Rust via libjerboa_native.so)
      landlock-native.sls # :std/os/landlock-native (Rust via libjerboa_native.so)
    net/
      request.sls      # :std/net/request (wraps chez-https — legacy)
      httpd.sls        # :std/net/httpd (wraps chez-https — legacy)
      ssl.sls          # :std/net/ssl (wraps chez-ssl — legacy)
    compress/
      zlib.sls         # :std/compress/zlib (wraps chez-zlib — legacy)
      native-rust.sls  # :std/compress/native-rust (flate2 via libjerboa_native.so)
    db/
      leveldb.sls      # :std/db/leveldb (wraps chez-leveldb — legacy)
      sqlite.sls       # :std/db/sqlite (wraps chez-sqlite — legacy)
      sqlite-native.sls # :std/db/sqlite-native (rusqlite via libjerboa_native.so)
      postgresql.sls   # :std/db/postgresql (wraps chez-postgresql — legacy)
      postgresql-native.sls # :std/db/postgresql-native (rust-postgres via libjerboa_native.so)
    crypto/
      digest.sls       # :std/crypto/digest
      native.sls       # :std/crypto/native (direct OpenSSL FFI — legacy)
      native-rust.sls  # :std/crypto/native-rust (ring via libjerboa_native.so)
      secure-mem.sls   # :std/crypto/secure-mem (mlock'd memory via Rust)
      cipher.sls       # :std/crypto/cipher (wraps chez-crypto — legacy)
      hmac.sls         # :std/crypto/hmac (wraps chez-crypto — legacy)
      pkey.sls         # :std/crypto/pkey (wraps chez-crypto — legacy)
      kdf.sls          # :std/crypto/kdf (wraps chez-crypto — legacy)
      etc.sls          # :std/crypto/etc (wraps chez-crypto — legacy)
    native.sls         # :std/native — Rust native library loader
    regex-native.sls   # :std/regex-native (Rust NFA regex via libjerboa_native.so)
    foreign.sls        # :std/foreign — FFI DSL
    cli/
      getopt.sls       # :std/cli/getopt
    srfi/
      srfi-13.sls      # :std/srfi/13
      srfi-19.sls      # :std/srfi/19
    pregexp.sls        # :std/pregexp
    pcre2.sls          # :std/pcre2 (wraps chez-pcre2 — legacy)
    test.sls           # :std/test
    logger.sls         # :std/logger
jerboa-native-rs/        # Rust native library project
  Cargo.toml             # ring, flate2, regex, rusqlite, postgres, inotify, libc
  src/
    lib.rs               # top-level: module declarations, init
    crypto.rs            # ring: digest, hmac, aead, csprng, pbkdf2, scrypt
    compress.rs          # flate2: deflate, inflate, gzip, gunzip
    regex_native.rs      # regex crate: compile, match, find, replace
    sqlite.rs            # rusqlite: open, prepare, bind, step, finalize
    postgres_native.rs   # rust-postgres: connect, query, execute
    epoll.rs             # epoll: create, ctl, wait
    inotify_native.rs    # inotify: init, add_watch, read_events
    landlock.rs          # landlock: ABI v1-v7, filesystem + network rules
    secure_mem.rs        # mlock, guard pages, explicit_bzero
    panic.rs             # catch_unwind wrapper for all extern "C" functions
tests/
  test-reader.ss       # 65 reader tests
  test-core.ss         # 68 core macro tests
  test-stdlib.ss       # 65 stdlib tests
  test-ffi.ss          # 7 FFI tests
  test-modules.ss      # 8 module path tests
  test-expanded-stdlib.ss  # 76 expanded stdlib tests
  test-wrappers.ss     # 27 wrapper module tests
  test-yaml-roundtrip.ss  # 58 YAML roundtrip tests
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
2. **Gambit `##` primitives** — provide needed ones case-by-case
3. **`(export #t)`** — re-export-everything needs explicit exports
4. **Gerbil-specific `syntax-case` binding semantics** — uses Chez R6RS semantics
