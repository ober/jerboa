# Jerboa: Remaining Gaps for Bulletproof Claude Code Generation

Updated 2026-03-21. Most gaps from the original review are now closed.
See docs/gaps.md for the full audit with completion status.

## Resolved (this session)

| Item | Solution | Commit |
|------|----------|--------|
| Safe-by-default prelude | `(jerboa prelude safe)` re-exports safe APIs under standard names | dd90984 |
| Finalizer safety net | Guardian-based leak detection in `(std safe)` | dd90984 |
| Lint: unsafe imports | `unsafe-import` rule warns on raw FFI module imports | dd90984 |
| Lint: SQL interpolation | `sql-interpolation` rule + runtime `check-sql-safety!` | dd90984 |
| Lint: bare error | `bare-error` rule suggests structured conditions | dd90984 |
| Lint: duplicate imports | `duplicate-import` rule | current |
| Lint: unused only-imports | `unused-only-import` rule | current |
| Structured concurrency default | Safe prelude exports `with-task-scope` etc., no `fork-thread` | current |
| Raw FFI excluded | Safe prelude does not export `c-lambda`, `foreign-procedure` | dd90984 |
| Init flag ordering bug | `sqlite-available?` etc. now set LAST after all evals | dd90984 |

## Previously Resolved (commit 9879d86)

- Resource RAII (`with-resource`, `with-resource1`)
- Contract-checked stdlib (`(std safe)`)
- Error condition hierarchy (`(std error conditions)`)
- Safe FASL serialization (`(std safe-fasl)`)
- Timeout enforcement (`(std safe-timeout)`, `with-timeout`)
- Immutable defaults
- Error context (`with-context`)
- JSON/XML parser size limits
- Actor mailbox backpressure (`(std actor bounded)`)
- Reproducible builds + SBOM generation

## Still Open

### Compile-Time Type Checking (P1)

Contracts are runtime-only. Wiring `(std typed)` gradual types into the
contract-checked APIs would catch type errors at compile time. This is a
larger project — depends on `(std typed)` maturity.

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
| Security architecture | A+ | Allowlist sandbox, capabilities, taint, Landlock |
| Safety (via safe prelude) | A | Contracts, finalizers, SQL injection detection |
| Safety (via raw prelude) | B | No contracts, no guardian net, fork-thread exposed |
| Claude-friendliness | A | Safe prelude is the recommended import |
| Resource management | A | with-resource + guardian + structured concurrency |
| Error diagnostics | A- | Full hierarchy, with-context, 14 lint rules |
| Type safety | B | Runtime-only; compile-time is the remaining frontier |
