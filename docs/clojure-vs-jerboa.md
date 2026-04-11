# Clojure vs Jerboa: Feature Gap Analysis

A comprehensive inventory of what Clojure offers that Jerboa/Chez Scheme doesn't (or has in weaker form), with detailed explanations of what each feature does and why Clojure developers consider it a game-changer.

Organized from most foundational to most specialized. In-progress Jerboa work noted where relevant.

---

## Table of Contents

1. [The Philosophical Foundation](#1-the-philosophical-foundation)
2. [Persistent Immutable Data Structures](#2-persistent-immutable-data-structures) (in progress)
3. [Transients](#3-transients)
4. [The Unified Sequence Abstraction](#4-the-unified-sequence-abstraction)
5. [Lazy Sequences](#5-lazy-sequences)
6. [Transducers](#6-transducers)
7. [Reducers](#7-reducers)
8. [The Four Reference Types](#8-the-four-reference-types)
9. [Software Transactional Memory (STM)](#9-software-transactional-memory-stm)
10. [core.async (CSP Channels)](#10-coreasync-csp-channels) (in progress)
11. [Protocols](#11-protocols)
12. [Multimethods](#12-multimethods)
13. [Records and Types](#13-records-and-types)
14. [Destructuring Everywhere](#14-destructuring-everywhere)
15. [Metadata](#15-metadata)
16. [Dynamic Vars and Thread-Local Binding](#16-dynamic-vars-and-thread-local-binding)
17. [Clojure Spec](#17-clojure-spec)
18. [Namespaces](#18-namespaces)
19. [EDN and Tagged Literals](#19-edn-and-tagged-literals)
20. [Reader Conditionals](#20-reader-conditionals)
21. [Rich Number Tower](#21-rich-number-tower)
22. [Keyword/Symbol Semantics](#22-keywordsymbol-semantics)
23. [`loop`/`recur` and Tail Calls](#23-looprecur-and-tail-calls)
24. [`for` Comprehensions](#24-for-comprehensions)
25. [Delays, Futures, and Promises](#25-delays-futures-and-promises)
26. [Memoize, Trampoline, and Friends](#26-memoize-trampoline-and-friends)
27. [Exception Design: ex-info](#27-exception-design-ex-info)
28. [core.match](#28-corematch)
29. [core.logic (miniKanren)](#29-corelogic-minikanren)
30. [Zippers](#30-zippers)
31. [Specter](#31-specter)
32. [Datafy / Nav](#32-datafy--nav)
33. [clojure.walk](#33-clojurewalk)
34. [Set Operations](#34-set-operations)
35. [Property-Based Testing (test.check)](#35-property-based-testing-testcheck)
36. [Component Lifecycle Libraries](#36-component-lifecycle-libraries)
37. [REPL-Driven Development Culture](#37-repl-driven-development-culture)
38. [Miscellaneous Small Things That Add Up](#38-miscellaneous-small-things-that-add-up)

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

**Status in Jerboa**: In progress.

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

### Jerboa Gap
Chez's built-in hashtables are mutable, and `eq?`/`equal?` comparison of them works but there's no structural sharing. Lists are persistent-ish (cons cells), but conjugate, assoc, update-in style operations don't exist. No persistent vector, map, set, or queue with HAMT characteristics. You're building this — it's the foundation for almost everything else.

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

**Jerboa gap**: No persistent structures yet, so no transients. When you build them, transients should be part of the design from day one — they're how Clojure avoids the "but immutable is slow!" critique.

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

**Jerboa has**: `for/collect`, `for/fold`, `map`, `filter`, `flatten`, `unique`, `take`, `drop`, `every`, `any`, `filter-map`, `group-by`, `zip`, `frequencies`, `partition`, `interleave`, `mapcat`, `distinct`, `keep`, `split-at`, `append-map`, `snoc`. Good coverage but not a single unified abstraction — lists, vectors, hash tables, and strings each have their own APIs. Iteration via `in-list`/`in-vector`/`in-hash-keys` in `for` is closest to the seq idea but is a macro-time thing, not a runtime polymorphic protocol.

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

**Jerboa has**: Chez's lazy library exists but isn't in the prelude. `in-producer` gives some of this via `for`. No culture of lazy-by-default; you build with eager collections and decide to go lazy. A lazy-seq macro integrated into the prelude would close much of the gap.

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

### Jerboa gap

Jerboa has `for/fold` and `for/collect` which are macro-level fused loops — conceptually similar in that they avoid intermediate lists, but not composable values you can pass around. Building a transducer library in Jerboa would require:
1. Agreeing on the reducing-function protocol.
2. Providing arity-overloaded `map`/`filter`/etc. that return transducers when called without a collection.
3. Providing `into`/`transduce`/`sequence`/`eduction` entry points.

Huge payoff. Probably the single feature most worth porting after persistent data.

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

**Jerboa gap**: No parallel fold. `pmap` exists (you mentioned fixing it recently), but no reducer-level parallelism that automatically splits collections. Chez has threads; the primitives are there.

---

## 8. The Four Reference Types

Clojure's unified concurrency model. All four embody identity-vs-value, differing on (a) sync vs async and (b) coordinated vs uncoordinated.

|             | **Uncoordinated**       | **Coordinated** |
|-------------|-------------------------|-----------------|
| **Sync**    | `atom`                  | `ref` (STM)     |
| **Async**   | `agent`                 | —               |

Plus `var` for thread-local dynamic binding.

### Atom

**Status in Jerboa**: Recently aliased in `(std misc atom)` and re-exported from the prelude.

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

**Jerboa gap**: Atoms just arrived. Agents and refs are the big missing pieces. Building agents on top of Chez threads + a work queue is straightforward. STM is harder.

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

**Jerboa gap**: None of this. Chez has mutexes and condition variables. Building STM requires:
1. Version counters on refs.
2. Transaction-local read/write sets.
3. A commit protocol with conflict detection.
4. Retry semantics.

It's a significant engineering project, but the abstraction is well-specified.

---

## 10. core.async (CSP Channels)

**Status in Jerboa**: In progress.

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

**Jerboa gap**: In progress per user note. Chez has threads and mutexes; the hard part is the `go` macro's state machine transformation (CPS transform). Possible approaches:
1. OS-thread-per-channel-worker (simpler, doesn't scale to millions).
2. Delimited continuations (Chez has them via `call/1cc`).
3. A full CPS transformation macro like Clojure's.

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

**Jerboa has**: `defmethod` on structs via `(defmethod (area (self circle)) ...)`. This is single-inheritance method dispatch tied to a struct. Clojure protocols are independent of type hierarchy and can be retrofitted onto any existing type. Jerboa's method system is closer to Gerbil/CLOS without the extensibility story.

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

**Jerboa gap**: No equivalent. `defmethod` is protocol-style (first-arg struct type). Building multimethods = a dispatch table keyed by the result of a user function, plus an `isa?` relation.

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

**Jerboa has**: `defrecord` which gives pretty-print and `->alist`. Good, but not protocol-implementing and not the same "record is a map" semantics. Jerboa `defstruct` is more primitive.

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

**Jerboa has**: `match` provides strong pattern matching, and `using` gives dot-access to struct fields. But you can't just write `(def (f [x y z]) ...)` and have it destructure a list argument in the parameter position across the language. Destructuring in `let` uses `let-values`/manual `car`/`cdr`. No map destructuring with `:keys` style. Jerboa has `let-alist` which is close.

A destructuring `def`/`let` macro in the prelude would be very high-value.

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

**Jerboa gap**: Chez doesn't have a unified metadata concept. You can wrap things but it's not systematic. Big value for introspection, documentation, and macro systems.

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

**Jerboa gap**: Chez has `fluid-let` and parameters (`make-parameter`, `parameterize`) which are similar. Jerboa's prelude doesn't surface these clearly. A `(def ^:dynamic *foo* ...)` + `(binding ...)` sugar would be natural.

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

**Jerboa has**: `list-of?`, `maybe`, `:` for checked cast, `assert!`, but no composable spec system, no function contracts, no generator integration.

This is a large feature. A scaled-down "malli" style (data-driven schema) is the common alternative in Clojure-land today; simpler to port.

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

**Jerboa has**: Chez-style module imports with `(import (std ...))`. Less introspection, no hot reload primitives in user code as far as I've seen. `:reload` style dev loop is missing.

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

**Jerboa has**: JSON, CSV, YAML support. No EDN-equivalent native "Scheme data serialization" format with tag extensions. S-expressions via `read`/`write` come close, but there's no registered tag extension hook and no safety partition.

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

**Jerboa gap**: Not currently relevant since Jerboa is one target, but reader conditionals become valuable when you have Jerboa-vs-Chez divergences or want to share code with Gerbil.

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

**Jerboa gap**: Jerboa has symbols but no `keyword` distinct type. `name:` reader syntax creates `#:name` keywords — it's there, but less pervasive in API design. Making keywords callable as functions-of-maps in Jerboa would be high impact (requires an applicable-struct system or a wrapper).

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

**Jerboa has**: `for/collect` which supports multiple bindings in `for`, and `#:when` style guards exist in Racket's `for`. Jerboa's `for` supports `(#:when cond)` — check the implementation. If not, this is a small but high-value addition: `:let`, `:while`, `:when` clauses in `for/collect`.

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

**Jerboa has**: `try-result`, async patterns in `(std async)`. Delay is partially there via Chez's `delay`/`force` — but future and promise in the Clojure sense need the thread pool + structured result. `(std concur)` has the building blocks.

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

**Jerboa has**: `compose`, `comp`, `partial`, `complement`, `identity`, `constantly`, `curry`, `flip`, `conjoin`, `disjoin`, `juxt`, `cut`. Very good coverage. Missing `memoize`, `fnil`, `iterate`, `every-pred`, `some-fn`, `repeatedly`. Easy to add.

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

**Jerboa has**: `try/catch/finally` with pattern-based catches and condition objects. `(std errors)` has its own structured errors. Close in spirit but not the standardized "ex-info + ex-data" convention that clojure-spec, pedestal, etc., all build on.

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

**Jerboa gap**: No logic programming. A Jerboa port of a miniKanren flavor is a self-contained library — not deeply integrated with core, so it's approachable.

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

**Jerboa gap**: No zipper library. Straightforward port; not integrated with any core feature.

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

**Jerboa gap**: No equivalent. Like zippers, a self-contained library that would pair naturally with persistent collections.

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

**Jerboa gap**: No unified datafy/nav protocol. Big value for REPL tooling and debugging.

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

**Jerboa gap**: No walker. Easy to build on top of a recursive structure visitor.

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

**Jerboa gap**: No set type or set operations in the prelude.

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

**Jerboa gap**: No generative testing framework. Massive win for testing serialization, round-tripping, parsers, algorithms.

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

**Jerboa gap**: No lifecycle framework. Low-urgency for small apps but important for long-running services. Could build on top of defrecord + a dependency graph.

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

**Jerboa has**: `jerboa_repl_session`, `jerboa_eval`, and MCP-based tooling that's actually quite strong here. The gap is mostly editor integration and the "send form from editor to live REPL, see it evaluate" experience. Jerboa + an nREPL-style protocol + LSP tooling could close this.

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

---

## Summary: Where to Focus

If I had to rank the features by "biggest game-changer you can practically add to Jerboa":

| Tier | Feature | Difficulty | Payoff |
|------|---------|-----------|--------|
| 1 | Persistent data structures + transients | Hard | Foundational |
| 1 | Transducers | Medium | Huge — unlocks reusable pipelines |
| 1 | core.async channels + go | Hard | Structured concurrency |
| 1 | Protocols | Medium | Extensibility + polymorphism |
| 1 | Map destructuring everywhere | Easy | Daily ergonomics |
| 2 | Atoms / agents / refs / STM | Medium-Hard | Concurrent programming story |
| 2 | Dynamic vars + binding | Easy | Context propagation |
| 2 | Spec (or malli-style schemas) | Medium | Validation + testing |
| 2 | Lazy sequences in prelude | Easy-Medium | Infinite data model |
| 2 | Multimethods | Easy | Open dispatch |
| 2 | Metadata on vars/collections | Medium | Introspection + tooling |
| 3 | core.match enhancements | Easy | Already strong |
| 3 | Zippers, clojure.walk, clojure.set | Easy | Library-level, self-contained |
| 3 | Property testing | Medium | Quality story |
| 3 | Datafy/Nav + REBL-style tooling | Medium | Dev experience |
| 3 | ex-info style structured errors | Easy | Error ergonomics |
| 3 | Specter | Medium | Deep update ergonomics |
| 4 | core.logic | Medium | Niche but fun |
| 4 | Component lifecycle | Medium | Long-running systems |
| 4 | nREPL-style editor integration | Hard | Ecosystem, not language |

The things that Chez/Jerboa already does as well or better than Clojure:
- **Proper tail calls** (no `loop`/`recur` needed)
- **Numeric tower** (Chez rationals + bignums are first-class)
- **Pattern matching** (Jerboa's `match` is strong)
- **Macro hygiene** (Chez's `syntax-case` is arguably more powerful than Clojure's macros)
- **Continuations** (Chez has `call/cc`; Clojure does not)
- **Compilation speed and startup time** (Chez AOT vs JVM warmup)

The things that are cultural/ecosystem rather than language:
- REPL-driven workflow tooling
- Dependency management
- Documentation conventions
- Community-maintained idiom libraries

The language features above are what you'd port. The culture is built alongside, one idiomatic library at a time.
