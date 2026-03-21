# Jerboa: Remaining Gaps for Bulletproof Claude Code Generation

Updated 2026-03-21. All stubs and partials from original audit are now fixed.
See docs/gaps.md for the full audit with completion status.

## Fixed This Session

| Item | What Was Wrong | What Was Done |
|------|---------------|---------------|
| Landlock | STUB: only set NO_NEW_PRIVS, no kernel enforcement | Real syscalls: landlock_create_ruleset, landlock_add_rule, landlock_restrict_self via foreign-alloc struct packing |
| Seccomp | STUB: no BPF bytecode generation | Real BPF program generation with arch validation, installed via seccomp(2) syscall |
| build/reproducible | Shell injection via system(), weak FNV-1a hash | Safe mkdir-p (no shell), SHA-256 via crypto module with FNV-1a fallback |
| build/sbom | No Rust dependency detection | Cargo.lock and Cargo.toml parsers, detect-all-deps aggregator |
| typed/check | Phase error (expand-time/run-time mismatch), warnings only | Fixed phase imports with meta define, added *type-errors-fatal* parameter |
| concur/deadlock | No drop-in replacements | Added make-checked-mutex and with-checked-mutex |

## Previously Fixed (this series of sessions)

| Item | Solution | Commit |
|------|----------|--------|
| Safe-by-default prelude | `(jerboa prelude safe)` re-exports safe APIs under standard names | dd90984 |
| Finalizer safety net | Guardian-based leak detection in `(std safe)` | dd90984 |
| Lint: unsafe imports | `unsafe-import` rule warns on raw FFI module imports | dd90984 |
| Lint: SQL interpolation | `sql-interpolation` rule + runtime `check-sql-safety!` | dd90984 |
| Lint: bare error | `bare-error` rule suggests structured conditions | dd90984 |
| Lint: duplicate imports | `duplicate-import` rule | c035f35 |
| Lint: unused only-imports | `unused-only-import` rule | c035f35 |
| Structured concurrency default | Safe prelude exports `with-task-scope` etc., no `fork-thread` | c035f35 |
| Raw FFI excluded | Safe prelude does not export `c-lambda`, `foreign-procedure` | dd90984 |
| Init flag ordering bug | `sqlite-available?` etc. now set LAST after all evals | dd90984 |

## Honest Status of Every Module

### Fully Real Implementations

| Module | What It Does | Verification |
|--------|-------------|-------------|
| security/landlock | Kernel Landlock syscalls for FS sandboxing | Real foreign-alloc struct packing, tested |
| security/seccomp | BPF bytecode generation + seccomp(2) install | Real BPF program with arch validation, tested |
| security/capability | Sealed opaque records + CSPRNG nonces | Unforgeable by construction |
| security/taint | Taint tracking with safe sinks | Prevents injection |
| security/flow | Information flow control | Label lattice |
| security/privsep | Privilege separation via fork | Real fork(2) |
| typed + typed/env + typed/infer | Gradual type system | Bidirectional inference, subtyping, 100+ builtins |
| typed/check | Compile-time type checking | Real expand-time inference, fatal mode |
| concur/structured | Structured concurrency | Real fork-thread with scope cleanup |
| concur/deadlock | Runtime deadlock detection | Wait-for graph + DFS cycle detection |
| concur (annotations) | Thread-safety annotations | eq-hashtable tracking |
| actor/bounded | Mailbox backpressure | Block/drop/error strategies |
| safe-timeout | Chez engine-based timeouts | Preemptive via engines |
| safe-fasl | Safe deserialization | Reject procedures, size limits, cycle detection |
| error/conditions | Full condition hierarchy | 14 condition types |
| build/reproducible | Content-addressed artifacts | SHA-256 (with fallback), safe mkdir |
| build/sbom | Software bill of materials | Scheme + C + Rust dep detection |
| safe (contract lib) | Contract-checked stdlib | Pre/post conditions, SQL injection detection |
| lint | 14 static analysis rules | unsafe-import, bare-error, sql-interpolation, etc. |

### Limitations (Honest)

| Module | Limitation | Why |
|--------|-----------|-----|
| Landlock | x86_64 only, requires Linux 5.13+ | Syscall numbers are arch-specific |
| Seccomp | x86_64 only, filters are irreversible | BPF bytecode is arch-specific by design |
| typed/check | Compile-time checks are warnings by default | Gradual typing standard practice; use *type-errors-fatal* for strict |
| build/reproducible | Falls back to FNV-1a if (std crypto hash) not available | SHA-256 requires the crypto module |
| concur/deadlock | Opt-in via make-checked-mutex | Auto-instrumenting all mutexes would break existing code |

## Still Open (Real Gaps, Not Stubs)

### Sandbox Entry Point (P2)

`(std security restrict)` exists but isn't auto-applied. A `run-safe` wrapper
combining capabilities + Landlock + seccomp + timeout would make sandboxing
trivial for Claude-generated code.

### Race Detector (P3)

No dynamic race detection. Structured concurrency reduces the risk but doesn't
eliminate it for code that opts into raw `fork-thread` via `(jerboa prelude)`.

## Current Safety Grade

| Category | Grade | Notes |
|----------|:---:|-------|
| Security architecture | A+ | Allowlist sandbox, capabilities, taint, **real Landlock + seccomp** |
| Safety (via safe prelude) | A | Contracts, finalizers, SQL injection detection |
| Safety (via raw prelude) | B | No contracts, no guardian net, fork-thread exposed |
| Claude-friendliness | A | Safe prelude is the recommended import |
| Resource management | A | with-resource + guardian + structured concurrency |
| Error diagnostics | A- | Full hierarchy, with-context, 14 lint rules |
| Type safety | A- | Runtime + compile-time, fatal mode available |
| Build integrity | B+ | Content-addressed + SBOM, no full orchestration |
