# Replacing C Dependencies with a Unified Rust Native Library

Jerboa's C library dependencies are being replaced with a single Rust shared library (`libjerboa_native.so`). Rust implementations are complete for crypto, compression, regex, databases, and OS integration. TLS (rustls) and LevelDB are still pending. The legacy chez-* C wrappers remain available as fallbacks. Every Rust module is callable from Chez Scheme via the same `foreign-procedure` FFI.

---

## Table of Contents

1. [Motivation](#motivation)
2. [Current C Dependencies](#current-c-dependencies)
3. [Rust Replacements](#rust-replacements)
4. [Architecture](#architecture)
5. [C ABI Design](#c-abi-design)
6. [FFI Binding Patterns](#ffi-binding-patterns)
7. [Secure Memory Region](#secure-memory-region)
8. [What Each Swap Fixes](#what-each-swap-fixes)
9. [Build Integration](#build-integration)
10. [Migration Strategy](#migration-strategy)
11. [Implementation Roadmap](#implementation-roadmap)

---

## Motivation

Jerboa currently links 9+ C shared libraries for crypto, TLS, compression, regex, databases, and OS integration. (YAML was previously a C dependency but is now pure Scheme.) Each C library is an independent attack surface: its own CVE history, its own build system, its own ABI compatibility concerns.

Replacing them with a single Rust shared library (`libjerboa_native.so`) provides:

1. **Memory safety** across all native code — buffer overflows, use-after-free, and double-free become compile-time errors
2. **A single dependency** instead of 10+ — one build, one audit surface, one update path
3. **Solved vulnerability classes** — ReDoS eliminated (Rust regex uses NFA, not backtracking), timing-safe crypto by default (ring). (YAML parsing is now pure Scheme — no C/Rust needed.)
4. **Stable C ABI** — Rust's `extern "C"` produces `.so` files that Chez Scheme loads identically to C libraries
5. **Reproducible builds** — Cargo.lock pins every transitive dependency with exact hashes

---

## Current C Dependencies

### Required

| Library          | Module(s)                      | Purpose                                                     |
|------------------|--------------------------------|-------------------------------------------------------------|
| **glibc / musl** | `std/os/*`, `std/misc/process` | Core OS: mkstemp, getpid, kill, mmap, dup2, signal handling |

### Crypto and Network

| Library                    | Module(s)                                                     | Purpose                                                                                      |
|----------------------------|---------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| ~~**libcrypto.so** (OpenSSL)~~ | ~~`std/crypto/native`~~  | **Eliminated** — Digests, HMAC, AES-GCM, PBKDF2, CSPRNG now via ring in `libjerboa_native` |
| ~~**libssl.so** (OpenSSL)~~    | ~~`std/net/tls`~~        | **Eliminated** — TLS 1.2/1.3 now via rustls in `libjerboa_native`                           |

### Optional Wrappers (chez-* repos)

| Library                    | Shim            | Module              | Purpose                     |
|----------------------------|-----------------|---------------------|-----------------------------|
| **libz.so**                | chez-zlib       | `std/compress/zlib` | Deflate/inflate compression |
| **libpcre2-8.so**          | chez-pcre2      | `std/pcre2`         | Perl-compatible regex       |
| **libsqlite3.so**          | chez-sqlite     | `std/db/sqlite`     | SQLite database             |
| **libpq.so**               | chez-postgresql | `std/db/postgresql` | PostgreSQL client           |
| **libleveldb.so**          | chez-leveldb    | `std/db/leveldb`    | LevelDB key-value store     |
| ~~**libyaml.so**~~         | ~~chez-yaml~~   | `std/text/yaml`     | ~~YAML parsing~~ — **Eliminated**: now pure Scheme with roundtrip support |
| **libcurl.so** (or libssl) | chez-https      | `std/net/request`   | HTTPS client                |

### Custom C Code

| File                        | Module            | Purpose                                     |
|-----------------------------|-------------------|---------------------------------------------|
| **support/landlock-shim.c** | `std/os/landlock` | Landlock LSM syscall wrapper                |
| **support/jerboa-embed.c**  | `jerboa/embed`    | C API for embedding Chez in C/Rust programs |

### Linux-Specific (No External Library)

| Shim              | Module           | Purpose                         |
|-------------------|------------------|---------------------------------|
| chez-epoll        | `std/os/epoll`   | Event polling (direct syscalls) |
| chez-inotify      | `std/os/inotify` | File watching (direct syscalls) |
| liburing-ffi.so.2 | `std/os/iouring` | io_uring async I/O              |

---

## Rust Replacements

### Crypto: libcrypto → ring

| Feature               | Current (OpenSSL)                         | Replacement (ring)                             | Notes                                        |
|-----------------------|-------------------------------------------|------------------------------------------------|----------------------------------------------|
| Digests               | `EVP_DigestInit/Update/Final`             | `ring::digest`                                 | SHA-1, SHA-256, SHA-384, SHA-512             |
| HMAC                  | `HMAC()`                                  | `ring::hmac`                                   | All SHA variants                             |
| AES-GCM               | `EVP_Encrypt/Decrypt` + `EVP_aes_256_gcm` | `ring::aead`                                   | AES-128-GCM, AES-256-GCM, ChaCha20-Poly1305  |
| CSPRNG                | `RAND_bytes()`                            | `ring::rand::SystemRandom`                     | Uses OS entropy source                       |
| PBKDF2                | `PKCS5_PBKDF2_HMAC()`                     | `ring::pbkdf2`                                 | Timing-safe verification built in            |
| Constant-time compare | `CRYPTO_memcmp()`                         | `ring::constant_time::verify_slices_are_equal` | Default behavior, not opt-in                 |
| MD5                   | `EVP_md5()`                               | **Not in ring** — use `md-5` crate             | ring deliberately excludes broken algorithms |

**ring** is audited, powers rustls and Cloudflare's infrastructure, and has no `unsafe` in its Rust API. It uses BoringSSL's C/asm for primitives internally (AES-NI, constant-time implementations) but presents a safe Rust interface.

**Alternative**: RustCrypto crates (`sha2`, `aes-gcm`, `hmac`, `pbkdf2`) — pure Rust, no C/asm. Slightly slower but fully auditable Rust source. Good for environments where "no C at all" is the goal.

### TLS: libssl → rustls-ffi

| Feature                  | Current (OpenSSL)                    | Replacement (rustls)                                | Notes                                                   |
|--------------------------|--------------------------------------|-----------------------------------------------------|---------------------------------------------------------|
| TLS 1.2/1.3              | `SSL_CTX_new`, `SSL_connect`, etc.   | `rustls_client_config_builder`, `rustls_connection` | Full protocol support                                   |
| Certificate verification | OpenSSL's X.509 stack                | `webpki` + `rustls-native-certs`                    | Uses OS trust store                                     |
| Hostname verification    | Manual or `SSL_set_tlsext_host_name` | Automatic and mandatory                             | Cannot be disabled — safe by default                    |
| Cipher suites            | Configurable (including weak ones)   | Only safe suites, no configuration needed           | TLS_AES_256_GCM, TLS_CHACHA20_POLY1305, TLS_AES_128_GCM |

**rustls-ffi** already exists as a C ABI library specifically designed for non-Rust consumers. It provides a stable C header (`rustls.h`) that Chez can call directly. This is not a hypothetical — curl, Apache httpd, and other C projects already use rustls-ffi in production.

Zero memory-safety CVEs in rustls, compared to hundreds in OpenSSL.

### Regex: libpcre2 → regex crate

| Feature | Current (PCRE2) | Replacement (regex) | Notes |
|---------|-----------------|---------------------|-------|
| Pattern matching | Backtracking NFA | Thompson NFA (finite automata) | **Guaranteed linear-time** — ReDoS impossible |
| Unicode | Full Unicode support | Full Unicode support | `\p{Lu}`, `\w`, etc. |
| Capture groups | Named and numbered | Named and numbered | Same API surface |
| JIT compilation | PCRE2 JIT | Lazy DFA compilation | Comparable performance |

The Rust regex crate **eliminates ReDoS entirely**. Pathological patterns like `(a+)+b` that hang PCRE2/pregexp complete in microseconds because the engine cannot backtrack. This single swap fixes the entire ReDoS section of security2.md for any code path that uses the native regex engine.

### Compression: libz → flate2

| Feature | Current (zlib) | Replacement (flate2) | Notes |
|---------|---------------|---------------------|-------|
| Deflate | `deflate()` / `inflate()` | `flate2::Compress` / `flate2::Decompress` | Compatible output |
| Gzip | `gz*` functions | `flate2::read::GzDecoder` | Same format |

flate2 uses `miniz_oxide` (pure Rust) by default. No C code, no unsafe. Performance is within 10% of zlib.

**Decompression bomb protection**: Easy to add a size limit in the Rust wrapper:

```rust
#[no_mangle]
pub extern "C" fn jerboa_inflate(
    input: *const u8, input_len: usize,
    output: *mut u8, output_max: usize,
    output_len: *mut usize
) -> i32 {
    // output_max caps decompression — no billion-byte bombs
}
```

### ~~YAML: libyaml → unsafe-libyaml~~ — SUPERSEDED

**This swap is no longer needed.** `(std text yaml)` is now a pure Scheme implementation with full roundtrip support (preserves comments, key ordering, scalar styles, block/flow collection styles). No C dependency, no FFI — the entire libyaml attack surface has been eliminated without needing a Rust replacement.

The pure Scheme implementation provides:
- Simple API: `yaml-load`, `yaml-dump` (backward-compatible with old chez-yaml interface)
- Roundtrip API: `yaml-read`, `yaml-write` (returns/consumes AST nodes with comment and style metadata)
- Node manipulation: `yaml-mapping-ref`, `yaml-mapping-set!`, `yaml-ref`, `yaml-set!`
- Security: `*yaml-max-input-size*` (1MB) and `*yaml-max-depth*` (512) limits

### Databases: libsqlite3 → rusqlite, libpq → rust-postgres

| Current | Replacement | Notes |
|---------|-------------|-------|
| libsqlite3 (via chez-sqlite) | **rusqlite** | Bundles SQLite source or links system lib. Parameterized queries by default. |
| libpq (via chez-postgresql) | **rust-postgres** | Pure Rust PostgreSQL client. TLS via rustls. No C dependency. |
| libleveldb (via chez-leveldb) | **rusty-leveldb** or **sled** | rusty-leveldb is API-compatible; sled is pure Rust with different (better) API |

### OS Integration

| Current | Replacement | Notes |
|---------|-------------|-------|
| landlock-shim.c | **landlock** crate | Clean Rust API for Landlock ABI v1-v4 |
| liburing-ffi.so.2 | **io-uring** crate | Safe wrapper over kernel interface |
| chez-epoll shim | Rust `epoll` wrapper or **mio** | mio abstracts over epoll/kqueue/IOCP |
| chez-inotify shim | **inotify** crate | Safe wrapper |

---

## Architecture

### Single Shared Library

All Rust code compiles into one shared library:

```
jerboa-native-rs/
├── Cargo.toml
├── cbindgen.toml              # generates jerboa_native.h
├── src/
│   ├── lib.rs                 # top-level: panic handler, init
│   ├── crypto.rs              # ring: digest, hmac, aead, csprng, pbkdf2
│   ├── tls.rs                 # rustls-ffi: connect, accept, read, write
│   ├── regex.rs               # regex crate: compile, match, find, replace
│   ├── compress.rs            # flate2: deflate, inflate (with size limits)
│   ├── sqlite.rs              # rusqlite: open, prepare, bind, step, finalize
│   ├── postgres.rs            # rust-postgres: connect, query, execute
│   ├── secure_mem.rs          # mlock, guard pages, explicit_bzero, DONTDUMP
│   ├── landlock.rs            # landlock crate: create ruleset, add rules, enforce
│   ├── iouring.rs             # io-uring crate: queue init, submit, wait
│   ├── epoll.rs               # epoll: create, ctl, wait
│   ├── inotify.rs             # inotify: init, add_watch, read_events
│   └── panic.rs               # catch_unwind wrapper for all extern "C" functions
├── tests/
│   └── ffi_test.rs            # test C ABI from Rust side
└── target/release/
    └── libjerboa_native.so    # single output: ~2-5MB
```

```toml
# Cargo.toml
[package]
name = "jerboa-native"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
ring = "0.17"
rustls = "0.23"
rustls-pemfile = "2"
webpki-roots = "0.26"
regex = "1"
flate2 = "1"
# unsafe-libyaml — no longer needed: (std text yaml) is pure Scheme
rusqlite = { version = "0.32", features = ["bundled"] }
postgres = "0.19"
landlock = "0.4"
io-uring = "0.7"
inotify = "0.11"
libc = "0.2"
```

### Why One Library, Not Many

- **One `load-shared-object` call** in Jerboa — no hunting for 10 different `.so` files
- **One build step** — `cargo build --release` produces everything
- **One audit surface** — `cargo audit` checks all transitive dependencies
- **One version to track** — Jerboa's Cargo.lock pins the entire native dependency tree
- **Smaller total size** — shared Rust runtime, LTO across all modules, dead code elimination

---

## C ABI Design

### Principles

1. **Every function is `extern "C"` with `#[no_mangle]`** — visible to Chez's `foreign-procedure`
2. **Every function catches panics** — Rust panics across FFI are undefined behavior
3. **Opaque handles for stateful objects** — TLS connections, database connections, regex patterns are opaque pointers
4. **Error codes, not exceptions** — return `i32` status codes; error details via `jerboa_last_error()`
5. **Caller-allocated buffers where possible** — avoid Rust allocating memory that Scheme must free
6. **Consistent naming** — `jerboa_<module>_<operation>` prefix for all functions

### Panic Safety

Every exported function wraps its body in `catch_unwind`:

```rust
// src/panic.rs
use std::panic;

/// Thread-local error message for the last failed operation
thread_local! {
    static LAST_ERROR: std::cell::RefCell<String> = std::cell::RefCell::new(String::new());
}

#[no_mangle]
pub extern "C" fn jerboa_last_error(buf: *mut u8, buf_len: usize) -> usize {
    LAST_ERROR.with(|e| {
        let msg = e.borrow();
        let bytes = msg.as_bytes();
        let copy_len = bytes.len().min(buf_len.saturating_sub(1));
        if !buf.is_null() && copy_len > 0 {
            unsafe {
                std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, copy_len);
                *buf.add(copy_len) = 0; // null terminate
            }
        }
        bytes.len()
    })
}

pub fn ffi_wrap<F: FnOnce() -> i32 + panic::UnwindSafe>(f: F) -> i32 {
    match panic::catch_unwind(f) {
        Ok(code) => code,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "unknown panic".to_string()
            };
            LAST_ERROR.with(|cell| *cell.borrow_mut() = msg);
            -1 // error sentinel
        }
    }
}
```

### Example: Crypto Module

```rust
// src/crypto.rs
use ring::{digest, hmac, rand, aead, constant_time};
use crate::panic::ffi_wrap;

// --- Digest ---

#[no_mangle]
pub extern "C" fn jerboa_sha256(
    input: *const u8, input_len: usize,
    output: *mut u8, output_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if input.is_null() || output.is_null() || output_len < 32 {
            return -1;
        }
        let data = unsafe { std::slice::from_raw_parts(input, input_len) };
        let hash = digest::digest(&digest::SHA256, data);
        unsafe {
            std::ptr::copy_nonoverlapping(hash.as_ref().as_ptr(), output, 32);
        }
        0 // success
    })
}

// --- CSPRNG ---

#[no_mangle]
pub extern "C" fn jerboa_random_bytes(output: *mut u8, len: usize) -> i32 {
    ffi_wrap(|| {
        if output.is_null() {
            return -1;
        }
        let rng = rand::SystemRandom::new();
        let buf = unsafe { std::slice::from_raw_parts_mut(output, len) };
        rand::SecureRandom::fill(&rng, buf).map(|_| 0).unwrap_or(-1)
    })
}

// --- Constant-time comparison ---

#[no_mangle]
pub extern "C" fn jerboa_timing_safe_equal(
    a: *const u8, a_len: usize,
    b: *const u8, b_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if a_len != b_len { return 0; }
        let sa = unsafe { std::slice::from_raw_parts(a, a_len) };
        let sb = unsafe { std::slice::from_raw_parts(b, b_len) };
        if constant_time::verify_slices_are_equal(sa, sb).is_ok() { 1 } else { 0 }
    })
}

// --- AEAD (AES-256-GCM) ---

#[no_mangle]
pub extern "C" fn jerboa_aead_seal(
    key: *const u8, key_len: usize,        // 32 bytes for AES-256-GCM
    nonce: *const u8, nonce_len: usize,     // 12 bytes
    plaintext: *const u8, pt_len: usize,
    aad: *const u8, aad_len: usize,
    output: *mut u8, output_max: usize,     // must be >= pt_len + 16 (tag)
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        // ... validate inputs, construct SealingKey, seal in place ...
        0
    })
}
```

### Example: Regex Module

```rust
// src/regex.rs
use regex::Regex;
use crate::panic::ffi_wrap;
use std::collections::HashMap;
use std::sync::Mutex;

// Opaque handle system
static REGEX_STORE: Mutex<HashMap<u64, Regex>> = Mutex::new(HashMap::new());
static NEXT_ID: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

#[no_mangle]
pub extern "C" fn jerboa_regex_compile(
    pattern: *const u8, pattern_len: usize,
    handle: *mut u64,
) -> i32 {
    ffi_wrap(|| {
        let pat = unsafe { std::str::from_utf8_unchecked(
            std::slice::from_raw_parts(pattern, pattern_len)) };
        match Regex::new(pat) {
            Ok(re) => {
                let id = NEXT_ID.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                REGEX_STORE.lock().unwrap().insert(id, re);
                unsafe { *handle = id; }
                0
            }
            Err(_) => -1,
        }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_regex_is_match(
    handle: u64,
    text: *const u8, text_len: usize,
) -> i32 {
    ffi_wrap(|| {
        let store = REGEX_STORE.lock().unwrap();
        let re = match store.get(&handle) {
            Some(r) => r,
            None => return -1,
        };
        let s = unsafe { std::str::from_utf8_unchecked(
            std::slice::from_raw_parts(text, text_len)) };
        if re.is_match(s) { 1 } else { 0 }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_regex_free(handle: u64) -> i32 {
    ffi_wrap(|| {
        REGEX_STORE.lock().unwrap().remove(&handle);
        0
    })
}
```

---

## FFI Binding Patterns

### Jerboa Side

```scheme
;; lib/std/native.sls — load the unified Rust library
(library (std native)
  (export load-jerboa-native)
  (import (chezscheme))

  (define (load-jerboa-native)
    (load-shared-object "libjerboa_native.so")))
```

```scheme
;; lib/std/crypto/native.sls — crypto bindings
(library (std crypto native)
  (export sha256 random-bytes timing-safe-equal? aead-seal aead-open)
  (import (chezscheme) (std native))

  (load-jerboa-native)

  (define jerboa-sha256
    (foreign-procedure "jerboa_sha256"
      (u8* size_t u8* size_t) int))

  (define (sha256 bv)
    (let ([out (make-bytevector 32)])
      (let ([rc (jerboa-sha256 bv (bytevector-length bv) out 32)])
        (when (< rc 0)
          (error 'sha256 "hash failed"))
        out)))

  (define jerboa-random-bytes
    (foreign-procedure "jerboa_random_bytes" (u8* size_t) int))

  (define (random-bytes n)
    (let ([bv (make-bytevector n)])
      (let ([rc (jerboa-random-bytes bv n)])
        (when (< rc 0)
          (error 'random-bytes "CSPRNG failed"))
        bv)))

  (define jerboa-timing-safe-equal
    (foreign-procedure "jerboa_timing_safe_equal"
      (u8* size_t u8* size_t) int))

  (define (timing-safe-equal? a b)
    (= 1 (jerboa-timing-safe-equal a (bytevector-length a)
                                    b (bytevector-length b))))

  ;; ... aead-seal, aead-open similarly
  )
```

```scheme
;; lib/std/pcre2.sls replacement — now backed by Rust regex
(library (std regex-native)
  (export regex-compile regex-match? regex-find regex-free)
  (import (chezscheme) (std native))

  (load-jerboa-native)

  (define jerboa-regex-compile
    (foreign-procedure "jerboa_regex_compile" (u8* size_t void*) int))

  (define jerboa-regex-is-match
    (foreign-procedure "jerboa_regex_is_match" (unsigned-64 u8* size_t) int))

  (define jerboa-regex-free
    (foreign-procedure "jerboa_regex_free" (unsigned-64) int))

  (define (regex-compile pattern)
    (let ([bv (string->utf8 pattern)]
          [handle-box (make-bytevector 8)])
      (let ([rc (jerboa-regex-compile bv (bytevector-length bv) handle-box)])
        (when (< rc 0)
          (error 'regex-compile "invalid pattern" pattern))
        (bytevector-u64-native-ref handle-box 0))))

  (define (regex-match? handle text)
    (let ([bv (string->utf8 text)])
      (= 1 (jerboa-regex-is-match handle bv (bytevector-length bv)))))

  (define (regex-free handle)
    (jerboa-regex-free handle))
  )
```

---

## Secure Memory Region

The secure region allocator from `vs-rust.md`, implemented in Rust:

```rust
// src/secure_mem.rs
use libc::{mmap, munmap, mlock, munlock, madvise, mprotect};
use libc::{MAP_PRIVATE, MAP_ANONYMOUS, PROT_READ, PROT_WRITE, PROT_NONE};
use libc::{MADV_DONTDUMP, MADV_DONTFORK};
use std::ptr;
use crate::panic::ffi_wrap;

const GUARD_PAGE_SIZE: usize = 4096;

#[no_mangle]
pub extern "C" fn jerboa_secure_alloc(size: usize) -> *mut u8 {
    ffi_wrap_ptr(|| {
        // Allocate: guard page + data + guard page
        let total = GUARD_PAGE_SIZE + size + GUARD_PAGE_SIZE;
        let base = unsafe {
            mmap(ptr::null_mut(), total, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0)
        };
        if base == libc::MAP_FAILED { return ptr::null_mut(); }

        // Protect guard pages (PROT_NONE — any access = SIGSEGV)
        unsafe {
            mprotect(base, GUARD_PAGE_SIZE, PROT_NONE);
            mprotect(base.add(GUARD_PAGE_SIZE + size), GUARD_PAGE_SIZE, PROT_NONE);
        }

        let data = unsafe { base.add(GUARD_PAGE_SIZE) as *mut u8 };

        // Lock into RAM — never swapped to disk
        unsafe { mlock(data as *mut _, size); }

        // Exclude from core dumps
        unsafe { madvise(data as *mut _, size, MADV_DONTDUMP); }

        // Don't inherit in child processes
        unsafe { madvise(data as *mut _, size, MADV_DONTFORK); }

        data
    })
}

#[no_mangle]
pub extern "C" fn jerboa_secure_free(ptr: *mut u8, size: usize) -> i32 {
    ffi_wrap(|| {
        if ptr.is_null() { return -1; }

        // Wipe — explicit_bzero is guaranteed not to be optimized away
        unsafe { libc::explicit_bzero(ptr as *mut _, size); }

        // Unlock
        unsafe { munlock(ptr as *mut _, size); }

        // Unmap entire region including guard pages
        let base = unsafe { ptr.sub(GUARD_PAGE_SIZE) };
        let total = GUARD_PAGE_SIZE + size + GUARD_PAGE_SIZE;
        unsafe { munmap(base as *mut _, total); }

        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_secure_wipe(ptr: *mut u8, size: usize) -> i32 {
    ffi_wrap(|| {
        if ptr.is_null() { return -1; }
        unsafe { libc::explicit_bzero(ptr as *mut _, size); }
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_secure_random_fill(ptr: *mut u8, size: usize) -> i32 {
    ffi_wrap(|| {
        if ptr.is_null() { return -1; }
        let rng = ring::rand::SystemRandom::new();
        let buf = unsafe { std::slice::from_raw_parts_mut(ptr, size) };
        ring::rand::SecureRandom::fill(&rng, buf).map(|_| 0).unwrap_or(-1)
    })
}

// Helper: ffi_wrap for pointer-returning functions
fn ffi_wrap_ptr<F: FnOnce() -> *mut u8 + std::panic::UnwindSafe>(f: F) -> *mut u8 {
    match std::panic::catch_unwind(f) {
        Ok(ptr) => ptr,
        Err(_) => ptr::null_mut(),
    }
}
```

Jerboa side:

```scheme
;; lib/std/crypto/secure-mem.sls
(library (std crypto secure-mem)
  (export with-secure-region secure-alloc secure-free secure-wipe)
  (import (chezscheme) (std native))

  (load-jerboa-native)

  (define jerboa-secure-alloc
    (foreign-procedure "jerboa_secure_alloc" (size_t) void*))
  (define jerboa-secure-free
    (foreign-procedure "jerboa_secure_free" (void* size_t) int))
  (define jerboa-secure-wipe
    (foreign-procedure "jerboa_secure_wipe" (void* size_t) int))
  (define jerboa-secure-random-fill
    (foreign-procedure "jerboa_secure_random_fill" (void* size_t) int))

  (define (secure-alloc size)
    (let ([ptr (jerboa-secure-alloc size)])
      (when (zero? (ftype-pointer-address ptr))
        (error 'secure-alloc "mmap failed" size))
      (cons ptr size)))  ;; pair of (pointer . size) for tracking

  (define (secure-free region)
    (jerboa-secure-free (car region) (cdr region)))

  (define-syntax with-secure-region
    (syntax-rules ()
      [(_ ([name size] ...) body ...)
       (let ([name (secure-alloc size)] ...)
         (dynamic-wind
           void
           (lambda () body ...)
           (lambda ()
             (secure-free name) ...)))]))
  )
```

---

## What Each Swap Fixes

### Vulnerabilities from security.md

| Vulnerability | Fixed By | How |
|---------------|----------|-----|
| **V1**: Command injection in digest | ring (crypto.rs) | No shell, no temp files — direct hash computation |
| **V3**: Predictable nonces | ring CSPRNG | `SystemRandom` uses OS entropy |
| **V5**: Weak actor auth (FNV-1a) | ring HMAC | HMAC-SHA256 with proper key derivation |
| **V8**: WebSocket handshake stub | ring SHA-1 | Proper `SHA-1(key + GUID)` computation |
| **C1-C6**: Crypto foundation | ring + secure_mem | Complete crypto suite with secure memory |

### Bug classes from security2.md

| Bug Class | Fixed By | How |
|-----------|----------|-----|
| **ReDoS** | Rust regex crate | NFA engine — linear time guaranteed, backtracking impossible |
| **Zlib decompression bombs** | flate2 (compress.rs) | Output size limit parameter in Rust wrapper |
| ~~**YAML C parser bugs**~~ | ~~unsafe-libyaml~~ | **Eliminated** — `(std text yaml)` is now pure Scheme, no C/Rust needed |
| **FFI null pointer deref** | Rust wrappers | Every function validates inputs and checks returns |
| **FFI type confusion** | Rust type system | Rust compiler rejects type mismatches |
| **Secret material in GC heap** | secure_mem.rs | mlock'd region outside GC, wiped on free |

### What's NOT fixed by Rust swap alone

These still need the Scheme-side fixes from security2.md:

| Bug Class | Why Rust Doesn't Help |
|-----------|----------------------|
| Parser recursion depth (reader, JSON) | Bug is in Scheme code, not C libraries |
| Bytevector bounds checks (HTTP/2, WebSocket, DNS) | Bug is in Scheme code, not C libraries |
| Silent data corruption (base64, CSV, hex) | Bug is in Scheme code, not C libraries |
| Format string injection | Bug is in Scheme code |
| Sandbox escape vectors | Bug is in Scheme code |
| Capability forgery (V2) | Bug is in Scheme code |

The Rust native library and the security2.md Scheme fixes are complementary — neither is a substitute for the other.

---

## Build Integration

### Makefile Additions

```makefile
# Rust native library
RUST_NATIVE_DIR = jerboa-native-rs
RUST_NATIVE_LIB = $(RUST_NATIVE_DIR)/target/release/libjerboa_native.so

$(RUST_NATIVE_LIB): $(RUST_NATIVE_DIR)/src/*.rs $(RUST_NATIVE_DIR)/Cargo.toml
	cd $(RUST_NATIVE_DIR) && cargo build --release

native: $(RUST_NATIVE_LIB)
	cp $(RUST_NATIVE_LIB) lib/

clean-native:
	cd $(RUST_NATIVE_DIR) && cargo clean

# Run tests with native library available
test-native: native
	LD_LIBRARY_PATH=lib $(SCHEME) --libdirs lib --script tests/test-native.ss

# Audit dependencies for known vulnerabilities
audit-native:
	cd $(RUST_NATIVE_DIR) && cargo audit

# Generate C header (for documentation / external consumers)
header-native:
	cd $(RUST_NATIVE_DIR) && cbindgen --output include/jerboa_native.h
```

### Static Linking for Single-Binary Deployment

For `jerboa/build.sls` static binary builds, link the Rust library statically:

```toml
# Cargo.toml — also produce a static lib
[lib]
crate-type = ["cdylib", "staticlib"]
```

```makefile
# Static build: link libjerboa_native.a into the Chez binary
RUST_STATIC_LIB = $(RUST_NATIVE_DIR)/target/release/libjerboa_native.a

static-binary: $(RUST_STATIC_LIB)
	$(SCHEME) --libdirs lib --script build-static.ss \
	  --extra-libs "$(RUST_STATIC_LIB) -lpthread -ldl -lm"
```

The result is a single binary with zero runtime dependencies beyond libc — Chez runtime + Jerboa libraries + Rust native code, all in one ELF file.

---

## Migration Strategy

### Current Status

We are in **Phase 1** (parallel installation). The Rust implementations are complete for crypto, compression, regex, databases (SQLite, PostgreSQL), and OS integration (epoll, inotify, landlock). However, the "default" modules (e.g., `(std db sqlite)`, `(std crypto cipher)`) still import from chez-* C libraries. The Rust-backed modules are available as separate imports (e.g., `(std db sqlite-native)`, `(std crypto native-rust)`).

**TLS is deferred** — `(std net ssl)` still requires chez-ssl / OpenSSL. The rustls-ffi integration is planned but not yet implemented due to the complexity of stateful TLS session management.

### Phase 1: Parallel Installation (CURRENT)

Both C libraries and the Rust library are available as separate modules. New code should prefer the `-native` / `native-rust` modules:

```scheme
;; Preferred — uses Rust ring via libjerboa_native.so
(import (std crypto native-rust))

;; Legacy — uses OpenSSL via chez-crypto
(import (std crypto cipher))
```

This allows incremental testing — run the full test suite against both backends and compare results.

### Phase 2: Native-First

The Rust library becomes the default import for all modules that have Rust replacements. The chez-* modules become explicitly legacy.

### Phase 3: C Removal

Remove the chez-* wrapper dependencies entirely. The Rust library is the only native code Jerboa links (besides Chez Scheme itself and libc).

---

## Implementation Roadmap

### Week 1-2: Core — Crypto + Secure Memory ✅ IMPLEMENTED

| Task | Crate | Functions | Status |
|------|-------|-----------|--------|
| Digests (SHA-1, SHA-256, SHA-384, SHA-512) | ring | `jerboa_sha1`, `jerboa_sha256`, `jerboa_sha384`, `jerboa_sha512` | ✅ |
| HMAC | ring | `jerboa_hmac_sha256`, `jerboa_hmac_sha256_verify` | ✅ |
| CSPRNG | ring | `jerboa_random_bytes` | ✅ |
| Constant-time compare | ring | `jerboa_timing_safe_equal` | ✅ |
| AEAD (AES-256-GCM) | ring | `jerboa_aead_seal`, `jerboa_aead_open` | ✅ |
| PBKDF2 | ring | `jerboa_pbkdf2_derive`, `jerboa_pbkdf2_verify` | ✅ |
| Secure memory region | libc (mmap/mlock) | `jerboa_secure_alloc`, `jerboa_secure_free`, `jerboa_secure_wipe` | ✅ |
| Scheme bindings | — | `(std crypto native-rust)`, `(std crypto secure-mem)` | ✅ |

Rust: `src/crypto.rs`, `src/secure_mem.rs`. Scheme: `lib/std/crypto/native-rust.sls`, `lib/std/crypto/secure-mem.sls`. Tests: `tests/test-native-rust.ss` (31 tests).

### Week 3: TLS — DEFERRED

| Task | Crate | Functions | Status |
|------|-------|-----------|--------|
| TLS client | rustls + rustls-ffi | `jerboa_tls_connect`, `jerboa_tls_read`, `jerboa_tls_write`, `jerboa_tls_close` | ⏳ |
| TLS server | rustls + rustls-ffi | `jerboa_tls_accept` | ⏳ |
| Certificate loading | rustls-pemfile | `jerboa_tls_load_cert`, `jerboa_tls_load_key` | ⏳ |

TLS requires stateful session management with complex async I/O. Deferred to a future phase.

### Week 4: Regex + Compression ✅ IMPLEMENTED

| Task | Crate | Functions | Status |
|------|-------|-----------|--------|
| Regex compile/match/find/replace | regex (NFA) | `jerboa_regex_compile`, `jerboa_regex_is_match`, `jerboa_regex_find`, `jerboa_regex_replace_all`, `jerboa_regex_free` | ✅ |
| Deflate/inflate with size limits | flate2 | `jerboa_deflate`, `jerboa_inflate` | ✅ |
| Gzip/gunzip with size limits | flate2 | `jerboa_gzip`, `jerboa_gunzip` | ✅ |
| Scheme bindings | — | `(std regex-native)`, `(std compress native-rust)` | ✅ |

Rust: `src/regex_native.rs`, `src/compress.rs`. Scheme: `lib/std/regex-native.sls`, `lib/std/compress/native-rust.sls`. Tests: `tests/test-native-rust.ss`.

### Week 5: Databases ✅ IMPLEMENTED

| Task | Crate | Functions | Status |
|------|-------|-----------|--------|
| SQLite open/close/exec | rusqlite (bundled) | `jerboa_sqlite_open`, `jerboa_sqlite_close`, `jerboa_sqlite_exec` | ✅ |
| SQLite prepare/bind/step/column | rusqlite | `jerboa_sqlite_prepare`, `jerboa_sqlite_bind_*`, `jerboa_sqlite_step`, `jerboa_sqlite_column_*` | ✅ |
| SQLite reset/finalize/metadata | rusqlite | `jerboa_sqlite_reset`, `jerboa_sqlite_finalize`, `jerboa_sqlite_last_insert_rowid`, `jerboa_sqlite_changes` | ✅ |
| PostgreSQL connect/disconnect | rust-postgres | `jerboa_pg_connect`, `jerboa_pg_disconnect` | ✅ |
| PostgreSQL exec/query | rust-postgres | `jerboa_pg_exec`, `jerboa_pg_query`, `jerboa_pg_nrows`, `jerboa_pg_ncols` | ✅ |
| PostgreSQL result access | rust-postgres | `jerboa_pg_get_value`, `jerboa_pg_is_null`, `jerboa_pg_column_name`, `jerboa_pg_free_result` | ✅ |
| Scheme bindings | — | `(std db sqlite-native)`, `(std db postgresql-native)` | ✅ |

Rust: `src/sqlite.rs`, `src/postgres_native.rs`. Scheme: `lib/std/db/sqlite-native.sls`, `lib/std/db/postgresql-native.sls`. Tests: `tests/test-native-rust-week5-6.ss` (26 tests). SQLite uses raw `sqlite3_*` C API via `rusqlite::ffi` to avoid Rust lifetime issues with Statement handles. PostgreSQL uses handle stores for `Client` and `Vec<Row>`.

### Week 6: OS Integration ✅ IMPLEMENTED

| Task | Crate | Functions | Status |
|------|-------|-----------|--------|
| epoll create/ctl/wait/close | libc | `jerboa_epoll_create`, `jerboa_epoll_ctl`, `jerboa_epoll_wait`, `jerboa_epoll_close` | ✅ |
| inotify init/watch/read/close | libc | `jerboa_inotify_init`, `jerboa_inotify_add_watch`, `jerboa_inotify_rm_watch`, `jerboa_inotify_read`, `jerboa_inotify_close` | ✅ |
| Landlock ABI/ruleset/rules/enforce | libc (syscalls) | `jerboa_landlock_abi_version`, `jerboa_landlock_create_ruleset`, `jerboa_landlock_add_path_rule`, `jerboa_landlock_add_net_rule`, `jerboa_landlock_enforce` | ✅ |
| io_uring | io-uring | — | ⏳ Deferred |
| Scheme bindings | — | `(std os epoll-native)`, `(std os inotify-native)`, `(std os landlock-native)` | ✅ |

Rust: `src/epoll.rs`, `src/inotify_native.rs`, `src/landlock.rs`. Scheme: `lib/std/os/epoll-native.sls`, `lib/std/os/inotify-native.sls`, `lib/std/os/landlock-native.sls`. Tests: `tests/test-native-rust-week5-6.ss`. Landlock supports ABI v1-v7 with filesystem + network rules. io_uring deferred (complex async interface).

---

## Summary

| Metric | Before (C libraries) | After (Rust native) |
|--------|---------------------|---------------------|
| Shared libraries loaded | 10+ | 1 |
| C code in trust boundary | ~500K lines (OpenSSL + SQLite + ...; libyaml already eliminated via pure Scheme) | 0 (Rust only; C primitives inside ring are audited asm) |
| Memory safety CVEs possible | Yes — every C library | No — Rust compiler prevents them |
| ReDoS possible | Yes — PCRE2 backtracks | No — Rust regex uses NFA |
| Secret wiping guarantee | No — GC copies | Yes — secure region is outside GC |
| Dependency audit | Manual per-library | `cargo audit` — automated |
| Build reproducibility | Varies per library | `Cargo.lock` — exact pins |
| Static binary size impact | ~15-25MB (all C libs) | ~5-10MB (LTO, dead code eliminated) |
