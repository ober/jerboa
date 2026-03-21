# Jerboa Security Architecture

A comprehensive security framework for building critical applications on Jerboa/Chez Scheme. This document catalogs every security-relevant feature already implemented, identifies vulnerabilities to fix, and proposes advanced features that would make Jerboa a uniquely secure platform for high-assurance software.

---

## Table of Contents

1. [Design Principles](#design-principles)
2. [Security Features Already Implemented](#security-features-already-implemented)
3. [Known Vulnerabilities to Fix](#known-vulnerabilities-to-fix)
4. [Proposed: Language-Level Safety](#proposed-language-level-safety)
5. [Proposed: Cryptographic Foundation](#proposed-cryptographic-foundation)
6. [Proposed: Network and Protocol Hardening](#proposed-network-and-protocol-hardening)
7. [Proposed: Operating System Integration](#proposed-operating-system-integration)
8. [Proposed: Supply Chain and Build Security](#proposed-supply-chain-and-build-security)
9. [Proposed: Observability and Incident Response](#proposed-observability-and-incident-response)
10. [Proposed: Distributed Systems Security](#proposed-distributed-systems-security)
11. [Implementation Roadmap](#implementation-roadmap)
12. [Architectural Position](#architectural-position)

---

## Design Principles

Every security decision in Jerboa should follow these principles:

1. **Default deny** — nothing is permitted unless explicitly granted. Allowlists over blocklists, everywhere.
2. **Defense in depth** — language-level types + runtime contracts + OS-level sandboxing + network-level controls. No single layer is trusted alone.
3. **Least privilege** — every component receives the minimum capabilities it needs. Capabilities attenuate monotonically; they never escalate.
4. **Fail secure** — errors result in denial, not bypass. A crashed capability check denies access.
5. **Audit everything** — every security-relevant decision produces a structured, immutable log entry.
6. **Assume breach** — design for containment. Compromised components cannot escalate to the rest of the system.
7. **Constant-time for secrets** — no timing side channels in any comparison involving secret material.
8. **Minimal attack surface** — fewer dependencies, smaller trusted computing base, less code to audit.
9. **Verify, don't trust** — never rely on caller-supplied metadata. Validate at every boundary.
10. **Make the safe path the easy path** — unsafe operations should require explicit opt-in; safe defaults should require no annotation.

---

## Security Features Already Implemented

Jerboa has a remarkably deep set of security-relevant features for a project of its age. This section catalogs every existing feature and how it contributes to security.

### Capability-Based Access Control — `(std security capability)`

An object-capability system where access rights are represented as unforgeable tokens rather than identity-based ACLs.

| Feature | Description |
|---------|-------------|
| **Four capability domains** | Filesystem (read/write/execute + path restrictions), Network (connect/listen + host restrictions), Process (spawn/signal), Environment (read/write) |
| **Unforgeable tokens** | Each capability carries a unique nonce |
| **Monotonic attenuation** | `attenuate-capability` can only restrict permissions, never add them |
| **Scoped contexts** | `with-capabilities` enforces that child contexts are subsets of parent contexts |
| **Violation conditions** | `&capability-violation` with structured type and detail fields |
| **Thread-safe** | Nonce generation is mutex-protected; capability context is a thread parameter |

**Security value**: Prevents confused deputy attacks. Code that receives a read-only filesystem capability cannot escalate to write access, even if it passes through untrusted intermediaries.

### Restricted Evaluation Sandbox — `(std security restrict)`

Evaluates untrusted code in an environment with only 29 safe bindings.

| Feature | Description |
|---------|-------------|
| **Explicit safe set** | Arithmetic, lists, strings, vectors, bytevectors, symbols, string ports, error handling |
| **Blocked categories** | FFI, file I/O, process execution, code loading, environment access, thread creation, module system manipulation |
| **Extra bindings** | Callers can inject additional bindings into the sandbox |
| **String evaluation** | `restricted-eval-string` for evaluating user-provided source text |

**Security value**: Enables safe execution of user-submitted code (configuration DSLs, rule engines, plugin systems).

### Embeddable Sandbox — `(jerboa embed)`

A higher-level sandboxing API with configuration, error translation, and lifecycle management.

| Feature | Description |
|---------|-------------|
| **Configuration record** | `max-eval-time`, `allowed-imports`, `capture-output` |
| **Error isolation** | Exceptions from sandboxed code are translated to `sandbox-error` records — internal details don't leak |
| **State management** | `sandbox-reset!` creates a fresh environment; `sandbox-define!` injects bindings |
| **Scoped API** | `with-sandbox` macro for deterministic lifecycle |

**Security value**: Production-ready embedding of untrusted code with structured error boundaries.

### Gradual Type System — `(std typed)`

Runtime type checking with zero-overhead release mode.

| Feature | Description |
|---------|-------------|
| **Annotated forms** | `define/t`, `lambda/t` with parameter and return type annotations |
| **Mode switching** | `*typed-mode*` parameter: `'debug` (checks enabled), `'release` (checks stripped), `'none` (no effect) |
| **Composite types** | `(listof T)`, `(vectorof T)`, `(hashof K V)`, `(-> A ... B)` |
| **Operator specialization** | `with-fixnum-ops`, `with-flonum-ops` replace generic arithmetic with safe fixed-width variants |
| **Custom predicates** | `register-type-predicate!` for user-defined types |

**Security value**: Catches type confusion bugs at function boundaries. Fixnum specialization prevents integer overflow from silently promoting to bignum (relevant for buffer size calculations, array indices).

### Linear Types — `(std typed linear)`

Use-exactly-once discipline for resources that must be consumed.

| Feature | Description |
|---------|-------------|
| **Consumption tracking** | `linear-use` marks a value as consumed; second use raises an error |
| **Scope enforcement** | `with-linear` checks that all linear values are consumed before scope exit |
| **Splitting** | `linear-split` creates N independent copies (for fork/join patterns) |
| **Read-only peek** | `linear-value` for inspection without consumption |

**Security value**: Guarantees that resources (file handles, network connections, cryptographic keys) are used exactly once and cannot be leaked or double-freed.

### Affine Types — `(std typed affine)`

Use-at-most-once discipline with automatic cleanup.

| Feature | Description |
|---------|-------------|
| **Guardian-based cleanup** | `make-affine/cleanup` registers a destructor that runs when the value is dropped |
| **Explicit drop** | `affine-drop!` runs the cleanup immediately |
| **Scope enforcement** | `with-affine` auto-drops on scope exit |
| **Peek without consumption** | `affine-peek` for read-only access |

**Security value**: Prevents double-free bugs. Guarantees that secrets (keys, tokens) are wiped when they leave scope. Guardian integration means cleanup happens even if the programmer forgets.

### Refinement Types — `(std typed refine)`

Values that satisfy both a base type and an additional predicate.

| Feature | Description |
|---------|-------------|
| **Built-in refinements** | `NonNeg`, `Positive`, `NonNull`, `NonEmpty`, `Bounded`, `NonZero`, `Natural` |
| **Annotated forms** | `define/r`, `lambda/r` inject runtime checks on function entry |
| **Flow-sensitive narrowing** | `refine-branch` and `with-refinement-context` avoid redundant checks after conditional tests |

**Security value**: Enforces invariants like "port number is 1-65535", "buffer size is non-negative", "user ID is non-null" at every function boundary. Flow-sensitive narrowing means proven refinements are not re-checked.

### Phantom Types — `(std typed phantom)`

State machine invariant enforcement via type-level protocol tracking.

| Feature | Description |
|---------|-------------|
| **Protocol registry** | Declares valid state transitions for a type |
| **State checking** | `phantom-check` asserts current state; `phantom-transition` enforces valid transitions |

**Security value**: Encodes security protocols as types. A TLS connection in state `'handshake` cannot be used for data transfer until it transitions to `'established`. File in state `'closed` cannot be read.

### GADTs — `(std typed gadt)`

Type-indexed algebraic data types with safe pattern matching.

| Feature | Description |
|---------|-------------|
| **Tagged constructors** | Each variant carries its constructor tag and fields |
| **Exhaustive matching** | `gadt-match` with catch-all `else` clause |

**Security value**: Prevents illegal state representations. A well-typed security token can only be constructed through authorized constructors.

### Contract System — `(std contract)`

Design-by-contract with pre/post conditions.

| Feature | Description |
|---------|-------------|
| **define/contract** | Functions with `(pre: ...)` and `(post: ...)` clauses |
| **Higher-order contracts** | `(-> pred ... pred)` wraps a function with argument and return checking |
| **Violation conditions** | `&contract-violation` with `who` and `message` fields |
| **Inline assertion** | `assert-contract` for ad-hoc checks |

**Security value**: Enforces API invariants at function boundaries. Combined with refinement types, provides defense-in-depth validation.

### Effect System — `(std effect)` and `(std typed effects)`

Algebraic effects with handler-based control flow and effect type annotations.

| Feature | Description |
|---------|-------------|
| **Effect handlers** | `with-handler` installs handlers for effect operations |
| **Resource effects** | `with-resources` / `acquire` for RAII-style cleanup with guaranteed destructor execution |
| **Scoped effects** | Koka-style scoped handlers with state, reader, and collection patterns |
| **Effect typing** | `define/te`, `lambda/te` annotate functions with their effect sets; `Pure T` marks effect-free code |
| **Effect inference** | `infer-effects` heuristically identifies effectful operations |
| **Effect discharge** | `check-effects!` validates all effects are handled |

**Security value**: Makes side effects explicit and trackable. Pure code cannot perform I/O, access the filesystem, or modify global state. Effect handlers can intercept and audit all I/O operations.

### Concurrency Safety — `(std concur)`

Three layers of thread-safety enforcement.

| Feature | Description |
|---------|-------------|
| **Thread-safety annotations** | `defstruct/immutable`, `defstruct/thread-local`, `defstruct/thread-safe` classify data structures |
| **Deadlock detection** | `make-tracked-mutex` with lock-order graph; BFS cycle detection prevents deadlock |
| **Resource leak detection** | `register-resource!` / `check-resource-leaks!` tracks per-thread resource ownership |
| **Lock order violations** | Recorded and queryable via `lock-order-violations` |

**Security value**: Deadlock is a denial-of-service vector. Lock-order tracking catches potential deadlocks before they occur in production. Resource leak detection prevents file descriptor exhaustion.

### Structured Concurrency — `(std control structured)`

Guaranteed task lifecycle management.

| Feature | Description |
|---------|-------------|
| **Task scopes** | `with-task-scope` guarantees all spawned tasks are cancelled on scope exit |
| **Parallel composition** | `parallel` spawns all, awaits all, collects results |
| **Race composition** | `race` spawns all, first to complete wins, cancels others |
| **Named tasks** | `scope-spawn-named` for debugging and monitoring |

**Security value**: Prevents thread leaks and zombie tasks. Every spawned task has a defined lifetime and cleanup path.

### Software Transactional Memory — `(std ds stm)` / `(std stm)`

Lock-free concurrent data access.

| Feature | Description |
|---------|-------------|
| **Transactional variables** | `make-tvar` with optimistic concurrency |
| **Atomic blocks** | `atomically` with automatic retry on conflict |
| **Composable retry** | `retry` and `or-else` for conditional blocking |
| **Snapshot isolation** | Read-set validation at commit prevents torn reads |

**Security value**: Eliminates data races without locks. No deadlock possible. Atomic blocks are composable (unlike mutexes).

### Rate Limiting — `(std net rate)`

Three rate limiting algorithms, all thread-safe.

| Feature | Description |
|---------|-------------|
| **Token bucket** | Smooth rate limiting with burst capacity |
| **Sliding window** | Precise per-window request counting |
| **Fixed window** | Efficient coarse-grained limiting |
| **Thread-safe wrapper** | `make-rate-limiter` with mutex-protected access |

**Security value**: Prevents brute-force attacks, credential stuffing, and DoS via request flooding.

### Schema Validation — `(std schema)`

Structural data validation with composable validators.

| Feature | Description |
|---------|-------------|
| **Type schemas** | `s:string`, `s:integer`, `s:number`, `s:boolean`, `s:null`, `s:any` |
| **Composite schemas** | `s:list`, `s:hash`, `s:union`, `s:enum`, `s:optional`, `s:required` |
| **Constraints** | `s:pattern`, `s:min-length`, `s:max-length`, `s:min`, `s:max` |
| **Structured errors** | `validation-error` records with path, message, and value |

**Security value**: Validates untrusted input (API payloads, configuration files) against declared schemas before processing.

### Connection Pooling — `(std net pool)`

Thread-safe connection lifecycle management.

| Feature | Description |
|---------|-------------|
| **Bounded pools** | Min/max size constraints with blocking acquire |
| **Health checking** | Periodic validation of idle connections |
| **Statistics** | Acquired, released, created, destroyed, wait counts |
| **Deterministic cleanup** | `with-connection` uses `dynamic-wind` for guaranteed release |

**Security value**: Prevents connection leaks and resource exhaustion. Health checks detect stale/poisoned connections.

### Thread-Safe Channels — `(std misc channel)`

Production-quality inter-thread communication.

| Feature | Description |
|---------|-------------|
| **Ring buffer** | Vector-based circular queue with dynamic growth |
| **Bounded/unbounded** | Backpressure via bounded channels that block on full |
| **Select** | Multiplexing across multiple channels with timeout |
| **GC-aware** | Consumed slots zeroed to help garbage collector |

**Security value**: Bounded channels prevent memory exhaustion from producer flooding.

### Static Analysis — `(std lint)`

9-rule linter for code quality.

| Feature | Description |
|---------|-------------|
| **Rules** | Empty begin, single-arm cond, missing else, deep nesting, long lambda, builtin redefinition, magic numbers, shadowed define, unused define |
| **Configurable** | Add/remove rules, set severity levels |

**Security value**: Catches code quality issues that correlate with security bugs (shadowed variables, missing error branches).

### Configuration with Schema Validation — `(std config)`

Typed configuration management.

| Feature | Description |
|---------|-------------|
| **Schema validation** | Type checking on config values (integer, string, boolean, list, symbol) |
| **Environment overrides** | `JERBOA_*` environment variables override config keys |
| **Change watchers** | Callbacks on config modification |
| **Nested access** | Dot-path navigation into config hierarchies |

### Additional Security-Relevant Features

| Module | Feature | Security Value |
|--------|---------|---------------|
| `(std assert)` | `assert!`, `assert-equal!`, `assert-pred`, `assert-exception` | Runtime invariant enforcement |
| `(std error)` | `Error`, `ContractViolation` condition types | Structured error classification |
| `(std debug replay)` | Record/replay execution | Deterministic reproduction of security incidents |
| `(std debug timetravel)` | Time-travel debugger with thread-safe event recording | Post-mortem analysis of security events |
| `(std pipeline)` | Data pipeline with timeout stages | Prevents unbounded computation in data processing |
| `(std rewrite)` | Term rewriting with fixed-point normalization | Formal transformation of security policies |
| `(std actor supervisor)` | OTP-style supervision with restart rate limiting | Fault tolerance; prevents restart-loop DoS |
| `(std build reproducible)` | Content-addressed artifact store with build records | Verifiable builds |
| `(jerboa lock)` | Lockfile with hash verification and diff | Dependency integrity tracking |
| `(std net tcp)` | GC-safe non-blocking I/O | Prevents thread starvation during stop-the-world GC |
| `(std foreign)` | `with-foreign-resource` deterministic cleanup, guardian thread | FFI resource safety |

---

## Known Vulnerabilities to Fix

### V1. Command Injection in Digest — ~~CRITICAL~~ FIXED

**File**: `lib/std/crypto/digest.sls`

**Status**: FIXED in commit `069d425` on `hardened` branch.

**What was fixed**:
- Replaced temp file approach with stdin piping via `open-process-ports`
- No user input appears in the command string — only hardcoded algorithm names from a `case` expression
- No temp files created (eliminates TOCTOU race, predictable filenames, cleanup issues)
- 17 tests verify correct hashes against NIST vectors, bytevector input, and no temp file creation

### V2. Forgeable Capabilities — ~~CRITICAL~~ FIXED

**Affected files**:
- `lib/std/security/capability.sls` — `(std security capability)`
- `lib/std/capability.sls` — `(std capability)`

**Status**: FIXED in commit `e4343d6` on `hardened` branch.

**What was fixed**:
- Both modules now use sealed, opaque `define-record-type` with constructor NOT exported
- `(std security capability)` uses `(nongenerative std-security-capability)`
- `(std capability)` uses `(nongenerative std-capability)` — distinct types, cross-module forgery impossible
- `capability?` predicate uses the record type descriptor, which cannot be forged
- Vectors, strings, numbers, and all other types correctly rejected by `capability?`
- 66 tests verify forgery prevention, cross-module isolation, attenuation, and capability contexts

### V3. Predictable Nonces — ~~CRITICAL~~ FIXED

**Affected files**:
- `lib/std/security/capability.sls`
- `lib/std/capability.sls`

**Status**: FIXED in commits `42b9fa2` (CSPRNG module) and `e4343d6` (capability hardening) on `hardened` branch.

**What was fixed**:
- New `(std crypto random)` module reads from `/dev/urandom` via binary port with `dynamic-wind` cleanup
- Both capability modules now use `(random-bytes 16)` — 128 bits of cryptographic randomness per capability
- Revocation table in `(std capability)` uses `equal-hash`/`equal?` hashtable for bytevector nonce keys
- 23 tests verify CSPRNG correctness (length, non-determinism, UUID format, hex encoding)

### V4. Sandbox Escape Vectors — ~~HIGH~~ FIXED

**File**: `lib/std/security/restrict.sls`

**Status**: FIXED on `hardened` branch.

**What was fixed**:
- Replaced blocklist approach with allowlist-only: `(environment '(only (chezscheme) ...))` creates an environment with ONLY approved bindings
- Removed `call/cc` and `call-with-current-continuation` (can escape dynamic scope)
- No `eval`/`compile`/`load` available (no self-escape)
- Future Chez additions cannot leak into the sandbox
- 30 tests verify safe operations work and all dangerous operations are blocked

### V5. Weak Distributed Actor Authentication — ~~HIGH~~ FIXED

**File**: `lib/std/actor/transport.sls`

**Status**: FIXED on `hardened` branch.

**What was fixed**:
- Replaced FNV-1a with HMAC-SHA256 challenge-response handshake via `(std crypto native)`
- Per-connection 256-bit random nonces prevent replay attacks
- Mutual authentication: both client and server prove knowledge of cookie
- Timing-safe comparison via `native-crypto-memcmp` prevents timing side channels
- Handshake: hello(nonce) → challenge(nonce) → auth(HMAC) → ok(HMAC)
- `(std net tls)` module added for TLS-encrypted transport

### V6. Shell Injection in Process Execution — ~~HIGH~~ FIXED

**File**: `lib/std/misc/process.sls`

**Status**: FIXED on `hardened` branch.

**What was fixed**:
- Added `run-process/exec` which requires args as a list of strings
- Each argument is individually strict-shell-quoted (single quotes with escaping)
- Shell metacharacters (`$(...)`, backticks, pipes, semicolons, `&&`) are treated as literal text
- Input validation rejects non-list, empty list, and non-string elements
- `run-process` (shell-based) retained for backward compatibility but `run-process/exec` is the safe default
- 15 tests verify injection prevention

### V7. Environment Variable Injection in Config — ~~MEDIUM~~ FIXED

**File**: `lib/std/config.sls`

**Status**: FIXED on `hardened` branch.

**What was fixed**:
- `env-override!` now checks schema for `env-overridable` flag (4th element in schema entry)
- Default-deny: no schema = no environment overrides allowed
- Only keys explicitly declared as overridable (4th element = `#t`) accept env var overrides
- 5 tests verify default-deny, blocking, and selective override behavior

### V8. WebSocket Handshake Stub — MEDIUM

**File**: `lib/std/net/websocket.sls`

The handshake implementation returns a hardcoded test vector instead of computing `SHA-1(key + GUID)`. Not production-ready.

**Fix**: Implement the SHA-1 computation (via `(std crypto digest)` once V1 is fixed) and proper Base64 encoding.

### V9. Logger Information Leakage — MEDIUM

**File**: `lib/std/logger.sls`

- No structured logging — format strings can leak sensitive data
- No log levels enforced at compile time
- No rate limiting on log output (DoS via log flooding)
- `deflogger` is a no-op stub

**Fix**: Add structured logging with mandatory field classification (public/internal/secret). Secret-classified fields are redacted in non-debug output.

### V10. Unbounded Actor Mailboxes — ~~MEDIUM~~ FIXED

**File**: `lib/std/actor/bounded.sls`

**Status**: FIXED on `hardened` branch.

**What was fixed**:
- New `(std actor bounded)` module with configurable mailbox capacity
- Three backpressure strategies: `'block` (sender blocks), `'drop` (silent drop), `'error` (raises `&mailbox-full`)
- `spawn-bounded-actor` / `spawn-bounded-actor/linked` with `make-mailbox-config`
- `bounded-send` enforces limits; regular `send` bypasses for backward compatibility
- `mailbox-size` and `mailbox-full?` for monitoring

---

## Proposed: Language-Level Safety

These features leverage Chez Scheme's macro system and Jerboa's existing type infrastructure to provide safety guarantees that most languages cannot express.

### L1. Taint Tracking — IMPLEMENTED

A compile-time/runtime system that marks data from untrusted sources and prevents it from reaching dangerous sinks without explicit sanitization. Implemented on `hardened` branch in `(std security taint)`.

**What was implemented**:
- `taint` / `taint-http` / `taint-env` / `taint-file` / `taint-net` / `taint-deser` for marking data
- `check-untainted!` and `assert-untainted` for sink protection
- `untaint` for explicit sanitization
- Taint-propagating string operations: `tainted-string-append`, `tainted-substring`
- `&taint-violation` condition type with class and sink
- Opaque sealed records — unforgeable

```scheme
;; Mark data as tainted
(define/tainted user-input (request-param req "name"))

;; Type error: tainted string cannot flow to SQL sink
(sql-query db (format "SELECT * FROM users WHERE name = '~a'" user-input))

;; Safe: explicit sanitization produces clean value
(sql-query db "SELECT * FROM users WHERE name = ?" (sanitize-sql user-input))
```

**Implementation**: Wrap tainted values in an opaque record type. Overload string operations to propagate taint. SQL/shell/filesystem functions check for taint and raise `&taint-violation`. Sanitization functions unwrap the taint after validation.

**Taint categories**:
| Source | Taint Class | Required Sanitizer |
|--------|------------|-------------------|
| HTTP request params | `'http-input` | `sanitize-sql`, `sanitize-html`, `sanitize-path` |
| Environment variables | `'env-input` | `validate-config-value` |
| File contents | `'file-input` | `validate-schema` |
| Network data | `'net-input` | `sanitize-protocol` |
| Deserialized data | `'deser-input` | `validate-schema` |

### L2. Information Flow Control — IMPLEMENTED

Extend the type system with security labels that prevent secret data from flowing to public outputs. Implemented on `hardened` branch in `(std security flow)`.

**What was implemented**:
- Four security levels: `level-public`, `level-internal`, `level-secret`, `level-top-secret`
- `classify` / `classified?` / `classified-level` / `classified-value` for wrapping values
- `check-flow!` / `assert-flow` prevent downward data flow (secret → public)
- `declassify` with mandatory audit reason and configurable `current-declassify-handler`
- `&flow-violation` condition type
- Custom security levels via `make-security-level`

```scheme
;; Declare security levels
(define-security-level 'public)
(define-security-level 'internal)
(define-security-level 'secret)
(define-security-level 'top-secret)

;; Annotate values
(define/classified api-key 'secret (getenv "API_KEY"))
(define/classified user-name 'public (request-param req "name"))

;; Type error: secret cannot flow to public output
(log-info "Processing request for ~a with key ~a" user-name api-key)

;; Safe: explicit declassification with audit trail
(log-info "Processing request for ~a with key ~a"
  user-name (declassify api-key 'audit-reason "logging request context"))
```

**Implementation**: Security labels form a lattice. Data can flow up (public -> secret) but not down (secret -> public) without explicit `declassify` which logs an audit entry. Leverages Jerboa's effect system to track information flow through effect handlers.

### L3. Capability-Typed Functions — IMPLEMENTED

Combine the capability system with the type system so functions declare their required capabilities in their type signature. Implemented on `hardened` branch in `(std security capability-typed)`.

**What was implemented**:
- `define/cap` macro: `(define/cap (name args) (requires: cap-type ...) body)`
- `lambda/cap` macro for anonymous functions with capability requirements
- `capability-requirements` registry for introspection
- Functions raise `&capability-violation` when called outside matching capability context

```scheme
;; This function requires filesystem read capability
(define/cap (read-config path)
  (requires: (fs-read))
  (call-with-input-file path read))

;; This function requires no capabilities (pure)
(define/cap (parse-config sexp)
  (requires: ())
  (validate-schema config-schema sexp))

;; Calling read-config outside a capability context is a type error
(with-capabilities
  (list (make-fs-capability read: #t paths: '("/etc/myapp/")))
  (lambda () (read-config "/etc/myapp/config.scm")))  ;; OK

(read-config "/etc/passwd")  ;; ERROR: no fs-read capability in context
```

**Implementation**: `define/cap` expands to a function that calls `check-capability!` before executing the body. The `(requires: ...)` clause is also available to static analysis tools and documentation generators.

### L4. Safe Arithmetic

Extend `with-fixnum-ops` to provide overflow-checked arithmetic that raises an exception instead of silently wrapping or promoting to bignum.

```scheme
;; Checked arithmetic: raises on overflow
(with-checked-fixnum-ops
  (let ([size (fx+ header-length payload-length)])  ;; raises if overflow
    (make-bytevector size)))

;; Saturating arithmetic: clamps to fixnum range
(with-saturating-fixnum-ops
  (let ([counter (fx+ counter 1)])  ;; clamps to most-positive-fixnum
    counter))
```

**Security value**: Buffer size calculations, array index computation, and protocol length fields must not silently overflow.

### L5. Lifetime-Scoped Secrets — IMPLEMENTED

Combine affine types with automatic memory wiping for cryptographic material. Implemented on `hardened` branch in `(std security secret)`.

**What was implemented**:
- `make-secret` wraps bytevectors as affine-typed secrets
- `secret-use` consumes and wipes original bytevector
- `secret-peek` for read-only access without consumption
- `with-secret` macro auto-wipes on scope exit (even on exception) via `dynamic-wind`
- `wipe-bytevector!` utility for explicit zeroing
- Double-use raises error ("use-after-wipe")

```scheme
;; Secret is wiped from memory when scope exits
(with-secret ([key (derive-key password salt)])
  (let ([ciphertext (encrypt key plaintext)])
    ;; key is wiped here, even on exception
    ciphertext))

;; key is no longer accessible — affine type consumed + memory zeroed
```

**Implementation**: `with-secret` wraps the key in an affine type with a cleanup function that calls `bytevector-fill!` with zeros. The guardian ensures wiping even if the programmer forgets `affine-drop!`.

### L6. Proof-Carrying Contracts

Extend `define/contract` so that proven invariants can be propagated to callers, reducing redundant runtime checks.

```scheme
(define/contract (safe-substring str start end)
  (pre: (string? str)
        (<= 0 start) (<= start end) (<= end (string-length str)))
  (post: string?)
  (proves: (NonNeg (string-length result))
           (<= (string-length result) (string-length str)))
  (substring str start end))

;; Caller knows the result satisfies NonNeg length — no re-check needed
(define/contract (first-n-chars str n)
  (pre: (string? str) (NonNeg n) (<= n (string-length str)))
  (post: string?)
  (safe-substring str 0 n))  ;; preconditions are discharged by post-conditions
```

### L7. Effect-Based I/O Interception — IMPLEMENTED

Use the existing effect system to create auditable I/O layers where every filesystem, network, and process operation can be intercepted, logged, and policy-checked. Implemented on `hardened` branch in `(std security io-intercept)`.

**What was implemented**:
- Three effect types: `FileIO` (read/write/delete), `NetIO` (connect/listen), `ProcessIO` (exec)
- Intercepted I/O: `io/read-file`, `io/write-file`, `io/delete-file`, `io/net-connect`, etc.
- `make-deny-all-io-handler` — blocks all I/O (sandbox mode)
- `make-allow-io-handler` — delegates to real I/O (production mode)
- `make-audit-io-handler` — logs then delegates (audit mode)
- `with-io-policy` macro for scoped handler installation

```scheme
(with-handler ([file-read (lambda (path resume)
                            (audit-log! 'file-read `((path . ,path)))
                            (check-capability! 'filesystem 'read path)
                            (resume (real-file-read path)))]
               [net-connect (lambda (host port resume)
                              (audit-log! 'net-connect `((host . ,host) (port . ,port)))
                              (check-capability! 'network 'connect host)
                              (resume (real-net-connect host port)))])
  (run-application))
```

**Security value**: All I/O is mediated by handlers. Testing can install mock handlers. Production installs audit + policy handlers. There is no way to perform unmediated I/O.

---

## Proposed: Cryptographic Foundation

### C1. Direct libcrypto FFI — `(std crypto native)`

Replace all shell-based crypto with direct FFI to OpenSSL's libcrypto.

```scheme
;; Core primitives via FFI
(define-ffi-library libcrypto ("libcrypto.so")
  ;; Digest
  (EVP_MD_CTX_new      () -> void*)
  (EVP_MD_CTX_free     (void*) -> void)
  (EVP_DigestInit_ex   (void* void* void*) -> int)
  (EVP_DigestUpdate    (void* u8* size_t) -> int)
  (EVP_DigestFinal_ex  (void* u8* void*) -> int)
  (EVP_sha256          () -> void*)
  (EVP_sha512          () -> void*)

  ;; CSPRNG
  (RAND_bytes          (u8* int) -> int)

  ;; HMAC
  (HMAC                (void* u8* int u8* int u8* void*) -> u8*)

  ;; Constant-time comparison
  (CRYPTO_memcmp       (u8* u8* size_t) -> int))
```

**Eliminates**: Temp files, shell invocation, TOCTOU races, predictable random values.

### C2. CSPRNG — `(std crypto random)`

Cryptographically secure random number generation.

```scheme
;; Generate random bytes
(random-bytes 32)           ;; → bytevector of 32 random bytes
(random-bytes! bv)          ;; Fill existing bytevector with random bytes

;; Generate random values
(random-u64)                ;; → random 64-bit unsigned integer
(random-token 32)           ;; → hex-encoded random token string
(random-uuid)               ;; → UUID v4 string

;; Secure random choice
(random-choice '(a b c d))  ;; → uniformly random element
```

**Implementation**: `/dev/urandom` as primary source with `RAND_bytes` as fallback. Never use `(random N)` for security-relevant values.

### C3. Timing-Safe Operations — `(std crypto compare)`

Constant-time comparison for all secret material.

```scheme
;; Constant-time bytevector comparison
(timing-safe-equal? bv1 bv2)     ;; → boolean, constant-time

;; Constant-time string comparison (via UTF-8 encoding)
(timing-safe-string=? s1 s2)     ;; → boolean, constant-time

;; HMAC verification (timing-safe internally)
(hmac-verify? key message expected-mac)
```

**Implementation**: XOR-accumulate over all bytes, check accumulator is zero. Length check returns `#f` in constant time relative to the shorter input (no early exit).

### C4. Password Hashing — `(std crypto password)`

Proper password storage with memory-hard KDFs.

```scheme
;; Hash a password for storage
(password-hash "hunter2")
;; → "$argon2id$v=19$m=65536,t=3,p=4$salt$hash"

;; Verify a password against stored hash
(password-verify? "hunter2" stored-hash)  ;; → boolean (timing-safe)

;; Configurable parameters
(password-hash "hunter2"
  algorithm: 'argon2id
  memory-cost: 65536    ;; KiB
  time-cost: 3          ;; iterations
  parallelism: 4)       ;; threads
```

### C5. AEAD — `(std crypto aead)`

Authenticated encryption with associated data.

```scheme
;; Encrypt with authentication
(let-values ([(ciphertext tag) (aead-encrypt 'aes-256-gcm key nonce plaintext aad)])
  (values ciphertext tag))

;; Decrypt and verify (raises on tamper)
(aead-decrypt 'aes-256-gcm key nonce ciphertext tag aad)

;; Supported algorithms
;; aes-128-gcm, aes-256-gcm, chacha20-poly1305
```

### C6. Key Management — `(std crypto keys)`

Key lifecycle management for long-running services.

```scheme
;; Key ring with rotation
(define keyring (make-key-ring
  current: (load-key "/run/secrets/current.key")
  previous: (load-key "/run/secrets/previous.key")))

;; Encrypt with current key, decrypt tries all keys
(key-ring-encrypt keyring plaintext)
(key-ring-decrypt keyring ciphertext)  ;; tries current, then previous

;; Key derivation
(derive-subkey master-key "purpose:encryption" context)
(derive-subkey master-key "purpose:authentication" context)

;; Secret wiping (via affine types)
(with-secret ([key (key-ring-current keyring)])
  (encrypt key data))
;; key is zeroed here
```

---

## Proposed: Network and Protocol Hardening

### N1. TLS Hardening — `(std net tls)` — IMPLEMENTED

Secure defaults for all TLS connections. Implemented on `hardened` branch.

**What was implemented**:
- `(std net tls)` module with hardened defaults: TLS 1.2 minimum, AEAD-only cipher suites
- `make-tls-config` / `tls-config-with` for configuration composition
- Peer verification enabled by default
- Certificate pinning support via `make-pin-set` / `pin-set-check`
- Full TLS connect/listen/accept/read/write/close API via OpenSSL FFI

```scheme
;; Secure defaults (no opt-out for production)
(define tls-defaults
  (make-tls-config
    min-version: 'tls-1.2
    cipher-suites: '(TLS_AES_256_GCM_SHA384
                     TLS_CHACHA20_POLY1305_SHA256
                     TLS_AES_128_GCM_SHA256)
    verify-peer: #t
    verify-hostname: #t
    certificate-pinning: #f    ;; optional
    ocsp-stapling: #t))

;; Certificate pinning for high-security connections
(define pinned-config
  (tls-config-with tls-defaults
    certificate-pinning: (pin-sha256 "base64-encoded-pin==")))
```

### N2. HTTP Security Defaults — `(std net http-security)`

Security headers and middleware for the HTTP server.

```scheme
;; Security middleware stack (applied to all responses)
(define security-middleware
  (compose-middleware
    (cors-middleware allowed-origins: '("https://app.example.com")
                     allowed-methods: '(GET POST)
                     max-age: 86400)
    (csp-middleware default-src: "'self'"
                    script-src: "'self'"
                    style-src: "'self' 'unsafe-inline'")
    (hsts-middleware max-age: 31536000 include-subdomains: #t)
    (xss-protection-middleware)
    (content-type-nosniff-middleware)
    (frame-options-middleware 'deny)
    (request-id-middleware)
    (request-size-limit-middleware max-body: (* 10 1024 1024))  ;; 10MB
    (rate-limit-middleware limiter: (make-rate-limiter 100 10))))

;; Applied to router
(router-middleware! router security-middleware)
```

### N3. Input Sanitization — `(std security sanitize)`

Context-aware input sanitization.

```scheme
;; HTML entity escaping (XSS prevention)
(sanitize-html "<script>alert('xss')</script>")
;; → "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"

;; SQL parameterization (injection prevention)
(sql-escape "Robert'; DROP TABLE students;--")
;; → "Robert''; DROP TABLE students;--"
;; But prefer: parameterized queries always

;; Path traversal prevention
(sanitize-path "../../etc/passwd")
;; → raises &path-traversal-violation
(safe-path-join base-dir user-input)
;; → resolves symlinks, verifies result is under base-dir

;; Header injection prevention
(sanitize-header-value "value\r\nX-Injected: true")
;; → raises &header-injection-violation

;; URL sanitization
(sanitize-url "javascript:alert(1)")
;; → raises &url-scheme-violation (only http/https allowed)
```

### N4. Connection Timeouts and Limits — IMPLEMENTED

Implemented on `hardened` branch in `(std net timeout)`.

**What was implemented**:
- `make-timeout-config` with connect/read/write/idle timeout defaults
- `make-http-limits` with max header size/count, URI length, body size, request timeout
- `with-timeout` deadline enforcement via thread + polling
- `check-header-limits`, `check-body-limits`, `check-uri-limits` validation
- `&limit-exceeded` condition type with structured error reporting

```scheme
;; TCP with deadlines
(tcp-connect host port
  connect-timeout: 5000      ;; ms
  read-timeout: 30000        ;; ms
  write-timeout: 10000       ;; ms
  idle-timeout: 60000)       ;; ms

;; HTTP request limits
(make-http-limits
  max-header-size: 8192       ;; bytes
  max-header-count: 100
  max-uri-length: 2048        ;; bytes
  max-body-size: 10485760     ;; 10MB
  request-timeout: 30000      ;; ms — Slowloris protection
  keep-alive-timeout: 5000)   ;; ms
```

### N5. Safe Process Execution — `(std misc process-safe)`

Shell-free process execution.

```scheme
;; Direct exec (no shell) — safe by default
(run-process/exec '("git" "log" "--oneline" "-10")
  directory: "/path/to/repo"
  environment: '(("PATH" . "/usr/bin:/bin"))  ;; explicit, not inherited
  timeout: 30000)

;; Explicit shell (opt-in, requires capability)
(with-capabilities (list (make-process-capability spawn: #t))
  (lambda ()
    (run-process/shell "find . -name '*.log' | wc -l")))
```

---

## Proposed: Operating System Integration

### O1. seccomp-BPF Integration — `(std security seccomp)`

Restrict available syscalls for sandboxed workers.

```scheme
;; Define syscall whitelist
(define compute-only-filter
  (make-seccomp-filter 'kill  ;; default action: kill process
    (allow 'read 'write 'close 'fstat 'mmap 'mprotect
           'munmap 'brk 'rt_sigaction 'rt_sigprocmask
           'clone 'exit_group 'futex)))

;; Apply filter (irreversible — can only tighten after this)
(seccomp-install! compute-only-filter)

;; Now: open, socket, execve, etc. → immediate SIGKILL
```

### O2. Landlock Integration — `(std security landlock)`

Filesystem access control without root privileges (Linux 5.13+).

```scheme
;; Restrict filesystem access
(with-landlock
  (landlock-rules
    (fs-read-only "/usr/lib" "/lib" "/etc/ssl")
    (fs-read-write "/var/myapp/data")
    (fs-no-access "/etc/shadow" "/root"))
  (lambda ()
    ;; Application runs here with restricted filesystem
    (start-server)))
```

### O3. Privilege Separation — `(std security privsep)`

Fork-based privilege separation for critical operations.

```scheme
;; Supervisor/worker architecture
(define-privilege-separated
  (supervisor
    (capabilities: (list (make-fs-capability read: #t write: #t)
                         (make-net-capability listen: #t)))
    (on-request: (lambda (req)
                   (case (request-type req)
                     [(read-secret) (read-key-file (request-path req))]
                     [(audit-log) (write-audit-entry (request-data req))]
                     [else (error 'supervisor "unauthorized request")]))))

  (worker
    (seccomp-filter: compute-only-filter)
    (landlock: (fs-read-only "/usr/lib"))
    (capabilities: (list (make-net-capability connect: #t)))
    (entry-point: (lambda (supervisor-channel)
                    ;; Worker can only communicate via channel to supervisor
                    ;; Cannot read secrets directly, cannot write audit log directly
                    (let ([key (channel-request supervisor-channel 'read-secret "/run/secrets/key")])
                      (process-requests key supervisor-channel))))))
```

### O4. Namespace Isolation — `(std security namespace)`

Linux namespace integration for container-like isolation.

```scheme
;; Create isolated execution environment
(with-namespaces
  (namespaces: '(mount pid net user))
  (mount-binds: '(("/usr/lib" . "/usr/lib")
                  ("/lib" . "/lib")))
  (network: 'loopback-only)
  (lambda ()
    ;; Running in isolated namespace
    ;; Own PID 1, own mount table, loopback-only network
    (run-untrusted-plugin plugin-code)))
```

---

## Proposed: Supply Chain and Build Security

### S1. Dependency Verification — `(std build verify)`

Cryptographic verification of all dependencies.

```scheme
;; Lock file with SHA-256 hashes (extend jerboa/lock.sls)
(lockfile
  (entry "chez-ssl" "1.2.0"
    hash: "sha256:a3f2b8c9d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1"
    source: "https://github.com/ober/chez-ssl/archive/v1.2.0.tar.gz"
    source-hash: "sha256:b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5"))

;; Build-time verification
(verify-dependencies!
  lockfile: "jerboa.lock"
  on-mismatch: 'abort)  ;; 'abort | 'warn | 'update-lock
```

### S2. SBOM Generation — `(std build sbom)`

Software Bill of Materials for auditing.

```scheme
;; Generate SBOM in CycloneDX format
(generate-sbom
  project: "myapp"
  version: "1.0.0"
  format: 'cyclonedx-json
  include: '(runtime build test)
  output: "sbom.json")

;; Contents:
;; - Jerboa version and commit hash
;; - Chez Scheme version
;; - All chez-* library versions and hashes
;; - All C library dependencies (from build.ss -l flags)
;; - Build flags and compiler version
```

### S3. Reproducible Build Verification

Extend the existing `(std build reproducible)` system.

```scheme
;; Build with full provenance tracking
(build-with-provenance
  source-hash: (git-tree-hash "HEAD")
  builder-id: (machine-id)
  timestamp: #f  ;; stripped for reproducibility
  output: "myapp"
  provenance-file: "myapp.provenance.json")

;; Verify a build was produced from expected source
(verify-provenance "myapp" "myapp.provenance.json"
  expected-source-hash: "abc123...")
```

### S4. Boot File Signing

Verify integrity of Chez Scheme boot files before loading.

```scheme
;; Sign boot files during build
(sign-boot-file "petite.boot" signing-key)
(sign-boot-file "scheme.boot" signing-key)

;; Verify at startup (before any Scheme code runs)
(verified-scheme-start
  boot-files: '("petite.boot" "scheme.boot")
  public-key: embedded-public-key
  on-failure: 'abort)
```

---

## Proposed: Observability and Incident Response

### A1. Structured Audit Logging — `(std security audit)`

Append-only, tamper-evident audit logging for all security events.

```scheme
;; Initialize audit logger
(define audit (make-audit-logger
  output: "/var/log/myapp/audit.jsonl"
  rotation: (make-rotation-config
    max-size: (* 100 1024 1024)   ;; 100MB
    max-age: (* 30 24 3600)       ;; 30 days
    compress: #t)
  tamper-detection: 'hash-chain   ;; each entry includes hash of previous
  fields: '(timestamp event-type actor resource action result
            request-id correlation-id source-ip)))

;; Log security events
(audit-log! audit 'auth-attempt
  `((actor . ,username)
    (action . login)
    (result . ,(if success? 'allow 'deny))
    (source-ip . ,client-ip)
    (request-id . ,req-id)
    (mfa . ,(if mfa-used? 'verified 'not-required))))

;; Automatic audit for capability checks
(define (check-capability!/audit type permission . detail)
  (let ([result (guard (e [#t 'denied])
                  (check-capability! type permission)
                  'allowed)])
    (audit-log! audit 'capability-check
      `((type . ,type)
        (permission . ,permission)
        (detail . ,(if (pair? detail) (car detail) ""))
        (result . ,result)))
    (when (eq? result 'denied)
      (raise (make-capability-violation type
               (if (pair? detail) (car detail) ""))))))
```

### A2. Security Metrics — `(std security metrics)`

Real-time security health indicators.

```scheme
;; Track security-relevant metrics
(define metrics (make-security-metrics))

;; Counters
(metric-increment! metrics 'auth-failures)
(metric-increment! metrics 'rate-limit-hits)
(metric-increment! metrics 'capability-denials)
(metric-increment! metrics 'sandbox-violations)

;; Gauges
(metric-set! metrics 'active-sessions session-count)
(metric-set! metrics 'open-connections connection-count)

;; Histograms
(metric-observe! metrics 'auth-latency-ms elapsed)

;; Alerting thresholds
(metric-alert! metrics 'auth-failures
  threshold: 100
  window: 300          ;; 5 minutes
  action: (lambda (count)
            (audit-log! audit 'brute-force-detected
              `((count . ,count) (window . 300)))))
```

### A3. Safe Error Responses — `(std security errors)`

Prevent information leakage through error messages.

```scheme
;; Error classification
(define-error-class 'internal  ;; never shown to client
  'sql-error 'file-not-found 'assertion-failure
  'stack-overflow 'null-pointer)

(define-error-class 'client    ;; safe to show
  'bad-request 'unauthorized 'forbidden 'not-found
  'rate-limited 'payload-too-large)

;; Safe error handler for HTTP
(define (safe-error-handler req exn)
  (let ([internal-id (random-token 16)])
    ;; Log full details internally
    (audit-log! audit 'internal-error
      `((error-id . ,internal-id)
        (exception . ,(condition-message exn))
        (stack . ,(get-stack-trace))
        (request . ,(sanitize-request req))))
    ;; Return generic error to client
    (http-respond-json 500
      `((error . "Internal server error")
        (reference . ,internal-id)))))
```

### A4. Execution Replay for Security Analysis

Extend the existing `(std debug replay)` for security incident reproduction.

```scheme
;; Record execution with security event tagging
(record-security-execution
  (lambda ()
    (handle-request req))
  on-event: (lambda (event)
    ;; Tag security-relevant events for later analysis
    (when (security-event? event)
      (tag-event! event 'security))))

;; Replay to reproduce a security incident
(replay-security-execution recording
  until: (event-matches? 'capability-violation)
  inspect: (lambda (state)
    ;; Examine state at the moment of violation
    (inspect-bindings state)))
```

---

## Proposed: Distributed Systems Security

### D1. Encrypted Actor Transport

Replace plaintext TCP with mandatory TLS for all inter-node communication.

```scheme
;; Node startup with TLS
(start-node! "node-1:9000"
  cookie: (load-secret "/run/secrets/cluster-cookie")
  tls: (make-tls-config
         certificate: "/etc/myapp/node.crt"
         private-key: "/etc/myapp/node.key"
         ca-certificate: "/etc/myapp/ca.crt"
         verify-peer: #t))
```

### D2. Message Authentication and Replay Protection

```scheme
;; Authenticated message envelope
(define-record-type authenticated-message
  (fields
    sender-id       ;; node that sent it
    sequence-number ;; monotonic per-connection
    timestamp       ;; wall clock (for drift detection)
    payload         ;; actual message
    hmac))          ;; HMAC-SHA256 of (sender || seq || timestamp || payload)

;; Replay window: reject messages with sequence numbers older than N
(define *replay-window-size* 1024)
```

### D3. Actor Capability Delegation

Extend the capability system to work across nodes.

```scheme
;; Grant a remote actor specific capabilities
(define remote-ref (make-remote-actor-ref "node-2:9000" actor-id))

;; Delegate attenuated capability
(send remote-ref
  `(grant-capability
    ,(attenuate-capability
       (make-fs-capability read: #t paths: '("/shared/data/"))
       write: #f execute: #f)))

;; Remote actor can only read from /shared/data/
;; Capability is verified at the receiving node
```

### D4. Cluster Security Policies

```scheme
;; Define cluster-wide security policy
(define cluster-policy
  (make-cluster-policy
    ;; Authentication
    auth-method: 'mutual-tls
    cookie-rotation-interval: 86400  ;; 24 hours

    ;; Authorization
    node-roles: '(("node-1" . coordinator)
                  ("node-2" . worker)
                  ("node-3" . worker))
    role-permissions: '((coordinator . (spawn-actor kill-actor read-state write-state))
                        (worker . (spawn-actor read-state)))

    ;; Network
    allowed-connections: '((coordinator . (worker))
                           (worker . (coordinator)))  ;; no worker-to-worker

    ;; Anomaly detection
    max-messages-per-second: 10000
    max-message-size: (* 1 1024 1024)  ;; 1MB
    dead-letter-alert-threshold: 100))
```

---

## Implementation Roadmap

### Phase 1: Fix Critical Vulnerabilities (P0)

| Item | Effort | What Changes |
|------|--------|-------------|
| V1: Command injection in digest | 2 days | Rewrite `(std crypto digest)` with direct libcrypto FFI |
| V2: Forgeable capabilities | 2 days | Replace vector with opaque sealed record type in both `(std security capability)` and `(std capability)` |
| V3: Predictable nonces | 1 day | CSPRNG from `/dev/urandom` in both capability modules |
| C2: CSPRNG module | 1 day | New `(std crypto random)` |
| C3: Timing-safe comparison | 1 day | New `(std crypto compare)` |

### Phase 2: Harden Foundations (P1)

| Item | Effort | What Changes |
|------|--------|-------------|
| V4: Sandbox escape | 3 days | Rewrite `(std security restrict)` with allowlist-only approach |
| V6: Shell injection in process | 2 days | Add `run-process/exec` via FFI `execvp` |
| V7: Config env injection | 1 day | Add `env-overridable` whitelist to schema |
| A1: Audit logging | 3 days | New `(std security audit)` with hash chain |
| N3: Input sanitization | 3 days | New `(std security sanitize)` |
| C1: Direct libcrypto FFI | 3 days | New `(std crypto native)` |

### Phase 3: Network and Authentication (P2)

| Item | Effort | What Changes |
|------|--------|-------------|
| ~~V5: Actor transport auth~~ | ~~3 days~~ | ~~HMAC-SHA256 + nonce + TLS~~ **DONE** |
| ~~N1: TLS hardening~~ | ~~2 days~~ | ~~Secure defaults wrapper~~ **DONE** |
| ~~N2: HTTP security headers~~ | ~~2 days~~ | ~~Security middleware stack~~ **DONE** |
| ~~N4: Connection timeouts~~ | ~~2 days~~ | ~~Extend TCP layer with deadlines~~ **DONE** |
| ~~C4: Password hashing~~ | ~~2 days~~ | ~~PBKDF2-HMAC-SHA256~~ **DONE** |
| ~~C5: AEAD~~ | ~~2 days~~ | ~~AES-256-GCM via libcrypto~~ **DONE** |
| ~~Authentication module~~ | ~~3 days~~ | ~~API keys, sessions, rate limiting~~ **DONE** |

### Phase 4: Language-Level Safety (P3)

| Item | Effort | What Changes |
|------|--------|-------------|
| ~~L1: Taint tracking~~ | ~~5 days~~ | ~~New `(std security taint)`~~ **DONE** |
| ~~L2: Information flow~~ | ~~5 days~~ | ~~New `(std security flow)`~~ **DONE** |
| ~~L3: Capability-typed functions~~ | ~~3 days~~ | ~~`(std security capability-typed)`~~ **DONE** |
| ~~L5: Lifetime-scoped secrets~~ | ~~2 days~~ | ~~New `(std security secret)`~~ **DONE** |
| ~~L7: Effect-based I/O interception~~ | ~~3 days~~ | ~~New `(std security io-intercept)`~~ **DONE** |
| ~~V10: Bounded actor mailboxes~~ | ~~2 days~~ | ~~New `(std actor bounded)`~~ **DONE** |

### Phase 5: OS-Level Enforcement (P3)

| Item | Effort | What Changes |
|------|--------|-------------|
| O1: seccomp-BPF | 5 days | New `(std security seccomp)` |
| O2: Landlock | 3 days | New `(std security landlock)` |
| O3: Privilege separation | 5 days | New `(std security privsep)` |
| A2: Security metrics | 3 days | New `(std security metrics)` |
| A3: Safe error responses | 2 days | New `(std security errors)` |

### Phase 6: Supply Chain and Distributed (P4)

| Item | Effort | What Changes |
|------|--------|-------------|
| S1: Dependency verification | 3 days | Extend `(jerboa lock)` |
| S2: SBOM generation | 2 days | New `(std build sbom)` |
| S3: Reproducible build verification | 2 days | Extend `(std build reproducible)` |
| D1-D4: Distributed security | 5 days | Extend actor transport + new cluster policy |

---

## Architectural Position

### Why Jerboa's Architecture Is Fundamentally Sound

**Small, auditable codebase**: 64K lines of library code, 326 modules. A single experienced auditor can review the entire security surface. Compare: a typical Node.js web application pulls in 1,500+ npm packages totaling millions of lines — no human or AI can audit that.

**Minimal native dependencies**: Stock Chez Scheme + optional chez-* wrappers. The trusted computing base is well-defined and small. Every native dependency is a known, versioned library.

**Macro system enables compile-time safety**: Taint tracking, capability checking, information flow control, and contract verification can all be implemented as macros that transform code at compile time. This is not possible in languages without hygienic macros.

**GC-managed memory**: Buffer overflows, use-after-free, and double-free are impossible in pure Scheme code. Memory safety concerns are confined to the FFI boundary — a small, auditable surface.

**Self-hosting bootstrap**: The entire build chain from source to binary is verifiable. Reproducible builds mean any two people building from the same source get the same output.

### What Jerboa Offers That Rust Cannot

| Feature | Jerboa | Rust |
|---------|--------|------|
| **Taint tracking** | Macro-based, zero-runtime-cost | Requires external tools (clippy lints) |
| **Capability-based security** | First-class, with attenuation and typing | Manual, via ownership patterns |
| **Effect system** | Algebraic effects with handlers | No native support (async is ad-hoc) |
| **Hot code reload** | Native (load + mtime tracking) | Requires restart |
| **Runtime contract verification** | `define/contract` with pre/post/proves | Only via `debug_assert!` |
| **Sandboxed evaluation** | `restricted-eval` with environment control | Not possible without separate process |
| **Formal verification hooks** | Proof-carrying contracts via macros | Requires external provers |
| **Linear/affine types** | Runtime-enforced with guardian cleanup | Compile-time only (ownership) |
| **GC + deterministic cleanup** | Affine types + guardians + `dynamic-wind` | RAII only (no GC) |

### What Rust Offers That Jerboa Should Adopt

| Feature | How Jerboa Can Achieve It |
|---------|--------------------------|
| **Compile-time memory safety** | Confined to FFI boundary; use `define-foreign/check` and `with-foreign-resource` |
| **Thread safety via ownership** | `defstruct/immutable` + `defstruct/thread-safe` + STM |
| **No null pointer dereference** | Refinement type `NonNull` + phantom type state tracking |
| **No data races** | STM for shared state; channels for message passing; no shared mutable state |
| **Fearless concurrency** | Structured concurrency (`with-task-scope`) + deadlock detection |

### The Security Stack

```
┌─────────────────────────────────────────────────────────────────┐
│  Application Code                                               │
│  (define/contract, define/t, define/cap, define/tainted)        │
├─────────────────────────────────────────────────────────────────┤
│  Jerboa Security Layer                                          │
│  Capabilities │ Taint Tracking │ Contracts │ Effects │ Types    │
├─────────────────────────────────────────────────────────────────┤
│  Jerboa Runtime                                                 │
│  Audit Logger │ Rate Limiter │ Schema Validator │ Sanitizer     │
├─────────────────────────────────────────────────────────────────┤
│  Crypto Foundation                                              │
│  libcrypto FFI │ CSPRNG │ AEAD │ HMAC │ Timing-Safe Compare    │
├─────────────────────────────────────────────────────────────────┤
│  OS Enforcement                                                 │
│  seccomp-BPF │ Landlock │ Namespaces │ Privilege Separation     │
├─────────────────────────────────────────────────────────────────┤
│  Chez Scheme (GC, threads, native compilation)                  │
├─────────────────────────────────────────────────────────────────┤
│  Linux Kernel                                                   │
└─────────────────────────────────────────────────────────────────┘
```

Every layer provides independent security guarantees. Compromise of one layer is contained by the others. This is not a Rust-or-nothing proposition — it is defense in depth using every tool the platform provides.
