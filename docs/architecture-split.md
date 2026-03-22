# Architecture: chez-* vs jerboa Module Split

Last updated: 2026-03-22.

## The Problem

Jerboa has 489 stdlib modules with actors, structured concurrency, channels, contracts, custodians, error conditions, and more. But companion libraries like `chez-ssh` are written as pure R6RS — they can't use any of it. They're writing 2006-era Scheme on a 2026-era platform.

Why? Because chez-* libraries were designed for the broader Chez Scheme community. But jerboa is a personal project — the only consumers are jerboa, jerboa-emacs, and Claude. The "portability to stock Chez" constraint costs real capability for zero benefit.

## The Rule

**If it's just FFI, it's chez-*. If it has logic, it's jerboa.**

Specifically:

### chez-* libraries (pure R6RS, no jerboa dependency)

Thin wrappers around C libraries via `foreign-procedure`, `foreign-alloc`, and type marshaling. These are mechanical translations of C APIs into Scheme calling conventions. There's nothing to gain from actors or channels in a `foreign-procedure` call.

Examples of what belongs here:
- `foreign-procedure` declarations
- C struct packing/unpacking via `foreign-alloc` + `foreign-ref`/`foreign-set!`
- Enum/constant definitions
- Bytevector ↔ C pointer conversion
- Init/cleanup lifecycle (`ssl-init!`, `ssl-cleanup!`)
- Simple error code → condition translation

### jerboa modules (full platform)

Everything that does real work on top of FFI shims. Protocol state machines, connection management, session lifecycle, error handling, concurrency, resource cleanup — all of this benefits from jerboa's stdlib.

Examples of what belongs here:
- Connection pooling (uses `(std db conpool)`, mutexes, condition variables)
- Protocol state machines (uses `(std misc state-machine)`, match, error conditions)
- Session management (uses custodians for cleanup, actors for concurrency)
- Retry logic (uses `(std misc retry)`, structured concurrency)
- Streaming data processing (uses channels, lazy-seq, transducers)
- Resource lifecycle (uses `(std misc custodian)`, `(std misc guardian-pool)`)
- Contract-checked public APIs (uses `(std contract)`)

## Current Inventory

### Correctly placed in chez-* (FFI shims)

These are pure C glue — no logic beyond marshaling:

| Library | C Library | What It Does |
|---------|-----------|-------------|
| chez-ssl | OpenSSL | `ssl-connect`, `ssl-read`, `ssl-write` — direct SSL_* calls |
| chez-zlib | zlib | `gzip-bytevector`, `gunzip-bytevector` — direct compress/uncompress |
| chez-crypto | OpenSSL libcrypto | Hash, HMAC, cipher, Ed25519 — direct EVP_* calls |
| chez-sqlite | SQLite3 | `sqlite-open`, `sqlite-exec`, `sqlite-prepare` — direct sqlite3_* calls |
| chez-postgresql | libpq | `pg-connect`, `pg-exec` — direct PQ* calls |
| chez-leveldb | LevelDB | `leveldb-open`, `leveldb-put`, `leveldb-get` — direct C API |
| chez-pcre2 | PCRE2 | `pcre2-compile`, `pcre2-match` — direct pcre2_* calls |
| chez-epoll | Linux kernel | `epoll-create`, `epoll-wait` — direct syscalls |
| chez-inotify | Linux kernel | `inotify-init`, `inotify-add-watch` — direct syscalls |
| chez-scintilla | Scintilla | Editor widget message passing — direct Scintilla API |
| chez-qt | Qt6 | Widget creation, signals/slots — direct Qt C++ shim |

### Correctly placed in chez-* (pure Scheme, no jerboa needed)

| Library | Why chez-* |
|---------|-----------|
| chez-yaml | Pure parser — no concurrency, no resource management, just string → data |
| chez-r7rs | Standards compliance layer — must be stock Chez by definition |

### Migrated to jerboa (completed)

| Library | FFI shim in chez-* | Logic in jerboa |
|---------|-------------------|----------------|
| **chez-ssh** | `(chez-ssh crypto)` — 21 FFI bindings for TCP, SHA-256, HMAC, Curve25519, ChaCha20-Poly1305, AES-256-CTR, Ed25519. `(chez-ssh)` — agent key management FFI | `(std net ssh)` — 10 modules: wire format, transport, kex, auth, channel, session, SFTP, known-hosts, port forwarding, high-level client (3,132 lines) |

### Should migrate logic to jerboa

| Library | FFI shim stays in chez-* | Logic moves to jerboa |
|---------|-------------------------|----------------------|
| **chez-https** | Could stay as-is (it's already pure Scheme over chez-ssl) — but connection pooling, retry, redirect following would benefit from jerboa | HTTP client with connection reuse, redirect following, retry → `(std net http)` using `(std misc pool)`, `(std misc retry)`, error conditions |

### Future libraries: where to put them

When building new functionality, apply the rule:

| Task | chez-* | jerboa |
|------|--------|--------|
| Bind libcurl | `chez-curl`: `foreign-procedure` wrappers for `curl_easy_*` | `(std net curl)`: connection pooling, async requests via fibers, progress callbacks |
| Bind libgit2 | `chez-libgit2`: `foreign-procedure` wrappers for `git_*` | `(std vcs git)`: porcelain commands, diff formatting, merge logic |
| Bind libnotify | `chez-notify`: `foreign-procedure` for `notify_*` | `(std gui notify)`: notification builder with contracts |
| New protocol (gRPC, MQTT, etc.) | Nothing — no C library needed | `(std net grpc)`, `(std net mqtt)`: full protocol in jerboa using channels, actors, binary-type |
| New data format | Nothing if pure Scheme | `(std text ...)`: parser using jerboa's error conditions, streaming via lazy-seq |

## The Two-Layer Pattern

For libraries with both FFI and logic, use two layers:

```
chez-foo/           ← FFI shim, pure R6RS
  chez_foo_shim.c   ← C glue code
  foo.sls           ← foreign-procedure declarations + minimal wrappers

jerboa/lib/std/     ← application logic, full jerboa platform
  net/foo.sls       ← high-level API using chez-foo + jerboa stdlib
```

The chez-* layer exports raw operations. The jerboa layer adds:

1. **Error conditions** — translate error codes into `(std error conditions)` hierarchy
2. **Resource management** — register handles with custodians/guardian-pools
3. **Concurrency** — wrap blocking operations in fibers or async tasks
4. **Contracts** — validate inputs at API boundaries
5. **Composition** — integrate with channels, pools, retry, rate limiting

Example for SSH:

```scheme
;; chez-ssh exports (low-level, pure R6RS):
(ssh-connect host port)        → raw socket handle
(ssh-auth-publickey handle ...) → error code
(ssh-channel-open handle)      → raw channel handle

;; (std net ssh) exports (high-level, full jerboa):
(ssh-session host port
  #:auth (ssh-agent-auth)
  #:timeout 30.0)              → managed session with custodian cleanup

(with-ssh-session session
  (lambda (s)
    (ssh-exec s "ls -la")      → result with proper error conditions
    (ssh-sftp-put s local remote))) → uses channels for streaming
```

## chez-srfis

SRFIs are a special case. They are standards-defined APIs that should be usable from stock Chez, so they belong in `chez-srfis` (like `chez-r7rs`). Jerboa provides thin `(std srfi srfi-N)` re-export wrappers for namespace compatibility.

## Summary

| Question | Answer |
|----------|--------|
| Is it `foreign-procedure` calls? | chez-* |
| Is it a standards compliance layer (R7RS, SRFIs)? | chez-* |
| Is it a pure parser with no resource/concurrency needs? | chez-* (like chez-yaml) |
| Does it manage connections, sessions, or state? | jerboa |
| Does it need concurrency, retry, or pooling? | jerboa |
| Does it have a public API that should be contract-checked? | jerboa |
| Does it manage resources that need cleanup? | jerboa |
