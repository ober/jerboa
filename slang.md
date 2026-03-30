# Slang: Secure Language Compiler

A restricted subset of Jerboa compiled to hardened native binaries for hostile environments.

Slang is to native code what the WASM codegen is to WebAssembly — a deliberately minimal
language surface that produces binaries leveraging every available hardware and OS security
mechanism. Just enough language to build real applications; nothing an attacker can abuse.

---

## Design Principle

The compiler's job is **restriction, not generation**. Chez Scheme already compiles Scheme
to native machine code with CET/BTI landing pads (secure branch). Slang validates that
source code uses only safe constructs, injects a security preamble, and hands the result
to Chez's existing compilation pipeline. The output is a static musl binary that
self-sandboxes on first instruction.

```
slang source (.ss)
  --> Slang front-end (validate safe subset, reject unsafe ops)
    --> Security preamble injection (seccomp/capsicum/landlock)
      --> Chez compile-whole-program (nanopass --> native code, CET/BTI)
        --> musl static link (PIE, RELRO, stack protector, FORTIFY_SOURCE)
          --> ed25519 sign
            --> single static binary, zero dependencies
```

---

## Language Subset

### In (sufficient for real applications)

**Definitions and control flow:**
- `def`, `def*`, `let`, `let*`, `letrec`, `lambda`
- `if`, `cond`, `case`, `when`, `unless`, `begin`
- `match` (full pattern matching with guards)
- `and`, `or`, `not`

**Data types (immutable by default):**
- `defstruct`, `defrecord` (value types)
- `define-enum` (closed enumerations)
- Numbers: fixnum, flonum, exact rationals
- Strings, symbols, keywords, characters
- Bytevectors (for binary protocols)
- Lists, vectors, hash tables (immutable construction preferred)
- Result types: `ok`, `err`, `unwrap`, `unwrap-or`, `->?`

**Iteration and comprehension:**
- `for`, `for/collect`, `for/fold`, `for/or`, `for/and`
- `in-list`, `in-vector`, `in-range`, `in-hash-keys`, `in-hash-values`, `in-hash-pairs`
- `in-bytevector`, `in-string`, `in-indexed`
- `map`, `filter`, `fold-left`, `fold-right`
- `while`, `until`, `dotimes` (bounded loops only -- see restrictions)

**String processing:**
- `string-split`, `string-join`, `string-trim`
- `string-prefix?`, `string-suffix?`, `string-contains`
- `string-upcase`, `string-downcase`
- `str` (safe concatenation with auto-coerce)
- `format`, `displayln`

**Structured error handling:**
- `try`/`catch`/`finally` (no bare `raise` with strings)
- Result threading: `->?`, `and-then`, `map-ok`, `map-err`
- `try-result`, `try-result*` (exceptions to results)
- `sequence-results` (list of results to result of list)
- `assert!` (debug-mode only, stripped in release)

**Resource management:**
- `with-resource` (deterministic cleanup, no leaks)
- Pre-opened file descriptors (Capsicum model)
- `read-file-string`, `read-file-lines` (on allowed paths only)
- `write-file-string` (on allowed paths only)

**Type annotations:**
- `define/t`, `lambda/t` (gradual typing from `(std typed)`)
- Enforced at runtime in debug mode, stripped in release
- `using` with dot-access for struct fields

**Concurrency (message-passing only):**
- Channels: `make-channel`, `channel-put`, `channel-get`
- `spawn` (structured -- parent waits for children)
- No shared mutable state, no locks, no atomics

**Threading macros:**
- `->`, `->>`, `some->`, `cond->`, `as->`

**Anaphoric/conditional binding:**
- `awhen`, `aif`, `when-let`, `if-let`

### Out (attack surface elimination)

| Excluded | Why |
|----------|-----|
| `eval`, `load`, `compile`, `expand` | No runtime code generation -- entire JIT attack surface gone |
| `foreign-procedure`, `c-lambda`, `ftype` | No raw FFI -- all native calls through vetted Rust backend |
| `call/cc`, `call-with-current-continuation` | No control-flow capture -- prevents stack manipulation |
| `dynamic-wind` | Paired with call/cc elimination |
| `gensym`, `interaction-environment` | No symbol table access -- prevents interning attacks |
| `system`, `process-create`, `fork` | No shell access -- all OS interaction through preamble |
| `open-input-file`, `open-output-file` (raw) | No ambient file access -- use pre-opened FDs or capability-gated I/O |
| `set!` on globals | No mutable global state -- all mutation is local |
| `define-syntax`, `syntax-case`, `syntax-rules` | No user-defined macros -- fixed language surface |
| `read` (raw) | No arbitrary deserialization -- use typed parsers |
| `string->number` (unbounded) | Numeric parsing through checked converters only |
| `make-parameter`, `parameterize` | No dynamic scope -- explicit argument passing |
| Unbounded recursion | Depth limits enforced by the compiler |
| `sleep`, `thread-sleep` | No arbitrary delays -- timeouts through `with-resource` |

### Restricted (available but constrained)

| Construct | Constraint |
|-----------|-----------|
| `hash-put!` | Allowed on locally-created tables only, not on received arguments |
| `vector-set!` | Allowed on locally-created vectors only |
| `string-set!` | Disallowed entirely (strings are immutable in Slang) |
| Recursion | Compiler enforces maximum depth (configurable, default 1000) |
| `dotimes`, `while`, `until` | Compiler inserts iteration limit (configurable, default 10M) |
| Allocation | Per-function allocation budget (prevents OOM as DoS) |
| Output | `displayln`, `format` only to pre-opened ports |

---

## Security Preamble

Every Slang binary starts execution with a security preamble before `main`. This is
injected by the compiler and cannot be bypassed -- it runs before any user code.

```scheme
;; === Slang Security Preamble (injected, not user-visible) ===

;; 1. Self-integrity: verify ed25519 signature or SHA-256 hash
;;    Abort immediately if binary has been modified.
(slang-verify-integrity!)

;; 2. Anti-debug: detect ptrace, TracerPid, LD_PRELOAD
;;    Abort if dynamic analysis is detected.
(slang-anti-debug!)

;; 3. Enter OS sandbox (irreversible):
;;    Linux:   seccomp-bpf (block mprotect(EXEC), ptrace, fork, exec)
;;             + Landlock (restrict filesystem to declared paths)
;;             + namespaces (PID, mount, network) if available
;;    FreeBSD: Capsicum cap_enter() (block all path-based access)
;;             + PROTMAX (block mprotect escalation)
;;             + per-fd rights limiting
(slang-enter-sandbox! platform-config)

;; 4. Drop privileges: setuid/setgid if running as root
(slang-drop-privileges!)

;; 5. Call user's main with pre-opened resources
(main pre-opened-fds capability-set)
```

### Post-Sandbox Invariants

After the preamble completes, these properties hold for the lifetime of the process:

| Property | Linux | FreeBSD | FreeBSD arm64 |
|----------|-------|---------|---------------|
| No new executable pages | seccomp blocks `mprotect(EXEC)` | PROTMAX | PROTMAX |
| No new file access | Landlock allowlist | Capsicum (no path ops) | Capsicum |
| No new processes | seccomp blocks `fork`/`exec` | Capsicum (no `fexecve`) | Capsicum |
| No ptrace | seccomp blocks `ptrace` | Anti-debug check | Anti-debug check |
| No network changes | Namespace or seccomp | Capsicum fd rights | Capsicum fd rights |
| HW control-flow integrity | CET SHSTK+IBT | None (x86) | ARM PAC+BTI |
| Return address protection | Shadow stack | WASM sandbox (primary) | PAC signing |
| Indirect branch protection | ENDBR64 landing pads | WASM sandbox (primary) | BTI landing pads |

---

## Compilation Model

### Module Declaration

A Slang program declares its resource requirements up front. The compiler uses these
declarations to generate the minimal sandbox policy.

```scheme
;; example: a DNS-over-TLS relay

(slang-module dns-relay
  ;; Resource declarations (become pre-opened FDs / capabilities)
  (require
    (network
      (listen "0.0.0.0:853" :proto tls)
      (connect "upstream-dns:53" :proto udp))
    (filesystem
      (read "/etc/dns-relay/config.toml")
      (read "/etc/dns-relay/certs/")
      (write "/var/log/dns-relay/"))
    (crypto
      (tls-server-cert "/etc/dns-relay/certs/server.pem")
      (tls-server-key  "/etc/dns-relay/certs/server.key")))

  ;; Maximum resource budgets
  (limits
    (max-memory-mb 64)
    (max-connections 1024)
    (max-recursion-depth 500)
    (max-iteration-count 1000000)))
```

The `require` block is the **complete** set of external resources. The sandbox policy is
generated from this: anything not declared is blocked at the kernel level.

### Three-File Architecture

Following the WASM codegen pattern (~1200 lines for format + codegen + runtime), Slang is
implemented in three modules:

#### `lib/std/secure/compiler.sls` -- Front-end (~800 lines)

Validates that source uses only the safe subset and transforms it for compilation.

Responsibilities:
- **Parse** Slang module declarations (`slang-module`, `require`, `limits`)
- **Walk AST** and reject excluded forms (`eval`, `foreign-procedure`, `call/cc`, etc.)
- **Enforce constraints** (recursion depth, iteration limits, allocation budgets)
- **Resolve resources** (map declared paths/ports to FD numbers for Capsicum)
- **Inject preamble** (platform-detected security initialization)
- **Emit safe Chez Scheme** that `compile-whole-program` can process

```scheme
(import (jerboa prelude))
(import (std secure compiler))

;; Compile a Slang source file to a .wpo bundle
(slang-compile "dns-relay.ss"
  target: 'native        ;; or 'wasm for parser modules
  platform: 'freebsd     ;; auto-detected if omitted
  debug: #f)             ;; #t enables type assertions and bounds checks
```

#### `lib/std/secure/preamble.sls` -- Security Bootstrap (~400 lines)

Platform-specific security initialization, compiled into every binary.

Responsibilities:
- **Integrity verification** (ed25519 signature check via Rust native)
- **Anti-debug** (ptrace self-trace, TracerPid scan, LD_PRELOAD detection)
- **Platform detection** (Linux/FreeBSD/macOS, x86_64/arm64)
- **Sandbox installation** (seccomp filter, Capsicum cap_enter, Landlock ruleset)
- **Privilege drop** (setuid/setgid)
- **FD pre-opening** (open declared resources before sandbox locks)
- **W^X enforcement** (PROTMAX on FreeBSD, seccomp mprotect filter on Linux)

The preamble reuses existing Jerboa modules:
- `(std security sandbox)` -- `run-safe` infrastructure
- `(std security seccomp)` -- BPF filter generation
- `(std security capsicum)` -- Capsicum API
- `(std security landlock)` -- Landlock API
- `(std native)` -- Rust native library (integrity, anti-debug, crypto)

#### `lib/std/secure/link.sls` -- Static Binary Builder (~300 lines)

Orchestrates the full pipeline from validated source to signed binary.

Responsibilities:
- **Compile** via `compile-whole-program` with whole-program optimization
- **Embed boot files** into C object via `jerboa-embed.c`
- **Static link** with musl (using `support/musl-chez-build.sh` infrastructure)
- **Apply hardening flags** (PIE, RELRO, stack protector, CET/BTI, FORTIFY_SOURCE)
- **Strip symbols** (optional, default on for release)
- **Sign binary** (ed25519 via Rust native)
- **Verify output** (check for static linking, run integrity self-test)

```scheme
(import (jerboa prelude))
(import (std secure link))

;; Build a signed static binary
(slang-link "dns-relay.wpo"
  output: "dns-relay"
  sign-key: "/path/to/ed25519.key"
  strip: #t
  verify: #t)

;; Result: single static binary, ~4-8MB
;; - Zero runtime dependencies
;; - Self-verifying integrity
;; - Self-sandboxing on startup
;; - Hardware CFI (CET or BTI depending on platform)
```

---

## Compilation Pipeline Detail

```
 Source (.ss)                    slang-compile
 +------------------+          +-----------------------------+
 | (slang-module    |   parse  | 1. Parse module declaration |
 |   (require ...)  | -------> | 2. Walk AST: reject unsafe  |
 |   (limits ...))  |          |    forms, enforce limits    |
 |                  |          | 3. Resolve resources to FDs |
 | (def (main ...) )|          | 4. Generate sandbox policy  |
 |   ...)           |          | 5. Inject preamble          |
 +------------------+          | 6. Emit safe Chez Scheme    |
                               +-------------+---------------+
                                             |
                                             v
                               +-----------------------------+
                               | compile-whole-program       |
                               | (Chez nanopass pipeline)    |
                               |                             |
                               | Lsrc -> cp0 -> cptypes ->  |
                               | cpnanopass -> x86_64/arm64  |
                               | -> native code with         |
                               |    ENDBR64/BTI landing pads |
                               +-------------+---------------+
                                             |
                                             v
                               +-----------------------------+
                               | slang-link                  |
                               |                             |
                               | 1. Embed boot + app into C  |
                               | 2. musl-gcc -static-pie     |
                               |    -fstack-protector-strong  |
                               |    -fcf-protection=full     |
                               |    -D_FORTIFY_SOURCE=2      |
                               |    -Wl,-z,relro,-z,now      |
                               | 3. Strip symbols            |
                               | 4. Ed25519 sign             |
                               | 5. Verify: file, integrity  |
                               +-------------+---------------+
                                             |
                                             v
                               +-----------------------------+
                               | Output: static binary       |
                               |                             |
                               | - Single ELF, ~4-8MB       |
                               | - Zero shared libraries    |
                               | - Self-integrity check     |
                               | - Self-sandboxing preamble |
                               | - HW CFI landing pads      |
                               | - All I/O pre-declared     |
                               +-----------------------------+
```

---

## Runtime Model

### Capability-Passing Style

Slang programs do not access ambient resources. Everything comes through the capability
set passed to `main`:

```scheme
(slang-module echo-server
  (require
    (network (listen "0.0.0.0:7" :proto tcp))
    (filesystem (write "/var/log/echo.log"))))

(def (main fds caps)
  ;; fds is a hash table: declared-name -> pre-opened fd
  ;; caps is the capability set matching the require block

  (let ((listener (hash-ref fds 'listen-0))
        (log-fd   (hash-ref fds 'log-0)))

    ;; These work -- resources were declared
    (accept-loop listener
      (lambda (conn)
        (let ((data (fd-read conn 4096)))
          (fd-write conn data)
          (fd-write log-fd (str (datetime-now) " echoed " (bytevector-length data) " bytes\n")))))

    ;; This would be a compile-time error:
    ;; (open-input-file "/etc/passwd")   ;; REJECTED: open-input-file not in subset
    ;; (system "ls")                      ;; REJECTED: system not in subset
    ))
```

### No Ambient Authority

The Capsicum model is the conceptual foundation, generalized across platforms:

| Platform | Mechanism | Effect |
|----------|-----------|--------|
| FreeBSD | `cap_enter()` + `cap_rights_limit()` | Kernel blocks all path-based syscalls; FDs restricted to declared rights |
| Linux | seccomp + Landlock | seccomp blocks `open`/`openat` (except pre-opened); Landlock restricts paths |
| Both | Compiler validation | `open-input-file`, `open-output-file` rejected at compile time |

The compiler validation is defense-in-depth: even if someone bypasses the front-end check,
the kernel sandbox blocks the operation at runtime.

### Structured Concurrency

All concurrency is structured -- no orphan threads, no shared mutable state:

```scheme
(def (process-batch items caps)
  ;; spawn returns when ALL children complete
  ;; children communicate via channels only
  (let ((results (make-channel)))
    (spawn-group
      (for ((item (in-list items)))
        (spawn
          (lambda ()
            (channel-put results (process-one item caps))))))
    ;; collect results
    (for/collect ((i (in-range (length items))))
      (channel-get results))))
```

No `fork-thread` (fire-and-forget), no `mutex`, no `cas!`. The only shared state is
channels, which are safe by construction.

---

## WASM Parser Modules

For security-critical parsing (DNS packets, HTTP headers, TLS handshakes), Slang supports
compiling parsers to WASM and executing them in an interpreter sandbox. This is the same
concept as the existing `lib/std/wasm/` infrastructure but production-grade.

```scheme
(slang-module dns-relay
  (require
    (wasm-parser "parsers/dns.wasm"    ;; pre-compiled WASM module
      (export parse-query   : bytevector -> result)
      (export build-response : alist -> bytevector))
    (network
      (listen "0.0.0.0:53" :proto udp))))

(def (main fds caps)
  (let ((sock    (hash-ref fds 'listen-0))
        (parser  (hash-ref caps 'wasm-parser-0)))  ;; WASM instance

    (accept-loop sock
      (lambda (packet)
        ;; parse-query runs inside WASM interpreter
        ;; no access to process memory, no syscalls, no escape
        (match (wasm-call parser 'parse-query packet)
          ((ok query)
           (let ((response (resolve-query query)))
             (wasm-call parser 'build-response response)))
          ((err msg)
           (log-error msg)))))))
```

The WASM parser runs in wasmi (Rust interpreter, embedded in `jerboa-native-rs`).
Even if the parser has a bug, the attacker is confined to the WASM linear memory --
they cannot reach the Chez heap, the native stack, or any file descriptors.

---

## Platform Security Matrix

What each target gets automatically from a Slang binary:

| Defense Layer | Linux x86_64 | FreeBSD x86_64 | FreeBSD arm64 |
|---------------|-------------|----------------|---------------|
| **Binary hardening** | | | |
| Static PIE (full ASLR) | Yes | Yes | Yes |
| Stack protector | Yes | Yes | Yes |
| FORTIFY_SOURCE=2 | Yes | Yes | Yes |
| Full RELRO | Yes | Yes | Yes |
| Symbol stripping | Yes | Yes | Yes |
| Ed25519 signature | Yes | Yes | Yes |
| **Hardware CFI** | | | |
| Return address protection | CET shadow stack | -- | ARM PAC |
| Indirect branch protection | CET IBT (ENDBR64) | -- | ARM BTI |
| **OS sandbox** | | | |
| Syscall filtering | seccomp-bpf | -- | -- |
| Block mprotect(EXEC) | seccomp | PROTMAX | PROTMAX |
| Filesystem restriction | Landlock | Capsicum fd rights | Capsicum fd rights |
| Resource confinement | Landlock + namespaces | Capsicum cap_enter | Capsicum cap_enter |
| Network restriction | seccomp + netns | Capsicum fd rights | Capsicum fd rights |
| **Application level** | | | |
| WASM parser isolation | wasmi interpreter | wasmi interpreter | wasmi interpreter |
| Capability-passing I/O | Compile-time enforced | Compile-time enforced | Compile-time enforced |
| Taint tracking | Runtime | Runtime | Runtime |
| Anti-debug | ptrace + TracerPid | ptrace | ptrace |
| Self-integrity | SHA-256 / ed25519 | SHA-256 / ed25519 | SHA-256 / ed25519 |

**Strongest target**: Linux x86_64 with CET (8 independent defense layers).
**Best FreeBSD target**: arm64 with PAC+BTI (7 layers, hardware CFI).
**Weakest target**: FreeBSD x86_64 (5 layers, WASM sandbox is primary CFI).

---

## What This Is Not

**Not a new compiler backend.** Chez's nanopass pipeline and machine backends are
world-class. Slang doesn't replace them -- it restricts input and hardens output.

**Not a new language.** Slang is a proper subset of Jerboa. Every Slang program is a
valid Jerboa program. The Slang compiler is a **filter** that rejects unsafe programs
before Chez compiles them.

**Not a VM or interpreter.** The output is native machine code, same as `scheme --compile`.
The only interpreter involved is the optional WASM sandbox for parser modules.

**Not a sandbox.** Slang binaries sandbox *themselves* using OS mechanisms. The language
restriction means the sandboxing cannot be circumvented from Scheme code -- there is no
`eval` to construct an escape, no `foreign-procedure` to call `mprotect`, no `system` to
spawn a shell.

---

## Implementation Roadmap

### Phase 1: Core Compiler (weeks)

1. `lib/std/secure/compiler.sls` -- AST validator + preamble injector
   - Parse `slang-module` declarations
   - Walk forms, reject excluded operations
   - Generate platform-specific preamble
   - Emit safe Chez Scheme for `compile-whole-program`

2. `lib/std/secure/preamble.sls` -- Security bootstrap
   - Reuse `(std security sandbox)`, `(std security seccomp)`, `(std security capsicum)`
   - Integrity check via `(std native)`
   - FD pre-opening from resource declarations

3. `lib/std/secure/link.sls` -- Static binary builder
   - Reuse `support/musl-chez-build.sh` infrastructure
   - Embed boot files via `support/jerboa-embed.c`
   - Sign with ed25519

4. Tests: compile + run a Slang echo server on FreeBSD and Linux

### Phase 2: WASM Parser Integration (weeks)

5. Add wasmi to `jerboa-native-rs/Cargo.toml`
6. Expose `jerboa_wasm_load` / `jerboa_wasm_call` FFI
7. Slang `wasm-parser` declaration support in compiler
8. Example: DNS packet parser compiled from Rust to WASM

### Phase 3: Hardening Completeness (days each)

9. PROTMAX integration on FreeBSD (post-JIT, before main)
10. Namespace isolation on Linux (PID, mount, network)
11. ARM64 PAC+BTI build target for FreeBSD arm64
12. Allocation budgets and iteration limits in AST validator

### Phase 4: Tooling (ongoing)

13. `slang-check` -- lint a Slang file without compiling
14. `slang-audit` -- report which security features are active on current platform
15. MCP tools: `jerboa_slang_compile`, `jerboa_slang_check`
16. Cookbook recipes for common Slang patterns
