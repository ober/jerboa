# Thread-safe hash tables vs persistent hashmaps in Jerboa

## The two concepts (they're different things)

**Thread-safe mutable hash table** — one hash table exists. Threads take
turns touching it under a mutex. Every write is visible immediately; there's
no "old" state. Cheap per-update (no allocation). Readers block writers (or
use a rwlock). Iteration means either holding the lock the whole time, or
snapshotting to a list first.

**Persistent hashmap** — there is *no* shared mutable table. Each thread
holds an **immutable** snapshot (a HAMT — hash array mapped trie).
"Updating" doesn't touch the old map; it builds a new one that shares nearly
all internal nodes with the old (O(log32 n) allocation, effectively O(1)).
Thread-safety is inherent because nothing is mutated. To coordinate "what's
the current map?" you put the reference in an atomic cell and swap it with
CAS.

They solve different problems:

|                         | Mutable + mutex          | Persistent + atomic cell     |
|-------------------------|--------------------------|------------------------------|
| Per-update cost         | tiny (in-place)          | small allocation             |
| Readers                 | block writers (or rwlock)| **lock-free**, grab snapshot |
| Iteration               | hold lock or copy out    | iterate a snapshot freely    |
| Multi-key consistency   | hand-rolled via lock scope | free (a snapshot *is* consistent) |
| Memory                  | constant                 | O(delta) live snapshots      |
| Forget-to-lock bug      | possible                 | impossible                   |

## What Jerboa actually has

All three classical building blocks are in the stdlib:

### 1. Raw primitives for the mutex approach

From `(jerboa prelude)` / `(std misc thread)`:

```scheme
(def ht  (make-hash-table))
(def mtx (make-mutex))
(with-mutex mtx (hash-put! ht "k" "v"))
(with-mutex mtx (hash-ref  ht "k" #f))
```

There is no pre-built "locked hash table" wrapper — you assemble it yourself.
Every callsite must remember to lock.

### 2. A persistent HAMT — `(std immutable)` (wraps `(std pmap)`)

```scheme
(import (std immutable))

(def m  (imap "a" 1 "b" 2))              ;; HAMT, 32-way branching, O(log32 n)
(def m2 (imap-set m "a" 99))              ;; returns new map, original untouched
(imap-ref m  "a")                         ;; => 1
(imap-ref m2 "a")                         ;; => 99
```

Verified working end-to-end: setting a key produces a new map while the
original still reads the old value.

**But there is a real bug**: `lib/std/pmap.sls:122` has a wrong-arity
`assoc` call (`(assoc key pairs equal-proc)` — Chez `assoc` only takes 2
args). It compiles as a warning and happens to still work for the common
case, but it will fail at runtime on a true hash collision. Worth fixing
before relying on this in production.

### 3. An atomic cell — `(std misc shared)`

The Clojure-atom analogue. This is the missing piece that turns a persistent
map into a "mutable-looking" API:

```scheme
(import (std misc shared)
        (std immutable))

(def state (make-shared (imap)))                              ;; atom holding imap
(shared-update! state (lambda (m) (imap-set m "k" "v")))      ;; functional update
(imap-ref (shared-ref state) "k" #f)                          ;; lock-free read
(shared-cas! state old-map new-map)                           ;; CAS
```

`shared-update!` takes the lock, applies the function, writes back. So
writers are serialized, but **readers never lock** — `shared-ref` grabs the
current imap pointer, and once you have it, you can iterate/filter/fold
without coordination because it's immutable.

Full API of `(std misc shared)`:

- `make-shared` / `shared?`
- `shared-ref`      — lock-free read of the current value
- `shared-set!`     — write
- `shared-update!`  — `(shared-update! s proc args…)` → `(proc old args…)`
- `shared-cas!`     — compare-and-swap, returns #t/#f
- `shared-swap!`    — atomic apply-and-return-old

### 4. `(std stm)` — Software Transactional Memory

```scheme
(import (std stm))

(def cell (make-tvar (imap)))
(atomically
  (tvar-write! cell (imap-set (tvar-read cell) "k" "v")))
```

Full API: `make-tvar`, `tvar?`, `tvar-read`, `tvar-ref`, `tvar-write!`,
`atomically`, `retry`, `or-else`.

Overkill for a single table, but if you ever need "update map A and map B
atomically," this is the right tool — you cannot do that with either of the
above without manual locking.

### 5. `(std concur)` — hardening tools

Useful for auditing once you've picked one of the approaches above:

- `defstruct/thread-safe` / `defstruct/immutable` / `defstruct/thread-local`
  — safety annotations
- `make-tracked-mutex` / `tracked-lock!` / `tracked-unlock!` /
  `with-tracked-mutex` — mutex with deadlock detection
- `deadlock-check!` / `lock-order-violations` — audit queries
- `register-resource!` / `close-resource!` / `check-resource-leaks!` —
  resource leak tracking

## Recommendation

If I had to pick one default for "I want a thread-safe hash-table-ish thing"
in Jerboa, I would pick **imap + shared cell** (option 2 + 3). Reasons:

- You *cannot* forget to synchronize. There's only one synchronization
  point — the cell — and every mutator goes through `shared-update!`.
- Readers are lock-free, which matters a lot if the table is read-heavy.
- Iterating is trivial and consistent: `(shared-ref state)` hands you a
  frozen snapshot you can walk without worrying about it changing
  underneath you.
- It composes with functional code:
  `(->? (shared-ref state) (imap-set …) …)`.

The mutex approach wins in exactly one scenario: very high write throughput
on a large table where the per-update allocation from imap matters. If
you're writing millions of updates per second, that allocation is real.

## Decision criteria

Before picking a concrete version, think through:

1. **Read/write ratio?** Mostly reads with occasional writes → imap+shared
   is clearly better. Heavy writes → mutex approach may be worth the
   ergonomic cost.
2. **Do you need to iterate the table?** (e.g. "scan all entries matching
   X"). If yes, imap+shared is a much better fit — you'd otherwise have to
   hold the mutex across iteration or copy-out.
3. **Do you need multi-key consistency?** (e.g. "move a value from key A to
   key B atomically, and nothing in between sees either state"). If yes,
   imap+shared handles it naturally; mutex approach needs careful lock
   scoping; anything cross-table needs `(std stm)`.
4. **Static/musl build or development?** The `pmap.sls:122` bug is a latent
   landmine for `imap` users — budget a small fix before shipping if you
   choose the persistent approach.

## Sketch: the recommended pattern

```scheme
(import (jerboa prelude)
        (std immutable)
        (std misc shared))

;; Create a thread-safe "hash-table-like" thing
(def users (make-shared (imap)))

;; Writers go through shared-update!, which serializes via mutex
(def (add-user! id data)
  (shared-update! users (lambda (m) (imap-set m id data))))

(def (remove-user! id)
  (shared-update! users (lambda (m) (imap-remove m id))))

;; Readers are lock-free: grab snapshot, use it freely
(def (get-user id)
  (imap-ref (shared-ref users) id #f))

;; Iteration is trivial and consistent — no lock held
(def (all-admins)
  (let ([snapshot (shared-ref users)])
    ;; walk snapshot with your favorite fold — it won't change
    (imap->list snapshot)))  ; or whatever imap's traversal is

;; Multi-key atomic update — transform the whole map in one swap
(def (rename-user! old-id new-id)
  (shared-update! users
    (lambda (m)
      (let ([data (imap-ref m old-id #f)])
        (if data
            (imap-set (imap-remove m old-id) new-id data)
            m)))))
```

Notes on this sketch:

- Every mutation is a `shared-update!` call with a pure function on the
  imap. You literally cannot forget the lock.
- `get-user` doesn't touch the mutex at all — `shared-ref` is a plain read
  of the current pointer.
- `rename-user!` is atomic without any explicit locking because the whole
  transformation is one function over the snapshot.
- If `rename-user!` needed to coordinate with another `shared` cell, you'd
  reach for `(std stm)` with two `tvar`s instead.

## How Jerboa's pmap compares to Clojure's PersistentHashMap

Both are HAMTs in the Phil-Bagwell-2001 sense — 32-way branching, bitmap-
indexed sparse interior nodes, path copying on insert, collision buckets for
true hash collisions. Jerboa's `(std pmap)` nails the core structure. But
Clojure's `PersistentHashMap` has 15 years of production-driven optimizations
layered on top that `pmap.sls` does not have. Honest comparison:

### What they agree on

- 5 bits per level, 32-way branching
- Bitmap + popcount compact array trick for sparse interior nodes
  (Jerboa: `hamt-bitpos`, `hamt-index`; Clojure: `bitpos`, `index`)
- Path copying on insert / delete
- Collision buckets when two distinct keys produce the same full hash

So the asymptotic shape is identical: O(log₃₂ n) ≈ effectively-O(1) for
ref / set / delete.

### What Clojure has that Jerboa's pmap is missing

**1. Transients — the big one.**
Clojure lets you "thaw" a persistent map into a transient, do a bulk of
mutations (`assoc!`, `dissoc!`) with near-mutable cost because only one
owner is assumed, then freeze it back (`persistent!`). Building a 100k-entry
map from an alist is ~4–8× faster with transients than with repeated
`assoc`. Jerboa's pmap has no transient mechanism — every `imap-set` inside
`persistent-map-map` / `persistent-map-filter` / `persistent-map-merge`
allocates a full path copy. See pmap.sls:344-358: `persistent-map-map`
literally does `(set! result (persistent-map-set result k (proc k v)))` in
a loop, one allocation-heavy step at a time.

**2. No ArrayNode (dense-node optimization).**
Clojure has *two* interior-node types: `BitmapIndexedNode` for sparse nodes
and `ArrayNode` for dense ones. When a bitmap-indexed node would reach ~16
children, Clojure promotes it to a 32-slot flat array with `nil` in empty
slots. Lookups in an ArrayNode skip the popcount indirection — you go
straight to `array[hash_chunk]`. Jerboa only has the bitmap variant, so
every lookup pays the popcount cost at every level, even in hot dense
regions of the tree.

**3. Leaves stored inline, not boxed.**
Clojure's `BitmapIndexedNode` stores `[k1, v1, k2, v2, …]` (or
`[nil, child]` for nested nodes) directly in the node's single array.
Jerboa allocates a separate `hamt-leaf` record for every leaf and stores a
pointer to it in the parent's array (pmap.sls:51-52, used throughout). For
a 1M-entry map that's 1M extra heap objects and one extra pointer
indirection on every successful lookup.

**4. A hash function picked for HAMT.**
Clojure uses Murmur3 (and `mix-collection-hash`) specifically because HAMT
performance is very sensitive to the uniformity of the low bits. Jerboa
pmap uses Chez's stock `equal-hash`, which is a reasonable general-purpose
hash but wasn't designed for this. In practice it's probably fine; in
pathological distributions it could mean deeper trees.

**5. Structural equality and hashing.**
A Clojure map *is* hashable by contents, so you can use a map as a key in
another map, and `(= m1 m2)` compares contents. Jerboa's `%pmap` is a plain
record — it uses identity equality by default, so you can't use an `imap`
as a key in an `imap` and `equal?` on two pmaps won't do what you want.

**6. Seq abstraction / lazy iteration.**
Clojure maps participate in the `seq` / `reduce` / `transducer` abstractions
for free, including early termination via `reduced`. Jerboa provides
`persistent-map-for-each`, `->list`, `-fold`, etc., but no lazy iterator —
no way to stop iteration early without hand-rolling an escape continuation.

**7. The `assoc` bug lives in the collision-bucket path.**
pmap.sls:122:

```scheme
[(hamt-coll? node)
 (and (= (hamt-coll-hash node) key-hash)
      (let ([p (assoc key (hamt-coll-pairs node) equal-proc)])  ; BUG
        p))]
```

Chez's `assoc` takes 2 args, not 3. SRFI-1's `assoc` takes an optional
3rd `=` argument, but Chez's built-in does not. So on any true hash
collision where you try to look up the colliding key, this will raise a
wrong-number-of-arguments error at runtime. The insert path at
pmap.sls:209 has the same bug. Fix is straightforward:

```scheme
;; replace (assoc key pairs equal-proc) with a hand-rolled find:
(let loop ([ps pairs])
  (cond
    [(null? ps) #f]
    [(equal-proc (caar ps) key) (car ps)]
    [else (loop (cdr ps))]))
```

This only bites on true hash collisions, which is why the compile warning
doesn't show up as an obvious runtime failure in normal testing. But once
you fix it, collision handling becomes correct.

### Practical takeaway

For a "thread-safe hash-table-ish thing" with light-to-moderate write rates,
Jerboa's pmap is functionally equivalent to Clojure's — same asymptotic
behavior, same thread-safety-by-immutability guarantee. The practical
differences only start to bite at:

- **Bulk construction** from large collections → you'll feel the lack of
  transients (a 10× hit on `persistent-map-map` / `persistent-map-merge`
  over millions of entries).
- **Very large dense maps** → ArrayNode absence adds a constant factor to
  every lookup, maybe 1.5–2× slower than Clojure at 1M+ entries.
- **Collision-heavy workloads** → the `assoc` bug at pmap.sls:122 will
  surface as a runtime crash. Fix it before shipping.

For the common case (thousands to tens of thousands of entries, moderate
mutation rate, read-heavy), the gap between Jerboa's pmap and Clojure's PHM
is not going to be your bottleneck. `imap + shared` remains the right
default for a thread-safe hash-table-like value in Jerboa.
