# Jerboa TODO

Updated 2026-03-21.

Tracks remaining work. Items marked DONE were either already implemented
or completed in the March 2026 sprint. Remaining items are genuinely open.

---

## Completed

### Developer Experience
- [x] **CLI entry point** — `bin/jerboa` with run, test, eval, repl, build, version (`bin/jerboa`)
- [x] **Error messages** — `(std errors)` with "did you mean" suggestions, Levenshtein distance, `install-error-handler!`
- [x] **Import conflict ergonomics** — `(jerboa prelude clean)` conflict-free prelude + `docs/import-conflicts.md` reference

### Language Features
- [x] **String interpolation** — `(std interpolate)` macro: `(interpolate "Hello ${name}")`
- [x] **Struct pattern matching** — `(std match2)` with `define-match-type`, sealed hierarchies, exhaustiveness
- [x] **Iterator protocol** — `(std iter)` with `for/collect`, `for/fold`, `in-range`, `in-hash-*`, etc.
- [x] **Interface/protocol system** — `(std interface)` with `definterface` + `(std generic)` with `defgeneric`

### Standard Library
- [x] **SRFI-1** (list library, 271 lines), **SRFI-13** (string library, 258 lines), **SRFI-14** (character sets), **SRFI-19** (date/time), **SRFI-43** (vectors), **SRFI-128** (comparators), **SRFI-141** (integer division)
- [x] **Process management** — `(std misc process)` with `process-port-pid`, `process-kill`, `tty?`
- [x] **Spawn/concurrency** — `(std misc thread)` with `spawn`, `spawn/name`, `spawn/group`, `thread-sleep!`
- [x] **CLI framework** — `(std cli multicall)` subcommands, `(std cli style)` ANSI colors, `(std cli completion)` bash/zsh
- [x] **Serialization** — `(std text toml)`, `(std text msgpack)`, `(std text cbor)`, `(std io)` structured I/O
- [x] **Networking** — `(std net smtp)`, `(std net json-rpc)`, `(std net udp)`, `(std net address)`

### Ecosystem & Tooling
- [x] **Package manager** — `(jerboa pkg)` with semver + `(jerboa lock)` with lockfiles
- [x] **Build system** — `(std build)` with module discovery, DAG ordering, content hashing
- [x] **Source translator** — `(jerboa translator)` with 20+ transform functions

### Validation & Trust
- [x] **CI pipeline** — `.github/workflows/test.yml` (GitHub Actions)
- [x] **Benchmark suite** — `benchmarks/bench-core.ss` (hash tables, match, sort, JSON, iterators, structs)
- [x] **Example applications** — `examples/hello-api.ss`, `examples/cli-tool.ss`, `examples/data-pipeline.ss`, `examples/chat-server.ss`
- [x] **Ports documentation** — `docs/ports.md`

### Documentation
- [x] **Quickstart guide** — `docs/quickstart.md`
- [x] **Migration guide** — `docs/migration.md`
- [x] **Import conflict reference** — `docs/import-conflicts.md`
- [x] **API reference generator** — `tools/gen-api-docs.ss`

- [x] **Struct patterns in prelude match** — `(jerboa prelude)` now re-exports `(std match2)`'s `match` with struct patterns, sealed hierarchies, active patterns, and `match/strict`
- [x] **Package registry** — `(jerboa registry)` with GitHub-based install/uninstall/update; `bin/jerboa install/uninstall/update/list` CLI commands
- [x] **LSP server** — `(std lsp server)` + `(std lsp symbols)` with JSON-RPC over stdio; `tools/jerboa-lsp.ss` entry point; completion, hover, go-to-definition, diagnostics
- [x] **Protocol Buffers** — `(std protobuf)` wire format encoder/decoder (proto3); varint, fixed32/64, length-delimited, zigzag, embedded messages

---

## Remaining

### Networking Polish

- **SOCKS proxy** — low priority
- **HTTP client API compat** — header format differences vs Gerbil
  (dotted pairs vs triples). `(std net request)` works but Gerbil
  ports need header conversion.
