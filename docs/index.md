# Jerboa Documentation

Updated 2026-03-22.

## Project Overview

- [status.md](status.md) — Current project status, feature inventory, known limitations
- [whats-new.md](whats-new.md) — What's new: 33 modules added in latest push
- [whatsnew.md](whatsnew.md) — Earlier additions: translator enhancements and initial stdlib
- [pending.md](pending.md) — Roadmap: what's left to make Jerboa better
- [architecture-split.md](architecture-split.md) — Design: chez-* (FFI shims) vs jerboa (application logic)
- [rocks.md](rocks.md) — Distribution and packaging

## Security

- [safety-guide.md](safety-guide.md) — Practical guide: writing secure Jerboa applications
- [security-reference.md](security-reference.md) — API reference for all security modules
- [ai-threat.md](ai-threat.md) — AI-assisted adversarial threat model
- [capability.md](capability.md) — Capability-based security design
- [import-conflicts.md](import-conflicts.md) — R6RS import conflict resolution

## Standard Library Reference

- [data-structures.md](data-structures.md) — Persistent maps, lazy sequences, weak collections, collection protocol, relations, diff, equiv
- [concurrency-extended.md](concurrency-extended.md) — Events, custodians, pools, delimited continuations, continuation marks, amb
- [metaprogramming.md](metaprogramming.md) — Typeclasses, CK-macros, format compilation, chaperones, advice, binary types
- [testing-and-infrastructure.md](testing-and-infrastructure.md) — QuickCheck, assert!, profiling, config, terminal, highlighting, guardian pools, memoization
- [protocols.md](protocols.md) — 9P2000 filesystem protocol, MessagePack serialization
- [fiber.md](fiber.md) — Green threads / fibers with M:N scheduling

## Networking

- `(std net ssh)` — Full SSH client: connect, exec, shell, SFTP, port forwarding (10 modules, 3,132 lines)

## Language Features

- [typing.md](typing.md) — Gradual type system: inference, refinements, GADTs, HKTs
- [pattern-matching.md](pattern-matching.md) — Pattern matching
- [effects.md](effects.md) — Algebraic effects
- [sequences.md](sequences.md) — Lazy sequences and iterators
- [staging.md](staging.md) — Multi-stage programming and macros
- [partial-evaluation.md](partial-evaluation.md) — Partial evaluation
- [cp0-passes.md](cp0-passes.md) — Chez cp0 optimization passes

## Concurrency and Distribution

- [concurrency.md](concurrency.md) — Concurrency safety toolkit
- [lightweight-concurrency.md](lightweight-concurrency.md) — Lightweight/green threads
- [async.md](async.md) — Async I/O
- [stm.md](stm.md) — Software transactional memory
- [actor-model.md](actor-model.md) — Actor model
- [distributed.md](distributed.md) — Distributed computing

## Build and Deployment

- [build.md](build.md) — Build system
- [single-binary.md](single-binary.md) — Single-binary compilation
- [static-binary-gotchas.md](static-binary-gotchas.md) — Static binary pitfalls
- [compiling-gerbil-projects.md](compiling-gerbil-projects.md) — Compiling Gerbil projects on Jerboa
- [packages.md](packages.md) — Package management
- [optimization.md](optimization.md) — Performance optimization

## Rust Native Backend

- [native-rust.md](native-rust.md) — Rust native backend architecture and implementation
- [vs-rust.md](vs-rust.md) — Jerboa vs Rust comparison
- [ffi.md](ffi.md) — FFI interface design

## Developer Experience

- [devex.md](devex.md) — Developer experience features
- [repl-protocol.md](repl-protocol.md) — REPL protocol

## Archive

Historical planning documents are in [archive/](archive/) for reference.
