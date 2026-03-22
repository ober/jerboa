# What's Missing to Make Jerboa Awesome

Updated 2026-03-21.

Jerboa is already a remarkable achievement: 364 modules, ~2,900 tests, real
kernel sandboxing, gradual typing, structured concurrency — all on stock Chez
Scheme with zero patches. This document catalogs what's still missing to go
from "impressive technical achievement" to "language people reach for first."

Each section includes severity (how much it hurts), effort (how hard to fix),
and concrete suggestions. See also `newer.md` (porting roadmap) and
`libraries.md` (module gap analysis) for related inventories.

---

## Table of Contents

1. [Developer Experience](#1-developer-experience)
2. [Language Features](#2-language-features)
3. [Standard Library Gaps](#3-standard-library-gaps)
4. [Ecosystem & Tooling](#4-ecosystem--tooling)
5. [Validation & Trust](#5-validation--trust)
6. [Documentation & Onboarding](#6-documentation--onboarding)
7. [Summary Matrix](#7-summary-matrix)

---

## 1. Developer Experience

### 1.1 CLI Entry Point

**Severity: High | Effort: Small**

Jerboa has a full-featured REPL (`(std repl)` with 40+ commands) and a
docstring system (`(std doc)` with `define/doc`), but no `jerboa` binary.
Users must know to invoke:

```sh
scheme --libdirs lib my-file.ss
```

What's needed is a single `jerboa` command that wraps this:

```sh
jerboa                    # launch REPL with (jerboa prelude) loaded
jerboa run file.ss        # run a script
jerboa test tests/        # discover and run tests
jerboa build              # compile project (invoke build.ss)
jerboa repl               # explicit REPL mode
jerboa eval '(+ 1 2)'    # one-shot evaluation
```

This is the single highest-leverage DX improvement. Every language people
actually use has a one-word entry point. The REPL and doc infrastructure
already exist — they just need a front door.

**Implementation path:** A small Chez Scheme script or shell wrapper that
sets `--libdirs`, loads the prelude, and dispatches on argv[1]. Could be
100 lines.

### 1.2 Error Messages

**Severity: High | Effort: Medium**

Chez Scheme's stock error messages are famously unhelpful:

```
Exception: variable foo is not bound
Exception in cdr: 3 is not a pair
```

A Jerboa error layer should:

- **Intercept common errors** and rewrite with context:
  ```
  Error: `foo` is not defined
    in module (myapp server), line 42
    Did you mean: `foo!` (exported from (std misc hash))?
  ```
- **Suggest imports** when an unbound identifier matches a known stdlib export
  (the data is already in `(std doc)`)
- **Explain arity mismatches** with expected vs. actual counts
- **Show source snippets** when file/line information is available

This doesn't require modifying Chez. A `with-friendly-errors` wrapper around
the condition handler that pattern-matches on common condition types is enough.

### 1.3 Import Conflict Ergonomics

**Severity: High | Effort: Small**

The #1 developer experience problem in jerboa porting (documented in
`newer.md` item 26). Every jerboa project has dozens of `(except ...)` clauses
because names collide between `(chezscheme)`, `(jerboa core)`, and `(std ...)`
modules.

Known conflict zones:
- `(chezscheme)` vs `(jerboa core)`: `sort`, `filter`, `format`, `iota`, `1+`,
  `1-`, `box`, `box?`, `unbox`, `set-box!`
- `(std misc string)` vs `(jerboa core)`: `string-split`, `string-join`,
  `string-index`, `string-trim`, `string-prefix?`
- `(std misc list)` vs `(jerboa core)`: `any`, `every`, `take`, `drop`,
  `filter-map`

Solutions:
- **`(jerboa prelude/clean)`**: A prelude variant that does NOT re-export
  conflicting Chez names, so `(import (chezscheme) (jerboa prelude/clean))`
  just works without `except` gymnastics
- **Pre-built import sets**: `(jerboa compat except-chez)` etc.
- **A conflict reference matrix** in docs (see section 6)

---

## 2. Language Features

### 2.1 String Interpolation

**Severity: Medium | Effort: Small**

`(std format)` provides runtime `printf`/`fprintf` with `~a`, `~s`, `~d`
directives, but there is no compile-time string interpolation. Users must
write:

```scheme
(string-append "Hello " name ", you have " (number->string count) " items")
;; or
(format "Hello ~a, you have ~a items" name count)
```

Every modern language has interpolated strings. A reader macro or syntax
extension:

```scheme
#"Hello ${name}, you have ${count} items"
```

...that expands to `(string-append ...)` or `(format ...)` at compile time.

**Implementation path:** A `defrule` macro or reader extension. The reader
(`lib/jerboa/reader.sls`) already handles `#!void` and `#!eof` — adding
`#"..."` is feasible. Alternatively, a pure macro `(interpolate "...")`
that parses at expansion time.

### 2.2 Struct Pattern Matching in Core `match`

**Severity: Medium | Effort: Small**

The core `match` in `(jerboa core)` supports lists, cons, predicates, guards,
and logical combinators — but NOT struct/record destructuring. The `match`
implementation explicitly marks vector patterns as TODO (line 513 of
`core.sls`).

Jerboa DOES have `(std match2)` which adds struct patterns via
`define-match-type`, sealed hierarchies, active patterns, and exhaustiveness
checking. But the core `match` that ships with the prelude lacks this.

The gap: users importing `(jerboa prelude)` get a `match` that can't
destructure their `defstruct` types. They must know to import `(std match2)`
separately. This should either:

- **Upgrade the prelude `match`** to support struct patterns natively, or
- **Re-export `(std match2)`'s `match`** from the prelude (breaking change
  — needs assessment), or
- **Document prominently** that struct matching requires `(std match2)`

### 2.3 Iterator Protocol

**Severity: High | Effort: Large**

The #1 missing module by import count across Gerbil projects (228 imports).
Documented in detail in `newer.md` item 4.

```scheme
(for/collect ((x (in-range 10))) (* x x))         ; => (0 1 4 9 16 ...)
(for/fold ((sum 0)) ((x (in-list '(1 2 3)))) (+ sum x))  ; => 6
(for ((k v) (in-hash ht))) (printf "~a: ~a\n" k v))
```

Without this, every loop is a manual `let loop` or `for-each` with
side-effects. The iterator protocol is table stakes for modern Scheme
and Jerboa needs it for porting the vast majority of Gerbil code.

Required generators: `in-range`, `in-list`, `in-vector`, `in-string`,
`in-hash`, `in-port`, `in-lines`, `in-indexed`.
Required consumers: `for`, `for/collect`, `for/fold`, `for/or`, `for/and`.
Required transformers: `in-filter`, `in-map`, `in-take`, `in-drop`, `in-zip`.

### 2.4 Interface / Protocol System

**Severity: Medium | Effort: Medium**

Gerbil's `definterface` (15 imports) and `defgeneric` (20 imports) enable
type-safe dispatch patterns that go beyond method tables. Documented in
`newer.md` items 24-25. Without these, structuring larger programs around
protocols requires manual dispatch boilerplate.

---

## 3. Standard Library Gaps

### 3.1 SRFI Coverage (Critical)

**Severity: High | Effort: Large**

Currently 2 SRFIs implemented out of 60+ that Gerbil provides (3% coverage).
The most painful gaps by import frequency:

| SRFI     | Imports | What It Provides    | Status                            |
|----------|---------|---------------------|-----------------------------------|
| SRFI-13  | 349     | Full string library | `(std misc string)` covers basics |
| SRFI-1   | 107     | Full list library   | `(std misc list)` covers basics   |
| SRFI-19  | 44      | Date/time types     | Not provided                      |
| SRFI-14  | ~30     | Character sets      | Not provided                      |
| SRFI-43  | 10      | Vector library      | Chez covers most                  |
| SRFI-128 | 10      | Comparators         | Not provided                      |

SRFI-13 and SRFI-1 together account for 456 import sites. These are the
single biggest porting blockers after the gambit compat layer.

### 3.2 Networking Depth

**Severity: Medium | Effort: Medium-Large**

The `lib/std/net/` directory has 18 modules, which is broader than the
`libraries.md` gap analysis suggests (it says 3). Actual inventory:

| Module                 | Status                                               |
|------------------------|------------------------------------------------------|
| `dns.sls`              | Implemented                                          |
| `grpc.sls`             | Implemented                                          |
| `http2.sls`            | Implemented                                          |
| `httpd.sls`            | Thin forwarder to chez-https                         |
| `pool.sls`             | Implemented                                          |
| `rate.sls`             | Implemented                                          |
| `request.sls`          | Implemented (API compat issues — see `newer.md` #12) |
| `router.sls`           | Implemented                                          |
| `security-headers.sls` | Implemented                                          |
| `ssl.sls`              | Thin forwarder to chez-ssl                           |
| `tcp-raw.sls`          | Implemented                                          |
| `tcp.sls`              | Implemented                                          |
| `timeout.sls`          | Implemented                                          |
| `tls.sls`              | Implemented                                          |
| `uri.sls`              | Implemented (new)                                    |
| `websocket.sls`        | Implemented                                          |
| `zero-copy.sls`        | Implemented                                          |

**Remaining gaps:**
- SMTP (email sending)
- SOCKS proxy
- JSON-RPC
- UDP (datagram sockets)
- HTTP client API compatibility with Gerbil (header format, SSL context,
  streaming, cookies, timeouts — see `newer.md` #12)

The `httpd.sls` and `ssl.sls` thin forwarders deserve assessment: are they
sufficient or do they need to become full implementations?

### 3.3 CLI Framework

**Severity: Medium | Effort: Medium**

Only `(std cli getopt)` exists. Missing:

- **Subcommand dispatch** (`jerboa <command> [options]` pattern)
- **Shell completion generation** (bash, zsh, fish)
- **Help text formatting** with automatic usage generation
- **Colored/styled terminal output** (ANSI codes, progress bars)
- **Multicall binary** support (busybox-style — documented in `libraries.md`)

Modern CLI tools (Rust's `clap`, Python's `click`, Go's `cobra`) set high
expectations here. A CLI-heavy language without good CLI tooling is friction.

### 3.4 Serialization Formats

**Severity: Low-Medium | Effort: Small per format**

Currently supported: JSON, CSV, YAML, XML, Base64, Hex, UTF-8.

Missing formats that matter for systems programming:
- **TOML** — Configuration files (widely replacing YAML)
- **MessagePack** — Binary JSON alternative (used in RPC)
- **CBOR** — RFC 8949, IoT and security token standard
- **Protocol Buffers** — Google's serialization (mentioned in `libraries.md`)
- **S-expressions as data** — `(std io)` for structured I/O (72 imports in
  Gerbil projects, listed as TODO)

### 3.5 Process Management

**Severity: High | Effort: Medium**

Documented in `newer.md` item 2. jerboa has `run-process` and `open-process`
but the shell port needed to write its own FFI for:

- `process-pid` (get PID from process port)
- `process-status` with WNOHANG (non-blocking wait)
- `process-kill` (signal delivery)
- `file-info` record (stat, mode, uid, gid, mtime)
- `user-info` (getpwuid/getpwnam)
- `tty?` / `tty-mode-set!` (terminal detection and raw mode)

Every non-trivial system tool needs these. Each jerboa port currently
reinvents them via FFI.

### 3.6 Spawn & Basic Concurrency API

**Severity: High | Effort: Small**

460 call sites across Gerbil projects. Both jerboa-es-proxy and jerboa-shell
shim this independently. Documented in `newer.md` item 3.

Gerbil's `spawn` is one of its most-used primitives. Chez has `fork-thread`
but the API differs. Need:

- `spawn` / `spawn/name` / `spawn/group`
- `thread-sleep!` (seconds-based, bridging Chez's time-object API)
- Ensure `with-lock` from `(std sugar)` works cleanly with `spawn`

---

## 4. Ecosystem & Tooling

### 4.1 Package Manager & Registry

**Severity: High | Effort: Large**

`(jerboa pkg)` and `(jerboa lock)` exist but the ecosystem question is open:

- **Where do packages live?** No registry, no discovery.
- **Can users install packages?** `jerboa install foo` doesn't exist.
- **Dependency resolution?** Lock files exist but the workflow isn't clear.
- **Versioning?** SemVer? Git tags? Both?

Without a package ecosystem, every library is manual vendoring. This is the
#1 barrier to community growth. Even a minimal solution (GitHub-based, like
early Go) would be transformative.

### 4.2 Build System

**Severity: Medium | Effort: Large**

Every jerboa project needs a build script. Documented in `newer.md` item 28.
A standard build system would provide:

- `define-library-target` / `define-program-target` / `define-test-target`
- Dependency tracking (only recompile changed files)
- Automatic `--libdirs` configuration
- Cross-project dependency resolution

### 4.3 Editor Integration

**Severity: Medium | Effort: Medium**

No LSP server, no editor plugins documented. For adoption:

- **LSP server** — even a basic one providing go-to-definition, completion
  from exports, and hover docs (using `(std doc)` data) would be huge
- **Emacs mode** — Scheme modes exist but Jerboa-specific indentation
  (for `def`, `defstruct`, `defclass`, `match`, `try`) needs configuration
- **VS Code extension** — syntax highlighting + basic LSP

### 4.4 Source Translator

**Severity: Medium | Effort: Large**

Both existing jerboa ports (es-proxy, shell) independently wrote source
translators. Documented in `newer.md` item 27. Common transformations:

- `#:keyword` syntax normalization
- `##gambit-primitive` to Chez equivalents
- `defstruct` to R6RS `define-record-type`
- `let-hash` / `using` expansion

A shared `(jerboa translator)` library would prevent each port from
reinventing these transformations.

---

## 5. Validation & Trust

### 5.1 Continuous Integration

**Severity: High | Effort: Small**

953+ tests exist with excellent coverage across reader, core, stdlib, FFI,
async, security, and types. 13 fuzz harnesses. Makefile targets for everything.

But there is **no CI pipeline**. No GitHub Actions, no GitLab CI. Users and
contributors cannot tell if master is green. This undermines the impressive
test infrastructure.

A basic CI setup:

```yaml
# .github/workflows/test.yml
- make test          # core (289 tests)
- make test-features # phase 2+3 (637 tests)
- make test-wrappers # external library tests (27 tests, needs deps)
```

This is a few hours of work for massive credibility gain.

### 5.2 Published Benchmarks

**Severity: Medium | Effort: Small**

`(std dev benchmark)` exists as a module, and `tests/test-benchmark.ss`
exercises it. But there are no **published benchmark results** comparing
Jerboa against:

- Gerbil (the system it reimplements — is it faster? slower? same?)
- Chez Scheme direct (what's the overhead of the Jerboa layer?)
- Racket, Guile, Chicken (competitive landscape)

Canonical benchmarks that would build confidence:
- JSON parse/serialize throughput
- HTTP request/response latency
- Pattern matching dispatch
- Hash table operations
- Startup time (REPL to first expression)
- Executable size (single-binary deployment)

### 5.3 Example Applications

**Severity: High | Effort: Medium**

Only `tests/example-musl.ss` exists (a static linking demo). No `examples/`
directory. No "built with Jerboa" showcase.

Needed:
- **HTTP API server** — demonstrates `httpd` + `router` + `json` + structured
  concurrency + the security sandbox
- **CLI tool** — demonstrates `getopt` + `process` + `format` + error handling
- **Data pipeline** — demonstrates iterators (once implemented) + `json` +
  `csv` + file I/O
- **Chat server** — demonstrates `websocket` + `channel` + `spawn` + actors

Each example should be self-contained, runnable with `jerboa run example.ss`,
and demonstrate multiple features working together. The goal isn't pedagogy —
it's proof that the stack composes into real programs.

### 5.4 Real-World Ports as Validation

**Severity: Medium | Effort: Ongoing**

Two ports exist (jerboa-es-proxy, jerboa-shell) but their status and lessons
learned aren't documented in Jerboa itself. A `docs/ports.md` capturing:

- What worked out of the box
- What required compat shims (and how much)
- What couldn't be ported and why
- Performance comparison vs. the Gerbil original

...would be invaluable for anyone considering Jerboa for their own project.

---

## 6. Documentation & Onboarding

### 6.1 Quickstart Guide

**Severity: High | Effort: Small**

No "Hello World to HTTP server in 5 minutes" guide exists. The README has a
feature table and module inventory but not a guided first experience.

A quickstart should cover:
1. Install Chez Scheme
2. Clone Jerboa, set library path
3. Hello World (REPL and file)
4. Define a struct, use pattern matching
5. Parse some JSON
6. Spin up an HTTP server
7. Run in a security sandbox

### 6.2 Import Conflict Reference

**Severity: Medium | Effort: Small**

Documented as a need in `newer.md` item 26 but doesn't exist yet. A reference
table of every known symbol conflict between `(chezscheme)`, `(jerboa core)`,
and `(std ...)` modules, with recommended resolution patterns.

### 6.3 Migration Guide from Gerbil

**Severity: Medium | Effort: Medium**

A comprehensive "Porting from Gerbil" guide covering:
- What works unchanged
- What needs mechanical transformation (and what the translator handles)
- What needs redesign (Gerbil expander API, `##` primitives)
- Common pitfalls (import conflicts, `parameterize` thread-locality)

### 6.4 API Reference Generation

**Severity: Low-Medium | Effort: Small**

`(std doc)` provides `define/doc`, `get-doc`, and doctest extraction. This
infrastructure could generate a browsable API reference (HTML or markdown)
for all 364 modules. Currently, the doc system exists but isn't used to
produce published documentation.

---

## 7. Summary Matrix

### Tier 1: High Impact, Low-Medium Effort (Do These First)

| # | Item | Severity | Effort | Section |
|---|------|----------|--------|---------|
| 1 | CLI entry point (`jerboa` command) | High | Small | 1.1 |
| 2 | CI pipeline | High | Small | 5.1 |
| 3 | Quickstart guide | High | Small | 6.1 |
| 4 | Import conflict ergonomics | High | Small | 1.3 |
| 5 | Spawn/concurrency API | High | Small | 3.6 |
| 6 | Example applications | High | Medium | 5.3 |

### Tier 2: High Impact, Medium-Large Effort (Build the Ecosystem)

| # | Item | Severity | Effort | Section |
|---|------|----------|--------|---------|
| 7 | SRFI-13 + SRFI-1 | High | Medium | 3.1 |
| 8 | Iterator protocol | High | Large | 2.3 |
| 9 | Error message improvement | High | Medium | 1.2 |
| 10 | Process management | High | Medium | 3.5 |
| 11 | Package manager & registry | High | Large | 4.1 |
| 12 | String interpolation | Medium | Small | 2.1 |

### Tier 3: Medium Impact, Fills Important Gaps

| # | Item | Severity | Effort | Section |
|---|------|----------|--------|---------|
| 13 | Struct patterns in core match | Medium | Small | 2.2 |
| 14 | CLI framework | Medium | Medium | 3.3 |
| 15 | Published benchmarks | Medium | Small | 5.2 |
| 16 | Editor integration / LSP | Medium | Medium | 4.3 |
| 17 | HTTP client API compat | Medium | Small | 3.2 |
| 18 | Migration guide from Gerbil | Medium | Medium | 6.3 |
| 19 | Build system | Medium | Large | 4.2 |
| 20 | Source translator library | Medium | Large | 4.4 |

### Tier 4: Nice to Have

| # | Item | Severity | Effort | Section |
|---|------|----------|--------|---------|
| 21 | Interface/protocol system | Medium | Medium | 2.4 |
| 22 | SRFI-19 date/time | Medium | Medium | 3.1 |
| 23 | Serialization formats (TOML, MsgPack) | Low-Med | Small each | 3.4 |
| 24 | API reference generation | Low-Med | Small | 6.4 |
| 25 | Networking depth (SMTP, UDP) | Low-Med | Medium | 3.2 |
| 26 | Import conflict reference doc | Medium | Small | 6.2 |

---

## The One Thing

If Jerboa could only do one thing from this list, it should be **item 6:
example applications**. Not because examples are technically important, but
because they answer the only question that matters for adoption:

> "Show me something real that works."

A 200-line HTTP API server using `httpd` + `router` + `json` + structured
concurrency + the security sandbox, runnable with a single command, would do
more for Jerboa's credibility than implementing 50 more SRFI modules.

The infrastructure is there. The modules exist. What's missing is the proof
that they compose into something someone would actually ship.
