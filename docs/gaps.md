# Jerboa Language Review: Security, Safety, Performance for Claude

A comprehensive review of Jerboa as a primary language for Claude to code in,
focused on best-in-class security, safety, and performance.

## What Jerboa Is

Jerboa reimplements Gerbil Scheme's API surface as pure **stock Chez Scheme**
libraries — 364 modules, ~2,900 tests, 13 fuzzing harnesses. No custom runtime,
no patched Chez. This is a significant engineering achievement.

---

## Strengths (What's Already Best-in-Class)

### Security Architecture — Exceptional

The layered defense model is genuinely impressive and ahead of most languages:

- **Allowlist-only sandbox** (`restrict.sls`) — 113 bindings, no blocklist.
  Future Chez additions can't leak in. `read` replaced with depth-limited
  `jerboa-read` (no `#.` read-eval). This is the right design.
- **Capability-based security** with sealed opaque records + CSPRNG nonces —
  unforgeable by construction.
- **Taint tracking** with safe sinks — prevents untrusted data from reaching
  `system`, `open-output-file`, etc.
- **OS-level enforcement** — Landlock (irreversible filesystem restrictions),
  seccomp, privsep via fork.
- **Secure memory** — mlock, guard pages, explicit_bzero, DONTDUMP, DONTFORK.
- **AI attack hardening** — 13 findings addressed (empty-host = deny, symlink
  resolution, etc.).
- **13 fuzzing harnesses** with configurable depth limits.

### Rust Native Backend — Smart Architecture

Replacing 10+ C dependencies with a single `libjerboa_native.so` via Rust is
the right call. ring for crypto, flate2 for compression, regex crate for
ReDoS-proof matching. The `ffi_wrap()`/`set_last_error()` panic handling is
correct.

### Type System Breadth

Refinement types, linear types, affine types, phantom types, GADTs,
typeclasses, row polymorphism, HKTs — all present. The `define/r` and
`lambda/r` forms for checked refinements are clean.

### Chez Scheme Foundation

Running on stock Chez gives you: engines (preemptive timeout), ephemerons
(GC-aware weak refs), FASL (fast serialization), ftypes (C struct access), WPO,
and a mature GC. These are genuine advantages over Gambit.

---

## Gaps and Recommendations for Best-in-Class

### 1. CRITICAL: Resource Safety / RAII Guarantees

**Gap**: The `borrow.sls` module tracks borrows at runtime, but there's no
compile-time or macro-enforced resource discipline that prevents "forgot to
close the file" bugs — the #1 source of resource leaks in dynamic languages.

**Recommendation**: Add a `with-resource` macro that is the **only** way to
acquire resources (files, sockets, DB connections, crypto contexts). Like
Python's `with` or Rust's `Drop`, but enforced:

```scheme
(with-resource ([db (sqlite-open "test.db")]
                [sock (tcp-connect "localhost" 8080)])
  (sqlite-exec db "SELECT 1")
  (tcp-write sock "hello"))
;; db and sock are guaranteed closed here, even on exception
```

The existing `dynamic-wind` and `with-destroy` patterns exist but aren't
mandatory. For Claude-generated code, making the safe path the easy path matters
more than flexibility.

### 2. CRITICAL: Contract-Checked Standard Library

**Gap**: The contract system (`define/contract`, `check-argument`) exists but
isn't applied to the standard library itself. Claude can call `sqlite-exec` with
wrong types and get cryptic FFI errors.

**Recommendation**: Wrap the top ~50 most-used stdlib APIs with contracts:

```scheme
(define/contract (sqlite-exec db sql)
  (pre: (sqlite-db? db) (string? sql))
  (post: (lambda (r) (or (null? r) (list? r))))
  ...)
```

This catches bugs at the Scheme boundary before they hit C/Rust FFI. In
`*typed-mode* 'release`, these should compile away to zero overhead.

### 3. HIGH: Structured Error Types Across the Stack

**Gap**: Many modules use bare `(error 'who "message")` which produces
unstructured error messages. The security modules have proper condition types
(`&taint-violation`, `&contract-violation`, `&sandbox-violation`), but
networking, database, and actor errors don't.

**Recommendation**: Define a condition hierarchy for every subsystem:

```scheme
;; Network errors
&network-error -> &connection-refused, &timeout, &dns-failure, &tls-error

;; Database errors
&db-error -> &query-error, &constraint-violation, &connection-lost

;; Actor errors
&actor-error -> &mailbox-full, &actor-dead, &supervision-failure
```

This lets Claude write proper error handling with `guard` clauses that
pattern-match on error type rather than parsing strings.

### 4. HIGH: Compile-Time Import Verification

**Gap**: No tool currently verifies at compile time that all imported symbols
are actually used, or that all used symbols are actually imported. The
`gerbil_lint` tool does this for Gerbil, but Jerboa needs its own.

**Recommendation**: Add a `jerboa lint` command that:

- Detects unused imports
- Detects unbound identifiers before runtime
- Warns on shadowed bindings
- Checks arity at call sites (using the type annotations when available)

### 5. HIGH: Timeout Enforcement on All External Operations

**Gap**: The engine-based timeout system is powerful (Chez-exclusive), but it's
not automatically applied to network I/O, database queries, or subprocess calls.
Claude-generated code that calls `tcp-read` without a timeout hangs forever.

**Recommendation**: Make timeouts mandatory or defaulted on all blocking
operations:

```scheme
;; Every blocking call should accept timeout:
(tcp-read sock 1024 timeout: 30)  ;; seconds, raises &timeout after 30s
(sqlite-query db "SELECT ..." timeout: 5)
(channel-get ch timeout: 10)

;; Or wrap in engine-based timeout:
(with-timeout 30
  (tcp-read sock 1024))
```

### 6. MEDIUM: Immutable-by-Default Data Structures

**Gap**: Hash tables, vectors, and records are mutable by default. For
Claude-generated code, accidental mutation is a common bug class.

**Recommendation**: Provide immutable variants as the default import, with
mutable opt-in:

```scheme
;; Default: immutable hash
(def h (hash ("key" "val")))  ;; immutable
(hash-set h "key2" "val2")    ;; returns new hash

;; Opt-in mutable
(def h (mutable-hash ("key" "val")))
(hash-set! h "key2" "val2")   ;; mutates in place
```

The persistent data structures (`pmap.sls`, `pvec.sls`) exist but aren't the
default. Making them default would prevent an entire class of bugs.

### 7. MEDIUM: Serialization Safety

**Gap**: FASL serialization is fast but can deserialize arbitrary objects
including procedures. This is dangerous for any network-facing code.

**Recommendation**: Add a safe serialization mode that only allows data (no
procedures, no records unless explicitly registered):

```scheme
(safe-fasl-write obj port)      ;; raises if obj contains procedures
(safe-fasl-read port)           ;; rejects procedures, unregistered records
(register-safe-record-type! <rtd>)  ;; opt-in for specific types
```

### 8. MEDIUM: Actor Mailbox Backpressure by Default

**Gap**: Actor mailboxes are unbounded by default (`bounded.sls` exists but is
opt-in). An actor receiving messages faster than it processes them will OOM.

**Recommendation**: Default mailbox size of 10,000 messages. `spawn` should
accept `mailbox-size:` parameter. When full, `send` should either block
(backpressure) or drop-oldest with a logged warning.

### 9. MEDIUM: Decompression Bomb Protection Everywhere

**Gap**: `native-rust.sls` has a 100MB decompression limit for zlib — good. But
JSON parsing, XML parsing, and FASL deserialization don't have size limits.

**Recommendation**: Add configurable limits to all parsers:

- `*json-max-size*` — bytes before rejecting
- `*xml-max-size*`, `*xml-max-depth*`
- `*fasl-max-object-count*` — prevent billion-laughs via nested structures

### 10. LOW: Deterministic Builds for Security Audit

**Gap**: `build/reproducible.sls` and `build/sbom.sls` exist. Verify they're
actually producing bit-identical output and complete SBOMs including the Rust
dependency tree.

### 11. Feature Addition: Structured Concurrency as Default

**Gap**: `structured.sls` exists but isn't the primary concurrency model. Raw
`fork-thread` is still accessible.

**Recommendation**: Make structured concurrency (nurseries/task groups) the
standard API. Every spawned task should belong to a scope that handles
cancellation:

```scheme
(with-task-group
  (spawn-task (lambda () (fetch-url "...")))
  (spawn-task (lambda () (query-db "...")))
  ;; if either task fails, the other is cancelled
  ;; all tasks must complete before scope exits
  )
```

### 12. Feature Addition: First-Class Error Context / Traces

**Recommendation**: Add automatic context accumulation for error diagnostics:

```scheme
(with-context "processing user request #1234"
  (with-context "validating input"
    (check-argument string? input 'validate)))
;; Error message includes:
;; "processing user request #1234 > validating input > argument failed predicate"
```

This is invaluable for debugging Claude-generated code in production.

---

## Summary Assessment

| Category | Current Grade | With Recommendations |
|----------|:---:|:---:|
| **Security** | A | A+ |
| **Safety** | B+ | A |
| **Performance** | B+ | A- |
| **Claude-friendliness** | B | A |
| **Error diagnostics** | C+ | A- |
| **Resource management** | B- | A |

### Strongest Differentiators vs. Other Languages for Claude

1. Allowlist sandbox — best-in-class for running AI-generated code safely
2. Capability-based security — unforgeable by construction
3. Chez engines — preemptive timeout without OS signals
4. Taint tracking — prevents injection from untrusted sources
5. Rust native backend — memory-safe FFI without C footguns

### Biggest Gaps to Close

1. Contract-checked stdlib (catches most Claude bugs before FFI)
2. Mandatory resource cleanup (prevents leaks)
3. Structured error types (enables proper error handling)
4. Default timeouts on blocking ops (prevents hangs)

### Conclusion

The foundation is genuinely strong. The security architecture is more
comprehensive than most production languages. The main work needed is making the
safe path the *default* path — so Claude generates correct code without having
to know about the safety features.
