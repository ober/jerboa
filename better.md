# Better: 30 Features for Gerbil→Jerboa Translation

Features identified from analysis of 43 gerbil-* repos, Chez Scheme 10.4.0 capabilities,
and real-world translation gaps. Each feature includes implementation plan, test strategy,
and documentation requirements.

---

## Translator Enhancements (1–10)

### 1. `translate-method-dispatch` — Curly-Brace Method Syntax
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Translate Gerbil's `{method obj args ...}` syntax to jerboa's `(~ obj method args ...)`.
Currently the translator has zero support for method dispatch syntax.

**Impact:** Blocks all OOP-heavy ports (gerbil-litehtml 100+ uses, gerbil-origin 200+).

### 2. `translate-defrules` — Macro Definition Translation
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Translate Gerbil's `(defrules name () (pat body) ...)` to jerboa's `(defrules name (pat body) ...)`.
Gerbil's defrules has an extra `()` literals list that jerboa's doesn't need.

**Impact:** 15+ projects with macro libraries.

### 3. `translate-defstruct` Enhancement — Parent & Mutable Fields
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Current `translate-defstruct` drops parent information and field mutability.
Enhance to emit `(parent ...)` clause and `(mutable field)` annotations.

**Impact:** 50+ structs across gerbil projects with inheritance or mutable fields.

### 4. `translate-hash-literal` — Hash Table Literal Syntax
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Translate Gerbil's hash table construction patterns:
- `(hash (key val) ...)` already works (jerboa core has it)
- Translate `(hash-eq (key val) ...)` patterns
- Translate `(list->hash-table alist)` calls (same API, just verify)

**Impact:** 30+ files in gerbil-utils, gerbil-postgres.

### 5. `translate-try-catch` — Exception Handling Normalization
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Normalize Gerbil's exception handling forms:
- `(with-catch handler thunk)` → `(with-exception-catcher handler thunk)` (jerboa core)
- Verify `(try ... (catch (e) ...) (finally ...))` passes through unchanged

**Impact:** Every project with error handling.

### 6. `translate-export` — Export Form Translation
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Translate Gerbil export forms:
- `(export ident ...)` → R6RS `(export ident ...)`
- `(export (struct-out name))` → expanded field accessor exports
- `(export (rename-out (old new) ...))` → R6RS `(rename (old new) ...)`

**Impact:** Every file that exports anything.

### 7. `translate-for-loops` — Iterator Syntax Translation
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Translate Gerbil's `:std/iter` forms to jerboa equivalents:
- `(for ((x (in-list lst))) body)` → `(for ((x (in-list lst))) body)` (same API)
- `(for/collect ...)` → same (jerboa has it)
- Verify pass-through since jerboa's `(std iter)` matches Gerbil's API

**Impact:** 228 imports across gerbil projects.

### 8. `translate-match-patterns` — Match Clause Normalization
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Normalize Gerbil match patterns to jerboa's match:
- `(? pred)` guard patterns → verify same syntax
- `(and pat ...)` / `(or pat ...)` → verify pass-through
- `(struct-name field ...)` patterns → verify compatibility
- `[a b c]` in match patterns → `(list a b c)` (binding context)

**Impact:** 500+ match expressions across gerbil projects.

### 9. `translate-spawn-forms` — Concurrency Syntax
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Verify/translate concurrency forms:
- `(spawn thunk)` → pass-through (jerboa core has spawn)
- `(spawn/name name thunk)` → pass-through (jerboa core has it)
- `(<- expr)` actor receive → verify pass-through

**Impact:** 460 call sites across gerbil projects.

### 10. `translate-package-to-library` — Full File Structure Translation
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Transform a complete Gerbil file structure to R6RS library:
- `(package: :foo/bar)` + `(export ...)` + body → `(library (foo bar) (export ...) (import ...) body)`
- Auto-detect imports from `(import ...)` forms
- Handle `(namespace ...)` directives (strip them)

**Impact:** Every Gerbil source file needs this for a full port.

---

## Missing Standard Library Modules (11–20)

### 11. `(std misc pqueue)` — Priority Queue
**Status:** DONE
**File:** `lib/std/misc/pqueue.sls`

Binary heap priority queue with:
- `make-pqueue`, `pqueue?`, `pqueue-empty?`, `pqueue-length`
- `pqueue-push!`, `pqueue-pop!`, `pqueue-peek`
- Optional custom comparator
- `pqueue->list`, `pqueue-for-each`

**Impact:** Used in scheduling, graph algorithms, event-driven systems.

### 12. `(std misc barrier)` — Thread Barrier
**Status:** DONE
**File:** `lib/std/misc/barrier.sls`

Cyclic barrier for thread synchronization:
- `make-barrier`, `barrier?`, `barrier-wait!`
- `barrier-reset!`, `barrier-parties`
- Reusable (cyclic) — automatically resets after all parties arrive

**Impact:** Parallel algorithm coordination.

### 13. `(std misc timeout)` — Timeout Operations
**Status:** DONE
**File:** `lib/std/misc/timeout.sls`

Timeout-wrapped operations using Chez's engine system:
- `with-timeout` — run thunk with time limit, return default on timeout
- `timeout?` — predicate for timeout sentinel
- `make-timeout` — timeout value constructor

Leverages Chez Scheme's `make-engine` for preemptive time-slicing — a
capability Gambit doesn't have. Engines provide tick-based fuel that the
compiler integrates at safe points, giving precise timeout control without
spawning extra threads.

**Impact:** Network operations, database queries, any blocking operation.

### 14. `(std misc func)` — Functional Combinators
**Status:** DONE
**File:** `lib/std/misc/func.sls`

Core functional utilities scattered across Gerbil projects:
- `compose`, `compose1` — function composition
- `identity` — identity function
- `constantly` — constant-returning function
- `flip` — swap first two arguments
- `curry`, `curryn` — partial application
- `memo-proc` — simple memoization wrapper
- `negate` — predicate negation
- `conjoin`, `disjoin` — predicate AND/OR

**Impact:** Foundational utilities used across every functional codebase.

### 15. `(std misc repr)` — Object Representation Protocol
**Status:** DONE
**File:** `lib/std/misc/repr.sls`

Custom print representations for user-defined types:
- `defmethod {write-repr obj port}` pattern
- `repr` — convert any object to readable string
- `display-repr` — write repr to port
- Default representations for records, hash tables, closures

**Impact:** Debugging, logging, REPL output for custom types.

### 16. `(std event)` — First-Class Events
**Status:** DONE
**File:** `lib/std/event.sls`

Gerbil's event system (NOT the existing event-emitter pub/sub):
- `sync`, `select` — synchronize on first-ready event
- `choice` — combine events
- `wrap`, `handle` — transform event results
- `timeout-evt` — event that fires after delay
- `channel-recv-evt`, `channel-send-evt` — channel events
- `always-evt`, `never-evt` — constant events

Leverages Chez's condition variables and the existing channel infrastructure.

**Impact:** Concurrent programming patterns from gerbil-origin, gerbil-persist.

### 17. `(std stxutil)` — Syntax Utilities
**Status:** DONE
**File:** `lib/std/stxutil.sls`

Macro-writing helpers:
- `stx-car`, `stx-cdr`, `stx-null?`, `stx-pair?` — syntax object accessors
- `stx-map`, `stx-for-each` — iterate over syntax lists
- `stx->datum`, `datum->stx` — conversion (aliases for syntax->datum etc.)
- `with-syntax*` — sequential with-syntax bindings
- `genident` — generate unique identifier

**Impact:** Any project defining macros.

### 18. `(std contract)` — Design by Contract
**Status:** DONE
**File:** `lib/std/contract.sls`

Contracts for defensive programming:
- `define/contract` — define with pre/post conditions
- `->` — function contract (domain → range)
- `->*` — function contract with optional/keyword args
- `contract-violation?` — predicate
- `check-argument` — argument validation with clear errors

**Impact:** API boundary validation, library quality.

### 19. `(std misc rwlock)` — Read-Write Lock
**Status:** DONE
**File:** `lib/std/misc/rwlock.sls`

Multiple-reader/single-writer lock:
- `make-rwlock`, `rwlock?`
- `rwlock-read-lock!`, `rwlock-read-unlock!`
- `rwlock-write-lock!`, `rwlock-write-unlock!`
- `with-read-lock`, `with-write-lock` — RAII-style macros

Leverages Chez's efficient mutex and condition variable primitives.

**Impact:** Concurrent data structure access patterns.

### 20. `(std misc symbol)` — Symbol Utilities
**Status:** DONE
**File:** `lib/std/misc/symbol.sls`

Symbol manipulation matching Gerbil patterns:
- `symbol-append` — concatenate symbols: `(symbol-append 'make- 'point)` → `make-point`
- `symbol->keyword`, `keyword->symbol` — interconversion
- `make-symbol` — alias for `symbol-append`
- `interned-symbol?` — check if symbol is interned (uses Chez's gensym detection)

**Impact:** Code generation, macro writing, serialization.

---

## Chez Scheme Power Features (21–27)

### 21. `(std engine)` — Preemptive Evaluation Engines
**Status:** DONE
**File:** `lib/std/engine.sls`

Expose Chez's unique engine system (time-sliced evaluation):
- `make-engine` — create an engine from a thunk
- `engine-run` — run engine for N ticks
- `engine-result` — get result if completed
- `engine-expired?` — check if ticks exhausted
- `engine-map` — transform engine result

Chez's engine system is unique among Scheme implementations — Gambit has
nothing comparable. It provides cooperative preemption at compiler-inserted
safe points, enabling timeout, resource limiting, and sandboxing without
threads.

**Impact:** Sandboxed evaluation, resource-limited computation, REPL timeouts.

### 22. `(std fasl)` — Fast-Load Serialization
**Status:** DONE
**File:** `lib/std/fasl.sls`

Expose Chez's binary serialization for high-performance data exchange:
- `fasl-write` — serialize any Scheme datum to binary
- `fasl-read` — deserialize from binary
- `fasl-file-write`, `fasl-file-read` — file-level operations
- Handles: pairs, vectors, records, bytevectors, bignums, symbols, etc.

Much faster than JSON/S-expr serialization for large data structures.
Chez FASL handles cycles and shared structure correctly.

**Impact:** Cache files, IPC, persistent data structures.

### 23. `(std inspect)` — Runtime Inspection
**Status:** DONE
**File:** `lib/std/inspect.sls`

Expose Chez's inspector API for debugging:
- `inspect-object` — get type, fields, and values of any object
- `inspect-procedure` — get source, arity, free variables of a closure
- `inspect-condition` — extract all fields from a condition
- `inspect-code` — disassemble a compiled procedure
- `object-counts` — count live objects by type (GC statistics)

**Impact:** REPL inspection, debugging tools, memory profiling.

### 24. `(std ephemeron)` — Ephemeron Tables
**Status:** DONE
**File:** `lib/std/ephemeron.sls`

Expose Chez's ephemeron support (GC-aware weak references):
- `make-ephemeron-eq-hashtable` — hash table where entries are GC'd when key is unreachable
- `ephemeron-pair`, `ephemeron-pair?` — raw ephemeron pairs
- `make-weak-eq-hashtable` — weak-key hash table

Ephemerons are stronger than weak references: an ephemeron's value is
only traced if its key is reachable through non-ephemeron paths.
Perfect for caches and observer patterns.

**Impact:** Memory-safe caching, observer patterns, interning tables.

### 25. `(std ftype)` — Foreign Type Definitions
**Status:** DONE
**File:** `lib/std/ftype.sls`

Expose Chez's ftype system for structured FFI:
- `define-ftype` — define C-compatible struct/union types
- `ftype-ref`, `ftype-set!` — field access
- `make-ftype-pointer` — allocate foreign memory
- `ftype-pointer?` — type predicate
- `ftype-sizeof` — size of foreign type

Chez's ftype system is far more expressive than Gambit's c-define-type,
supporting bit fields, unions, endianness control, and nested structs.

**Impact:** FFI-heavy projects, system programming.

### 26. `(std compress lz4)` — LZ4 Compression
**Status:** DONE
**File:** `lib/std/compress/lz4.sls`

LZ4 compression using Chez's built-in support or FFI:
- `lz4-compress` — compress bytevector
- `lz4-decompress` — decompress bytevector
- `make-lz4-compress-port` — streaming compression
- `make-lz4-decompress-port` — streaming decompression

Chez has built-in port compression support; expose it at the bytevector level.

**Impact:** Data storage, network protocols, log compression.

### 27. `(std profile)` — Profiling Utilities
**Status:** DONE
**File:** `lib/std/profile.sls`

Wrap Chez's profiling infrastructure:
- `with-profile` — profile a thunk, return timing/allocation stats
- `profile-dump` — dump profile data as alist
- `time-it` — simple wall-clock timing with display
- `allocation-count` — count bytes allocated during a thunk

Chez has `(time expr)` but no programmatic API. This wraps the internal
`statistics` and profiling counters.

**Impact:** Performance optimization, benchmarking.

---

## Quality of Life (28–30)

### 28. `(std misc hash-more)` — Extended Hash Table Operations
**Status:** DONE
**File:** `lib/std/misc/hash-more.sls`

Hash operations missing from jerboa's runtime but common in Gerbil code:
- `hash-filter` — filter entries by predicate
- `hash-map/values` — map over values only
- `hash-ref/default` — explicit default (vs hash-ref's error)
- `hash-value-set!` — alias for hash-put! (Gerbil naming)
- `hash->alist` — alias for hash->list with explicit key-value pairs
- `hash-union` — merge with conflict resolution function
- `hash-intersect` — intersection of two hash tables

**Impact:** Data manipulation in every project.

### 29. `(std misc string-more)` — Extended String Operations
**Status:** DONE
**File:** `lib/std/misc/string-more.sls`

String operations from Gerbil's `:std/misc/string` not yet in jerboa:
- `string-prefix?`, `string-suffix?` — test prefix/suffix
- `string-contains?` — substring search predicate
- `string-trim-both` — trim both ends (alias for string-trim in some contexts)
- `string-join` — join list of strings with separator
- `string-repeat` — repeat string N times
- `string-index` — find first occurrence of char/pred
- `string-pad-left`, `string-pad-right` — padding

**Impact:** String processing in every project.

### 30. `(std misc list-more)` — Extended List Operations
**Status:** DONE
**File:** `lib/std/misc/list-more.sls`

List operations from Gerbil that aren't in jerboa core or SRFI-1:
- `flatten` — deep flatten nested lists
- `group-by` — group list elements by key function
- `partition-by` — partition based on predicate (returns two lists)
- `zip-with` — zip with combining function
- `interleave` — interleave two lists
- `chunk` — split list into sublists of size N
- `unique` — remove duplicates (with optional equality)
- `frequencies` — count occurrences as hash table

**Impact:** Data transformation pipelines in every project.

---

## Implementation Tracking

All 30 features implemented. 202 tests passing in `tests/test-better.ss`.

| # | Feature | Status | Tests | Docs | Committed |
|---|---------|--------|-------|------|-----------|
| 1 | translate-method-dispatch | DONE | 5 | inline | YES |
| 2 | translate-defrules | DONE | 3 | inline | YES |
| 3 | translate-defstruct enhanced | DONE | 6 | inline | YES |
| 4 | translate-hash-literal | DONE (pass-through) | 1 | inline | YES |
| 5 | translate-try-catch | DONE | 2 | inline | YES |
| 6 | translate-export | DONE | 5 | inline | YES |
| 7 | translate-for-loops | DONE (pass-through) | 1 | inline | YES |
| 8 | translate-match-patterns | DONE (pass-through) | 1 | inline | YES |
| 9 | translate-spawn-forms | DONE (pass-through) | 1 | inline | YES |
| 10 | translate-package-to-library | DONE | 3 | inline | YES |
| 11 | pqueue | DONE | 13 | inline | YES |
| 12 | barrier | DONE | 4 | inline | YES |
| 13 | timeout | DONE | 5 | inline | YES |
| 14 | func | DONE | 16 | inline | YES |
| 15 | repr | PRE-EXISTING | — | — | YES |
| 16 | event | DONE | 5 | inline | YES |
| 17 | stxutil | DONE | 10 | inline | YES |
| 18 | contract | DONE | 7 | inline | YES |
| 19 | rwlock | PRE-EXISTING | — | — | YES |
| 20 | symbol utils | DONE | 6 | inline | YES |
| 21 | engine | DONE | 5 | inline | YES |
| 22 | fasl | DONE | 4 | inline | YES |
| 23 | inspect | DONE | 9 | inline | YES |
| 24 | ephemeron | DONE | 5 | inline | YES |
| 25 | ftype | DONE | 7 | inline | YES |
| 26 | lz4 | DONE | 2 | inline | YES |
| 27 | profile | DONE | 6 | inline | YES |
| 28 | hash-more | DONE | 21 | inline | YES |
| 29 | string-more | DONE | 19 | inline | YES |
| 30 | list-more | DONE | 19 | inline | YES |
