# Jerboa Security Reference

Consolidated reference for all implemented security features. Module paths are provided for each feature so developers know what to import.

Replaces: `docs/archive/security.md`, `docs/archive/security2.md`, `docs/archive/findings.md`, `docs/archive/topsecret.md`.

---

## 1. Security Architecture Overview

Jerboa's security model is layered defense-in-depth. No single layer is trusted alone.

| Layer | What It Does | Module(s) |
|-------|-------------|-----------|
| **Language-level sandbox** | Allowlist-only evaluation environment | `(std security restrict)` |
| **Capability system** | Unforgeable tokens gate filesystem, network, process, environment access | `(std security capability)` |
| **Taint tracking** | Mark untrusted data, reject at dangerous sinks | `(std security taint)` |
| **Kernel enforcement** | Landlock filesystem rules, seccomp-BPF syscall filtering | `(std security landlock)`, `(std security seccomp)` |
| **Privilege separation** | Fork-based isolation, supervisor/worker architecture | `(std security privsep)` |
| **Parser hardening** | Depth limits, size limits, backtracking budgets | Various (see section 7) |
| **Crypto** | AEAD, CSPRNG, HMAC, KDF, timing-safe comparison, secure memory | `(std crypto ...)` |
| **Input sanitization** | Context-aware escaping for HTML, SQL, paths, headers, URLs | `(std security sanitize)` |
| **Audit logging** | Append-only hash-chain log (JSONL) with tamper detection | `(std security audit)` |

Design principles: default deny, least privilege, fail secure, constant-time for secrets, minimal attack surface.

---

## 2. Allowlist Sandbox

**Module**: `(std security restrict)`

Creates an evaluation environment containing only approved bindings. Uses Chez Scheme's `(environment '(only (chezscheme) ...))` -- nothing exists unless explicitly listed.

### Exports

- `make-restricted-environment` -- create a new restricted environment, optionally with extra bindings
- `restricted-eval` -- evaluate an expression in a restricted environment
- `restricted-eval-string` -- parse and evaluate a string (uses `jerboa-read`, not Chez `read`)
- `safe-bindings` -- the list of allowed symbols

### What's allowed

Core syntax (`lambda`, `if`, `begin`, `let`, `cond`, `case`, `when`, `unless`, `do`, `define-syntax`, `syntax-rules`, `quasiquote`), arithmetic (including bitwise ops), comparison, booleans, pairs/lists, strings, characters, vectors, bytevectors, symbols, string-port I/O, hashtables, error handling, `apply`, `values`, `dynamic-wind`, `sort`, `format`, `void`.

### What's blocked

- All file I/O (`open-input-file`, `open-output-file`, etc.)
- Process execution (`system`, `process`)
- FFI (`foreign-procedure`, `load-shared-object`)
- Code loading (`load`, `eval`, `compile-file`)
- Environment access (`getenv`, `putenv`)
- Thread creation (`fork-thread`)
- Module system manipulation (`import`, `library`)
- `call/cc` (can escape dynamic scope)
- Bare `read` (supports `#.` read-eval) -- replaced by `jerboa-read` which has depth limits and no read-eval
- `gensym` (leaks runtime state via monotonic counter)

### Usage

```scheme
(import (std security restrict))

;; Basic evaluation
(restricted-eval '(+ 1 2))  ;; => 3

;; With extra bindings
(let ([env (make-restricted-environment
             (list (cons 'my-fn (lambda (x) (* x 2)))))])
  (eval '(my-fn 21) env))  ;; => 42

;; String evaluation (safe reader)
(restricted-eval-string "(map (lambda (x) (* x x)) '(1 2 3))")
```

---

## 3. Capability-Based Security

**Module**: `(std security capability)`

Access rights are unforgeable tokens (sealed, opaque records with CSPRNG nonces). Capabilities attenuate monotonically -- they can only be restricted, never escalated.

### Four capability domains

| Domain | Constructor | Permission checks |
|--------|-----------|-------------------|
| Filesystem | `make-fs-capability` | `fs-read?`, `fs-write?`, `fs-execute?`, `fs-allowed-path?` |
| Network | `make-net-capability` | `net-connect?`, `net-listen?`, `net-allowed-host?` |
| Process | `make-process-capability` | `process-spawn?`, `process-signal?` |
| Environment | `make-env-capability` | `env-read?`, `env-write?` |

### Key properties

- **Sealed records**: cannot be subtyped or inspected via `record-type-descriptor`
- **CSPRNG nonces**: each capability carries a unique random nonce from `/dev/urandom`
- **Path canonicalization**: uses `realpath(3)` via FFI to resolve symlinks before path checks
- **Default deny for hosts**: empty host list means no hosts allowed (not all allowed)
- **Intersection**: `with-capabilities` intersects child capabilities against parent per-permission (ANDs booleans, set-intersects lists)
- **Thread-safe**: nonce generation is mutex-protected; capability context is a thread parameter

### Enforcement

```scheme
(import (std security capability))

(let ([cap (make-fs-capability read: #t write: #f paths: '("/data"))])
  (with-capabilities (list cap)
    (check-capability! 'filesystem 'read "/data/config.scm")  ;; ok
    (check-capability! 'filesystem 'write "/data/config.scm") ;; raises &capability-violation
    ))
```

### Related modules

- `(std security capability-typed)` -- `define/cap` and `lambda/cap` macros that declare capability requirements in function signatures
- `(std security import-audit)` -- build-time scanner that detects direct `(chezscheme)` imports bypassing the capability system

---

## 4. Taint Tracking

**Module**: `(std security taint)`

Wraps untrusted data in sealed opaque records. Dangerous operations reject tainted values unless explicitly sanitized.

### Taint categories

`taint-http`, `taint-env`, `taint-file`, `taint-net`, `taint-deser`

### Core operations

- `(taint class value)` -- wrap a value with a taint class
- `(tainted? x)` -- check if a value is tainted
- `(taint-value x)` -- extract the wrapped value
- `(untaint x)` -- explicitly remove taint (the sanitization boundary)
- `(check-untainted! x sink-name)` -- raise `&taint-violation` if tainted

### Safe sink wrappers

These automatically call `check-untainted!` and reject tainted arguments:

- `safe-open-input-file`
- `safe-open-output-file`
- `safe-system`
- `safe-delete-file`

### Taint-propagating string operations

`tainted-string-append`, `tainted-string-ref`, `tainted-substring`, `tainted-string-length` -- operations on tainted strings propagate the taint to results.

---

## 5. Kernel Enforcement

### Landlock -- `(std security landlock)`

Linux 5.13+ filesystem access control. Uses real `landlock_create_ruleset(2)`, `landlock_add_rule(2)`, and `landlock_restrict_self(2)` syscalls via FFI. Rules are irreversible.

- `(landlock-available?)` -- check kernel support (probes ABI version via syscall)
- `(make-landlock-ruleset)` -- create a new ruleset
- `(landlock-add-read-only! ruleset path ...)` -- allow read-only access
- `(landlock-add-read-write! ruleset path ...)` -- allow read-write access
- `(landlock-add-execute! ruleset path ...)` -- allow execute access
- `(landlock-install! ruleset)` -- install rules (irreversible, calls `prctl(PR_SET_NO_NEW_PRIVS)` + real Landlock syscalls)
- `(with-landlock ruleset body ...)` -- scoped installation
- `(make-readonly-ruleset path ...)` / `(make-tmpdir-ruleset path ...)` -- convenience constructors

Supports Landlock ABI v1, v2 (REFER), and v3 (TRUNCATE). Auto-detects kernel ABI version.

### seccomp-BPF -- `(std security seccomp)`

Linux syscall filtering via real BPF bytecode. Generates actual `sock_filter` programs and installs via `seccomp(2)` syscall. Includes architecture validation (x86_64) to prevent syscall number confusion attacks.

- `(seccomp-available?)` -- check kernel support
- `(make-seccomp-filter default-action: action allowed: syscall-list)` -- create a filter
- `(seccomp-install! filter)` -- install filter (irreversible)
- Pre-built filters: `compute-only-filter`, `io-only-filter`, `network-server-filter`
- Actions: `seccomp-kill`, `seccomp-trap`, `seccomp-errno`, `seccomp-log`

BPF program structure: validate architecture, load syscall number, check against allowed list, apply default action for non-matching syscalls.

### Privilege Separation -- `(std security privsep)`

Fork-based privilege separation. Supervisor holds elevated privileges; workers are sandboxed. Communication via pipe-based message passing.

- `(make-privsep handler)` -- fork a worker process
- `(privsep-request ps message)` -- send request to worker, get response
- `(privsep-shutdown! ps)` -- SIGTERM + `waitpid` (prevents zombie accumulation)
- `(make-privsep-channel)` -- low-level pipe channel
- `*max-privsep-children*` -- concurrent child limit (default 64), enforced with active tracking

---

## 6. Sandbox Entry Point

**Module**: `(std security sandbox)`

Combines all protection layers into a single `run-safe` call. Forks a child process (so kernel protections are irreversible without affecting the parent), applies protections, runs the thunk, and sends the result back via pipe.

### API

```scheme
(import (std security sandbox))

;; Run with defaults (30s timeout, compute-only seccomp, no landlock)
(run-safe (lambda () (+ 1 2)))  ;; => 3

;; Custom config
(run-safe (lambda () (+ 1 2))
  (make-sandbox-config
    'timeout 10
    'seccomp 'io-only
    'landlock (make-readonly-ruleset "/usr/lib" "/lib")))

;; Evaluate a string in full sandbox
(run-safe-eval "(+ 1 2)")
(run-safe-eval "(+ 1 2)" (make-sandbox-config 'timeout 10))
```

### Default parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `*sandbox-timeout*` | 30 seconds | Max execution time (`#f` = no limit) |
| `*sandbox-seccomp*` | `'compute-only` | Seccomp filter preset |
| `*sandbox-landlock*` | `#f` | No filesystem restriction by default |

### Protection order (in child process)

1. Install Landlock filesystem rules (if configured and available)
2. Install seccomp-BPF filter (if configured and available)
3. Set capability context
4. Evaluate in restricted environment with timeout

Raises `&sandbox-error` with phase (`'landlock`, `'seccomp`, `'capability`, `'timeout`, `'eval`, `'fork`) and detail.

---

## 7. Parser Hardening

Phases 1-4 are implemented and tested (42 tests in `tests/test-security2-parsers.ss`). Phase 5 (FFI audit) is not started.

### Depth limits

| Parser | Parameter | Default | Module |
|--------|-----------|---------|--------|
| Jerboa reader | `*max-read-depth*` | 1000 | `(jerboa reader)` |
| Block comments | (internal) | 1000 | `(jerboa reader)` |
| JSON | `*json-max-depth*` | 512 | `(std text json)` |
| XML/SXML | depth limit | 512 | `(std text xml)` |
| Schema validation | depth limit | 100 | `(std schema)` |
| DNS compression pointers | hop limit | 64 | `(std net dns)` |

### Size limits

| Parser | Parameter | Default | What |
|--------|-----------|---------|------|
| Reader | `*max-string-length*` | 10 MB | Per-string literal |
| Reader | `*max-list-length*` | 1M elements | Per-list |
| Reader | `*max-symbol-length*` | 4 KB | Per-symbol |
| JSON | string length limit | configurable | Per-string value |
| HTTP/2 | frame size cap | 16 KB | Per-frame |
| WebSocket | payload cap | 64 MB | Per-message |
| Zlib | decompression limit | configurable | Output size |
| YAML | input size limit | configurable | Total input |
| Actor messages | `*max-message-size*` | 1 MB | Per-message |

### Other hardening

| Parser | Protection | Module |
|--------|-----------|--------|
| Base64 | Strict validation (rejects non-alphabet chars) | `(std text base64)` |
| Hex | Odd-length rejection | `(std text hex)` |
| CSV | Strict quote handling | `(std text csv)` |
| Pregexp | Backtracking budget (prevents ReDoS) | `(std text pregexp)` |
| Format strings | `safe-printf`, `safe-fprintf`, `safe-eprintf` (no `%n`) | `(std text format)` |

---

## 8. AI Attack Hardening

13 findings from a dedicated security review of Jerboa's attack surface against adversarial AI systems. All 13 addressed (12 fully fixed, 1 has real implementation that replaced the original stubs).

| # | Finding | Severity | Fix |
|---|---------|----------|-----|
| 1 | Sandbox defaulted to full `(interaction-environment)` | CRITICAL | `make-sandbox` now defaults to `(make-restricted-environment)` from `(std security restrict)`. `sandbox-import!` enforces `allowed-imports`. `max-eval-time` enforced via watchdog thread. |
| 2 | `sandbox-eval-string` used Chez `read` (no depth limits, supports `#.` read-eval) | HIGH | Both `sandbox-eval-string` and `restricted-eval-string` now use `jerboa-read`. |
| 3 | Capability intersection checked type only, not permissions | HIGH | `intersect-capabilities` now ANDs boolean permissions and set-intersects list permissions. |
| 4 | Empty network host list meant "all allowed" | HIGH | Empty list now means no hosts allowed. Explicit `"*"` required for wildcard. |
| 5 | Path canonicalization didn't resolve symlinks | HIGH | `canonicalize-path` now uses `realpath(3)` via FFI. |
| 6 | Distributed actors used `read` for deserialization (remote code exec via `#.`) | CRITICAL | `deserialize-message` wraps `read` in `(parameterize ([read-eval #f]) ...)`. Message size limit enforced. |
| 7 | Seccomp/Landlock were stubs | HIGH | Both now have real implementations with actual syscalls (BPF bytecode generation, Landlock ABI detection). |
| 8 | Taint tracking had no automatic sink enforcement | MEDIUM | Added `safe-open-input-file`, `safe-open-output-file`, `safe-system`, `safe-delete-file` that auto-reject tainted args. |
| 9 | Restricted environment allowlist included `read` and `gensym` | MEDIUM | `read` removed (replaced by `jerboa-read`). `gensym` removed. |
| 10 | No reader input size limits | MEDIUM | Added `*max-string-length*` (10 MB), `*max-list-length*` (1M), `*max-symbol-length*` (4 KB). |
| 11 | AI-generated code could bypass capabilities via direct Chez imports | MEDIUM | New `(std security import-audit)` scans for forbidden imports at build time. |
| 12 | HTML sanitization incomplete for attribute/URL contexts | MEDIUM | Added `sanitize-html-attribute` (hex-encodes non-alphanumeric) and `sanitize-url-attribute` (rejects `javascript:`, `data:`, `vbscript:`, `blob:` schemes). |
| 13 | Privilege separation had no child reaping | LOW | `privsep-shutdown!` sends SIGTERM then calls `waitpid`. `*max-privsep-children*` (default 64) prevents PID exhaustion. |

---

## 9. Secure Memory

**Module**: `(std crypto secure-mem)`

Allocates memory outside the GC heap with protections against leakage. Backed by `libjerboa_native.so` (Rust).

### Properties

- **mmap + mlock**: memory is locked into RAM, never swapped to disk
- **Guard pages**: PROT_NONE pages before and after the allocation (buffer overflow = SIGSEGV)
- **MADV_DONTDUMP**: excluded from core dumps
- **MADV_DONTFORK**: not inherited by child processes
- **explicit_bzero on free**: guaranteed wipe that cannot be optimized away by the compiler

### API

```scheme
(import (std crypto secure-mem))

;; Manual lifecycle
(let ([region (secure-alloc 32)])
  ;; ... use region ...
  (secure-wipe region)
  (secure-free region))

;; Scoped (auto-free on exit)
(with-secure-region ([key 32] [iv 12])
  ;; key and iv are secure-region records
  (secure-random-fill key)
  ;; ... use key and iv ...
  )  ;; auto-freed here
```

---

## 10. Cryptography

### CSPRNG -- `(std crypto random)`

Reads directly from `/dev/urandom`. Never uses Chez's `(random N)` for security operations.

- `random-bytes` / `random-bytes!` -- generate random bytevectors
- `random-u64` -- random 64-bit integer
- `random-token` -- random hex string
- `random-uuid` -- random UUID v4

### Digests -- `(std crypto digest)` and `(std crypto native)`

Via OpenSSL libcrypto FFI: MD5, SHA-1, SHA-256, SHA-384, SHA-512.

### HMAC -- `(std crypto hmac)` and `(std crypto native)`

HMAC-SHA256 via OpenSSL EVP interface.

### AEAD -- `(std crypto aead)`

AES-256-GCM via OpenSSL EVP: `aead-encrypt`, `aead-decrypt`, `aead-key-generate`. 12-byte IV, 16-byte tag.

### Rust-backed crypto -- `(std crypto native-rust)`

Drop-in replacement using `ring` via `libjerboa_native.so` (Rust). No OpenSSL dependency.

| Function | Description |
|----------|-------------|
| `rust-sha1`, `rust-sha256`, `rust-sha384`, `rust-sha512` | Digests |
| `rust-random-bytes` | CSPRNG |
| `rust-hmac-sha256`, `rust-hmac-sha256-verify` | HMAC |
| `rust-timing-safe-equal?` | Constant-time comparison |
| `rust-aead-seal`, `rust-aead-open` | AES-256-GCM |
| `rust-chacha20-seal`, `rust-chacha20-open` | ChaCha20-Poly1305 AEAD |
| `rust-scrypt` | scrypt KDF |
| `rust-pbkdf2-derive`, `rust-pbkdf2-verify` | PBKDF2 |

### ChaCha20-Poly1305

Available via `(std crypto native-rust)`. Useful when AES-NI hardware is unavailable (ARM, older x86). Same AEAD interface as AES-256-GCM.

### scrypt KDF

Available via both `(std crypto kdf)` (wraps `chez-crypto`) and `(std crypto native-rust)` (`rust-scrypt`).

### Password hashing -- `(std crypto password)`

PBKDF2-HMAC-SHA256 via OpenSSL. 600,000 iterations default (OWASP 2023 recommendation).

- `password-hash` -- derive hash from password + salt
- `password-verify` -- constant-time verification
- `make-password-salt` -- generate random salt

### Timing-safe comparison -- `(std crypto compare)`

- `timing-safe-equal?` -- constant-time bytevector comparison (XOR accumulator, no early exit)
- `timing-safe-string=?` -- constant-time string comparison

---

## 11. Fuzzing

13 fuzz harnesses in `tests/fuzz/harness/`, plus a combined runner (`fuzz-all.ss`).

| Harness | Target |
|---------|--------|
| `fuzz-reader.ss` | Jerboa S-expression reader |
| `fuzz-json.ss` | JSON parser |
| `fuzz-websocket.ss` | WebSocket frame parser |
| `fuzz-dns.ss` | DNS message parser |
| `fuzz-pregexp.ss` | Regular expression engine |
| `fuzz-csv.ss` | CSV parser |
| `fuzz-base64.ss` | Base64 decoder |
| `fuzz-hex.ss` | Hex decoder |
| `fuzz-uri.ss` | URI parser |
| `fuzz-format.ss` | Format string processor |
| `fuzz-router.ss` | HTTP router |
| `fuzz-http2.ss` | HTTP/2 frame parser |
| `fuzz-sandbox.ss` | Restricted evaluation sandbox |

Fuzzing framework: `(std test fuzz)`.

---

## 12. Additional Security Modules

These modules are implemented but not covered in depth above.

| Module | Purpose |
|--------|---------|
| `(std security sanitize)` | Context-aware sanitization: `sanitize-html`, `sanitize-html-attribute`, `sanitize-url-attribute`, `sql-escape`, `sanitize-path`, `safe-path-join`, `sanitize-header-value`, `sanitize-url`. Raises `&path-traversal`, `&header-injection`, `&url-scheme-violation`. |
| `(std security errors)` | Error classification (internal vs client-safe). Generates opaque error references for correlation. Prevents leaking internal details in error responses. |
| `(std security audit)` | Append-only JSONL audit log with SHA-256 hash chain. `audit-log!`, `verify-audit-chain`, `check-capability!/audit`. |
| `(std security auth)` | API key stores, session tokens with expiry, auth middleware pattern, rate limiting for auth attempts. |
| `(std security flow)` | Information flow control. Security levels form a lattice: public < internal < secret < top-secret. Data flows up freely; downward flow requires explicit `declassify` which is logged. |
| `(std security metrics)` | Security counters, gauges, histograms with alerting thresholds. |
| `(std security io-intercept)` | Effect-based I/O interception. All filesystem, network, and process operations mediated by handlers that can audit, deny, or mock. |

---

## 13. What's NOT Covered -- Honest Limitations

These are known gaps. They are not on any roadmap in this document -- just honest statements about what does not exist.

- **No formal verification.** The security modules are tested but not formally proved. No Coq/Isabelle/ACL2 proofs exist.
- **No FIPS 140-3 validation.** The crypto uses OpenSSL or ring, which can be FIPS-validated, but Jerboa itself has not undergone FIPS evaluation.
- **No covert channel analysis.** Chez Scheme's GC is a timing side channel. No mitigation exists for timing, storage, or resource-exhaustion covert channels.
- **No Common Criteria evaluation.** No Protection Profile, Security Target, or EAL evaluation has been performed.
- **Seccomp is x86_64 only.** The BPF bytecode generator hardcodes `AUDIT_ARCH_X86_64` and x86_64 syscall numbers.
- **Landlock requires Linux 5.13+.** No equivalent on macOS, BSDs, or older Linux kernels. `landlock-available?` returns `#f` on unsupported systems.
- **Taint tracking is opt-in.** Only the `safe-*` wrappers enforce taint checks. Native Chez operations (`open-input-file`, `system`, etc.) do not check taint. No static analysis enforcement exists.
- **No message authentication for distributed actors.** `deserialize-message` disables `#.` read-eval but messages are still plaintext with no HMAC.
- **No TOCTOU-safe path checking.** `canonicalize-path` uses `realpath(3)` before access, not `O_NOFOLLOW` + `/proc/self/fd/N` after open.
- **`define-syntax` remains in the sandbox allowlist.** Macro definition in sandboxed code is possible. Whether this is a risk depends on the use case.
- **No max-output-size for sandboxes.** A sandboxed expression can produce unbounded output via `display`/`write`.
- **No Argon2id.** Password hashing uses PBKDF2 (universally available via OpenSSL) rather than Argon2id (requires separate library).
- **FFI audit (Phase 5 of parser hardening) is not started.** Null return checks, type validation, and SQL injection lint rules are unimplemented.
- **No red team evaluation.** No independent adversarial testing has been performed.
- **Secure memory is outside GC.** The `with-secure-region` API requires manual pointer arithmetic via `foreign-ref`/`foreign-set!`. There is no high-level typed interface.
