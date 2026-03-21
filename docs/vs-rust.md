# Jerboa vs Rust for Secure Crypto Infrastructure

An honest analysis of where GC is a real limitation, where it isn't, and what features Jerboa should adopt from Rust to close the gap.

---

## Table of Contents

1. [The Question](#the-question)
2. [What GC Actually Prevents](#what-gc-actually-prevents)
3. [What's Not Fundamental — Just Missing Features](#whats-not-fundamental--just-missing-features)
4. [What Jerboa Should Steal from Rust](#what-jerboa-should-steal-from-rust)
5. [The Right Language for Each Layer](#the-right-language-for-each-layer)
6. [The Honest Assessment](#the-honest-assessment)

---

## The Question

If you were building a highly secure crypto infrastructure — key management, encrypted transport, policy enforcement, audit — would you choose Rust or Jerboa?

The naive answer is Rust, because memory safety. The real answer is more nuanced, because "crypto infrastructure" is a stack with different requirements at each layer, and GC-based memory safety is a different tradeoff than ownership-based memory safety.

---

## What GC Actually Prevents

There are exactly three things a garbage collector makes impossible or very hard. These are fundamental to the GC model, not implementation bugs that Chez could fix.

### 1. Guaranteed Secret Wiping

When you call `bytevector-fill!` to zero a cryptographic key, the GC may have already copied that bytevector during heap compaction. The old copy sits in the heap until it's overwritten by a future allocation. You can't find it, you can't zero it, and a core dump or cold boot attack recovers it.

Rust's `Zeroize` trait has a similar problem with the optimizer (LLVM can eliminate "dead" stores to memory that's about to be freed), but `Pin` + `ManuallyDrop` + volatile writes give you a fighting chance. With GC, you have no chance — the collector moves objects without telling you, and you cannot enumerate all previous locations of an object.

**Impact**: Any time a cryptographic key, password, token, or other secret exists as a Scheme bytevector, copies may persist in the heap indefinitely.

### 2. Deterministic Timing

GC pauses inject unpredictable latency. In a protocol where you need constant-time behavior — MAC verification must take the same time regardless of where the mismatch is, TLS record processing must not reveal plaintext length through timing — a GC pause between two timing measurements corrupts the guarantee.

The primitive operation itself might be constant-time (via OpenSSL's `CRYPTO_memcmp` called through FFI), but the Scheme wrapper around it isn't. If the GC fires between "start timer" and "end timer," the attacker sees variable latency and can extract information.

**Impact**: Any Scheme-level timing measurement is unreliable. Constant-time operations must be pushed entirely into C/FFI, with no Scheme allocation between the timing-sensitive start and end points.

### 3. Memory Layout Control

You can't place two keys in adjacent cache lines to minimize cache side-channel exposure. You can't ensure a nonce counter is in a specific memory region. You can't use `mlock` reliably because GC moves the object after you've locked its page. You can't use `madvise(MADV_DONTDUMP)` on a Scheme object because it might be relocated before the core dump happens.

**Impact**: Side-channel mitigations that depend on memory placement (cache-line isolation, page-level protections) are impossible for GC-managed objects.

### What GC Does NOT Prevent

These three limitations affect a narrow part of the security stack: **secret material handling and timing-critical operations**. They do not affect:

- Capability enforcement
- Access control policy logic
- Audit logging
- Schema validation
- Protocol state machines (correctness, not timing)
- Key management policy (who can use which key for what)
- Sandbox enforcement
- Taint tracking
- Contract verification
- Effect tracking

For all of the above, GC is irrelevant to security. The language features that matter are expressiveness, type safety, and correctness guarantees — areas where Jerboa has advantages over Rust.

---

## What's Not Fundamental — Just Missing Features

Rust has several features that improve security. Most of them are not inherent to Rust's memory model — they're language features that could be added to Jerboa.

### Compile-Time Exhaustive Matching

**Rust**: `match` on an `enum` is exhaustive — forget a variant and the compiler rejects it. This matters for security state machines where a missing case means a missing security check.

**Jerboa today**: `match` has a runtime catch-all. Missing a case silently falls through.

**Jerboa could add**:

```scheme
;; Hypothetical: exhaustive-match that requires listing all known variants
(defstruct message-type)
(defstruct (handshake-init message-type) fields: (client-hello))
(defstruct (handshake-response message-type) fields: (server-hello))
(defstruct (data message-type) fields: (payload))
(defstruct (close message-type) fields: (reason))

(exhaustive-match msg message-type
  [(handshake-init? msg) ...]
  [(handshake-response? msg) ...]
  [(data? msg) ...]
  ;; compile-time error: missing (close? msg) case
  )
```

**Implementation**: A `defstruct`-aware macro that knows the variant list for a parent type and verifies at macro-expansion time that all variants are covered. No runtime cost, no language change — just a macro.

### Compile-Time Lifetime Tracking

**Rust**: The borrow checker catches use-after-free, double-use, and forgotten-drop at compile time.

**Jerboa today**: Linear and affine types catch these at runtime — use a value twice and you get an error when the code runs, not when it compiles.

**Jerboa could add**: A static analysis pass that checks linear consumption for annotated code. It wouldn't be as complete as Rust's borrow checker (Chez's macro system isn't a full type checker), but it could catch the obvious cases before the code runs:

- Double use of a linear value
- Scope exit without consuming a linear value
- Passing a linear value to a function that doesn't consume it

Think of it as a lint pass, not a type system. Catches 80% of the bugs at 20% of the implementation cost.

### Send/Sync — Compile-Time Thread Safety

**Rust**: `Send` and `Sync` traits prevent data races at compile time. A non-`Send` type cannot be moved to another thread. Period.

**Jerboa today**: Runtime annotations (`defstruct/thread-safe`, `defstruct/immutable`) and STM. Thread safety is enforced by convention and runtime checks.

**Jerboa could add**: A static analysis pass that verifies mutable structs don't cross thread boundaries without synchronization. Inspect `spawn`, `thread-start!`, `channel-put`, and `send` calls for arguments that are mutable, non-thread-safe structs.

### Sum Types with Associated Data

**Rust**: Enums carry data per variant — `Result<T, E>` is `Ok(T) | Err(E)`. Pattern matching destructures them.

**Jerboa today**: GADTs provide tagged constructors with fields, but they're runtime-checked. `defstruct` with subtypes is close but doesn't integrate with exhaustive matching.

**Jerboa could add**: Tighter integration between `defstruct` variant hierarchies and `match`, enabling the exhaustive matching described above plus ergonomic destructuring.

### No-Panic / Infallible APIs

**Rust**: Distinguishes `Result<T, E>` (recoverable) from `panic!` (unrecoverable). Libraries document which functions can panic and which return `Result`.

**Jerboa today**: Any function can raise any condition. There's no way to declare or verify that a function is total (always returns a value, never raises).

**Jerboa could add**:

```scheme
;; define/total: statically verified to never raise
(define/total (parse-config sexp)
  ;; compile-time error if body contains: error, raise, assert, or calls
  ;; to non-total functions without guard/catch
  (validate-schema config-schema sexp))
```

This is valuable for security-critical code paths where you need the guarantee that error handling cannot be bypassed by an unexpected exception. If a capability check is `define/total`, you know it always returns allow/deny — it never crashes in a way that might default to allow.

### Typestate Enforcement

**Rust**: Session types and typestate patterns via `enum` transitions — a TCP socket in state `Connected` has different methods than one in state `Listening`.

**Jerboa today**: Phantom types provide runtime state tracking with `phantom-check` and `phantom-transition`.

**Jerboa could add**: Compile-time transition checking. The phantom type registry already declares valid transitions — a macro could verify at expansion time that code only calls methods valid for the declared state.

---

## What Jerboa Should Steal from Rust

Ranked by impact on closing the security gap:

### 1. Foreign Region Allocator — Eliminates the #1 GC Limitation

A non-GC-managed memory region for secrets. This is the single most important feature for crypto infrastructure.

```scheme
;; Secure memory region outside GC's reach
(with-secure-region ([key (secure-alloc 32)]
                     [nonce (secure-alloc 12)])
  ;; key and nonce are in mlock'd memory, invisible to GC
  ;; they are bytevector-like but NOT managed by the collector
  (secure-random-fill! key)
  (secure-random-fill! nonce)
  (let ([ciphertext (aead-encrypt key nonce plaintext)])
    ;; ciphertext is GC-managed (not secret) — that's fine
    ciphertext))
;; key and nonce are zeroed and munlock'd here — guaranteed
;; even on exception — because dynamic-wind + explicit_bzero
```

**Implementation**:

| Component | Mechanism |
|-----------|-----------|
| Allocation | `mmap(MAP_PRIVATE \| MAP_ANONYMOUS)` via FFI |
| Page locking | `mlock()` — prevents swapping to disk |
| Core dump protection | `madvise(MADV_DONTDUMP)` — excluded from core dumps |
| Guard pages | `mprotect(PROT_NONE)` on pages before and after — catches buffer overflows |
| Wiping | `explicit_bzero()` — guaranteed not optimized away |
| Scope management | `dynamic-wind` — wipe runs even on exception or continuation escape |
| GC isolation | Region is outside the Chez heap — collector never sees it, never copies it |

This is the pattern libsodium uses (`sodium_malloc` / `sodium_free` / `sodium_mprotect_noaccess`). Chez can implement it entirely via FFI to `mmap`/`mlock`/`madvise`. The secure region is outside the GC heap, so the collector never sees it, never copies it, never leaves remnants.

The secure allocator would integrate with Jerboa's existing affine types:

```scheme
;; Secure region values are automatically affine — use at most once
;; Guardian ensures wiping even if the programmer forgets
(define key (secure-alloc/affine 32 cleanup: secure-wipe!))
;; ... use key ...
(affine-drop! key)  ;; explicit wipe — or auto-wipe on scope exit
```

**Effort**: 3-5 days. The FFI calls are straightforward. The integration with `dynamic-wind` and affine types requires care but Jerboa already has both primitives.

### 2. Compile-Time Exhaustive Match

Catches missed security states at compile time. A TLS state machine with 8 states and a `match` that only handles 7 is a vulnerability — and today Jerboa only catches it when the 8th state is reached at runtime.

```scheme
(define-variants tls-state
  tls-idle tls-handshake-sent tls-handshake-received
  tls-established tls-closing tls-closed
  tls-error tls-resumed)

(exhaustive-match (connection-state conn) tls-state
  [(tls-idle) ...]
  [(tls-handshake-sent) ...]
  [(tls-handshake-received) ...]
  [(tls-established) ...]
  [(tls-closing) ...]
  [(tls-closed) ...]
  [(tls-error) ...]
  ;; COMPILE-TIME ERROR: missing tls-resumed case
  )
```

**Effort**: 2-3 days. Macro that tracks variant registrations and checks coverage at expansion time.

### 3. Static Linearity Checking

Catches use-after-drop before runtime. Today, using a dropped affine value is a runtime error. A lint pass could catch the obvious cases statically.

```scheme
(with-linear ([key (derive-key password salt)])
  (encrypt key plaintext)
  (encrypt key plaintext)  ;; STATIC WARNING: key already consumed
  )
```

**Effort**: 3-5 days. Static analysis over SSA-like form of the code. Won't catch everything (higher-order, conditional consumption), but catches the common mistakes.

### 4. Total Function Annotation

Guarantees critical paths complete without exception.

```scheme
(define/total (check-permission user resource action)
  ;; Guaranteed to return 'allow or 'deny — never raises
  ;; Compiler verifies: no unguarded calls to non-total functions
  (if (and (valid-user? user)
           (capability-permits? user resource action))
    'allow
    'deny))
```

**Effort**: 2-3 days. Macro that analyzes body for `error`/`raise` calls and unguarded calls to non-total functions.

### 5. Typestate at Compile Time

Extends phantom types with compile-time transition verification.

```scheme
(define-protocol tls-protocol
  (transitions
    [idle -> handshake-sent]
    [handshake-sent -> handshake-received error]
    [handshake-received -> established error]
    [established -> closing]
    [closing -> closed]))

;; Compile-time error: cannot transition from idle to established
(phantom-transition conn 'idle 'established)
```

**Effort**: 3-5 days. Extends the existing phantom type registry with compile-time checking.

### Summary Table

| Feature | What It Fixes | Effort | Priority |
|---------|--------------|--------|----------|
| Secure region allocator | Secret wiping, memory layout, mlock | 3-5 days | Critical |
| Exhaustive match | Missed security states | 2-3 days | High |
| Static linearity | Use-after-drop at compile time | 3-5 days | High |
| Total functions | Exception-bypass in security checks | 2-3 days | Medium |
| Typestate checking | Protocol state machine correctness | 3-5 days | Medium |
| Send/Sync analysis | Thread safety | 3-5 days | Lower |

---

## The Right Language for Each Layer

No single language is optimal for all layers of a crypto infrastructure. The right answer is a stack.

### Crypto Primitives (AES, SHA, ECDSA, key derivation)

**Best language**: C or assembly.

Not because C is safe — it's the opposite — but because crypto primitives need:

- Constant-time guarantees (no branch on secret data, no secret-dependent memory access)
- Precise control over memory layout (to wipe keys, avoid optimizer-eliminated stores)
- No GC that copies secrets to unpredictable locations
- SIMD intrinsics for performance (AES-NI, CLMUL, AVX2)

No high-level language gives you all of that. In practice, you don't write your own — you use libsodium or OpenSSL's libcrypto.

### Protocol Layer (TLS, key exchange, certificate validation, message framing)

**Best language**: Rust.

This layer is where most real-world crypto bugs live. Heartbleed was a bounds check bug in the TLS heartbeat handler, not in any cipher. This layer needs:

- Memory safety (buffer overflows are the #1 vulnerability class in protocol implementations)
- Strong type system (state machines encoded as types)
- No GC pauses (matters for timing-sensitive protocols)
- Good FFI to call the C primitives underneath

Rust delivers all of this. `rustls` is proof — a TLS implementation with zero memory safety CVEs, compared to OpenSSL's hundreds.

### Application Security Layer (key management, access control, audit, policy)

**Best language**: Jerboa (with the features above) or a similarly expressive language.

This layer needs:

| Requirement | Jerboa Feature | Rust Equivalent |
|-------------|---------------|----------------|
| Capability-based access control | First-class capabilities with attenuation | Manual, via ownership patterns |
| Audit logging with mediated I/O | Effect system with handlers | No native support |
| Sandboxed evaluation | `restricted-eval` with environment control | Not possible without separate process |
| Runtime contract verification | `define/contract` with pre/post/proves | Only `debug_assert!` |
| Key policy enforcement | Taint tracking + capabilities + types | External tools (clippy lints) |
| Hot code reload | Native (load + mtime tracking) | Requires restart |
| Formal verification hooks | Proof-carrying contracts via macros | Requires external provers |
| Key lifetime management | Affine types + secure regions + guardians | RAII + `Zeroize` + `Pin` |

The stack:

```
┌─────────────────────────────────────────────────────────────────┐
│  Policy / Key Management / Audit / Access Control               │
│  Jerboa                                                         │
│  (capabilities, effects, contracts, taint tracking, sandbox)    │
├─────────────────────────────────────────────────────────────────┤
│  Protocol Layer                                                 │
│  Rust                                                           │
│  (memory safety, no GC, strong types, state machines)           │
├─────────────────────────────────────────────────────────────────┤
│  Crypto Primitives                                              │
│  C / assembly (via libsodium or libcrypto)                      │
│  (constant-time, hardware control, SIMD, timing guarantees)     │
└─────────────────────────────────────────────────────────────────┘
```

Each layer uses the language whose strengths match the threat model at that layer. The primitives need hardware control. The protocol needs memory safety without GC. The policy layer needs expressiveness.

---

## The Honest Assessment

### If Forced to Pick One Language

**Rust**. It's the best single-language compromise: memory safe without GC, good FFI to C primitives, strong enough types for protocol state machines, and while its application layer isn't as expressive as Jerboa's, it's adequate. The ecosystem (ring, rustls, RustCrypto) is mature and audited.

### Where Jerboa Wins Today

For key management services, policy-driven encryption gateways, or any system where the hard problem is "who can decrypt what under which conditions" rather than "implement AES correctly," Jerboa is already more expressive than Rust:

- **Capabilities** can't be forged (after V2 fix), attenuate monotonically, and integrate with the type system
- **Effects** make I/O explicit and interceptable — every key operation can be mediated and audited
- **Contracts** enforce API invariants at every boundary
- **Taint tracking** prevents secret data from flowing to public outputs
- **Sandbox** enables safe evaluation of user-provided policy expressions
- **Hot reload** enables key rotation and policy updates without downtime

### Where Jerboa Loses Today

- **Secret material in memory** — GC copies keys. Fixed by the secure region allocator.
- **Timing guarantees** — GC pauses. Mitigated by doing timing-critical work in FFI.
- **Compile-time safety** — exhaustiveness, linearity, thread safety are runtime-only. Fixed by the features above.
- **Ecosystem maturity** — Rust has audited, production-deployed crypto libraries. Jerboa has design documents.

### After the Proposed Features

With the secure region allocator and compile-time exhaustive match, Jerboa's security story becomes:

| Layer | Jerboa Status | vs Rust |
|-------|--------------|---------|
| Crypto primitives | Call libsodium/libcrypto via FFI | Equal (both call C) |
| Secret handling | Secure regions + affine types + guardians | On par with `Zeroize` + `Pin` |
| Protocol state machines | Exhaustive match + phantom types + typestate | Comparable to Rust enums |
| Application security | Capabilities + effects + contracts + taint + sandbox | Significantly ahead |
| Constant-time operations | FFI to C for timing-critical paths | Slight disadvantage (GC pauses around FFI calls) |

GC is the limitation for roughly 5% of the crypto stack — secret material in memory and timing-critical operations. The secure region allocator covers most of that 5%. The remaining sliver — true constant-time execution at the Scheme level — requires C/asm and always will, in any GC'd language.

For the other 95% of crypto infrastructure, Jerboa is already more expressive than Rust, and the features proposed here would widen that gap.
