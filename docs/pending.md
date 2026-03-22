# Pending: What's Left to Make Jerboa Awesome

Last updated: 2026-03-22.

## Current State

Jerboa is a complete reimplementation of Gerbil Scheme's API surface as pure stock Chez Scheme libraries: **489 modules, ~120,000 lines of code, 2,900+ tests, 13 fuzzing harnesses**. No custom runtime, no patched Chez, no external dependencies beyond optional chez-* library wrappers.

| Category | Grade | Notes |
|----------|:-----:|-------|
| Core Language | A+ | Reader, macros, runtime, FFI — complete and tested |
| Standard Library | A | 489 modules across misc, net, text, crypto, db, actor, etc. |
| Security | A+ | Real Landlock + seccomp + capabilities, allowlist sandbox |
| Safety | A | Contract-checked stdlib, finalizers, timeouts |
| Type System | A- | Gradual with refinements, GADTs, HKTs, typeclasses |
| Concurrency | A | Structured concurrency, actors, STM, fibers, channels |
| Build System | B+ | Reproducible artifacts, SBOM, content hashing |
| Testing | A | 2,900+ tests, 13 fuzz harnesses, QuickCheck |
| Documentation | A- | 123 docs (69K lines), comprehensive but dense |
| Editor | A | Full Emacs-inspired editor with TUI + Qt backends (jerboa-emacs) |
| Tooling | A- | LSP server, REPL, CLI, linter, editor with LSP client |
| Deployment | B | Single-binary possible but not automated |
| Package Manager | B | GitHub-based install — no central registry |

---

## The Jerboa Platform

Jerboa is not just a standard library — it's an entire platform spanning multiple repositories in `~/mine/`.

### jerboa-emacs: A Full Editor Written in Jerboa

`~/mine/jerboa-emacs` is a **standalone Emacs-inspired editor** written entirely in Chez Scheme on top of jerboa. It is NOT an Emacs plugin — it's a complete editor with two frontends.

| Feature | Status |
|---------|--------|
| **TUI backend** | Complete — 66 modules, ~65K lines |
| **Qt GUI backend** | Complete — 45 modules, ~49K lines, 65MB static binary |
| **Buffer/window management** | Full — splitting, switching, undo/redo |
| **Syntax highlighting** | Custom lexers + Scintilla/Lexilla |
| **Paredit / S-expression editing** | Full — slurp, barf, transpose, strict mode |
| **Org-mode** | Full — 10 dedicated modules: headings, tables, babel, agenda, capture, clock, export (HTML/LaTeX/PDF) |
| **LSP client** | Integrated — connects to jerboa-lsp for completion, hover, go-to-definition |
| **Git/VCS integration** | Magit-style — status, log, diff, add, commit, blame, branch switching |
| **Shell integration** | Embedded POSIX shell (jerboa-shell/jsh) with C-g interrupt |
| **Helm completion** | Fuzzy-matching command/file/buffer picker |
| **Which-key mode** | Delayed keybinding hints at prefix keys |
| **Debug REPL** | TCP server with text + s-expression protocols, auth tokens |
| **Session persistence** | Desktop-save-mode — restores open buffers across restarts |
| **AI/chat integration** | LLM chat module |
| **Tests** | 42 test files, all passing |

**Binaries:** `jemacs` (TUI), `jemacs-qt` (Qt GUI, statically linked)

**Dependencies:** jerboa, jerboa-shell, chez-scintilla, chez-pcre2; Qt backend also needs chez-qt.

### Companion Ecosystem: chez-* Libraries

15 production-ready chez-* libraries in `~/mine/`:

#### Integrated into Jerboa (11 libraries)

In the Makefile's `CHEZ_EXT_LIBDIRS`, fully usable via `(std ...)` imports:

| Library | Wraps | Key Capability |
|---------|-------|----------------|
| **chez-ssl** | OpenSSL TLS | TLS client/server, SNI, cert validation |
| **chez-https** | HTTP/1.1 (over chez-ssl) | `http-get/post/put/delete`, chunked encoding |
| **chez-zlib** | zlib | gzip/deflate compression/decompression |
| **chez-crypto** | OpenSSL libcrypto | SHA-256, HMAC, AES, Ed25519, AEAD, scrypt |
| **chez-pcre2** | PCRE2 | Perl-compatible regex, JIT, pregexp-compat API |
| **chez-yaml** | *Pure Scheme* (no C) | Full YAML 1.2 parser/emitter, 82 tests |
| **chez-sqlite** | SQLite3 | Prepared statements, parameterized queries |
| **chez-postgresql** | libpq | Parameterized queries, escaping, connection info |
| **chez-leveldb** | LevelDB | Iterators, snapshots, write batches, bloom filters |
| **chez-epoll** | Linux epoll(7) | High-performance I/O multiplexing |
| **chez-inotify** | Linux inotify(7) | Filesystem event monitoring |

#### Available but Not Integrated (4 libraries)

Tested and working — not wired into the default jerboa build:

| Library | What It Provides | Status |
|---------|-----------------|--------|
| **chez-qt** | Full Qt6 widget bindings — dialogs, layouts, painters, events, system tray. 18 working examples. | **Complete, production-ready** |
| **chez-scintilla** | Scintilla text editor component — syntax highlighting via Lexilla, code folding, markers, autocomplete, search, TUI backend. | **Complete, production-ready** |
| **chez-ssh** | SSH agent protocol + Ed25519 signing. mlock'd keys, explicit_bzero, MADV_DONTDUMP. Full SFTP, channel, transport, KEX, auth. | **Complete, production-grade security** |
| **chez-r7rs** | 16 R7RS-small standard libraries (`(scheme base)` through `(scheme write)`). Fully mixable with `(chezscheme)`. | **Complete** |

### Implications for Roadmap

- **Editor is NOT missing** — `jerboa-emacs` is a complete Emacs-class editor with TUI + Qt, Org-mode, LSP, Git, and a debug REPL.
- **IDE is NOT missing** — `jerboa-emacs` already connects to `jerboa-lsp` for semantic intelligence. It just needs DAP for debugging.
- **GUI toolkit is NOT missing** — `chez-qt` provides full Qt6, and `jerboa-emacs` already uses it for its Qt backend.
- **SSH is NOT missing** — `chez-ssh` is production-ready with secure key storage.
- **R7RS compatibility is NOT missing** — `chez-r7rs` covers all of R7RS-small.

---

## Tier 1: Adoption Blockers

These prevent people from trying Jerboa at all. Highest priority.

### 1.1 Pre-built Binaries

**Problem:** Users must build from source. Instant drop-off for anyone who isn't already a Chez Scheme user.

**Solution:**
- CI pipeline (GitHub Actions) producing Linux x86_64 tarballs on each tagged release
- Include pre-compiled chez-* .so shims so users don't need to build C code
- Ship `jemacs` TUI binary alongside jerboa (zero-config editor out of the box)
- Optional: ARM64 cross-compilation
- Publish to GitHub Releases

**Effort:** Small — Makefile and CI config only.

### 1.2 VS Code Extension

**Problem:** Not everyone will use jemacs. The LSP server (`tools/jerboa-lsp.ss`) is fully implemented but ~70% of developers use VS Code.

**Solution:**
- Minimal VS Code extension that launches `jerboa-lsp` over stdio
- Syntax highlighting via TextMate grammar (`.ss`, `.sls` files)
- Snippets for common forms (`define-record-type`, `match`, `lambda`, etc.)
- Debugger integration could follow later via DAP

**Effort:** Small — boilerplate VS Code extension, ~200 lines of TypeScript + tmLanguage JSON.

### 1.3 Docker Image

**Problem:** Can't `docker run jerboa` to try it.

**Solution:**
- `Dockerfile` based on `ubuntu:24.04` (jerboa-emacs already has one)
- Install Chez Scheme, copy jerboa libraries + all 11 chez-* shims + jemacs binary
- Expose `bin/jerboa` and `jemacs`
- Publish to GitHub Container Registry

**Effort:** Small — single Dockerfile (adapt from jerboa-emacs's existing one).

### 1.4 Project Scaffolding

**Problem:** No `jerboa new` to create a project skeleton. First experience after installing is "now what?"

**Solution:**
- `jerboa new myproject` creates directory with:
  - Project manifest
  - `src/main.ss` with hello world
  - `tests/main-test.ss` with example test
  - `Makefile` with build/test/run targets
- Templates: `--template cli`, `--template web`, `--template library`, `--template qt-gui`

**Effort:** Small — template files + CLI subcommand.

---

## Tier 2: Developer Experience Gaps

These cause people to try Jerboa but bounce. Medium priority.

### 2.1 Expanded Tutorials

**Problem:** `docs/quickstart.md` is 194 lines — thin relative to 489 available modules. Hard to discover what's there.

**Solution:**
- "Build a REST API in 5 minutes" — httpd + router + json + sqlite
- "Build a CLI tool" — getopt + process + terminal colors
- "Build a data pipeline" — csv + json + msgpack + lazy-seq
- "Build a Qt GUI app" — chez-qt + jerboa modules
- "Secure a service" — sandbox + taint + capability + landlock
- "Edit code with jemacs" — getting started with the built-in editor
- Each tutorial references real stdlib modules with working code

**Effort:** Small — writing only, no code changes.

### 2.2 High-Level Web Framework

**Problem:** `(std net httpd)`, `(std net router)`, `(std text json)`, `(std db sqlite)` all exist individually, but there's no batteries-included framework tying them together.

**Solution:**
- `(std web)` — opinionated web framework built on existing modules
- Route definitions with parameter extraction
- JSON request/response helpers
- Middleware stack (logging, auth, CORS, rate limiting — `(std net rate)` and `(std net security-headers)` already exist)
- Database integration with connection pooling (`(std db conpool)` exists)
- Static file serving
- WebSocket support (`(std net websocket)` exists)

**Effort:** Medium — most pieces exist, needs glue and conventions.

### 2.3 Database Migrations

**Problem:** DB drivers exist (`chez-sqlite`, `chez-postgresql`, connection pooling via `(std db conpool)`) but no schema versioning.

**Solution:**
- `(std db migrate)` — numbered migration files, up/down, migration tracking table
- CLI integration: `jerboa migrate up`, `jerboa migrate down`, `jerboa migrate status`
- Works with both SQLite and PostgreSQL

**Effort:** Small-medium.

### 2.4 Integrate chez-qt into Default Build

**Problem:** `chez-qt` is a fully working Qt6 binding with 18 examples, but it's not in the jerboa Makefile. Users don't know it exists.

**Solution:**
- Add `chez-qt` to `CHEZ_EXT_LIBDIRS` (conditional on Qt6 being installed)
- Create `(std gui qt)` thin wrapper in jerboa's namespace
- Add "Building GUI Apps" section to documentation
- Ship the 18 examples as `examples/qt-*`

**Effort:** Small — integration and docs only, the library is already complete.

### 2.5 Integrate chez-ssh

**Problem:** `chez-ssh` provides production-grade SSH with secure key storage, but it's not accessible from jerboa's `(std ...)` namespace.

**Solution:**
- Add to Makefile's `CHEZ_EXT_LIBDIRS`
- Create `(std net ssh)` thin wrapper
- Enables: SSH tunneling, SFTP file transfer, remote command execution from jerboa

**Effort:** Small — integration only.

### 2.6 Integrate chez-r7rs

**Problem:** `chez-r7rs` provides full R7RS-small compatibility. Users coming from Chibi, Gauche, or other R7RS Schemes can't use their familiar `(scheme base)` imports.

**Solution:**
- Add `chez-r7rs/lib` to the library path
- Document R7RS compatibility and how to mix `(scheme base)` with `(chezscheme)`
- This is a major selling point: *the only Scheme that's simultaneously R6RS, R7RS, and Gerbil-compatible*

**Effort:** Small — path configuration and documentation.

### 2.7 Central Package Registry

**Problem:** `jerboa install` works for GitHub URLs only. No discovery, no search, no browsing.

**Solution (phased):**
1. **Phase 1:** Curated `packages.json` in a GitHub repo — searchable via `jerboa search`. Seed it with the chez-* libraries and any community packages.
2. **Phase 2:** Simple web frontend listing available packages with descriptions
3. **Phase 3:** Full registry with accounts, publishing, versioning

**Effort:** Phase 1 is small. Phase 2-3 require hosted infrastructure.

---

## Tier 3: Power Features

These differentiate Jerboa from other Schemes and make advanced users productive.

### 3.1 DAP Debugger for jemacs + VS Code

**Problem:** Time-travel debugging (`std debug timetravel`), replay (`std debug replay`), and inspector (`std debug inspector`) exist. `jerboa-emacs` has a debug REPL. But there's no step-through debugger integrated into either jemacs or VS Code.

**Solution:**
- DAP (Debug Adapter Protocol) server, similar to the existing LSP server
- Step, breakpoint, watch, and inspect
- Integrate into jemacs (already has LSP client infrastructure — DAP is similar)
- Also usable from VS Code
- Leverage existing inspector and time-travel infrastructure

**Effort:** Large — DAP is a substantial protocol, but jemacs's LSP client is a template.

### 3.2 Single-Binary Automation

**Problem:** Single-binary compilation is documented (`docs/single-binary.md`) and the Rust native backend exists, but it's not a one-command workflow.

**Solution:**
- `jerboa build --static` or `jerboa compile --single-binary`
- Automates: compile all modules → link with Rust native backend → produce one ELF binary
- Cross-compilation support: `--target aarch64-linux`

**Effort:** Medium — orchestration of existing pieces.

### 3.3 Race Detector

**Problem:** Structured concurrency (`std concur structured`) reduces risk, but code using raw `fork-thread` has no safety net. No dynamic race detection.

**Solution:**
- Instrument `mutex-acquire`/`mutex-release`, `hashtable-set!`/`hashtable-ref`, and shared mutable state
- Detect happens-before violations at runtime
- Report stack traces for conflicting accesses

**Effort:** Large — requires dynamic analysis framework.

### 3.4 Profiler Visualization

**Problem:** `(std misc profile)` and `(std profile)` provide programmatic profiling, but no flamegraph or visual output.

**Solution:**
- Export to Chrome trace format (`chrome://tracing`)
- Or: Generate SVG flamegraphs from profile data
- `jerboa profile my-script.ss` CLI command
- Potentially integrate into jemacs as a profiler mode

**Effort:** Small-medium.

### 3.5 More SRFIs → `chez-srfis` Repo

**Problem:** 35 SRFIs implemented in `lib/std/srfi/`. Some commonly expected ones are missing.

**Solution: Create `~/mine/chez-srfis` as a standalone repo** (like `chez-r7rs`).

SRFIs are pure R6RS libraries with no jerboa dependency — they serve the entire Chez Scheme community, not just jerboa users. A separate repo means:
- Broader audience and contribution pool
- Canonical SRFI test suites can run in isolation
- Jerboa integrates via Makefile `CHEZ_EXT_LIBDIRS` (same as other chez-* libraries)
- Thin `(std srfi srfi-N)` re-export wrappers stay in jerboa for namespace compatibility and conflict avoidance (e.g., SRFI-1 excludes names already in `(chezscheme)`)

**Priority SRFIs to implement:**
- SRFI-41 (streams) — partially covered by `(std misc lazy-seq)` but not the standard API
- SRFI-64 (test framework) — some users expect it over `(std test)`
- SRFI-69 (hash tables) — older, widely-used predecessor to SRFI-125
- SRFI-152 (strings) — newer string library
- SRFI-170 (POSIX API) — would complement `(std os *)`
- SRFI-171 (transducers) — have `(std transducer)` but not SRFI-compatible API
- SRFI-196 (ranges) — useful for numeric work

**Effort:** Medium — each SRFI is small-medium, but there are many. Targeting 100+ total.

### 3.6 Windows Support

**Problem:** Security stack (Landlock, seccomp) is Linux-only. Jerboa works on Windows via Chez but without the security modules.

**Solution:**
- Graceful degradation: security modules return warnings on non-Linux
- Windows-specific sandboxing via Job Objects / AppContainers
- Or: Accept Linux-only for security features, document clearly
- Note: `chez-epoll` and `chez-inotify` are also Linux-only; would need `kqueue`/IOCP alternatives

**Effort:** Large for real Windows sandboxing; small for graceful degradation.

---

## Tier 4: Moonshots

Nice-to-have items that would make Jerboa extraordinary.

### 4.1 WASM Playground

**Problem:** Can't try Jerboa without installing it.

**Solution:**
- WebAssembly build of Chez Scheme + Jerboa prelude
- Simple web page with editor + output pane
- Host at jerboa-lang.org or similar

**Effort:** Large — WASM Chez is experimental territory.

### 4.2 jemacs as a Language Workbench

**Problem:** jemacs is already a capable editor, but it could become the standard environment for Jerboa development — like DrRacket is for Racket.

**Assets already in place:**
- Full editor with TUI + Qt backends
- LSP client (completion, hover, go-to-definition)
- Debug REPL with eval, inspect, apropos
- Org-mode for literate programming
- Git integration for version control
- Shell integration for build/test

**Missing pieces:**
- DAP integration for step-through debugging
- Inline profiler visualization
- REPL-driven development workflow (eval expression in buffer, show result inline)
- Package browser (connect to package registry)

**Effort:** Medium per feature — the editor infrastructure is already there.

---

## Prioritized Roadmap

### Phase 1: "People Can Try It" (weeks)

1. [ ] CI pipeline producing Linux binaries + Docker image (include jemacs)
2. [ ] VS Code extension wrapping existing LSP
3. [ ] `jerboa new` project scaffolding
4. [ ] Integrate chez-r7rs (library path + docs)
5. [ ] Expanded quickstart tutorials (including jemacs guide)

### Phase 2: "People Can Build With It" (months)

6. [ ] High-level web framework `(std web)`
7. [ ] Integrate chez-qt into default build + GUI tutorial
8. [ ] Integrate chez-ssh as `(std net ssh)`
9. [ ] Database migrations `(std db migrate)`
10. [ ] Curated package registry (GitHub-based, Phase 1)

### Phase 3: "People Can Ship With It" (quarters)

11. [ ] Single-binary automation (`jerboa build --static`)
12. [ ] DAP debugger server + jemacs + VS Code integration
13. [ ] Flamegraph/Chrome-trace profiler output
14. [ ] Race detector prototype

### Phase 4: "Ecosystem Growth" (ongoing)

15. [ ] Central package registry with web UI
16. [ ] `chez-srfis` repo (targeting 100+ SRFIs, integrate into jerboa via Makefile)
17. [ ] Windows graceful degradation
18. [ ] jemacs as language workbench (inline eval, package browser, profiler mode)
19. [ ] WASM playground

---

## What Makes Jerboa Unique

No other Scheme implementation has all of these simultaneously:

1. **Triple compatibility** — R6RS + R7RS (via chez-r7rs) + Gerbil API surface
2. **Real kernel sandboxing** — Landlock + seccomp + capabilities (not stubs)
3. **Production FFI ecosystem** — 15 chez-* libraries covering TLS, HTTP, crypto, databases, Qt GUI, SSH, regex, compression
4. **Its own editor** — jemacs: Emacs-class editor with TUI + Qt, Org-mode, LSP, Git, debug REPL — written in the language itself
5. **Gradual type system** — with refinements, GADTs, HKTs, and typeclasses
6. **Full actor system** — with supervision trees, distribution, and backpressure
7. **Chez Scheme's optimizer** — cp0 partial evaluation, engines, native threads

The gap between "technically complete" and "easy to adopt" is primarily **distribution and discoverability** — not language, library, or tooling completeness. The platform is remarkably self-hosted: the editor, shell, build system, and LSP server are all written in jerboa itself. Phase 1 of the roadmap focuses on making this discoverable.
