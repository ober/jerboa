# Pending: Making Jerboa Better

Last updated: 2026-03-22.

## Current State

500 modules, ~123K lines, 2,900+ tests, 13 fuzz harnesses. Full Gerbil API surface on stock Chez Scheme. Rust native backend (`libjerboa_native.so`) for crypto, compression, regex, databases, and OS integration. Legacy chez-* C FFI shims still available as fallbacks. A complete editor (jerboa-emacs) with TUI + Qt, Org-mode, LSP, Git.

---

## Language Completeness

### chez-srfis — Standalone SRFI Repository

35 SRFIs currently in `lib/std/srfi/`. Create `~/mine/chez-srfis` as a standalone repo (like `chez-r7rs`) and push toward 100+.

**Priority SRFIs:**
- SRFI-41 (streams) — standard API over lazy-seq
- SRFI-64 (test framework)
- SRFI-69 (hash tables) — older widely-used API
- SRFI-152 (strings)
- SRFI-170 (POSIX API) — complement `(std os *)`
- SRFI-171 (transducers) — standard API over `(std transducer)`
- SRFI-196 (ranges)

Jerboa keeps thin `(std srfi srfi-N)` re-export wrappers for namespace/conflict handling.

### Integrate Remaining chez-* Libraries

Most chez-* C FFI libraries have been superseded by the Rust native backend (see `docs/native-rust.md`). The remaining chez-* libraries that still need integration:

| Library | Integration |
|---------|------------|
| **chez-qt** | Add to `CHEZ_EXT_LIBDIRS`, create `(std gui qt)` wrapper |
| **chez-scintilla** | Already used by jerboa-emacs; expose via `(std gui scintilla)` |
| **chez-r7rs** | Add to library path for `(scheme base)` etc. |

`chez-ssh` is done — protocol logic split into `(std net ssh ...)` (10 modules, 3,132 lines), FFI stays in `(chez-ssh crypto)`.

### Complete Rust Native Migration

Move remaining modules from chez-* to Rust native:
- **TLS**: `(std net ssl)` still uses chez-ssl / OpenSSL — need rustls-ffi integration
- **LevelDB**: `(std db leveldb)` still uses chez-leveldb — need rusty-leveldb or sled
- **Default imports**: Main modules (e.g., `(std db sqlite)`) still import from chez-* — need to rewire to `-native` modules

### Web Framework

`(std net httpd)`, `(std net router)`, `(std text json)`, `(std db sqlite)`, `(std db conpool)`, `(std net websocket)`, `(std net rate)`, `(std net security-headers)` all exist. Glue them into `(std web)`:

- Route definitions with parameter extraction
- JSON request/response helpers
- Middleware stack
- Database integration with connection pooling
- Static file serving

### Database Migrations

`(std db migrate)` — numbered migration files, up/down, tracking table. Works with both SQLite and PostgreSQL (via Rust native or legacy chez-* backends).

---

## Build & Deployment

### Single-Binary Automation

`jerboa build --static` — compile all modules → link with Rust native backend → one ELF binary. The pieces exist (docs/single-binary.md, jerboa-native-rs/), just needs one-command orchestration.

---

## Tooling

### DAP Debugger

Time-travel debugging, replay, and inspector already exist. A DAP server would connect them to jemacs (which already has LSP client infrastructure as a template) and VS Code.

### Profiler Visualization

`(std misc profile)` provides programmatic profiling. Add Chrome trace format export or SVG flamegraph generation. Could integrate into jemacs as a profiler mode.

### Race Detector

Instrument mutex/hashtable operations, detect happens-before violations, report conflicting access stack traces. Would catch bugs in code using raw `fork-thread` outside structured concurrency.

---

## Claude-as-Developer Improvements

### Better CLAUDE.md for Jerboa

The current CLAUDE.md is oriented toward Gerbil MCP tools. It should also have:
- Jerboa-specific patterns and idioms
- Common R6RS gotchas (definition context, phase separation)
- Which backend to use (Rust native vs legacy chez-*) for what
- How jerboa's module namespace maps to Gerbil's
- Testing conventions

### Example Corpus

More `examples/` showing real patterns Claude can reference when generating code:
- Web API with auth and database
- CLI tool with subcommands
- Data processing pipeline
- Actor system with supervision
- FFI binding to a C library
- Qt GUI application

---

## Wishlist

Things that would be cool but aren't blocking anything:

- **Windows graceful degradation** — security modules warn instead of crash on non-Linux
- **WASM Chez** — run jerboa in the browser (experimental territory)
- **jemacs inline eval** — evaluate expression in buffer, show result inline (REPL-driven development)
- **jemacs package browser** — browse available libraries (Rust native + chez-*) from the editor
