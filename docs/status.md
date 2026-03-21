# Jerboa Project Status

Updated 2026-03-21.

## What Jerboa Is

Jerboa reimplements Gerbil Scheme's API surface as pure stock Chez Scheme
libraries — 364 modules, ~2,900 tests, 13 fuzzing harnesses. No custom runtime,
no patched Chez. The design prioritizes security, safety, and Claude-friendliness:
`(jerboa prelude safe)` gives AI-generated code a safe-by-default environment with
contracts, structured concurrency, timeouts, and kernel sandboxing out of the box.

---

## Assessment Grades

| Category | Grade | Notes |
|----------|:---:|-------|
| Security architecture | A+ | Allowlist sandbox, capabilities, taint, real Landlock + seccomp |
| Safety (safe prelude) | A | Contracts, finalizers, SQL injection detection |
| Safety (raw prelude) | B | No contracts, no guardian net, fork-thread exposed |
| Claude-friendliness | A | Safe prelude is the recommended import |
| Resource management | A | with-resource + guardian + structured concurrency |
| Error diagnostics | A- | Full condition hierarchy, with-context, 14 lint rules |
| Type safety | A- | Runtime + compile-time, fatal mode available |
| Build integrity | B+ | Content-addressed artifacts + SBOM, no full orchestration |
| Performance | B+ | Chez engines, Rust native backend, WPO |

---

## Implemented Features

### Security

| Module | Description |
|--------|-------------|
| `(std security sandbox)` | One-call sandbox: `run-safe` / `run-safe-eval` with fork-based isolation, Landlock + seccomp + capabilities + engine timeout |
| `(std security restrict)` | Allowlist-only sandbox — 113 bindings, no blocklist. `read` replaced with depth-limited `jerboa-read` (no `#.` read-eval) |
| `(std security landlock)` | Kernel Landlock syscalls for filesystem sandboxing via foreign-alloc struct packing |
| `(std security seccomp)` | BPF bytecode generation + seccomp(2) installation with architecture validation |
| `(std security capability)` | Capability-based security with sealed opaque records + CSPRNG nonces — unforgeable by construction |
| `(std security taint)` | Taint tracking with safe sinks — prevents untrusted data reaching `system`, `open-output-file`, etc. |
| `(std security flow)` | Information flow control with label lattice |
| `(std security privsep)` | Privilege separation via real fork(2) |
| `(std secure-mem)` | mlock, guard pages, explicit_bzero, DONTDUMP, DONTFORK |
| Rust native backend | Single `libjerboa_native.so` replaces 10+ C deps (ring for crypto, flate2, regex). `ffi_wrap()`/`set_last_error()` panic handling |
| 13 fuzzing harnesses | Configurable depth limits across input parsers |
| AI attack hardening | 13 findings addressed (empty-host = deny, symlink resolution, etc.) |

### Safety

| Module | Description |
|--------|-------------|
| `(std safe)` | Contract-checked stdlib: SQLite, TCP, File I/O, JSON with pre/post-condition checks. Runtime SQL injection heuristics. `*safe-mode*` parameter: `'check` or `'release` |
| `(std resource)` | `with-resource` macro with LIFO cleanup via `dynamic-wind` |
| `(std safe)` guardian net | Guardian-based finalizer safety net — warns when handles are GC'd without close, with best-effort cleanup |
| `(std safe-timeout)` | `with-timeout` using Chez engines. `*default-timeout*` (30s) |
| `(std safe-fasl)` | Rejects procedures, enforces record type registry, size limits, cycle detection |
| `(jerboa prelude safe)` | Re-exports all safe APIs under standard names. Excludes `fork-thread` and raw FFI. Safe path is the default |

### Error Handling

| Module | Description |
|--------|-------------|
| `(std error conditions)` | Full condition hierarchy: `&jerboa` -> `&jerboa-network`, `&jerboa-db`, `&jerboa-actor`, `&jerboa-resource`, `&jerboa-timeout`, `&jerboa-serialization`, `&jerboa-parse` with subtypes |
| `(std error context)` | `with-context` for automatic context accumulation in error diagnostics |

### Types

| Module | Description |
|--------|-------------|
| `(std typed)` + `(std typed env)` + `(std typed infer)` | Gradual type system with bidirectional inference, subtyping, 100+ builtins |
| `(std typed check)` | Compile-time type checking via expand-time inference. `*type-errors-fatal*` for strict mode |
| Refinement, linear, affine, phantom, GADTs, typeclasses, row polymorphism, HKTs | `define/r` and `lambda/r` for checked refinements |

### Concurrency

| Module | Description |
|--------|-------------|
| `(std concur structured)` | `with-task-scope`, `scope-spawn`, `task-await`, `task-cancel`, `parallel`, `race` |
| `(std concur deadlock)` | Runtime deadlock detection via wait-for graph + DFS cycle detection. `make-checked-mutex`, `with-checked-mutex` |
| `(std concur)` annotations | Thread-safety annotations with eq-hashtable tracking |
| `(std actor bounded)` | `spawn-bounded-actor` with 10,000 message default capacity. Strategies: `'block`, `'drop`, `'error` |

### Build

| Module | Description |
|--------|-------------|
| `(build reproducible)` | SHA-256 content hashing (FNV-1a fallback), safe `mkdir-p`, content-addressed artifact store |
| `(build sbom)` | Cargo.lock + Cargo.toml parsers for Rust dep detection. `detect-all-deps` aggregates Scheme + C + Rust into SBOM |

### Linting

| Module | Description |
|--------|-------------|
| `(std lint)` | 14 rules: `unused-define`, `shadowed-define`, `redefine-builtin`, `unsafe-import`, `duplicate-import`, `unused-only-import`, `bare-error`, `sql-interpolation`, `empty-begin`, `single-arm-cond`, `missing-else`, `deep-nesting`, `long-lambda`, `magic-number` |

### Decompression Bomb Protection

| Input | Limit |
|-------|-------|
| JSON | `*json-max-depth*` (512), `*json-max-string-length*` (10 MB) |
| XML | `*sxml-max-depth*` (512), `*sxml-max-output-size*` (50 MB) |
| FASL | `*fasl-max-object-count*` (1M), `*fasl-max-byte-size*` (100 MB) |
| Zlib | 100 MB decompression limit in Rust native backend |

---

## Known Limitations

| Module | Limitation | Reason |
|--------|-----------|--------|
| Landlock | x86_64 only, requires Linux 5.13+ | Syscall numbers are architecture-specific |
| Seccomp | x86_64 only, filters are irreversible | BPF bytecode is architecture-specific by design |
| typed/check | Compile-time checks are warnings by default | Gradual typing standard practice; use `*type-errors-fatal*` for strict |
| build/reproducible | Falls back to FNV-1a if `(std crypto hash)` unavailable | SHA-256 requires the crypto module |
| concur/deadlock | Opt-in via `make-checked-mutex` | Auto-instrumenting all mutexes would break existing code |
| Lint | No full unbound-identifier detection or call-site arity checking | Requires compile-time analysis beyond static linting |
| Build | No bit-identical reproducible build verification end-to-end | Full build orchestration pipeline not implemented |

---

## Remaining Work

1. **Race detector** — No dynamic race detection. Structured concurrency reduces risk but does not eliminate it for code using raw `fork-thread` via `(jerboa prelude)`.
2. **Full build orchestration pipeline** — Content-addressed artifacts and SBOM exist, but end-to-end reproducible build orchestration is not wired up.

---

## Stub/Partial Audit Result

Original audit found 2 stubs and 6 partials. **All are now fixed (0 stubs remaining).**

| Module | Was | Resolution |
|--------|-----|------------|
| security/landlock | STUB (no kernel calls) | Real foreign-alloc struct packing + real syscalls |
| security/seccomp | STUB (no BPF generation) | Real BPF bytecode generator + seccomp(2) install |
| typed/check | PARTIAL (phase error, warnings only) | Fixed phase imports, added `*type-errors-fatal*` |
| concur/deadlock | PARTIAL (no drop-in replacements) | Added `make-checked-mutex`, `with-checked-mutex` |
| build/reproducible | PARTIAL (shell injection, weak hash) | Safe `mkdir-p`, SHA-256 with fallback |
| build/sbom | PARTIAL (no Rust deps) | Cargo.lock + Cargo.toml parsers |
| concur | PARTIAL (no distributed) | Was always real for local use; documented as limitation |

---

## Key Differentiators vs. Other Languages for Claude

1. Allowlist sandbox — best-in-class for running AI-generated code safely
2. Capability-based security — unforgeable by construction
3. Chez engines — preemptive timeout without OS signals
4. Taint tracking — prevents injection from untrusted sources
5. Rust native backend — memory-safe FFI without C footguns
6. Safe-by-default prelude — Claude gets safety without asking for it
7. Real Landlock + seccomp — kernel-enforced sandboxing (Linux 5.13+)
