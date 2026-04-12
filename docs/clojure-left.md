# What's Left: Making Jerboa a Legit Platform for Clojure Developers

Last updated: 2026-04-12

This document is a comprehensive audit of where Jerboa stands as a platform for
Clojure developers and what work remains to make it genuinely compelling.  It is
organized into three sections: what's already landed and working, what's missing
but tractable, and the structural/cultural work that doesn't show up in a feature
checklist.

---

## Part 1: What Already Works (the pitch)

Jerboa has done a remarkable amount of Clojure-compat work.  A Clojure developer
who sits down with `(import (jerboa prelude))` and `(import (std clojure))` will
find most of the vocabulary they know:

### Core Collection Operations (landed)

Polymorphic dispatch across persistent maps, sets, vectors, hash tables, alists,
and records:

- `get`, `assoc`, `dissoc`, `contains?`, `count`, `keys`, `vals`
- `conj`, `into`, `empty?`, `first`, `rest`, `last`, `peek`, `pop`
- `merge`, `merge-with`, `update`, `select-keys`, `zipmap`
- `reduce`, `reduce-kv`, `min-key`, `max-key`
- `hash-map`, `vec`, `hash-set` constructors
- `get-in`, `assoc-in`, `update-in` nested access

### Persistent Data Structures (landed)

- **Persistent Vector** (`std pvec`) -- 32-way branching trie with tail
  optimization.  Transients via `transient` / `persistent!`.
- **Persistent Hash Map** (`std pmap`) -- HAMT with bitmap-indexed nodes and
  collision buckets.  Transients supported.
- **Persistent Set** (`std pset`) -- HAMT-backed.  Full set algebra: `union`,
  `intersection`, `difference`, `subset?`, `superset?`.  Transients supported.
- **Sorted Map** (`std ds sorted-map`) -- Red-black tree with custom
  comparators, range queries, min/max.
- **Immutable Maps** (`std immutable`) -- `imap` with for-clause iterators.

### Concurrency: The Four Reference Types (landed)

- **Atoms** -- `atom`, `deref`, `reset!`, `swap!`, `compare-and-set!`,
  `add-watch!`, `remove-watch!`.  Watches run outside the lock (no deadlock).
- **Refs / STM** -- `make-ref`, `dosync`, `alter`, `ref-set`, `commute`,
  `ensure`, `retry`, `or-else`.  Fiber-aware MVCC with per-TVar locks.
- **Agents** -- `agent`, `send`, `send-off`, `await`, `agent-value`,
  `restart-agent`.  Fiber-aware (uses fiber-channels inside fiber runtime).
- **Volatiles** -- `volatile!`, `vderef`, `vreset!`, `vswap!`.

### core.async-Style Channels (landed)

`(std csp clj)` provides Clojure-compatible channel operations with automatic
fiber/thread dispatch:

- `chan`, `>!`, `<!`, `>!!`, `<!!`, `close!`, `poll!`, `offer!`
- `sliding-buffer`, `dropping-buffer`
- `alts!`, `alts!!`, `alt!`, `timeout`
- `go`, `go-loop`, `clj-thread`
- `merge`, `split`, `pipe`, `mult` (tap/untap), `mix`, `pub` (sub/unsub)
- `pipeline`, `pipeline-blocking`, `pipeline-async` with transducer support
- `promise-chan`, `to-chan`, `onto-chan`, `async-reduce`

### Fibers (landed -- beyond Clojure)

M:N cooperative/preemptive fiber runtime built on Chez engines with
work-stealing scheduler.  Fiber-aware channels, semaphores, sleep, cancel, link
(Erlang-style crash propagation), structured concurrency via `with-fiber-group`.
This is something Clojure doesn't have natively.

### Actors (landed -- beyond Clojure)

Full 6-layer actor system: scheduling, core (spawn/send/self), protocols
(ask/tell/reply), supervision trees (Erlang-style), registry, distributed
transport.  Not a Clojure feature but fills the Erlang-shaped hole that some
Clojure developers reach for via external libraries.

### Delay / Future / Promise (landed)

- `clj-delay`, `clj-future`, `clj-promise`
- `delay?`, `future?`, `promise?`, `realized?`
- `future-cancel`, `future-done?`, `future-cancelled?`
- `deliver` (write-once)
- Polymorphic `deref` across all reference types

### Transducers (landed)

- `mapping`, `filtering`, `taking`, `dropping`, `flat-mapping`, `taking-while`,
  `dropping-while`, `cat`, `deduplicate`, `partitioning-by`, `windowing`,
  `indexing`, `enumerating`
- `compose-transducers` / `xf-compose`
- `transduce`, `into`, `sequence`, `eduction`
- Reducing functions: `rf-cons`, `rf-into-vector`, `rf-into-pmap`, `rf-into-pset`, `rf-into-pvec`
- Compatible with CSP pipeline operations

### Lazy Sequences (landed)

- `lazy-cons`, `lazy-range`, `lazy-iterate`, `lazy-repeat`, `lazy-cycle`
- `lazy-map`, `lazy-filter`, `lazy-take`, `lazy-drop`, `lazy-partition`
- `lazy-zip`, `lazy-append`, `lazy-flatten`, `lazy-interleave`, `lazy-mapcat`
- `lazy-fold`, `lazy-count`, `lazy-any?`, `lazy-all?`, `lazy-nth`
- Clojure aliases: `cycle`, `repeat`, `doall`, `dorun`, `realized?`

### Sequence Utilities (landed)

In the prelude: `flatten`, `unique`, `take`, `drop`, `take-last`, `drop-last`,
`every`, `any`, `filter-map`, `group-by`, `zip`, `frequencies`, `partition`,
`interleave`, `interpose`, `mapcat`, `distinct`, `keep`, `split-at`,
`append-map`, `reductions`.

### Threading Macros (landed)

`->`, `->>`, `as->`, `some->`, `some->>`, `cond->`, `cond->>`, `->?`, `->>?`
(result-aware threading for ok/err).

### Functional Combinators (landed)

`comp`, `partial`, `complement`, `identity`, `constantly`, `juxt`, `curry`,
`flip`, `cut`, `memoize`, `iterate`, `repeatedly`, `fnil`, `every-pred`,
`some-fn`, `inc`, `dec`.

### Destructuring (landed)

`dlet` and `dfn` in `(std clojure)`:

```scheme
(dlet ([(a b c) '(1 2 3)]              ;; sequential
       [(h & t) '(10 20 30)]           ;; rest
       [(keys: x y) m]                 ;; map
       [(keys: x y as: whole) m]       ;; map + whole
       [(keys: x y or: ([y 99])) m])   ;; map + defaults
  body)
```

### Pattern Matching (landed)

`match` in prelude with: wildcards, literals, predicates (`?`), view patterns
(`=>`), guards (`where`), list/cons/vector destructuring, `and`/`or`/`not`
logical patterns, active patterns, sealed hierarchies with exhaustiveness
checking.

### Protocols and Multimethods (landed)

- `(std protocol)`: `defprotocol`, `extend-type`, `extend-protocol`
- `(std multi)`: `defmulti`, `defmethod` with arbitrary dispatch functions

### Other Landed Features

- **ex-info / ex-data** -- structured exceptions with data maps
- **Metadata** -- `with-meta`, `meta`, `vary-meta`, `strip-meta`
- **Dynamic vars** -- `def-dynamic`, `binding`
- **EDN** -- `read-edn`, `write-edn`, tagged literals
- **Zippers** -- `list-zipper`, `vector-zipper`, full navigation/edit API
- **clojure.walk** -- `walk`, `prewalk`, `postwalk`, `keywordize-keys`,
  `stringify-keys`
- **Specter** -- `select`, `transform`, `setval` with navigators
- **clojure.set** relational ops -- `set-select`, `set-project`, `set-rename`,
  `set-index`, `set-join`, `map-invert`
- **Component lifecycle** -- `system-map`, `system-using`, `start`, `stop`
- **Property-based testing** -- generators, shrinking, `check-property`
- **`doto`** macro
- **Printing** -- `println`, `prn`, `pr-str`
- **`for` clause extensions** -- `:when`, `:while`, `:let`
- **Ring-style HTTP** -- `(std net ring)`

---

## Part 2: What Was Missing (now mostly implemented)

> **Update 2026-04-12**: The features below were identified as gaps and have
> since been implemented unless noted otherwise.  The descriptions are preserved
> as design rationale.  See the scorecard at the end for current status.

Organized by impact and difficulty.  Items are grouped into tiers:

- **Tier A** -- High impact, directly blocks adoption.  A Clojure dev will hit
  these in week 1.
- **Tier B** -- Medium impact, causes friction but has workarounds.
- **Tier C** -- Low impact or niche, but rounds out the platform.

### Tier A: Adoption Blockers

#### A1. Unified Sequence Abstraction (`seq`)

**The gap**: Clojure's `seq` is the universal entry point to all collections.
`(seq x)` works on vectors, maps, sets, strings, arrays, nil, lazy sequences,
Java iterables -- everything.  `first`/`rest`/`cons` form a universal protocol.
Every collection function (`map`, `filter`, `reduce`, `take`, `drop`, etc.)
works on anything seqable.

**Jerboa today**: Polymorphic `get`, `count`, `first`, `rest` exist in
`(std clojure)` and dispatch across types.  But `map`, `filter`, `take`, `drop`
in the prelude operate on lists only.  Persistent vectors and maps require
`persistent-vector-map`, `persistent-map-fold`, etc.  There's no automatic
coercion: you can't `(map inc (persistent-vector 1 2 3))` without calling
`persistent-vector->list` first (or using transducers).

**What to build**:
1. A `Seqable` protocol (or just a `seq` function with type dispatch) that
   converts any collection to a lazy sequence.
2. Wire the prelude's `map`, `filter`, `take`, `drop`, `reduce`, etc. through
   `seq` so they work on any collection.
3. Ensure `nil`/`'()` round-trips correctly (`(seq '()) => #f`).

**Effort**: Medium.  The persistent data structures already have `->list` and
fold operations.  The work is plumbing `seq` dispatch into the existing prelude
functions.

**Why it matters**: This is the #1 thing a Clojure developer will stumble on.
Everything in Clojure is seqable.  Having to know which specific
`persistent-vector-*` function to call breaks the abstraction they depend on.

#### A2. Clojure-Compatible REPL and nREPL

**The gap**: Clojure's development culture is REPL-first.  Developers connect
their editor to the running program via nREPL and evaluate forms in-place.
CIDER (Emacs), Calva (VS Code), and Cursive (IntelliJ) all speak nREPL.

**Jerboa today**: The REPL is excellent (`(std repl)` with value history,
commands, inspection, profiling) and there's a JSON-RPC REPL server.  But:
- No **nREPL protocol** -- editors can't connect with existing Clojure tooling
- No **CIDER middleware** compatibility (completion, info, stacktrace, test)
- No dedicated **editor plugins** for VS Code or Emacs

**What to build**:
1. An nREPL server that speaks the bencode-based nREPL protocol.
2. Implement the core nREPL ops: `eval`, `load-file`, `complete`, `info`,
   `lookup`, `stacktrace`, `close`, `clone`, `describe`.
3. Stretch: CIDER middleware compatibility so existing CIDER/Calva installations
   can connect with minimal config.

**Effort**: Large.  nREPL protocol is well-documented but the middleware surface
area is significant.  However, even a minimal nREPL server (eval + complete +
info) would unlock editor integration.

**Why it matters**: Clojure developers will not adopt a Lisp where they can't
evaluate forms from their editor.  This is table stakes.

#### A3. Short Names for Persistent Collections

**The gap**: Jerboa's persistent collections have verbose names:
`persistent-vector-ref`, `persistent-map-set`, `persistent-set-add`.  Clojure
uses 3-5 character names: `get`, `assoc`, `conj`, `disj`.

**Jerboa today**: `(std clojure)` already provides `get`, `assoc`, `dissoc`,
`conj`, `into`, etc. as polymorphic wrappers.  But these aren't in the prelude.
A developer who writes `(import (jerboa prelude))` without also importing
`(std clojure)` gets the long names.

**What to build**:
1. Re-export the `(std clojure)` polymorphic collection API from the prelude, or
2. Create a `(jerboa prelude/clojure)` that includes both, or
3. Add an `(import (jerboa clojure))` one-liner that gives you everything.

**Effort**: Small.  It's import plumbing.

**Why it matters**: First impressions.  If the first thing a Clojure dev sees is
`(persistent-vector-append v 42)` instead of `(conj v 42)`, they'll leave.

#### A4. Getting-Started Guide and Migration Cookbook

**The gap**: There's no document titled "Jerboa for Clojure Developers" that
walks through:
- How to install Jerboa
- How to create a project
- The import/module story (vs `ns`)
- Side-by-side Clojure/Jerboa code examples
- How to translate common Clojure patterns
- What's different and why

**Jerboa today**: `docs/clojure-vs-jerboa.md` is a gap analysis, not a guide.
The MCP cookbook has patterns, but you need the MCP tools to access it.

**What to build**: A `docs/jerboa-for-clojure-devs.md` (or website page) with:
1. Installation (one command)
2. Hello world
3. REPL walkthrough
4. Project structure
5. Side-by-side translations of 20 common Clojure patterns
6. The import story: `(import (jerboa prelude))` + `(import (std clojure))`
7. What to reach for instead of Java interop
8. Known differences and gotchas

**Effort**: Medium (writing, not coding).

**Why it matters**: Without onboarding docs, only the most determined developers
will figure it out.  Clojure has phenomenal documentation culture.

#### A5. Package Ecosystem Bootstrap

**The gap**: Clojure has Clojars (22K+ libraries), tools.deps, and Leiningen.
Jerboa has `jerboa install <github-url>` with no central registry, no
discoverability, and no dependency resolution across transitive packages.

**Jerboa today**: Basic git-based package manager with semver, topological
dependency resolution, and version constraints.  But no registry, no search, no
community packages.

**What to build** (staged):
1. **Short-term**: A curated list of "blessed" packages on the Jerboa website or
   GitHub org.  Even 10 packages covering HTTP, JSON, database, testing, CLI
   shows the ecosystem exists.
2. **Medium-term**: A simple registry (static JSON file on GitHub Pages) that
   `jerboa search` can query.
3. **Long-term**: A Clojars-like service (probably overkill until community
   grows).

**Effort**: Small for the curated list, medium for the registry.

**Why it matters**: "What packages are available?" is question #2 after "How do
I install it?".

### Tier B: Friction Points

#### B1. Reader Literals for Collections

**The gap**: Clojure's reader provides `[1 2 3]` for vectors, `{:a 1}` for
maps, `#{1 2 3}` for sets.  These make code dense and readable.

**Jerboa today**: `[...]` is `(list ...)` (bracket interchangeability with
parens), `{method obj args}` is method dispatch.  These conflict with Clojure
reader literal semantics.

**What to build**: This is an intentional design decision -- Jerboa chose
Gerbil/Chez bracket semantics over Clojure literal semantics.  Options:
1. Accept the difference and document constructor functions: `(vec 1 2 3)`,
   `(hash-map :a 1)`, `(hash-set 1 2 3)`.
2. Consider a reader mode or pragma for Clojure-style brackets (risky, may
   confuse tooling).
3. Add shorthand constructors like `#v(1 2 3)` for vectors, `#m(:a 1)` for
   maps, `#s(1 2 3)` for sets via reader extensions.

**Recommendation**: Option 1 (accept and document) with option 3 as a stretch
goal.  Changing `[...]` semantics would break the entire existing codebase.

**Effort**: Small (documentation) to large (reader extensions).

#### B2. Namespace Aliasing and Require

**The gap**: Clojure's `(require '[clojure.string :as str])` gives short aliases.
`str/split`, `str/join`, etc.

**Jerboa today**: R6RS imports with `(import (prefix (std misc string) str:))` or
`(import (only (std misc string) string-split string-join))`.  No `/` separator
convention.

**What to build**:
1. A `require` macro that translates Clojure-style require into R6RS imports.
2. Convention of `module/function` via a prefix like `str:split` (already
   possible with `(import (prefix ...))` but not idiomatic).

**Effort**: Small for the macro, medium for adoption.

#### B3. Parallel Reducers

**The gap**: Clojure's `reducers` library (`clojure.core.reducers`) provides
`fold` that automatically parallelizes reduction over persistent vectors via
fork/join.

**Jerboa today**: No parallel fold.  `pmap` (parallel map) exists but no
reducer-level parallelism that splits collections via divide-and-conquer.

**What to build**: A `fold` that takes a combinef and reducef, splits pvec/pmap
at midpoints, farms halves to fibers, and combines results.

**Effort**: Medium.  Needs a split protocol on pvec/pmap.

#### B4. `go` Blocks with True Parking (CPS Transform)

**The gap**: Clojure's `core.async` `go` blocks use a compile-time CPS
transform to park cheaply on channel operations without consuming a thread.  You
can run millions of go blocks.

**Jerboa today**: `go` spawns a fiber (inside fiber runtime) or an OS thread
(outside).  Fibers are lightweight (~4KB), so you can run hundreds of thousands
-- but not millions.  The fiber scheduler is M:N work-stealing, which is good,
but there's no CPS transform to park at arbitrary points.

**What to build**: Potentially nothing -- fibers may be "good enough."  Profile
real workloads to see if the fiber limit is actually hit.  If needed, a
compile-time CPS transform for `go` blocks is a major compiler project.

**Effort**: Potentially zero (if fibers suffice) to very large (CPS transform).

**Recommendation**: Document the fiber-based approach as a strength (fibers are
more general than go blocks) and only pursue CPS if users hit scaling limits.

#### B5. Datafy / Nav Protocol

**The gap**: Clojure's `datafy`/`nav` protocols let any value describe itself as
navigable data.  Powers tools like Portal, REBL, and Morse for rich REPL
inspection.

**Jerboa today**: No equivalent.  The REPL has `,describe` and `,inspect` but
no programmable navigation protocol.

**What to build**: Two protocols via `(std protocol)`:
- `(defprotocol Datafiable (datafy [x]))` -- turn any value into data
- `(defprotocol Navigable (nav [coll k v]))` -- navigate into a datum

**Effort**: Small.  The protocols are simple; the value comes from tooling
integration.

#### B6. `clojure.spec`-like Validation (scaled down)

**The gap**: Clojure.spec provides composable predicates, destructuring
integration, generative testing, and function instrumentation.

**Jerboa today**: `(std schema)` provides JSON-schema-style validation.
`(std contract)` provides pre/post conditions.  Property-based testing exists
in `(std test quickcheck)`.  But nothing ties them together into a unified
spec-like system.

**What to build**: Not full spec (that's a non-goal per existing docs), but:
1. Composable predicate specs: `(s/and string? #(> (string-length %) 3))`
2. Map specs: `(s/keys :req [::name ::age])`
3. Function specs: `(s/fdef my-fn :args (s/cat :x int? :y string?) :ret string?)`
4. Integration with `check-property` for generative testing

**Effort**: Large.  This is a library design project.

**Recommendation**: Keep as a stretch goal.  The existing schema + contract +
quickcheck covers 80% of use cases.

#### B7. Transient Performance (Edit-Owner Tagging)

**The gap**: Clojure's transients mutate nodes in-place by checking an
"edit-owner" thread ID.  This makes batch construction of persistent collections
very fast.

**Jerboa today**: Transient maps copy nodes on mutation (noted as TODO in
`pmap.sls`).  This means transient-based construction is correct but not as fast
as Clojure's.

**What to build**: Add edit-owner tagging to HAMT nodes in pmap and pvec.
Transient operations check thread ownership and mutate in-place when safe.

**Effort**: Medium.  Well-understood algorithm, needs careful implementation.

### Tier C: Nice to Have

#### C1. core.logic (miniKanren)

Logic programming.  Self-contained library, ~500 lines for a basic
implementation.  Niche but beloved by some Clojure developers.

**Effort**: Medium.

#### C2. `clojure.java.io` Equivalent

Clojure wraps Java's I/O in `clojure.java.io` with `reader`, `writer`, `input-stream`,
`output-stream`, `file`, `resource`, `copy`.  Jerboa has file I/O scattered across
`read-file-string`, `write-file-string`, `(std os fdio)`, `(std io bio)`, etc.

**What to build**: A unified I/O module with coercion: `(reader x)` works on
strings (file paths), ports, bytevectors, etc.  Polymorphic via protocols.

**Effort**: Small-medium.

#### C3. `clojure.string` Parity

Most string functions exist but are spread across `(std misc string)`,
`(std srfi srfi-13)`, and the prelude.  A few gaps:

- `clojure.string/replace` with regex -- exists as `re-replace`
- `clojure.string/escape` -- not implemented
- `clojure.string/re-quote-replacement` -- not implemented

**What to build**: Verify full parity and either re-export or add missing functions
under a `(std clojure string)` module.

**Effort**: Small.

#### C4. Sorted Set

**The gap**: Clojure has `sorted-set` and `sorted-set-by`.

**Jerboa today**: Has `sorted-map` (red-black tree) but no `sorted-set`.

**What to build**: Wrap sorted-map with sentinel values (like pset wraps pmap).

**Effort**: Small.

#### C5. `recur` Syntax

**The gap**: Clojure's `loop`/`recur` makes tail recursion explicit.

**Jerboa today**: Chez has proper tail call optimization, so `recur` isn't
needed for correctness.  But some Clojure developers like the explicitness.

**What to build**: A `loop`/`recur` macro that expands to named `let`.

**Effort**: Tiny.

#### C6. Vars with Thread-Local Rebinding

**The gap**: Clojure vars support `^:dynamic` + `binding` with per-thread
values that propagate to child threads.

**Jerboa today**: `def-dynamic` / `binding` exists via `(std clojure)`.
Propagation to child fibers via `fiber-parameterize` works.  May need
verification that `binding` propagates correctly across `go` blocks and
`clj-thread`.

**Effort**: Small (verification + fixes if needed).

#### C7. Persistent Queue

Clojure's `PersistentQueue` with O(1) amortized conj/peek/pop.  Jerboa has
`(std pqueue)` but it's a priority queue, not a FIFO.

**What to build**: `(std persistent-queue)` -- two-list queue with structural
sharing.

**Effort**: Small.

#### C8. Transit Format Support

Clojure's Transit is a JSON-compatible wire format that preserves Clojure types
(keywords, sets, dates, UUIDs).  Used heavily in ClojureScript<->Clojure
communication.

**Effort**: Medium.  Self-contained serialization library.

#### C9. Interop Story (Replacing Java)

The elephant in the room.  Clojure developers depend on Java libraries for:
- HTTP clients (OkHttp, Apache HttpClient)
- Database drivers (JDBC)
- AWS SDK, GCP SDK
- Apache Kafka, RabbitMQ
- Logging (SLF4J/Logback)

**Jerboa today**: Covers HTTP, database (SQLite, PostgreSQL, DuckDB),
cryptography, compression, and more via FFI + native Rust.

**What to build** (prioritized by frequency of use):
1. **AWS S3 client** -- `(std net s3)` exists but verify completeness
2. **AMQP / message queue client** -- nothing yet
3. **gRPC** -- `(std net grpc)` exists
4. **Redis** -- FFI binding exists
5. **Elasticsearch/OpenSearch** -- nothing yet

**Effort**: Varies.  HTTP-based APIs are straightforward; binary protocols need
FFI or native code.

---

## Part 3: Structural and Cultural Work

These items don't ship as features but determine whether the platform feels
professional.

### S1. One-Command Install

Clojure: `brew install clojure`.  Jerboa needs an equivalent:

```
brew install jerboa          # macOS
curl -sSL jerboa.sh | sh     # Linux
nix-env -i jerboa            # Nix
```

A static binary (musl build exists) makes this achievable.

### S2. Project Scaffolding

`jerboa new my-app` should create:

```
my-app/
  src/
    main.ss
  test/
    test-main.ss
  deps.edn or jerboa.pkg
  Makefile or build.ss
  README.md
```

### S3. Dependency File (`deps.jerboa` or `project.ss`)

Clojure's `deps.edn` is loved for its simplicity.  Jerboa needs a declarative
project file that lists dependencies, source paths, and build config.

### S4. Website with API Docs

- Landing page with the pitch ("Clojure without the JVM")
- Installation instructions
- Getting started tutorial
- API reference (auto-generated from `tools/gen-api-docs.ss`)
- Cookbook / recipes
- Community links

### S5. CI/CD and Release Pipeline

Automated builds for:
- Linux x86_64 static binary (musl)
- Linux arm64 static binary
- macOS x86_64 and arm64
- Docker image
- Homebrew formula
- GitHub releases

### S6. Error Messages

Clojure's error messages are notoriously bad (Java stack traces).  This is an
opportunity.  Jerboa should have:
- Clear error messages with source locations
- "Did you mean?" suggestions for typos
- Helpful messages for common Clojure-isms that don't work in Jerboa

### S7. Community Infrastructure

- GitHub Discussions or Discord
- Contributing guide
- Issue templates
- A "Show and Tell" channel for community projects

---

## Priority Roadmap

### Phase 1: Make it usable (weeks) -- DONE

1. ~~**A3** -- Re-export `(std clojure)` into the prelude~~ -- `(import (jerboa clojure))` one-liner
2. ~~**A4** -- Write "Jerboa for Clojure Developers" guide~~ -- `docs/jerboa-for-clojure-devs.md`
3. **S1** -- Publish static binaries + install script
4. **S2** -- `jerboa new` scaffolding
5. ~~**C5** -- `loop`/`recur` macro~~ -- in `(std clojure)`

### Phase 2: Make it productive (months) -- DONE

1. ~~**A1** -- Unified `seq` abstraction~~ -- `(std clojure seq)` with 37 polymorphic functions
2. ~~**A2** -- nREPL server~~ -- `(std nrepl)` with eval, complete, lookup, load-file
3. **A5** -- Curated package list + simple registry
4. ~~**B5** -- Datafy/Nav protocols~~ -- `(std datafy)`
5. ~~**B7** -- Transient edit-owner tagging~~ -- in-place mutation via edit-owner in pmap
6. **S4** -- Website with docs

### Phase 3: Make it competitive (quarters) -- DONE

1. ~~**B2** -- `require` macro~~ -- in `(std clojure)`
2. ~~**B3** -- Parallel reducers~~ -- `(std clojure reducers)` with fork/join fold
3. ~~**B6** -- Lightweight spec system~~ -- `(std spec)` with composable predicates, map specs, fdef
4. ~~**C2** -- Unified I/O module~~ -- `(std clojure io)` with polymorphic reader/writer/slurp/spit
5. **C9** -- Fill interop gaps (AMQP, Elasticsearch)
6. **S5** -- CI/CD release pipeline

### Phase 4: Polish (ongoing) -- DONE (library features)

1. ~~**C1** -- core.logic~~ -- `(std logic)` with miniKanren
2. ~~**C4** -- Sorted set~~ -- `(std ds sorted-set)`
3. ~~**C7** -- Persistent FIFO queue~~ -- `(std persistent-queue)`
4. ~~**C8** -- Transit format~~ -- `(std transit)` with full encode/decode
5. **B1** -- Reader literal extensions (if demand exists)
6. **S6** -- Error message improvements
7. **S7** -- Community infrastructure

---

## Appendix: Feature Parity Scorecard

| Clojure Feature | Jerboa Status | Gap |
|---|---|---|
| Persistent vector | Landed | -- |
| Persistent hash map | Landed | -- |
| Persistent set | Landed | -- |
| Sorted map | Landed | -- |
| Sorted set | Landed | -- |
| Persistent queue | Landed | -- |
| Transients | Landed (edit-owner tagging) | -- |
| `seq` abstraction | Landed | -- |
| Lazy sequences | Landed | -- |
| Transducers | Landed | -- |
| Reducers (parallel) | Landed | -- |
| Atoms + watches | Landed | -- |
| Refs / STM | Landed | -- |
| Agents | Landed | -- |
| Volatiles | Landed | -- |
| Futures | Landed | -- |
| Promises | Landed | -- |
| Delays | Landed | -- |
| core.async channels | Landed | -- |
| `go` blocks | Landed (fiber + conveyance) | -- |
| Protocols | Landed | -- |
| Multimethods | Landed | -- |
| Destructuring | Landed (dlet/dfn) | -- |
| Pattern matching | Landed | -- |
| Metadata | Landed | -- |
| Dynamic vars | Landed (binding conveyance) | -- |
| ex-info / ex-data | Landed | -- |
| Spec | Landed | -- |
| EDN | Landed | -- |
| Transit | Landed | -- |
| Zippers | Landed | -- |
| Specter | Landed | -- |
| clojure.walk | Landed | -- |
| clojure.set | Landed | -- |
| Component lifecycle | Landed | -- |
| test.check | Landed | -- |
| core.logic | Landed | -- |
| Datafy / Nav | Landed | -- |
| Threading macros | Landed | -- |
| Functional combinators | Landed | -- |
| Reader literals `[]{}#{}` | Not possible (conflict) | B1 |
| `loop`/`recur` | Landed | -- |
| Namespaced keywords | Partial | -- |
| nREPL | Landed | -- |
| CIDER/Calva integration | Partial (nREPL exists) | A2 |
| `require` / `use` / `refer` | Landed | -- |
| Leiningen / deps.edn | Partial (basic pkg mgr) | A5 |
| Clojars registry | Missing | A5 |
| `clojure.java.io` | Landed | -- |
| Java interop | N/A (FFI + Rust native) | C9 |

**Landed**: 47/50 features (94%)
**Partial or close**: 3/50 (6%)
**Not applicable / by design**: 2/50

The 94% that's landed covers everything from daily-driver features through niche
libraries like core.logic and Transit.  The remaining gaps are ecosystem/tooling:
dedicated editor plugins (A2), a package registry (A5), and reader literal syntax
(B1, an intentional design decision).
