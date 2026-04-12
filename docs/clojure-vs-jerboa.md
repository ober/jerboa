# Clojure vs Jerboa: Feature Gap Analysis

A comprehensive inventory of what Clojure offers that Jerboa/Chez Scheme doesn't (or has in weaker form), with detailed explanations of what each feature does and why Clojure developers consider it a game-changer.

Organized from most foundational to most specialized. Status markers:

- **[landed]** — shipped in Jerboa; see the section for the module name
- **[partial]** — some of the feature exists, some parts still missing
- **[open]** — real gap, still worth implementing
- **[deferred]** — real gap, intentionally deferred (see section for reasoning)
- **[non-goal]** — deliberately not pursued (see section)

Last updated: 2026-04-11 after Phase E of the Clojure-compat campaign (metadata, multimethods, protocols, atom watches, agents, record-as-map). See [`clojure-remaining.md`](./clojure-remaining.md) for the campaign's own design doc.

---

## Table of Contents

1. [The Philosophical Foundation](#1-the-philosophical-foundation)
2. [Persistent Immutable Data Structures](#2-persistent-immutable-data-structures) **[landed]**
3. [Transients](#3-transients) **[landed]**
4. [The Unified Sequence Abstraction](#4-the-unified-sequence-abstraction) **[partial]**
5. [Lazy Sequences](#5-lazy-sequences) **[open]**
6. [Transducers](#6-transducers) **[landed]**
7. [Reducers](#7-reducers) **[open]**
8. [The Four Reference Types](#8-the-four-reference-types) **[partial]** — atoms, agents, volatiles landed; refs (STM) open
9. [Software Transactional Memory (STM)](#9-software-transactional-memory-stm) **[open]**
10. [core.async (CSP Channels)](#10-coreasync-csp-channels) **[landed]** — minus parked-go CPS
11. [Protocols](#11-protocols) **[landed]**
12. [Multimethods](#12-multimethods) **[landed]**
13. [Records and Types](#13-records-and-types) **[landed]**
14. [Destructuring Everywhere](#14-destructuring-everywhere) **[partial]**
15. [Metadata](#15-metadata) **[landed]**
16. [Dynamic Vars and Thread-Local Binding](#16-dynamic-vars-and-thread-local-binding) **[partial]**
17. [Clojure Spec](#17-clojure-spec) **[non-goal]**
18. [Namespaces](#18-namespaces) **[partial]**
19. [EDN and Tagged Literals](#19-edn-and-tagged-literals) **[open]**
20. [Reader Conditionals](#20-reader-conditionals) **[deferred]**
21. [Rich Number Tower](#21-rich-number-tower) **[landed]** (via Chez)
22. [Keyword/Symbol Semantics](#22-keywordsymbol-semantics) **[partial]**
23. [`loop`/`recur` and Tail Calls](#23-looprecur-and-tail-calls) **[landed]** (proper TCO via Chez)
24. [`for` Comprehensions](#24-for-comprehensions) **[partial]**
25. [Delays, Futures, and Promises](#25-delays-futures-and-promises) **[partial]**
26. [Memoize, Trampoline, and Friends](#26-memoize-trampoline-and-friends) **[partial]**
27. [Exception Design: ex-info](#27-exception-design-ex-info) **[open]**
28. [core.match](#28-corematch) **[landed]**
29. [core.logic (miniKanren)](#29-corelogic-minikanren) **[open]**
30. [Zippers](#30-zippers) **[open]**
31. [Specter](#31-specter) **[open]**
32. [Datafy / Nav](#32-datafy--nav) **[open]**
33. [clojure.walk](#33-clojurewalk) **[open]**
34. [Set Operations](#34-set-operations) **[landed]**
35. [Property-Based Testing (test.check)](#35-property-based-testing-testcheck) **[open]**
36. [Component Lifecycle Libraries](#36-component-lifecycle-libraries) **[open]**
37. [REPL-Driven Development Culture](#37-repl-driven-development-culture) **[partial]**
38. [Miscellaneous Small Things That Add Up](#38-miscellaneous-small-things-that-add-up) **[partial]**

**See also:** [Where to focus next](#still-worth-implementing-as-of-2026-04-11) — a condensed roadmap of the remaining open items ranked by value/effort.

---

## 1. The Philosophical Foundation

Before features, Clojure's mindset:

### Identity vs Value (Rich Hickey's Model)

**Values** are immutable things: the number 42, the string "hello", the map `{:a 1}`. They never change. Two values that are equal are indistinguishable.

**Identities** are named things that *change what value they point to* over time. A bank account isn't a number that mutates; it's an identity whose value at time T is some immutable balance.

Every Clojure reference type (atom, ref, agent, var) embodies this split: the reference is the identity, swapping pointers; the value it points to is always immutable. This is why Clojure concurrency "just works" — readers can never see a half-mutated value, because values don't mutate at all. They are replaced atomically.

**Why this matters for Jerboa**: Scheme has `set!` everywhere and mutable cons cells, boxes, and vectors. To get Clojure's guarantees you need to *culturally* commit to persistent structures and discipline around mutation, plus the reference types described below.

### Code is Data (Homoiconicity) + The Reader

All Lisps are homoiconic, but Clojure's reader ships with rich literal forms:
- `[1 2 3]` — persistent vector
- `{:a 1 :b 2}` — persistent map
- `#{1 2 3}` — persistent set
- `'(1 2 3)` — persistent list
- `#"regex"` — compiled regex literal
- `#inst "2026-04-10"` — tagged literal for instant
- `#uuid "..."` — tagged UUID
- `#_form` — reader-level comment, skips next form

Jerboa has `[...]` aliased to `(...)` and has strings/numbers, but no literal map/set/vector with distinct types, no tagged literal extension mechanism for the reader.

---

## 2. Persistent Immutable Data Structures

**Status in Jerboa**: **[landed]** — `(std pmap)` / `(std pvec)` / `(std pset)` / `(std pqueue)` / `(std sorted-set)`. All HAMT-based where applicable, structural equality and hashing, polymorphic iteration via `(std iter)`.

Clojure's defining technical achievement. Four core persistent collections, all implemented via **Hash Array Mapped Tries (HAMT)** or variants, giving effectively-O(1) (really O(log32 N)) updates with **structural sharing**.

### PersistentVector
```clojure
(def v [1 2 3 4 5])
(conj v 6)        ; => [1 2 3 4 5 6]  — v is unchanged
(assoc v 0 99)    ; => [99 2 3 4 5]
(pop v)           ; => [1 2 3 4]
(nth v 2)         ; => 3
(subvec v 1 3)    ; => [2 3]
```
Implemented as a 32-way trie. Random access, append, and update are all O(log32 N) ≈ O(1) in practice. Old versions remain valid and consume negligible extra memory due to sharing.

### PersistentHashMap
```clojure
(def m {:a 1 :b 2})
(assoc m :c 3)           ; => {:a 1 :b 2 :c 3}
(dissoc m :a)            ; => {:b 2}
(get m :a)               ; => 1
(:a m)                   ; => 1   (keywords are functions!)
(merge m {:d 4})         ; => {:a 1 :b 2 :d 4}
(update m :a inc)        ; => {:a 2 :b 2}
(update-in m [:a] + 10)  ; => {:a 11 :b 2}
```
The workhorse. HAMT-based. The `update`/`update-in`/`assoc-in` functions let you "modify" deeply nested data trivially:
```clojure
(update-in state [:users 42 :profile :email] clojure.string/lower-case)
```

### PersistentHashSet
```clojure
(def s #{1 2 3})
(conj s 4)          ; => #{1 2 3 4}
(disj s 2)          ; => #{1 3}
(contains? s 1)     ; => true
(s 1)               ; => 1    (sets are functions of their members!)
```

### PersistentList / PersistentQueue
Lists are the classic singly-linked list but immutable. Queues are O(1) persistent FIFO: `(conj q x)` adds to tail, `(pop q)` removes from head, `(peek q)` sees head.

### Why This Is a Game-Changer

1. **Fearless sharing**: Pass a map to another thread, another function, into a channel — no defensive copies, ever.
2. **Time travel / undo**: Keep a list of previous states. Each takes trivial extra memory.
3. **Reasoning**: If you have a reference to a value, nobody can change it from under you.
4. **Compositional updates**: `assoc-in`, `update-in`, `merge-with`, `get-in`.
5. **Equality by value**: Two maps are `=` iff they contain the same entries. Same for nested structures. Hashes are structural.

### Jerboa Status

Jerboa now has the full family:

- `(std pmap)` — HAMT persistent map with O(log32 N) assoc/dissoc/lookup, structural equality, structural hashing. Also exported as `imap` via `(std immutable)`. Records participate polymorphically: `(get point 'x)`, `(keys point)`, etc.
- `(std pvec)` — 32-way persistent vector, O(log32 N) assoc/conj/pop/nth, structural equality.
- `(std pset)` — HAMT persistent set, structural equality, union/intersection/difference.
- `(std pqueue)` — O(1) amortized persistent FIFO queue.
- `(std sorted-set)` — ordered persistent set with range queries.
- Update-in-style operations (`get-in`, `assoc-in`, `update-in`) live in `(std misc nested)` and dispatch polymorphically over all of the above plus records, concurrent-hash, hash-table, and vector.

---

## 3. Transients

A sidekick to persistent data: **transients** are a mutable "building mode" for persistent collections.

```clojure
(defn build-big-vec [n]
  (persistent!
    (reduce (fn [v i] (conj! v i))
            (transient [])
            (range n))))
```

`transient` turns a persistent collection into an ephemeral mutable one — *but only the thread that created it can use it*. You batch mutations (`conj!`, `assoc!`, `dissoc!`), then call `persistent!` to freeze it back. The internal structure is shared with the result, so this is much faster than repeated `conj`/`assoc` when building large collections in a loop.

The genius: transients give you mutability's performance without losing immutability's semantics, as long as you don't leak the transient across threads.

**Jerboa status**: **[landed]**. Each of the persistent types has a transient sidekick:

- `imap-transient` / `tmap-set!` / `tmap-delete!` / `persistent-map!` for pmap.
- `pvec-transient` / `transient-set!` / `transient-append!` / `pvec-persistent!` for pvec.
- `pset` has `pset-persistent!` for bulk building.

`(std clojure)` exposes the Clojure-style surface: `transient`, `persistent!`, `assoc!`, `dissoc!`, `conj!`. The typical "build a big collection in a loop" pattern gets the Clojure perf story without losing the immutable API on the outside.

---

## 4. The Unified Sequence Abstraction

`seq` is Clojure's universal iteration abstraction. Anything "seqable" — list, vector, map, set, string, Java iterable, lazy seq, channel poll — can be treated through the same API:

```clojure
(first coll)    ; first element or nil
(rest coll)     ; remaining elements as seq
(next coll)     ; like rest but nil if empty
(cons x coll)   ; prepend
(seq coll)      ; coerce to seq, nil if empty
```

Every higher-order operation — `map`, `filter`, `reduce`, `take`, `drop`, `take-while`, `drop-while`, `partition`, `partition-by`, `partition-all`, `interpose`, `interleave`, `mapcat`, `iterate`, `cycle`, `repeat`, `repeatedly`, `range`, `distinct`, `dedupe`, `frequencies`, `group-by`, `sort-by`, `keep`, `keep-indexed`, `map-indexed`, `reductions`, `tree-seq`, `flatten`, `zipmap`, `split-at`, `split-with` — takes and/or returns seqs.

Because of this uniformity, once you learn 40 sequence functions, they work on *everything*.

**Jerboa status**: **[partial]**. Very good functional coverage: `for/collect`, `for/fold`, `map`, `filter`, `flatten`, `unique`, `take`, `drop`, `every`, `any`, `filter-map`, `group-by`, `zip`, `frequencies`, `partition`, `interleave`, `mapcat`, `distinct`, `keep`, `split-at`, `append-map`, `snoc`. Two runtime-polymorphic layers have landed since the original writeup:

- `(std iter)` — a polymorphic iteration protocol that `for` can consume, bridging pmap/pset/pvec/list/vector/string uniformly.
- `(std clojure)` — `first`/`rest`/`next`/`last`/`seq`/`reduce`/`into` dispatch polymorphically over all the persistent types, plus records-as-maps.

What's still not there is a **lazy** unified seq — Clojure's `seq` abstraction is lazy by default, and Jerboa's polymorphic iteration is eager. That's §5 territory.

---

## 5. Lazy Sequences

Sequences in Clojure are **lazy by default**. `(map f coll)` does not walk `coll`; it returns a lazy sequence that realizes elements on demand.

```clojure
(def naturals (iterate inc 0))         ; infinite!
(take 10 naturals)                      ; => (0 1 2 3 4 5 6 7 8 9)

(def squares (map #(* % %) naturals))   ; infinite, not computed
(take 5 squares)                        ; => (0 1 4 9 16)

(defn primes-from [n]
  (cons n (lazy-seq (primes-from (+ n 1)))))  ; build your own
```

Key operators:
- `lazy-seq` — the primitive; delays a sequence expression
- `iterate f x` — `(x (f x) (f (f x)) ...)` infinite
- `repeat x` / `repeat n x` — infinite or n copies
- `repeatedly f` / `repeatedly n f` — call f on demand
- `cycle coll` — infinite repetition of coll
- `range`, `range n`, `range start end`, `range start end step` — optionally infinite

Laziness composes naturally with `take`, `take-while`, `drop-while`. You can write algorithms that look like they process infinite data, and they do, one element at a time.

**Gotchas Clojure exposes**: chunking (realizes 32 at a time for efficiency), head retention (holding the head of a lazy seq prevents GC of realized elements), and `doall`/`dorun` for forcing.

**Jerboa status**: **[open]**. Chez's lazy library exists but isn't in the prelude. `in-producer` gives some of this via `for`. No culture of lazy-by-default; you build with eager collections and decide to go lazy. A `lazy-seq` macro integrated into the prelude plus `cycle`/`repeat`/infinite `iterate`/`take-while`/`drop-while` would close most of the gap. Tier 2 in the roadmap below.

---

## 6. Transducers

Introduced in Clojure 1.7, transducers are **composable algorithmic transformations decoupled from their input and output**.

### The problem they solve

Consider:
```clojure
(->> data
     (map inc)
     (filter even?)
     (take 10))
```

In classical Clojure, each step produces an intermediate lazy sequence. With large data or tight loops, that's allocation overhead. Also, the same logical pipeline has to be rewritten for different contexts: sequences vs channels vs streams.

### The transducer idea

A transducer is a function that takes a *reducing function* and returns a new reducing function. `map`, `filter`, `take`, etc., all have **arity-1 forms** that return transducers:

```clojure
(def xf (comp (map inc) (filter even?) (take 10)))   ; a transducer
```

This `xf` is just a function composition. Now apply it in any context:

```clojure
(into [] xf data)              ; build a vector, no intermediate seqs
(sequence xf data)             ; lazy sequence
(transduce xf + 0 data)        ; reduce to a number
(chan 10 xf)                   ; a core.async channel that transforms values
(eduction xf data)             ; reusable reducible
```

The same pipeline works over eager collections, lazy seqs, channels, and reducibles. Zero intermediate collections. Compose with `comp`.

### Why it's a game-changer

- **Performance**: no intermediate allocations
- **Reusability**: one pipeline, many contexts
- **Composability**: `comp` chains them; you can build libraries of reusable transformations
- **Channel transformation**: core.async channels can apply a transducer as values flow through — extremely elegant for stream processing

### The formal definition

```clojure
;; A transducer:
(fn [rf]                      ; takes a reducing function (acc, input -> acc)
  (fn
    ([] (rf))                 ; init arity
    ([acc] (rf acc))          ; completion arity
    ([acc input] ...)))       ; step arity
```

Most people never write raw transducers — they compose `map`, `filter`, `mapcat`, `take`, `drop`, `dedupe`, `distinct`, `partition-by`, `partition-all`, `map-indexed`, `keep`, `keep-indexed`, `cat` (catenating transducer), `halt-when`, `interpose`, `random-sample`.

### Jerboa status

**[landed]** — `(std transducer)` ships a full transducer library with the standard cast: `tmap`, `tfilter`, `tmapcat`, `ttake`, `tdrop`, `tdistinct`, `tdedupe`, `tpartition-by`, `tpartition-all`, `tkeep`, `ttake-while`, `tdrop-while`, `tinterpose`, `thalt-when`, etc. Composed with `comp`, applied with `transduce` or `into`, and wired into CSP channels via `(chan n xform)` so transducers transform values as they flow through `(std csp)` pipelines. `(into [] xform data)` works uniformly over lists, vectors, pmaps, psets, pvecs. Zero intermediate allocation.

---

## 7. Reducers

An earlier (2012) attempt at the same composition problem that lives on alongside transducers. `clojure.core.reducers` provides:

- `r/map`, `r/filter`, `r/mapcat`, `r/take`, `r/drop` — return **reducibles** (things that know how to reduce themselves), not seqs
- `r/fold` — parallel reduce via fork/join, splits the work across cores automatically for supported collections (vectors and maps)
- `r/reduce`, `r/foldcat`

```clojure
(require '[clojure.core.reducers :as r])
(r/fold + (r/map inc (r/filter odd? big-vector)))    ; parallel!
```

The `fold` bit is the key — Clojure automatically parallelizes the reduction for persistent vectors/maps using a divide-and-conquer `combine-fn`.

**Jerboa status**: **[open]**. No parallel fold. `pmap` exists but no reducer-level parallelism that automatically splits collections via a divide-and-conquer combine function. Chez has threads; the primitives are there. This would need a split protocol on pvec and pmap that returns two halves, plus a fork/join driver. Tier 2.

---

## 8. The Four Reference Types

Clojure's unified concurrency model. All four embody identity-vs-value, differing on (a) sync vs async and (b) coordinated vs uncoordinated.

|             | **Uncoordinated**       | **Coordinated** |
|-------------|-------------------------|-----------------|
| **Sync**    | `atom`                  | `ref` (STM)     |
| **Async**   | `agent`                 | —               |

Plus `var` for thread-local dynamic binding.

### Atom

**Status in Jerboa**: **[landed]** — `(std misc atom)` and re-exported from the prelude. Includes `add-watch!` / `remove-watch!`, `set-validator!`, and `volatile!` / `vreset!` / `vswap!` / `vderef` for single-thread-fast volatiles.

```clojure
(def counter (atom 0))
@counter                          ; deref: 0
(swap! counter inc)               ; atomically: 1
(swap! counter + 10)              ; 11
(reset! counter 0)                ; 0
(compare-and-set! counter 0 42)   ; CAS
```

Uses compare-and-swap. `swap!`'s function may retry if another thread raced — so the function **must be pure**. No coordination with other refs.

Also:
- `add-watch` — register a callback on change
- `remove-watch`
- `set-validator!` — reject invalid values

### Ref

The STM reference. See section [9](#9-software-transactional-memory-stm).

### Agent

An identity that updates asynchronously:
```clojure
(def a (agent 0))
(send a inc)                      ; queue a fn; returns immediately
(send-off a slow-io-fn)           ; for blocking IO, uses unbounded pool
@a                                ; may or may not have applied yet
(await a)                         ; block until all queued actions done
```

Key properties:
- Actions are queued and applied serially per-agent (no races on a single agent).
- Errors set the agent to a failed state; `agent-error`, `restart-agent`.
- `send` uses a fixed thread pool; `send-off` uses unbounded (for IO-bound work).
- Combines naturally with STM: within a `dosync`, `send` is deferred until commit.

### Var and Dynamic Binding

See section [16](#16-dynamic-vars-and-thread-local-binding).

**Jerboa status**: **[partial]**. Atoms, volatiles, and agents have landed; STM refs are still open.

- **Atoms** — `(std misc atom)`, with watches and validators.
- **Volatiles** — `(std misc atom)`, for cases where you want a mutable cell without CAS.
- **Agents** — `(std agent)`. A dedicated worker thread per agent, backed by a CSP channel queue. `send` / `send-off` / `await` / `agent-error` / `agent-value` / `restart-agent` / `shutdown-agent!` / `clear-agent-errors` all present. Matches Clojure's `:fail` error-mode semantics: if an action throws, the agent enters an error state and further sends raise until `restart-agent` is called.
- **Refs (STM)** — still open. See §9.

---

## 9. Software Transactional Memory (STM)

Clojure's most distinctive concurrency primitive. Coordinated, synchronous updates across multiple refs with ACI guarantees (no D — STM isn't durable).

```clojure
(def account-a (ref 100))
(def account-b (ref 0))

(defn transfer [from to amount]
  (dosync
    (alter from - amount)
    (alter to + amount)))

(transfer account-a account-b 30)
```

Inside `dosync`:
- Reads use `@ref` or `(deref ref)`.
- Writes use `alter`, `ref-set`, or `commute`.
- If another transaction committed to a ref you read or wrote, your transaction **automatically retries**.
- All updates commit atomically or none do.
- The body must be **side-effect free** (it may be rerun). Use `agents` or explicit `io!` blocks for side effects.

### `commute` vs `alter`
- `alter` requires that the ref hasn't changed since you read it. Strict ordering.
- `commute` lets concurrent transactions interleave if the update is commutative (e.g. `+`, `conj`). Can improve throughput dramatically.

### `ensure`
- Prevents another transaction from modifying a ref you read, without actually writing to it. For when a read needs to be protected.

### Why it matters

Lock-based concurrency is notoriously error-prone: deadlocks, lock ordering, forgotten unlocks, coarse-vs-fine granularity tradeoffs. STM sidesteps all of that: you write the transaction as if you had exclusive access; the runtime ensures isolation via optimistic concurrency and retry.

**Cost**: transactions can't do IO (or must be idempotent), and contention leads to retry churn. But for "update these five refs consistently" problems, nothing is as ergonomic.

**Jerboa status**: **[open]**. None of STM exists yet. Chez has mutexes and condition variables; building STM requires:

1. Version counters on refs.
2. Transaction-local read/write sets.
3. A commit protocol with conflict detection.
4. Retry semantics.

It's a significant engineering project, but the abstraction is well-specified. Atoms + agents cover ~80% of the "I need concurrent state" use cases; STM matters most when you need to coordinate updates across multiple refs atomically (transfer-money problems). A scaled-down STM that coordinates 2–8 refs per transaction is dramatically simpler than a fully general one and covers most practical uses.

---

## 10. core.async (CSP Channels)

**Status in Jerboa**: **[landed]** — `(std csp)`. Channels, `go`, `alts!`, transducer-backed channels via `(chan n xform)`, buffers (fixed, dropping, sliding), `timeout`, `pipe`, `pipeline`, `mult`/`tap`, `pub`/`sub`, `mix`/`admix!`/`unmix!`/`toggle!`, `put!`/`take!` with callbacks, `split`, `onto-chan!`, `async/reduce`. Timer wheel for `timeout` behind `JERBOA_CSP_TIMER_WHEEL`. The one non-landed piece is **parked-go via CPS transformation** — Jerboa's `go` runs on an OS thread rather than a state-machine-transformed continuation, so you can't have a million parked go-blocks on a small thread pool. See [§3.8 in `clojure-remaining.md`](./clojure-remaining.md#38-fully-parked-go-cps-transformed) — it's a research project, indefinitely deferred.

Clojure's CSP-style concurrency library. Not in core but ships with Clojure projects almost universally.

### The basics

```clojure
(require '[clojure.core.async :as a :refer [chan go >! <! >!! <!! close! alts!]])

(def c (chan 10))                     ; buffered channel, capacity 10
(go (>! c "hello"))                    ; async put, parks if full
(go (println (<! c)))                  ; async take, parks if empty
```

- `chan` — unbuffered by default; `(chan n)` fixed buffer; `(chan (dropping-buffer n))`, `(chan (sliding-buffer n))`
- `>!` / `<!` — parking put/take, only inside a `go` block
- `>!!` / `<!!` — blocking put/take, outside go blocks
- `put!` / `take!` — callback-based, lowest level
- `close!` — no more puts; pending takes return `nil`

### `go` blocks

The magic. `go` is a macro that performs **state machine transformation** on its body, turning code with `>!`/`<!` into a continuation-passing machine that **parks** (not blocks) on a channel operation:

```clojure
(go
  (let [x (<! c1)
        y (<! c2)]
    (>! c3 (+ x y))))
```

When `(<! c1)` can't immediately get a value, the go block is suspended without consuming a thread. The scheduler resumes it when `c1` has a value. This lets you have millions of "logical" concurrent workers on a small thread pool.

### `alts!` — select over many channels

```clojure
(go
  (let [[val ch] (alts! [c1 c2 c3])]
    (println "got" val "from" ch)))
```

Also supports `(alts! [[ch val] c2])` — try to put `val` on `ch` OR take from `c2`, whichever can proceed first. `:default` option for non-blocking. `:priority` for ordering.

### Pipelines

- `pipe`, `pipeline`, `pipeline-async`, `pipeline-blocking` — connect channels with transducers and parallelism
- `merge` — combine multiple channels into one
- `mult` / `tap` — broadcast one channel to many
- `pub` / `sub` — topic-based pub/sub
- `mix`/`admix`/`unmix` — dynamically composable input channel

### Transducer integration

```clojure
(chan 10 (comp (map inc) (filter even?)))
```

A channel can apply a transducer to values as they flow. The pipeline steps execute on the put side, inline.

### Why it matters

- Structured concurrent communication without shared mutable state.
- Uniform API across "real threads" (`<!!`) and lightweight go-blocks (`<!`).
- Composes beautifully with transducers.
- Solves the "what if I want millions of workers" problem on a JVM with thousands of OS threads.

**Remaining gap**: Parked `go`. Jerboa's current `go` forks an OS thread; each one costs real stack and scheduling overhead. Clojure's trick is a compile-time CPS transform on the `go` body that turns channel ops into state transitions, so the block's "pending state" is a tiny closure in a scheduler's run queue. That's a research-scale macro project (pattern-match over every Scheme special form, rewrite into CPS, keep source locations). Deferred.

---

## 11. Protocols

Interface-like polymorphism on the **first argument's type**. Like Rust traits but runtime-dispatched, and extensible from outside.

```clojure
(defprotocol Shape
  (area [this])
  (perimeter [this]))

(defrecord Circle [radius]
  Shape
  (area [this] (* Math/PI radius radius))
  (perimeter [this] (* 2 Math/PI radius)))

(defrecord Rectangle [w h]
  Shape
  (area [this] (* w h))
  (perimeter [this] (* 2 (+ w h))))

(area (->Circle 5))        ; => 78.54...
```

### The killer feature: extend from outside

```clojure
(extend-protocol Shape
  String
  (area [s] (count s))
  (perimeter [s] 0))
```

You can make **types you didn't define** (including built-in types, Java types) satisfy your protocol. This solves the **expression problem**: you can add new operations over existing types, and new types supporting existing operations, without modifying either.

Also: `extend-type`, `reify` (anonymous implementation of a protocol), `satisfies?` (runtime check).

### Performance

Protocol dispatch is extremely fast — compiles to a type-keyed cache that becomes direct dispatch after warmup. Near-virtual-call speed.

**Jerboa status**: **[landed]** — `(std protocol)`. Exports `defprotocol`, `extend-type`, `extend-protocol`, `reify`, `satisfies?`. Method dispatch uses a type-keyed cache that becomes near-direct after warmup. Protocols can be extended to any type — records, built-ins, custom types — from outside their definition site, solving the expression problem. Jerboa's older struct-bound `defmethod` is still there for single-dispatch on first-arg type; protocols are the preferred path for new code.

---

## 12. Multimethods

Where protocols dispatch on the first argument's class, **multimethods dispatch on the value of an arbitrary dispatch function**:

```clojure
(defmulti area :shape-type)

(defmethod area :circle [s]
  (* Math/PI (:radius s) (:radius s)))

(defmethod area :square [s]
  (let [side (:side s)] (* side side)))

(area {:shape-type :circle :radius 5})
```

- The dispatch function can return **any value** (keyword, string, vector, anything).
- Methods match by `isa?` — supports hierarchies!
- `derive`, `underive`, `ancestors`, `parents`, `make-hierarchy` — user-defined taxonomies completely decoupled from class hierarchies.
- `:default` method for fallback.
- `prefer-method` to break ambiguities.

### Dispatch on multiple things

```clojure
(defmulti collide (fn [a b] [(:type a) (:type b)]))
(defmethod collide [:ship :asteroid] [a b] ...)
(defmethod collide [:ship :ship] [a b] ...)
```

True multiple dispatch (CLOS-style).

### Why it matters

Separates "how do I choose which code runs" from "what code runs". Can model taxonomies that cross-cut your type system. Overkill for many things (hence protocols are preferred for type-based dispatch) but invaluable when you need real multi-argument dispatch or value-based dispatch.

**Jerboa status**: **[landed]** — `(std multi)`. Exports `defmulti`, `defmethod` (multimethod arity), `remove-method`, `prefer-method`, `methods`, `get-method`, `derive`, `underive`, `isa?`, `parents`, `ancestors`, `descendants`, `make-hierarchy`. Full taxonomy support via user-defined hierarchies, `:default` fallback, and prefer-method for ambiguity resolution. Vector dispatch works for true multi-argument dispatch: `(defmulti collide (fn [a b] [(:type a) (:type b)]))`.

---

## 13. Records and Types

```clojure
(defrecord Person [name age email])

(def alice (->Person "Alice" 30 "alice@example.com"))
(def alice2 (map->Person {:name "Alice" :age 30 :email "a@b.com"}))

(:name alice)              ; => "Alice"   (behaves like a map!)
(assoc alice :age 31)      ; => #Person{...}  still a Person
(merge alice {:age 31})    ; works, returns Person
(= alice alice2)           ; structural equality
```

Records are:
- **Map-like**: support `get`, `assoc`, `dissoc` (dissoc of a defined field returns a plain map).
- **Type-stamped**: distinguishable by type for protocol dispatch.
- **Performant**: fields are real Java fields, not hash lookups.
- **Protocol-implementing**: can implement protocols inline in the `defrecord` form.
- **Auto-generate**: constructor (`->Person`), map-constructor (`map->Person`), positional factory.

### `deftype`

Lower level: raw type, doesn't implement `=` by field value, no map interface by default. For when you need "I want to implement a protocol efficiently but don't want map overhead."

### `reify`

Anonymous implementation:
```clojure
(reify
  Runnable
  (run [_] (println "running"))
  Shape
  (area [_] 0))
```

Creates an unnamed instance implementing those protocols/interfaces. Like an ad-hoc object.

**Jerboa status**: **[landed]**. Two pieces came together:

- **Protocol-implementing records** via `(std protocol)` + `extend-type` or `extend-protocol`. Any `defstruct` or `defrecord` type can satisfy protocols from outside.
- **Record-as-map** via `(std clojure)`. `defstruct` and `define-record-type` instances now answer to the full polymorphic collection API: `get`, `contains?`, `count`, `empty?`, `keys`, `vals`. Keys coerce symbol/string/keyword. Inherited fields are included in declaration order. `get-in` walks into records nested inside pmaps and vice versa.

The one intentional non-match: `assoc` / `dissoc` on a record **escapes to a persistent-map** instead of returning a new record of the same type. Chez's sealed-record model doesn't expose a generic rebuild path, and the pmap escape is uniform. Users who need to preserve the record type on update should use the record's own field setter or allocate a fresh record via the constructor. `reify` is provided by `(std protocol)` for ad-hoc anonymous implementations. See [`clojure-records-as-maps` in the cookbook](../README.md) for the full pattern.

---

## 14. Destructuring Everywhere

Possibly the feature Clojure programmers miss most in other languages. Destructuring works in `let`, `fn`, `defn`, `loop`, `doseq`, `for`, `if-let`, `when-let`, `receive`, etc.

### Sequential destructuring

```clojure
(let [[a b c] [1 2 3]] ...)
(let [[x & rest] coll] ...)
(let [[a b :as whole] coll] ...)       ; also binds the whole
(let [[[a b] c] [[1 2] 3]] ...)        ; nested
```

### Map destructuring

```clojure
(let [{:keys [name age]} person] ...)
;; equivalent to
(let [name (:name person), age (:age person)] ...)

(let [{name :name, age :age} person] ...)    ; explicit
(let [{:keys [name age] :or {age 0}} p] ...) ; defaults
(let [{:keys [name] :as whole} p] ...)
(let [{:strs [name age]} p] ...)             ; string keys
(let [{:syms [name age]} p] ...)             ; symbol keys
(let [{{:keys [street city]} :address} p] ...) ; nested
```

### In function parameters

```clojure
(defn greet [{:keys [name age]}]
  (str "Hello " name ", age " age))

(defn process [config & {:keys [timeout retries] :or {timeout 30 retries 3}}]
  ...)
;; call: (process cfg :timeout 60 :retries 5)
```

Keyword-argument style falls out of rest + map destructuring.

**Jerboa status**: **[partial]**. `match` provides strong pattern matching, and `using` gives dot-access to struct fields. `let-alist` handles alist-key destructuring. What's missing:

- `(def (f [x y z]) ...)` — destructure a list argument in the parameter position
- `(def (f {:keys [name age]}) ...)` — map destructuring with `:keys` style in function params or `let`
- `:as` for "bind the whole plus the pieces"
- `:or` for defaults on missing keys

This is probably the **single biggest daily-ergonomics gap** for Clojure migrants. A destructuring `def`/`let` macro that desugars to the existing `match` machinery would cover most of it. Tier 1 in the "still worth implementing" list.

---

## 15. Metadata

Every Clojure value of a "reference type" (symbols, vars, collections, functions) can carry a metadata map that doesn't affect equality:

```clojure
(def x ^{:doc "the answer"} 42)                 ; no — numbers can't carry meta
(def v ^{:flagged true} [1 2 3])                ; collection — yes
(meta v)                                         ; => {:flagged true}
(with-meta v {:other :data})                    ; new vector with new meta
(vary-meta v assoc :count 3)                    ; update meta

(= v [1 2 3])                                    ; true — metadata doesn't affect =
```

### Shorthand readers

- `^:private` → `^{:private true}`
- `^String x` → `^{:tag String} x` — type hint for the compiler
- `^:const` → compile-time inline constant
- Stackable: `^:private ^String ^{:doc "..."} x`

### Uses

1. **Type hints** for compiler optimization / avoiding reflection.
2. **Docstrings**, `:file`, `:line`, `:column` — every var carries source location.
3. **Flags**: `:private`, `:dynamic`, `:deprecated`, `:const`.
4. **User-defined**: attach arbitrary data to forms for macros to consume.

### `clojure.repl`

Uses metadata heavily: `(doc f)`, `(source f)`, `(dir ns)` — all pulled from var metadata.

**Jerboa status**: **[landed]** — `(std misc meta)`. Exports `with-meta`, `meta`, `vary-meta`, `meta-wrapped?`, `strip-meta`. Uses a wrapper-record approach (rather than modifying every record type to add a metadata slot), so only values you actually call `with-meta` on pay any allocation. `with-meta` replaces rather than nests — `strip-meta` is single-step. `=?` in `(std clojure)` strips meta on both sides, so metadata doesn't affect equality, matching Clojure's contract.

Remaining gap: the shorthand reader syntax `^:private x` / `^String x` / `^{:doc "..."} x` has no equivalent — you write `(with-meta x '((private . #t)))` in long form. Deferred along with the rest of §4.9 reader work; see [`docs/clojure-reader.md`](./clojure-reader.md).

---

## 16. Dynamic Vars and Thread-Local Binding

```clojure
(def ^:dynamic *debug* false)

(defn log [msg]
  (when *debug*
    (println "DEBUG:" msg)))

(log "hi")                          ; (nothing)
(binding [*debug* true]
  (log "hi"))                       ; DEBUG: hi
```

`binding` establishes a **thread-local dynamic scope**. Within the binding form (including everything it calls), `*debug*` has the new value. When the scope exits, the old value is restored.

Also thread-aware: `bound-fn`, `bound-fn*` capture current dynamic bindings so you can start a thread that inherits them.

### Classic uses

- `*out*`, `*in*`, `*err*` — stdin/stdout/stderr are dynamic; `with-out-str` redirects.
- `*print-length*`, `*print-level*` — control REPL output.
- Database connections, HTTP request context, tracing flags.
- Anything you'd otherwise pass through 15 function signatures as a context arg.

### `set!` within bindings

Inside a binding thread, dynamic vars can be `set!` to a new value for the rest of the thread's execution. Lets you update state that started as a dynamic default.

**Jerboa status**: **[partial]**. Chez has `fluid-let`, `make-parameter`, and `parameterize` — the underlying mechanism exists and is powerful. What's missing is the Clojure-friendly syntactic layer:

- `(def-dynamic *foo* default)` — sugar over `(define *foo* (make-parameter default))`
- `(binding [*foo* new-val *bar* other] body)` — sugar over `(parameterize ([*foo* new-val] [*bar* other]) body)`
- A convention that `*earmuffed*` names are dynamic and fair game to `binding`

These are three small macros. Tier 1 in the roadmap below.

---

## 17. Clojure Spec

Added in Clojure 1.9. Reconsiders data validation, function contracts, and generative testing as one unified system.

```clojure
(require '[clojure.spec.alpha :as s])

(s/def ::name string?)
(s/def ::age (s/and integer? #(>= % 0)))
(s/def ::email (s/and string? #(re-matches #".+@.+" %)))

(s/def ::person (s/keys :req-un [::name ::age] :opt-un [::email]))

(s/valid? ::person {:name "Alice" :age 30})        ; true
(s/explain ::person {:name "Alice" :age -1})        ; prints readable error
(s/explain-data ::person {:name "Alice" :age -1})   ; structured error
(s/conform ::person {:name "Alice" :age 30})        ; canonicalize; :clojure.spec.alpha/invalid on failure
```

### Spec composition

- `s/and`, `s/or`
- `s/coll-of`, `s/map-of`, `s/tuple`
- `s/keys` — maps with required/optional keys, namespaced or unnamespaced
- `s/cat`, `s/alt`, `s/*`, `s/+`, `s/?` — **regex over sequences** (matches like string regex)
- `s/nilable`, `s/multi-spec`

### Sequence regex

```clojure
(s/def ::config (s/cat :name string?
                        :options (s/* (s/cat :k keyword? :v any?))))
(s/conform ::config ["foo" :a 1 :b 2])
;; => {:name "foo" :options [{:k :a :v 1} {:k :b :v 2}]}
```

### Function specs

```clojure
(s/fdef transfer
  :args (s/cat :from ::account :to ::account :amount pos-int?)
  :ret ::account
  :fn #(= (-> % :ret :balance)
          (+ (-> % :args :to :balance) (-> % :args :amount))))
```

Instruments functions: when enabled, arguments and return values are validated against the spec at call time.

### Generative testing

```clojure
(s/exercise ::person 5)
;; => a list of [sample-value conformed] pairs, each a valid person
```

Every predicate in a spec can have a generator. With `s/fdef`, `clojure.spec.test.alpha/check` runs your function against N generated inputs and asserts the spec holds. Property-based testing nearly for free once you've written specs.

### Why it matters

- **Data validation** with good error messages.
- **Function contracts** without static typing.
- **Documentation** — specs are the truth about what shape data takes.
- **Generative testing** without writing generators.

**Jerboa status**: **[non-goal]** for full spec; **[open]** for a scaled-down schema library. Today Jerboa has `list-of?`, `maybe`, `:` for checked cast, `assert!`, but no composable spec system, no function contracts, no generator integration.

Full `clojure.spec` is a large feature and tied to assumptions about the Clojure runtime. A scaled-down **malli**-style data-driven schema system is the pragmatic alternative in Clojure-land today and far simpler to port — schemas are just nested data structures with a validation/conform/explain API. Recommended if anyone needs it; not on the current roadmap.

---

## 18. Namespaces

Clojure namespaces are first-class runtime objects, not just compile-time file organizers.

```clojure
(ns myapp.core
  (:require [clojure.string :as str]
            [clojure.set :refer [union intersection]]
            [myapp.db :as db])
  (:import [java.util Date UUID]))
```

- `:as` — alias
- `:refer [x y z]` / `:refer :all` — bring specific names unqualified
- `:as-alias` — alias without loading (for keyword namespace prefixes)
- `:rename {old new}`
- `:import` — for Java classes

### Runtime namespace manipulation

```clojure
(create-ns 'foo.bar)
(ns-publics 'clojure.core)     ; map of public names to vars
(ns-interns 'foo.bar)          ; all interned, including private
(ns-refers 'foo.bar)
(intern 'foo.bar 'x 42)        ; programmatically add a var
(resolve 'some-sym)            ; look up the var
```

### Hot reload

```clojure
(require 'myapp.core :reload)
(require 'myapp.core :reload-all)
```

Reloads a namespace's file and re-interns its vars. Combined with REPL-driven development, this is the core of the Clojure workflow.

**Jerboa status**: **[partial]**. Chez-style module imports with `(import (std ...))` work, and the MCP tooling (`jerboa_module_exports`, `jerboa_module_catalog`, `jerboa_find_definition`) provides substantial introspection. What's missing is the **hot reload** primitive — `(require 'ns :reload)` without restarting the process. Chez doesn't expose this cleanly. Tier 3 in the roadmap.

---

## 19. EDN and Tagged Literals

**EDN** (Extensible Data Notation) is Clojure's cousin of JSON: a subset of Clojure's reader syntax used as a universal data interchange format. Supports:
- nil, true, false
- integers, floats
- strings, characters
- symbols, keywords
- lists, vectors, sets, maps
- tagged elements `#tag value`

```clojure
(require '[clojure.edn :as edn])
(edn/read-string "{:name \"Alice\" :age 30}")
;; => {:name "Alice", :age 30}
```

Unlike `read-string` (which can execute code — dangerous on untrusted input), `edn/read-string` is safe.

### Tagged literals

The extension mechanism. `#inst "2026-04-10"` gets parsed by a registered reader fn that returns a `java.util.Date`.

You can register your own:
```clojure
(edn/read-string
  {:readers {'my/point (fn [[x y]] (->Point x y))}}
  "#my/point [1 2]")
```

### Data literals are printable

`print-method` dispatch lets records, custom types, etc., round-trip through EDN.

**Jerboa status**: **[open]**. JSON, CSV, YAML supported. No EDN-equivalent native Scheme-data serialization with tag extensions. S-expressions via `read`/`write` come close, but there's no registered tag extension hook and no sandboxed-read/unsafe-read partition. Tier 2 — medium effort, self-contained library.

---

## 20. Reader Conditionals

For code that runs on multiple platforms (Clojure, ClojureScript, ClojureCLR, babashka):

```clojure
(defn read-file [path]
  #?(:clj  (slurp path)
     :cljs (js/fetch path)
     :bb   (babashka.fs/read-file path)))

#?@(:clj  [(require '[clojure.java.io :as io])
            (def base-dir (io/file "."))])
```

Platform-specific branches baked into the reader. Not #ifdef — actual platform selection at read time.

**Jerboa status**: **[deferred]**. Not currently relevant since Jerboa is one target. Reader conditionals become valuable if/when Jerboa adds a second target (wasm, for example) or wants to share code with stock Chez or Gerbil. Revisit then.

---

## 21. Rich Number Tower

Clojure inherits and extends the Lisp numeric tower:
- `Long` (64-bit) by default for integers
- `Double` for floats
- **`BigInt`** — arbitrary-precision integer, written `42N`
- **`BigDecimal`** — arbitrary-precision decimal, written `0.1M`
- **`Ratio`** — exact rational, automatically from integer division: `(/ 1 3)` → `1/3`

Arithmetic is polymorphic. Integer overflow can either throw (`+`) or promote (`+'`) depending on which operator you use. `*'`, `-'`, `inc'`, `dec'` all auto-promote.

```clojure
(+ Long/MAX_VALUE 1)        ; ArithmeticException: overflow
(+' Long/MAX_VALUE 1)       ; 9223372036854775808N   (BigInt)
(* 1/3 3)                   ; 1N
(+ 0.1 0.2)                 ; 0.30000000000000004
(+ 0.1M 0.2M)               ; 0.3M                   (BigDecimal)
```

Type coercion is also explicit: `int`, `long`, `float`, `double`, `bigint`, `bigdec`, `rationalize`.

**Jerboa/Chez has**: Chez has an excellent number tower — exact rationals, arbitrary precision integers, real and complex numbers, `(sqrt 2)` vs `(exact->inexact (sqrt 2))`. This is one area where **Chez is as good as or better than Clojure**. The gap is stylistic: Clojure's rich number tower is prominent in teaching and everyday use; Chez's is often hidden.

---

## 22. Keyword/Symbol Semantics

Small but constant ergonomic wins:

```clojure
(:name {:name "Alice"})       ; keywords are functions that look themselves up
(:age {:name "Alice"} 0)      ; with default

('sym {'sym 42})              ; symbols work too
```

This one trick makes `(map :name users)` idiomatic where other languages need `(map #(:name %) users)` or equivalent.

### Namespaced keywords

```clojure
:user/name
::name                      ; auto-namespaced to current ns
::db/user                   ; auto-namespaced using :as-alias
```

Used heavily by spec, clojure.xml, datascript, and API design. Lets you have `:user/name` and `:account/name` without collision.

### Interning and identity

Keywords are interned; `(identical? :foo :foo)` is always true. Same for symbols.

**Jerboa status**: **[partial]**. Jerboa has a distinct `keyword` type and `name:` reader syntax that creates them, plus `keyword?`, `string->keyword`, `keyword->string` helpers. `(std clojure)`'s `get` and friends accept symbol, string, and keyword keys on records and pmaps interchangeably, so the pragmatic "keyword as API key" use case works today.

What's missing is **keywords callable as functions of maps** — `(:name m)` as shorthand for `(get m :name)`. That requires an applicable-struct system or a reader rewrite (and collides with Jerboa's `:std/sort` module-path syntax). Low priority: `(get m 'name)` reads nearly as cleanly. Deferred.

---

## 23. `loop`/`recur` and Tail Calls

Clojure runs on the JVM which doesn't guarantee TCO. So Clojure provides **explicit** recur points.

```clojure
(defn factorial [n]
  (loop [acc 1, n n]
    (if (zero? n)
      acc
      (recur (* acc n) (dec n)))))
```

`recur` rebinds the loop bindings and jumps to the top. The compiler enforces it's in tail position; if not, it's a compile error. Same with `recur` inside `fn` — rebinds parameters.

### `trampoline`

For mutual tail recursion:
```clojure
(declare odd?)
(defn even? [n] (if (zero? n) true #(odd? (dec n))))
(defn odd?  [n] (if (zero? n) false #(even? (dec n))))
(trampoline even? 1000000)     ; returns thunks to keep stack flat
```

**Jerboa / Chez**: Chez has proper tail calls — `loop`/`recur` is unnecessary. **This is a Jerboa advantage**. You can write natural recursive code. But adding a `(loop ... (recur ...))` macro for Clojure migrants would still be a nice-to-have for familiarity.

---

## 24. `for` Comprehensions

Not the side-effecting `for` of JS — list comprehensions with filters and lets.

```clojure
(for [x (range 10)
      y (range 10)
      :when (< x y)
      :let [sum (+ x y)]
      :while (< sum 15)]
  [x y sum])
```

- Multiple generators nest (Cartesian product).
- `:when pred` — filter.
- `:let [...]` — intermediate bindings.
- `:while pred` — break when false (within the innermost loop).
- Returns a lazy seq.

### `doseq` — side-effect version

```clojure
(doseq [x (range 5) :when (odd? x)]
  (println x))
```

**Jerboa status**: **[partial]**. `for/collect` and `for/fold` support multiple bindings (Cartesian product nesting). Clause extensions (`:let`, `:while`, `:when` style) aren't fully standardized — worth verifying what's implemented and adding anything missing. Small user-facing win; Tier 3.

---

## 25. Delays, Futures, and Promises

Three small concurrency primitives that compose well.

### Delay

Lazy, memoized computation:
```clojure
(def config (delay (load-expensive-config)))
@config                ; computes now, caches
@config                ; returns cached
(realized? config)     ; true
```

Think: `lazy val` in Scala, `OnceCell::get_or_init` in Rust.

### Future

Runs a body on a thread pool, returns a handle:
```clojure
(def f (future (expensive-computation)))
@f                     ; blocks until done
(future-done? f)
(future-cancel f)
(deref f 100 :timeout) ; deref with timeout and default
```

Exceptions from the body are stored and rethrown on deref.

### Promise

Set-once synchronization:
```clojure
(def p (promise))
(future (deliver p (compute)))
@p                     ; blocks until delivered
(deliver p :other)     ; no-op; once delivered, stuck
```

Used for rendezvous between threads, or anywhere you need "some thread will eventually produce this value."

**Jerboa status**: **[partial]**. `try-result`, async patterns in `(std async)`, and CSP `go` blocks cover most use cases. Chez's `delay`/`force` provide the lazy-value part directly. What's missing is the named Clojure surface: `delay` + `realized?`, `future` + `deref` + `future-cancel`, `promise` + `deliver`. These are thin wrappers over the existing primitives — Tier 3 in the roadmap.

---

## 26. Memoize, Trampoline, and Friends

Small built-ins that matter:

- `(memoize f)` — returns a function that caches `f`'s results by argument.
- `(juxt f g h)` — `(fn [x] [(f x) (g x) (h x)])`, great with `sort-by`, `group-by`.
- `(comp f g h)` — right-to-left composition.
- `(partial f a b)` — partial application.
- `(complement pred)` / `(constantly x)` / `(identity x)`.
- `(fnil f default)` — `f` but substitutes `default` for nil arguments.
- `(every-pred p1 p2 ...)` / `(some-fn p1 p2 ...)` — predicate combinators.
- `(iterate f x)` — lazy infinite `[x (f x) (f (f x)) ...]`.
- `(repeatedly n f)` — calls f n times, lazily.

**Jerboa status**: **[partial]**. `compose`/`comp`, `partial`, `complement`, `negate`, `identity`, `constantly`, `curry`, `flip`, `conjoin`/`disjoin` (Clojure's `every-pred`/`some-fn` under different names), `juxt`, `cut` are all in the prelude. Still missing: **`memoize`**, lazy **`iterate`** (Clojure's `(iterate f x)` = `[x (f x) (f (f x)) ...]`), **`repeatedly`**, **`fnil`**, **`trampoline`** (only strictly needed for mutual recursion across value-returning branches, since Chez has proper tail calls). These are all small, one-day adds. Tier 1 in the roadmap.

---

## 27. Exception Design: ex-info

Clojure's answer to "exceptions should carry data, not just strings":

```clojure
(throw (ex-info "Transfer failed"
                {:from account-a
                 :to account-b
                 :amount 100
                 :reason :insufficient-funds}))

(try
  (transfer ...)
  (catch clojure.lang.ExceptionInfo e
    (let [data (ex-data e)]
      (if (= (:reason data) :insufficient-funds)
        (handle-nsf)
        (throw e)))))
```

- `ex-info` — creates a `clojure.lang.ExceptionInfo` with a message, a map of data, and optional cause.
- `ex-data` — extracts the map.
- `ex-cause`, `ex-message` — access helpers.
- `Throwable->map` — canonical map representation of any exception.

Lets you catch by data-pattern rather than by class hierarchy, and serialize exceptions through channels/queues.

**Jerboa status**: **[open]**. `try/catch/finally` with pattern-based catches and condition objects exist. `(std errors)` has its own structured errors. Close in spirit but not the standardized `ex-info`/`ex-data` surface that clojure-spec, pedestal, and porters expect. This is a ~10-line shim on top of Jerboa's condition system — Tier 1 in the roadmap.

---

## 28. core.match

```clojure
(require '[clojure.core.match :refer [match]])
(match [x y]
  [0 0] :origin
  [0 _] :y-axis
  [_ 0] :x-axis
  [_ _] :anywhere
  [a b] (str "a=" a " b=" b))
```

Clojure's pattern matching library. Supports:
- Literal, wildcard, bind patterns
- Sequence and map patterns
- Guards (`:guard pred`)
- Or patterns
- Efficient decision tree compilation (Maranget's algorithm)

**Jerboa has**: `match` in the prelude with good coverage. This is one area of parity — Jerboa's `match` is already strong. Possible gaps: decision-tree compilation efficiency, more sophisticated nested patterns. Worth comparing carefully.

---

## 29. core.logic (miniKanren)

A logic programming library embedded in Clojure — miniKanren on the JVM:

```clojure
(require '[clojure.core.logic :as l])

(l/run* [q]
  (l/fresh [x y]
    (l/== q [x y])
    (l/membero x [1 2 3])
    (l/membero y [:a :b])))
;; => ([1 :a] [1 :b] [2 :a] [2 :b] [3 :a] [3 :b])
```

Unification, relations, constraints, goals. Used for:
- Type inference
- Program synthesis
- Expert systems
- Constraint solving

Also `clojure.core.logic.pldb` — Prolog-like deductive database.

**Jerboa status**: **[open]** (low priority). No logic programming. A Jerboa port of a miniKanren flavor is a self-contained library — not deeply integrated with core, so it's approachable. Off the Clojure-compat critical path; valuable for anyone doing logic programming specifically. Tier 4.

---

## 30. Zippers

`clojure.zip` — functional tree editing with O(1) local operations:

```clojure
(require '[clojure.zip :as z])
(def t (z/vector-zip [1 [2 3] [4 [5 6]]]))
(-> t z/down z/right z/down z/node)    ; => 2
(-> t z/down z/right (z/replace [99])) ; replace [2 3] with [99]
```

A zipper represents "a location in a data structure": the node you're at plus enough context to rebuild the whole tree. Moves (`up`, `down`, `left`, `right`, `next`) are O(1). `root` rebuilds the whole tree with your edits.

Essential for:
- Tree rewriting
- AST manipulation
- HTML/XML navigation (see `clojure.data.zip`)
- Functional editors

**Jerboa status**: **[open]**. No zipper library. Straightforward port of `clojure.zip`, ~200 lines, not integrated with any core feature. Tier 2.

---

## 31. Specter

Third-party but near-ubiquitous. Path-based deep navigation and transformation of arbitrary nested data:

```clojure
(require '[com.rpl.specter :as s])

(s/transform [s/MAP-VALS s/ALL :age] inc
             {:team-a [{:age 30} {:age 25}]
              :team-b [{:age 40}]})
;; => {:team-a [{:age 31} {:age 26}] :team-b [{:age 41}]}
```

Defines **navigators** as composable objects. Navigators include `ALL`, `MAP-VALS`, `MAP-KEYS`, `FIRST`, `LAST`, integer indices, keys, predicate filters, walkers, etc. You compose them into a path and then `select` or `transform`.

`update-in`/`assoc-in` scale to the depth you're at; Specter scales to arbitrary *shapes* of navigation.

**Jerboa status**: **[open]**. No equivalent. Like zippers, a self-contained library that would pair naturally with persistent collections. Tier 2.

---

## 32. Datafy / Nav

Added in Clojure 1.10. The idea: **any opaque value can be turned into inspectable data**, and **that data can be navigated lazily**.

```clojure
(require '[clojure.datafy :refer [datafy nav]])

(def conn (jdbc/get-connection ...))
(datafy conn)
;; => {:url "jdbc:..." :schema "..." :tables [{:name "users"} ...]}

(nav (datafy conn) :tables [{:name "users"}])
;; => fetches columns lazily when navigated
```

Used by tooling like REBL and Reveal to build **data inspectors**: click into a database connection, see a map; click a table, see rows; click a row, see cells. Any type can implement `Datafiable` to expose itself.

**Jerboa status**: **[open]**. No unified datafy/nav protocol. Big value for REPL tooling and debugging. Now more tractable since `(std protocol)` is in place — datafy/nav is naturally expressed as two protocols. Tier 2.

---

## 33. clojure.walk

```clojure
(require '[clojure.walk :as w])

(w/postwalk (fn [x] (if (number? x) (* x 2) x))
            {:a 1 :b [2 3 {:c 4}]})
;; => {:a 2 :b [4 6 {:c 8}]}

(w/keywordize-keys {"a" 1 "b" 2})
;; => {:a 1, :b 2}

(w/stringify-keys {:a 1 :b 2})

(w/walk inner outer form)   ; low-level
(w/prewalk f form)           ; top-down
(w/postwalk f form)          ; bottom-up
(w/macroexpand-all form)     ; expand all macros
```

Generic tree rewriting that works on arbitrary nested Clojure data. One of those "I use it once a month but it's the right tool" libraries.

**Jerboa status**: **[open]**. No walker. Easy to build on top of a recursive structure visitor — ~100 lines total including `postwalk`/`prewalk`/`walk`/`keywordize-keys`/`stringify-keys`/`macroexpand-all`. Tier 1 in the roadmap.

---

## 34. Set Operations

`clojure.set`:

```clojure
(require '[clojure.set :as set])
(set/union #{1 2} #{2 3})        ; #{1 2 3}
(set/intersection #{1 2} #{2 3}) ; #{2}
(set/difference #{1 2 3} #{2})   ; #{1 3}
(set/subset? #{1} #{1 2})        ; true
```

Plus relational operators:
```clojure
(set/project users [:name :email])         ; SQL-like SELECT
(set/select #(> (:age %) 30) users)        ; SQL-like WHERE
(set/join users addresses {:user-id :id})  ; SQL-like JOIN
(set/rename users {:email :contact})
(set/index users [:city])                  ; group by
```

Small relational algebra over sets of maps. Rarely used in production but beautifully minimal.

**Jerboa status**: **[landed]** for the core operations. `(std clojure)` and `(std pset)` provide `hash-set`, `persistent-set`, `union`, `intersection`, `difference`, `subset?`, `superset?`, `disj`, `contains?`, `conj`. The **relational** operators (`project`, `select`, `join`, `rename`, `index`) from `clojure.set` are still open — they're a small self-contained library that would compose naturally on top of `(std pset)` + pmap.

---

## 35. Property-Based Testing (test.check)

Integrates with `clojure.spec`:

```clojure
(require '[clojure.test.check :as tc]
         '[clojure.test.check.generators :as gen]
         '[clojure.test.check.properties :as prop])

(def sort-idempotent
  (prop/for-all [v (gen/vector gen/int)]
    (= (sort v) (sort (sort v)))))

(tc/quick-check 100 sort-idempotent)
```

- **Generators**: `gen/int`, `gen/string`, `gen/vector`, `gen/map`, `gen/one-of`, `gen/such-that`, `gen/fmap`, `gen/bind` — compose to produce arbitrary shapes.
- **Shrinking**: when a test fails, test.check automatically shrinks the input to a minimal failing case.
- **Spec integration**: `(stest/check 'my-fn)` generates inputs from the spec and checks the function.

Clojure's property-based testing culture is notable — many libraries ship `test.check` suites.

**Jerboa status**: **[open]**. No generative testing framework. Would be a major quality-of-life win for testing serialization, round-tripping, parsers, algorithms. Generators + shrinking can be built as a self-contained library; QuickCheck ports are well-documented so the API surface is known. Tier 2.

---

## 36. Component Lifecycle Libraries

Stuart Sierra's `component`, `integrant`, and `mount` — patterns for managing stateful resources (DB connections, HTTP servers, queues) over a system's lifecycle.

```clojure
;; component-style
(defrecord Database [uri connection]
  component/Lifecycle
  (start [this] (assoc this :connection (jdbc/connect uri)))
  (stop [this] (jdbc/disconnect connection) (assoc this :connection nil)))

(def system
  (component/system-map
    :db (->Database "jdbc:..." nil)
    :web (component/using (->WebServer 8080) [:db])))

(component/start system)
(component/stop system)
```

Solves the "how do I wire up 15 stateful services with dependencies and restart them cleanly at the REPL" problem. Makes hot-reload of business code possible without losing connections to the world.

**Jerboa status**: **[open]**. No lifecycle framework. Low-urgency for small apps but important for long-running services. Could build on top of `defrecord` + `(std protocol)` (for `Lifecycle` start/stop) + a dependency graph. Now easier to implement since protocols landed. Tier 3.

---

## 37. REPL-Driven Development Culture

Not a feature per se but an ecosystem. Clojure's REPL story:

- **nREPL** — REPL as a network service, shared by editors.
- **CIDER** (Emacs), **Cursive** (IntelliJ), **Calva** (VS Code), **Conjure** (Neovim) — IDE integrations that evaluate forms in place, show inline results, jump-to-definition using the running runtime.
- **Hot reload**: save file, reload namespace, existing references update.
- **REBL / Reveal / Portal** — visual data inspectors using datafy/nav.
- **tools.deps / deps.edn** — declarative dependencies, git deps, local deps, aliases for dev/test/prod.
- **Leiningen** — older build tool, still widely used.
- **babashka** — bakes Clojure into a GraalVM native binary for fast startup; scripts that run in ~30ms.

The whole stack rewards "keep the system running, shape it from inside."

**Jerboa status**: **[partial]**. `jerboa_repl_session`, `jerboa_eval`, and the MCP tool surface are actually quite strong for "evaluate this form in a live runtime and see the result" — that's most of the non-visual nREPL experience, delivered as tool calls to the agent instead of messages to an editor. The gap is the **editor-side integration**: the "hit C-x C-e on a form in your source buffer, see the result inline" experience that CIDER/Calva/Conjure deliver. Closing it requires either a proper nREPL-compatible server (so existing Clojure editor plugins work) or native LSP extensions for Jerboa-aware editors. Either is a separate project from language features. Tier 4 in the roadmap.

---

## 38. Miscellaneous Small Things That Add Up

### Anonymous function shorthand
```clojure
#(+ % %2)         ; => (fn [%1 %2] (+ %1 %2))
```

### Threading variants
- `->` (thread-first) and `->>` (thread-last) — Jerboa has these.
- `some->` / `some->>` — short-circuit on nil — Jerboa has these.
- `cond->` / `cond->>` — conditional steps — Jerboa has these.
- `as->` — named threading — Jerboa has these.
- `doto` — thread with side effects on the same object: `(doto (Thing.) (.a) (.b))`.

### Collection helpers
- `get-in` / `assoc-in` / `update-in` — deep access/update by path vector
- `merge-with f m1 m2` — combine maps with a conflict resolver
- `select-keys m ks` — subset of keys
- `zipmap keys vals` — two sequences → a map
- `reduce-kv f init m` — reduce over map entries
- `group-by`, `frequencies`, `partition-by`
- `juxt` for multi-field key extraction

### Conditionals
- `condp` — `cond` with a shared predicate/fn: `(condp contains? x #{1 2} :small ...)`
- `case` — compile-time dispatch on literal values, O(1)
- `when`, `when-not`, `when-let`, `if-let`, `when-first`, `if-not`

### Arithmetic
- `quot`, `rem`, `mod` — division variants
- `min`, `max`, `min-key`, `max-key` — `(max-key :age users)`
- `bit-and`, `bit-or`, `bit-shift-left`, etc. — all present but named consistently

### Collection construction
- `{}`, `#{}`, `[]` literals
- `hash-map`, `array-map`, `sorted-map`, `sorted-map-by`
- `hash-set`, `sorted-set`, `sorted-set-by`
- `into` — pour one collection into another: `(into [] (map inc) data)`

### `doto`
```clojure
(doto (StringBuilder.)
  (.append "hello ")
  (.append "world"))
```
Threads an object through side-effecting calls that all return something else. Gold for Java interop but also nice for builders.

### `declare`
Forward declarations so mutually recursive top-level defs compile.

### `pr` vs `print`
Clojure distinguishes `print` (human-readable, no escapes) from `pr` (EDN-readable round-trippable output). `prn` = `pr` + newline. `println` = `print` + newline. Tiny but constant aid for REPL debugging.

### Jerboa status roll-up for this section

**Landed** in `(jerboa prelude)` or dedicated modules:
- Threading: `->`, `->>`, `some->`, `cond->`, `as->` (all present); also `->?` for ok/err result threading
- Collection helpers: `get-in` / `assoc-in` / `update-in` via `(std misc nested)`; `group-by`, `frequencies`, `partition`, `juxt`, `zip`, `into`, `merge`, `select-keys`, `update` (via `(std clojure)` and the prelude)
- Conditionals: `when`, `when-not`, `when-let`, `if-let`, `if-not`, `awhen`, `aif`, full `case` (via Chez)
- Arithmetic: `quot`, `rem`, `mod`, `min`, `max`, `bit-*` ops (all via Chez)
- Set/map construction: `hash-map`, `hash-set`, `sorted-set`, variadic constructors from `(std clojure)` and `(std sorted-set)`
- Predicate combinators `conjoin`/`disjoin` (same shape as Clojure's `every-pred`/`some-fn`), `complement`, `negate`
- `declare` — Chez `define` forward refs work naturally; no separate macro needed
- `pr`/`pr-str` vs `print`/`display` — Chez `write` vs `display` is the structural analogue

**Open** (worth adding):
- `doto` macro — threads side-effecting calls on one object. Trivial macro. **Tier 1**.
- Anonymous `#(...)` reader shorthand — requires reader modification (same class of work as [`clojure-reader.md`](./clojure-reader.md)); Jerboa uses `(lambda (x) ...)` / `(cut + <> 1)` instead. **Deferred.**
- `condp` — single-predicate dispatch form. Small macro, nice-to-have. **Tier 3**.
- `merge-with`, `zipmap`, `reduce-kv` — the last few map-convenience functions not yet in `(std clojure)`. (`merge` and `select-keys` already landed.) Small self-contained additions. **Tier 1**.
- `min-key` / `max-key` — select the element of a collection that minimizes/maximizes a key function: `(max-key :age users)`. Trivial ~5-line definitions. **Tier 1**.
- `fnil` — wraps a function so `nil`/`#f` arguments get replaced with defaults before calling. Trivial closure. **Tier 1**.

---

## Summary: Where Things Stand (2026-04-11)

### What's landed

Most of the features originally ranked "Tier 1 / Tier 2" are now in place. The Clojure-compat campaign tracked in [`clojure-remaining.md`](./clojure-remaining.md) — plus earlier work on the persistent data structures and CSP channels — has shipped:

| Feature | Module | Notes |
|---------|--------|-------|
| Persistent map / vector / set | `(std pmap)` `(std pvec)` `(std pset)` | HAMT where applicable, structural `=?` and hash |
| Persistent queue | `(std pqueue)` | O(1) amortized FIFO |
| Sorted set | `(std sorted-set)` | Range queries, ordered traversal |
| Transients | `imap-transient`, `pvec-transient`, `pset-persistent!` | Bulk-build API via `(std clojure)` `transient`/`persistent!`/`conj!`/`assoc!` |
| Transducers | `(std transducer)` | `map`/`filter`/`take`/`dedupe`/etc., composed with `comp`, applied with `transduce`/`into`, integrated with CSP channels via `(chan n xform)` |
| core.async CSP | `(std csp)` | Channels, `go`, `alts!`, buffers, `mult`/`tap`, `pub`/`sub`, `mix`, `pipe`, `pipeline`, `put!`/`take!`, `timeout` with timer wheel, transducer channels |
| Atoms + watches + volatiles | `(std misc atom)` | `atom`, `swap!`, `reset!`, `compare-and-set!`, `add-watch!`, `remove-watch!`, `volatile!`/`vreset!`/`vswap!` |
| Agents | `(std agent)` | `send`/`send-off`/`await`/`agent-error`/`restart-agent`, `:fail` error mode |
| Protocols | `(std protocol)` | `defprotocol`, `extend-type`, `extend-protocol`, `reify`, `satisfies?` |
| Multimethods | `(std multi)` | `defmulti`, `defmethod`, `prefer-method`, `derive`, `isa?` hierarchies |
| Metadata | `(std misc meta)` | `with-meta`, `meta`, `vary-meta`, `strip-meta`; `=?` strips before comparing |
| Record-as-map | `(std clojure)` + `(std misc nested)` | Records answer `get`/`keys`/`vals`/`count`/`contains?`/`empty?`; `assoc`/`dissoc` escape to pmap; `get-in` walks records |
| Set operations | `(std pset)` + `(std clojure)` | `union`, `intersection`, `difference`, `subset?`, `superset?` |
| `get-in`/`assoc-in`/`update-in` | `(std misc nested)` | Polymorphic over pmap, chash, hash-table, vector, pair (alist), and records |
| Pattern matching | `(jerboa prelude)` | `match` with nested, guards, predicates, or-patterns, view patterns |

### What Chez/Jerboa does as well or better than Clojure

- **Proper tail calls** — Chez guarantees TCO, so no `loop`/`recur` ceremony. Natural recursion is fine; `(loop ... (recur ...))` is only a familiarity nicety for migrants.
- **Numeric tower** — Chez has exact rationals, arbitrary-precision integers, bignums, and complex numbers built in. The Clojure `BigInt`/`BigDecimal`/`Ratio` distinction is flatter and more pervasive in Chez.
- **Pattern matching** — Jerboa's `match` is already excellent; this was one area of parity from the start.
- **Macro hygiene** — Chez's `syntax-case` is arguably more powerful than Clojure's macros. Jerboa inherits this.
- **Continuations** — Chez has `call/cc`; Clojure doesn't.
- **Compilation speed and startup time** — Chez AOT vs JVM warmup. Jerboa scripts start in ms, not seconds.

### Cultural/ecosystem gaps (not language features)

- REPL-driven workflow tooling (partially addressed via MCP tools, `jerboa_repl_session`, `jerboa_eval`)
- Dependency management
- Documentation conventions
- Community-maintained idiom libraries

---

## Still Worth Implementing (as of 2026-04-11)

What's left, ranked by value-per-effort. Each entry links to the section above for the full discussion.

### Tier 1 — ✅ Landed (2026-04-11)

All Tier 1 items shipped in a single batch in `(std clojure)` and `(std clojure walk)`.

| Feature | Section | Status | Notes |
|---------|---------|--------|-------|
| **Map destructuring with `:keys` in `let`/`def`** | [§14](#14-destructuring-everywhere) | ✅ Landed | `dlet` macro with list destructure, map `:keys`, `:as`, `:or` defaults. `dfn` for destructured function params. |
| **`ex-info` / `ex-data` structured exceptions** | [§27](#27-exception-design-ex-info) | ✅ Landed | `ex-info`, `ex-info?`, `ex-data`, `ex-message`, `ex-cause`. Condition-type based. |
| **`memoize` / `iterate` / `repeatedly`** | [§26](#26-memoize-trampoline-and-friends) | ✅ Landed | Re-exported from prelude internals. `iterate` is strict/bounded: `(iterate n f x)`. |
| **`clojure.walk` (`postwalk` / `prewalk` / `keywordize-keys`)** | [§33](#33-clojurewalk) | ✅ Landed | New `(std clojure walk)` module. Handles lists, vectors, pmaps, pvecs, psets. |
| **`doto` macro** | [§38](#38-miscellaneous-small-things-that-add-up) | ✅ Landed | `syntax-rules` macro in `(std clojure)`. |
| **Dynamic vars + `binding` sugar** | [§16](#16-dynamic-vars-and-thread-local-binding) | ✅ Landed | `def-dynamic` wraps `make-parameter`, `binding` wraps `parameterize`. |
| **Map-convenience stragglers** | [§38](#38-miscellaneous-small-things-that-add-up) | ✅ Landed | `merge-with`, `zipmap`, `reduce-kv`, `min-key`, `max-key`. |

### Tier 2 — High value, medium effort, self-contained

| Feature | Section | Effort | Why it's worth doing |
|---------|---------|--------|----------------------|
| **Lazy sequences in the prelude** | [§5](#5-lazy-sequences) | Medium | `lazy-seq`, `cycle`, `repeat`, infinite `iterate`, `take-while`, `drop-while`. Chez has the primitives; expose them as a first-class idiom. |
| **Zippers (`clojure.zip`)** | [§30](#30-zippers) | Medium | Functional tree editing. Classic, well-specified, ~200 lines. Pairs naturally with `match` for AST work. |
| **Specter-style path navigation** | [§31](#31-specter) | Medium | Path-based deep navigation over arbitrary nested data. Scales `update-in` to arbitrary *shapes*. |
| **Reducers / parallel fold** | [§7](#7-reducers) | Medium | Auto-parallel `(r/fold + (r/map inc big-vec))`. Needs a divide-and-conquer split protocol on pvec and pmap. |
| **EDN format with tagged literals** | [§19](#19-edn-and-tagged-literals) | Medium | Safe Scheme-data serialization with an extension hook. Fill-in for JSON/EDN interop. |
| **Datafy / Nav** | [§32](#32-datafy--nav) | Medium | Protocol for exposing opaque values as inspectable data. Big dev-experience win once REPL tooling matures. |
| **Property-based testing (test.check style)** | [§35](#35-property-based-testing-testcheck) | Medium | Generators + shrinking. Clojure's `clojure.test.check` is the canonical reference. |

### Tier 3 — Significant effort, significant payoff

| Feature | Section | Effort | Why it's (maybe) worth doing |
|---------|---------|--------|------------------------------|
| **STM refs (`ref` / `dosync` / `alter` / `commute`)** | [§9](#9-software-transactional-memory-stm) | Hard | The last big concurrency primitive Jerboa doesn't have. Well-specified design (version counters + read/write sets + commit protocol), just a real engineering project. A scaled-down variant that only coordinates 2–8 refs per transaction is much easier than a fully general one. |
| **Component lifecycle framework** | [§36](#36-component-lifecycle-libraries) | Medium | Stuart Sierra's `component`, `integrant`, or `mount`. Solves "start 15 services in dependency order, restart cleanly at the REPL." Mostly a library on top of `defrecord` + a dependency graph. |
| **`clojure.set` relational operators** | [§34](#34-set-operations) | Easy | `project`, `select`, `join`, `rename`, `index`. Small relational algebra over sets of maps. Self-contained. |
| **Namespace hot reload** | [§18](#18-namespaces) | Medium | `(require 'ns :reload)` without restarting. Chez doesn't expose this cleanly, so it needs real wiring — but it's the linchpin of REPL-driven dev. |
| **`for` comprehension `:let`/`:while`/`:when` clauses** | [§24](#24-for-comprehensions) | Easy | Jerboa's `for/collect` is already close; this is clause additions. Small user-facing win. |
| **Delay / Future / Promise polish** | [§25](#25-delays-futures-and-promises) | Easy | Chez has the primitives; wrap them as `delay`/`force`/`realized?`, `future`/`deref`, `promise`/`deliver` for Clojure parity. |

### Tier 4 — Niche, deferred, or non-goal

| Feature | Section | Status | Reasoning |
|---------|---------|--------|-----------|
| **Clojure reader literals (`{}`/`#{}`/`[]`/`:kw`)** | [`clojure-reader.md`](./clojure-reader.md), [§4.9](./clojure-remaining.md#49-reader-literals-----v-kw) | Deferred (risky) | Requires opt-in file-local reader modes; permanent debuggability weirdness; most porters adapt to constructor forms in a day. Could be deferred forever. |
| **Parked `go` via CPS transform** | [§10](#10-coreasync-csp-channels), §3.8 in `clojure-remaining.md` | Deferred | Research-scale macro project. Jerboa's OS-thread `go` is fine for thousands-of-coroutines use cases, just not millions. |
| **Clojure Spec / full schema system** | [§17](#17-clojure-spec) | Non-goal | Too large to port faithfully. A scaled-down malli-style schema library is the recommended alternative for anyone who needs it. |
| **core.logic (miniKanren)** | [§29](#29-corelogic-minikanren) | Open, low priority | A self-contained library port; valuable for anyone doing logic programming, but far from the Clojure-compat critical path. |
| **Keywords as functions `(: k m)` on pmaps** | [§22](#22-keywordsymbol-semantics) | Deferred | Would require applicable-struct support. Instead use `(get m k)`, which is already polymorphic. |
| **nREPL-style editor protocol** | [§37](#37-repl-driven-development-culture) | Partial | Jerboa's MCP tooling covers a lot of the same ground (`jerboa_eval`, `jerboa_repl_session`). A proper nREPL server would unlock CIDER/Calva-style editor integration but is a separate project. |
| **Reader conditionals** | [§20](#20-reader-conditionals) | Deferred | Useful only when Jerboa has multiple targets; currently one target. Revisit if Jerboa-wasm or Gerbil-share becomes real. |
| **`.clj` source loading** | — | Non-goal | Not porting the JVM compiler. |

### Recommendation

Tier 1 is done. The next natural pass is **Tier 2 items in isolation** — lazy sequences, zippers, and Specter-style paths each stand alone and become more attractive now that the core ergonomics gap is closed. Tier 3's STM is the only remaining "foundational" gap and deserves a real design round of its own.

The language features above are what you'd port. The culture is built alongside, one idiomatic library at a time.
