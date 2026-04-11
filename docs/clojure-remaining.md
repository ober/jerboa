# Clojure compatibility — remaining work

A detailed architecture doc for the outstanding gaps between Jerboa and Clojure,
focused on **core.async** and **the PersistentHashMap family**. Written after
Phases 0-3 of `docs/core-async.md` landed and the persistent data structure
work in tasks 1-7 was merged.

This doc is a plan, not a manifesto. Every gap listed here is scoped, grounded
in a specific file, and sized against work that is already on disk.

---

## Table of contents

1. [Goals and non-goals](#1-goals-and-non-goals)
2. [Current state — what already works](#2-current-state--what-already-works)
3. [core.async — remaining gaps](#3-coreasync--remaining-gaps)
   - 3.1 [Transducer-backed channels (`(chan n xform)`)](#31-transducer-backed-channels-chan-n-xform)
   - 3.2 [`mix` / `admix` / `unmix` / `toggle` / solo-mode](#32-mix--admix--unmix--toggle--solo-mode)
   - 3.3 [Timer wheel for `timeout`](#33-timer-wheel-for-timeout)
   - 3.4 [Callback-style `put!` / `take!`](#34-callback-style-put--take)
   - 3.5 [`async/reduce` and `onto-chan!`/`onto-chan!!`](#35-asyncreduce-and-onto-chanonto-chan)
   - 3.6 [`split` n-way classifier](#36-split-n-way-classifier)
   - 3.7 [Mult slow-subscriber policy](#37-mult-slow-subscriber-policy)
   - 3.8 [Parking go (research, likely deferred)](#38-parking-go-research-likely-deferred)
   - 3.9 [Semantic edges: nil vs eof, closed-channel puts](#39-semantic-edges-nil-vs-eof-closed-channel-puts)
4. [PersistentHashMap family — remaining gaps](#4-persistenthashmap-family--remaining-gaps)
   - 4.1 [Transducer ↔ pmap/pset bridge](#41-transducer--pmappset-bridge)
   - 4.2 [Persistent queue (`clojure.lang.PersistentQueue`)](#42-persistent-queue-clojurelangpersistentqueue)
   - 4.3 [Persistent sorted-set](#43-persistent-sorted-set)
   - 4.4 [Metadata system (`with-meta` / `meta` / `vary-meta`)](#44-metadata-system-with-meta--meta--vary-meta)
   - 4.5 [Value-dispatched multimethods (`defmulti` / `defmethod`)](#45-value-dispatched-multimethods-defmulti--defmethod)
   - 4.6 [Protocols (`defprotocol` / `extend-protocol` / `extend-type`)](#46-protocols-defprotocol--extend-protocol--extend-type)
   - 4.7 [Atom watches + volatiles](#47-atom-watches--volatiles)
   - 4.8 [Agents](#48-agents)
   - 4.9 [Reader literals (`{}`, `#{}`, `[v]`, `:kw`)](#49-reader-literals---v-kw)
   - 4.10 [Record-as-map (`defrecord` map interface)](#410-record-as-map-defrecord-map-interface)
   - 4.11 [IReduce and seq-over-map fast paths](#411-ireduce-and-seq-over-map-fast-paths)
5. [Implementation phases and sequencing](#5-implementation-phases-and-sequencing)
6. [Non-goals](#6-non-goals)
7. [Summary table](#7-summary-table)

---

## 1. Goals and non-goals

### Goals

1. **Port viability.** A Clojure developer porting `core.async` pipelines, ref
   types, persistent data structures, and polymorphic collection operations
   should find an equivalent Jerboa idiom for every non-reader feature they
   touch.
2. **Mental-model parity.** `conj`, `assoc`, `get-in`, `swap!`, `alts!!`,
   `transduce`, `pipeline` should behave exactly as Clojure's counterparts
   modulo explicit documented differences.
3. **No macro gymnastics required.** The user should not need to know which
   library an operator comes from; `(std clojure)` remains the single import
   that pulls in the compatibility surface.
4. **No runtime penalty for non-users.** Every addition lands in a library
   that the rest of `(std ...)` can opt out of via `(except ...)`. The
   prelude grows only for universally-useful names (atoms, `deref`, `swap!`
   are already in; metadata would be).

### Non-goals

1. **CPS-transformed parked `go`.** Explicitly deferred (see §3.8).
2. **Byte-exact compatibility with Clojure's implementation.** The goal is
   behavioural parity, not bit-for-bit identical internals.
3. **Loading `.clj` files.** This is a porting layer, not an interop shim.
4. **`:keyword` leading-colon reader syntax.** Jerboa's reader rewrites
   `:x` into a module path; changing that breaks every existing
   `(import :std/sort)` call in the codebase. Keywords in Jerboa use the
   trailing-colon form `name:` which the reader turns into a `#:name`
   keyword object; in user code, symbols (`'foo`) are the ergonomic
   stand-in for `:foo`.
5. **`{k v}` / `#{a b c}` / `[x y]` collection literal readers.** These
   compose with #1 above — every square bracket in the current codebase
   is a parenthesis, and `{}` is reserved for future reader extensions.
   The `(hash-map ...)` / `(hash-set ...)` / `(vec ...)` constructors are
   the ergonomic stand-ins.
6. **Full `clojure.spec` port.** Separate, massive, likely a research track.

---

## 2. Current state — what already works

### Persistent data structures

| Capability | Module | Status |
|---|---|---|
| HAMT persistent map | `(std pmap)` `lib/std/pmap.sls` | 639 lines — full |
| HAMT persistent set | `(std pset)` `lib/std/pset.sls` | 253 lines — full |
| Bitmapped vector trie | `(std pvec)` `lib/std/pvec.sls` | 328 lines — full |
| Alternative imap/ivec | `(std immutable)` | 167 lines — full |
| Transients for pmap | `persistent-map!`/`tmap-set!` | Task 5 |
| Transients for pvec | `transient`/`persistent!` | Full |
| Transients for pset | `pset-persistent!` | Full |
| Structural equality + hash | `persistent-map=?`/`persistent-map-hash` | Task 7 |
| In-pmap iterators | `in-pmap`/`in-pmap-pairs`/`in-pmap-keys`/`in-pmap-values` | Task 7 |
| Merging / diffing | `persistent-map-merge`/`persistent-map-diff` | Full |
| Sorted map | `(std ds sorted-map)` | 328 lines — full |
| Lazy sequences | `(std seq)` + `(std misc lazy-seq)` | ~574 lines — full |
| Transducer library | `(std transducer)` | 469 lines — full |

### `(std clojure)` surface (already re-exports everything above)

```
get assoc dissoc contains? count keys vals
merge update select-keys
first rest next last
conj cons* empty?
reduce into range
seq =? hash
inc dec
nil? some? true? false?
transient persistent! transient?
assoc! dissoc! conj!
hash-set set set?
disj union intersection difference subset? superset?
hash-map vec list* vector*
make-hash-set
println prn pr pr-str prn-str
atom atom? deref reset! swap! compare-and-set!
get-in assoc-in update-in
```

Plus pmap, pset, pvec, imap, ivec, and concurrent-hash types, all with
polymorphic dispatch inside `count`, `empty?`, `get`, `first`, `last`, `conj`,
`reduce`, `=?`, `hash`, etc.

### core.async — `(std csp)` / `(std csp select)` / `(std csp ops)` / `(std csp clj)`

| Capability | Status |
|---|---|
| Fixed / sliding / dropping buffers | Full |
| `chan-put!`/`chan-get!`/`chan-try-put!`/`chan-try-get` | Full |
| `alts!` / `alts!!` / `alt!` / `alt!!` | Full |
| `timeout` channel | Full (thread-per-timeout) |
| `to-chan` / `onto-chan` / `chan-into` / `chan-reduce` | Full |
| `merge` / `split` / `pipe` | Full |
| `mult` / `tap` / `untap` / `untap-all` | Full |
| `pub` / `sub` / `unsub` / `unsub-all` | Full |
| `pipeline` / `pipeline-async` | Full |
| `promise-chan` | Full |
| `go` / `go-loop` / `clj-thread` | Full (OS-thread based) |
| Clojure-named surface | Full |

### Adjacent capabilities

- **CLOS-style multimethods via class dispatch:** `(std clos)` provides
  `define-generic`/`define-method` with type-based dispatch and method
  combination. This is *type-dispatched*, not value-dispatched.
- **STM refs and alter:** `(std concur stm)` provides software transactional
  memory; Clojure's `ref`/`alter`/`dosync` can be built on it.
- **Concurrent hash map:** `(std concur hash)` for the mutable-with-mutex
  case — not part of the persistent family but covered in `clojure`'s
  polymorphic dispatch.
- **Actor model:** `(std actor)` is available for message-passing use cases
  that would use Clojure's `agent`.

---

## 3. core.async — remaining gaps

### 3.1 Transducer-backed channels (`(chan n xform)`)

**Status:** currently raises
`(error 'chan "transducers are not supported yet")` at
`lib/std/csp/clj.sls:98`.

**What Clojure does.** `(chan n xform [ex-handler])` creates a buffered
channel where every value flowing from `>!` through the internal buffer is
transformed by `xform`. The transducer is applied on the **writer** side:
if `xform` is `(filter odd?)` and the producer `>!`s an even number, the
value is dropped and the buffer stays as-is. If `xform` is `(map inc)`,
the value is incremented. If `xform` is `(take 3)`, the channel closes
after the third successful put.

**Design.**

1. **Extend the `channel` record** in `lib/std/csp.sls` with an optional
   `xform-rf` field. Default `#f`. Zero overhead when absent.

   ```scheme
   (define-record-type channel
     (fields ...
             (mutable xform-rf)   ;; either #f or a reducing function
             (immutable ex-handler)))
   ```

2. **Add a constructor** `make-channel/xform cap xform ex-handler` in
   `lib/std/csp.sls` that:
   - Builds a base channel with capacity `cap`.
   - Constructs a bottom rf that performs the buffer write directly on
     the base channel's internal queue:
     ```scheme
     (define (make-write-rf ch)
       (case-lambda
         [() ch]
         [(acc) (chan-close! acc) acc]
         [(acc val) (q-enqueue! acc val) acc]))
     ```
   - Calls `((xducer-fn xform) (make-write-rf ch))` to fuse the user's
     transducer with the buffer writer. Stores the result in `xform-rf`.
   - Stashes `ex-handler` for step 4.

3. **Branch in `chan-put!` / `chan-try-put!`**: if `xform-rf` is set, call
   `(xform-rf ch val)` inside the channel's mutex instead of
   `q-enqueue!`. The rf handles the filter/map/flat-map logic. Result
   semantics:

   - Returns `ch` (the accumulator) → operation succeeded, value may or
     may not have been enqueued (filter can drop, mapcat can enqueue
     multiple).
   - Returns `(reduced ch)` → transducer signaled "done". Close the
     channel immediately (no further puts accepted). Then unwrap and
     call the 1-arity completion to flush any buffered partial state
     (needed for `partition-all` etc.).

4. **Exception handler.** Wrap the rf call in `guard`:
   ```scheme
   (guard (exn [else
                (cond
                  [ex-handler
                   (let ([replacement (ex-handler exn)])
                     (unless (eq? replacement #f)
                       (q-enqueue! ch replacement)))]
                  [else (raise exn)])])
     (let ([r (xform-rf ch val)])
       (cond
         [(reduced? r)
          (chan-close! ch)
          (xform-rf (unreduced r))]    ;; 1-arity flush
         [else r])))
   ```

5. **Wire the clj layer.** Replace the error stub at `lib/std/csp/clj.sls:97`:
   ```scheme
   [(_n _xform)
    (cond
      [(integer? _n) (make-channel/xform _n _xform #f)]
      [(buffer-spec? _n)
       (make-channel/xform (buffer-spec-size _n) _xform #f)]
      [else (error 'chan "first arg must be integer or buffer spec" _n)])]
   [(_n _xform _ex)
    (make-channel/xform
      (if (integer? _n) _n (buffer-spec-size _n)) _xform _ex)]
   ```

6. **`sliding-buffer` and `dropping-buffer` composition with xform.** If
   the user writes `(chan (sliding-buffer 10) (map inc))`, the policy
   applies *after* the transducer: transducer decides what goes in, then
   the underlying policy handles overflow. Concretely: `make-write-rf`
   calls `q-enqueue!` which already implements the policy, so this falls
   out for free.

**Effort:** ~100 lines in `(std csp)` + ~20 in `(std csp clj)` + ~50 lines
of tests. Half a day.

**Risks:**

- **Stateful transducers across threads.** `(take 3)` captures a mutable
  counter in its closure. With multiple producers `>!`ing concurrently
  on the same transducer-channel, the rf call must be inside the
  channel's mutex — which is already where `chan-put!` executes, so
  this is automatic as long as we don't accidentally drop the mutex.
- **`(chan 0 xform)` edge case.** Clojure allows unbuffered channels with
  transducers; this means the transducer must run at rendezvous time.
  Simplest interpretation: treat `(chan 0 xform)` as `(chan 1 xform)` with
  a warning, since Jerboa has no rendezvous rewind path.

### 3.2 `mix` / `admix` / `unmix` / `toggle` / solo-mode

**What Clojure does.** A `mix` is a dynamic fan-in: you create one with
`(mix out)` pointing to an output channel, then `(admix m ch)` adds `ch`
as a source, `(unmix m ch)` removes it, and `(toggle m {ch {:mute ..,
:pause .., :solo ..}})` lets you per-input mute or pause or solo without
tearing the mix down. Useful for audio streams, log multiplexing, and
any pipeline where the set of inputs changes at runtime.

**Design.**

New file: `lib/std/csp/mix.sls`

```scheme
(define-record-type csp-mix
  (fields out              ;; destination channel
          (mutable inputs) ;; alist: (ch . state)
          state-mutex      ;; guards inputs
          control-ch))     ;; signal channel for reconfig

(define (make-mix out)
  (let ([m (make-csp-mix out '() (make-mutex) (make-channel 1))])
    (fork-thread (lambda () (mix-loop m)))
    m))

(define (mix-loop m)
  (let loop ()
    (let* ([inputs (filter-active (csp-mix-inputs m))]
           [specs  (cons (csp-mix-control-ch m) (map car inputs))]
           [pick   (alts!! specs)]
           [v      (car pick)]
           [ch     (cadr pick)])
      (cond
        [(eq? ch (csp-mix-control-ch m))
         ;; reconfiguration event — reread inputs under mutex
         (loop)]
        [(eof-object? v)
         ;; a source closed — drop it
         (unmix-internal m ch)
         (loop)]
        [else
         (let ([state (assoc-state m ch)])
           (unless (mix-state-muted? state)
             (chan-put! (csp-mix-out m) v)))
         (loop)]))))
```

The **state** per input is a record `(make-mix-state muted? paused?
solo?)`. `filter-active` computes the effective set of input channels
given solo/pause/mute states: if any input has `solo? = #t`, only solo'd
inputs are considered; otherwise all non-paused inputs are considered;
muted inputs are still read from but their values are dropped.

The **control channel** is how reconfiguration wakes the loop. When
`admix` or `toggle` mutates `inputs`, it puts a sentinel on the control
channel so the current `alts!!` unblocks and the new source list is
re-materialized next iteration.

**Exports** (goes into `(std csp ops)` and re-exports in `(std csp clj)`):
```scheme
make-mix mix?
admix unmix unmix-all
toggle solo-mode
```

Clojure names:
```scheme
(define mix    make-mix)
(define admix  admix!)
(define unmix  unmix!)
(define toggle toggle-mix!)
```

**Effort:** ~200 lines for the mix module + 80 lines of tests. One day.

**Risks:**

- **Control-channel back-pressure.** The control channel needs to be
  size-1 and non-blocking (use `chan-try-put!`). Reconfigs must never
  block the caller; dropped control signals are fine because the mix
  loop re-reads the full state every iteration anyway.
- **Race between a source closing and an `unmix!` call.** If both happen
  at once, `unmix-internal` is idempotent (assoc-delete on not-present
  is a no-op), so we're fine.

### 3.3 Timer wheel for `timeout`

**Current behaviour.** `(timeout ms)` at `lib/std/csp/select.sls:259`
creates a fresh channel and spawns one helper thread that sleeps `ms`
then closes the channel. For low-rate timeouts (tens per second) this is
fine. For high-rate short-timeout workloads (rate limiting, retry
back-off, I/O deadlines) the thread churn becomes the bottleneck.

**What Clojure does.** core.async uses Java's `ScheduledThreadPoolExecutor`
to schedule a single closing action per timeout without dedicating a
thread per deadline.

**Design.**

One **timer thread** manages all outstanding deadlines. It owns:

- A **min-heap** keyed by absolute deadline. Entry = `(deadline . channel)`.
  Use `(std misc pqueue)` (already in-tree — a mutable binary heap).
- A **wake-up channel** (size-1) used to nudge the timer thread when the
  current minimum changes because of a new shorter-deadline entry.
- A **mutex** guarding the heap.

Algorithm:

```
loop:
  lock mutex
  if heap empty:
    unlock, block on wake-up channel, loop
  else:
    peek min deadline d
    now = current-time
    if d <= now:
      pop min (chan), close chan, loop
    else:
      unlock
      alts!! on [(timeout-until d), wake-up-chan]
      loop
```

The `timeout-until d` channel is a **single-use** helper backed by one
direct sleep — but only one lives at a time. Or, better, use an
`alts!!` with a computed sleep that can be interrupted: implement via
`condition-wait` with a computed wait-until time on a Chez `condition`.
Chez's condvars don't natively support deadlined waits, so the simplest
correct approach is to call `sleep` on the diff and use the wake-up
channel to short-circuit when a shorter deadline arrives.

```scheme
(define (timeout ms)
  (let* ([deadline (+ (current-time-ms) ms)]
         [ch (make-channel)])
    (timer-wheel-enqueue! deadline ch)
    ch))
```

**Fallback strategy.** Keep the old per-thread implementation as an
alternative and add a compile-time / env switch `JERBOA_CSP_TIMER_WHEEL`
that selects between them. Default off until the wheel has a week of
soak testing.

**Exports.** None — `timeout` stays the public API.

**Effort:** ~150 lines for the wheel + 50 for tests. Half a day.

**Risks:**

- **Heap + wake-up race.** When a new `timeout` with a deadline earlier
  than the current min lands, the timer thread is already sleeping on
  the old (longer) diff. Must signal the wake-up channel under the heap
  mutex so the thread re-reads the new min. Standard pattern.
- **Deadline drift.** Chez's `sleep` is not guaranteed-precise. A
  deadline 10ms away might fire at 11ms or 12ms. This is fine for
  core.async semantics — core.async itself is not a real-time system.
- **Accidental GC pressure.** Each `(timeout ms)` allocates a channel
  record + a heap entry. For pathological high-rate use (10k+ timeouts
  per second) a timeout-channel pool and/or a recycled channel would
  reduce allocations. Defer until it's measured.

### 3.4 Callback-style `put!` / `take!`

**Status.** [landed] `(std csp ops)` exports `put!` and `take!` and the
Clojure names are re-exported from `(std csp clj)`. Both spawn one
helper thread per callback (documented thread-explosion hazard) and
guard the user callback so a raising callback prints a warning to
`current-error-port` instead of silently killing the helper thread.
Exercised by `tests/test-csp.ss` — seven tests covering successful put,
put on a closed channel, fire-and-forget, take that sees a value, take
that sees `eof-object` on close, and a full round-trip.

**What Clojure does.** In addition to the blocking / parking `>!!`/`>!`
and `<!!`/`<!`, core.async offers non-blocking *callback* forms:

```clojure
(put! ch v fn)   ; calls (fn true-or-false) when the put completes
(take! ch fn)    ; calls (fn val) when a value arrives or the chan closes
```

These are the foundation for bridging callback-based APIs (Netty, AJAX,
raw sockets) into channel pipelines without spawning a go block per
request.

**Design.**

```scheme
(define (put! ch v fn)
  (fork-thread
    (lambda ()
      (let ([result (guard (exn [else #f])
                      (chan-put! ch v)
                      #t)])
        (fn result)))))

(define (take! ch fn)
  (fork-thread
    (lambda ()
      (let ([v (chan-get! ch)])
        (fn v)))))
```

This is the naive version: one thread per callback. Fine for the low-
to-medium rate case. A more efficient version would use a dedicated
worker pool that processes callback requests from a shared queue —
roughly equivalent to what Clojure's core.async does with its dispatch
thread.

**Exports.** Add to `(std csp ops)`:
```
put! take!
```
Re-export in `(std csp clj)`.

**Effort:** ~40 lines + tests. 1-2 hours for the naive version.

**Risks:**

- **Exception isolation.** If the callback `fn` throws, the spawned
  thread dies silently. Wrap in `guard` and log, or propagate to a
  user-provided default handler.
- **Thread explosion.** At high request rates the naive per-callback
  thread will create thousands of short-lived threads. Document this
  and point at the worker-pool variant as the production option.

### 3.5 `async/reduce` and `onto-chan!`/`onto-chan!!`

**Status.** [landed] `(std csp ops)` now exports `chan-reduce-async`,
`onto-chan!`, and `onto-chan!!`. `(std csp clj)` re-exports them under
the Clojure names `async-reduce`, `onto-chan!`, `onto-chan!!`.
Matching Clojure's actual implementation, `async-reduce` returns a
plain size-1 channel (NOT a promise-channel) — the first taker gets
the folded value, the channel then closes, and subsequent takers see
`(eof-object)`. Callers who need caching semantics should wrap the
result channel in a mult or promise-chan. Covered by eight tests in
`tests/test-csp.ss`.

**What Clojure does.** `clojure.core.async/reduce` is a go-block reduce
that reads from a channel until it closes and returns a promise-chan
with the final result:

```clojure
(def result-chan (async/reduce + 0 input-ch))
(<!! result-chan)  ; blocks until input-ch closes, then returns the sum
```

`onto-chan!` puts a collection onto a channel asynchronously and closes
the channel (with optional don't-close flag). `onto-chan!!` is the
blocking variant that waits for all puts to complete.

**Design.**

In `(std csp ops)`:

```scheme
;; Async reduce — returns a promise-chan with the final value.
(define (chan-reduce-async f init ch)
  (let ([p (make-promise-channel)])
    (fork-thread
      (lambda ()
        (let loop ([acc init])
          (let ([v (chan-get! ch)])
            (if (eof-object? v)
                (promise-channel-put! p acc)
                (loop (f acc v)))))))
    p))

;; Clojure alias
(define async-reduce chan-reduce-async)

;; Blocking onto-chan.
(define (onto-chan!! ch coll close?)
  (for-each (lambda (v) (chan-put! ch v)) coll)
  (when close? (chan-close! ch)))

;; Non-blocking onto-chan — spawns a feeder thread.
(define (onto-chan! ch coll close?)
  (fork-thread (lambda () (onto-chan!! ch coll close?))))
```

Note: `chan-reduce` (the synchronous form) already exists in
`(std csp ops)`. The async variant is the new addition.

**Exports.** Add to `(std csp ops)`:
```
chan-reduce-async
onto-chan! onto-chan!!
```

**Effort:** ~30 lines + tests. One hour.

**Risks:** Minimal — wraps existing primitives.

### 3.6 `split` n-way classifier

**Current behaviour.** `chan-split` at `lib/std/csp/ops.sls` takes a
predicate and returns a pair of channels (true-chan, false-chan).

**What Clojure does.** `split` takes a predicate and returns
`[true-chan false-chan]` — this is what Jerboa already has. But Clojure
also offers a variant that takes a classification function returning an
arbitrary key, plus a buffer factory for the created channels. This is
better known as `dispatch` or `split-by-key`.

**Design.**

New variant in `(std csp ops)`:

```scheme
(define (chan-classify-by f in buf-fn)
  (let ([outs (make-hash-table)])
    (fork-thread
      (lambda ()
        (let loop ()
          (let ([v (chan-get! in)])
            (cond
              [(eof-object? v)
               (hash-for-each
                 (lambda (_k ch) (chan-close! ch))
                 outs)]
              [else
               (let* ([k  (f v)]
                      [ch (hash-ref outs k
                             (lambda ()
                               (let ([c (buf-fn k)])
                                 (hash-put! outs k c)
                                 c)))])
                 (chan-put! ch v))
               (loop)])))))
    outs))
```

The returned hash-table maps classification keys to freshly-created
channels. `buf-fn` is called with the key to let the caller control
buffer size per-class.

**Exports.** Add to `(std csp ops)` and `(std csp clj)`:
```
chan-classify-by
```

**Effort:** ~40 lines + tests. One hour.

**[landed]** `chan-classify-by` is in `(std csp ops)`; `(std csp clj)`
re-exports it as both `chan-classify-by` and the short Clojure-style
alias `split-by`. The implementation extends the sketch in two ways:
it is thread-safe (a mutex protects the hashtable so callers can read
while the classifier is writing), and it accepts an optional
`initial-keys` list that eagerly pre-creates channels so tests and
known-universe callers can look up channels before the classifier has
processed any values. Arities:

```scheme
(chan-classify-by f ch)
(chan-classify-by f ch buf-fn)
(chan-classify-by f ch buf-fn initial-keys)
```

Default `buf-fn` makes an unbuffered channel; all output channels
(both pre-populated and lazily-created) are closed once the source
closes. Covered by 5 tests in `tests/test-csp.ss`.

### 3.7 Mult slow-subscriber policy

**Current behaviour.** `make-mult` at `lib/std/csp/ops.sls` fans a source
channel out to all tapped subscribers via parallel `chan-put!`. If one
subscriber is slow, it blocks the fan-out thread and stalls every other
subscriber.

**What Clojure does.** core.async's `mult` uses `put!` (callback style)
on all taps and only advances to the next source item when **all** taps
have acknowledged. The default behaviour is therefore "block on slowest
subscriber". Clojure does not ship alternative policies, but several
third-party libraries do: *drop-slow*, *timeout-slow*, *burst-slow*.

**Design.**

Extend `make-mult` to accept an optional policy:

```scheme
(make-mult src)                 ;; block-on-slowest (current behaviour)
(make-mult src 'drop)           ;; drop value for a subscriber that's slow
(make-mult src 'timeout 100)    ;; give each sub 100ms to accept, else drop
```

Implementation for `'drop` mode: use `chan-try-put!` on each subscriber.
If it returns `#f`, that subscriber misses this value. Fast path.

Implementation for `'timeout N`: use `alts!!` with per-subscriber put
specs and a `timeout N` as the default-cutoff:

```scheme
(define (fan-out-with-timeout val subs ms)
  (for-each
    (lambda (sub)
      (alts!! (list (list sub val) (timeout ms))))
    subs))
```

**Exports.** Unchanged signature; additional optional args.

**Effort:** ~60 lines + tests. Two hours.

**Risks:**

- **Mode switching at runtime.** Clojure's mult is fixed at creation
  time; if you want a different policy you create a new mult. Keep the
  same constraint in Jerboa — the policy is set once.

### 3.8 Parking go (research, likely deferred)

**The problem.** Jerboa's `(go body ...)` spawns a real OS thread. Each
thread has a ~2MB stack and full OS scheduling overhead. Clojure's `go`
CPS-transforms the body into a state machine that parks on a lightweight
scheduler, so you can have millions of go-blocks with a single-digit
number of OS threads.

**Options.**

1. **Chez engines.** `(chez engines)` provides an instruction-count-
   bounded preemptive execution primitive. In principle you could build
   a scheduler that runs each go block as an engine, parks it on a
   channel take/put, and resumes on channel signal. **Problem:** engines
   don't compose with `call/cc` or dynamic-wind in the ways Clojure's
   state-machine transform requires, and suspending cleanly at arbitrary
   `>!`/`<!` points is non-trivial without a CPS rewrite.

2. **First-class continuations via `call/cc`.** Write a macro that
   expands `go` bodies into continuation-passing form, where every
   `>!`/`<!` captures the continuation and registers it with the
   scheduler. **Problem:** requires either a full CPS transform (write
   your own Scheme→Scheme compiler pass) or delimited continuations
   (`call/1cc` works, but fully reliable multi-shot suspension is
   hairy). This is a 3-6 month research project, not a library addition.

3. **Wait for Chez to ship fibers.** Not happening on our timeline.

4. **Keep OS-thread go.** Document the scaling ceiling (few thousand
   concurrent go-blocks) and accept it as the Jerboa-specific tradeoff.

**Recommendation.** Option 4 for now. Revisit if we get a concrete
workload that needs tens of thousands of concurrent go-blocks and
threads become the bottleneck. Until then, point users at OS threads +
pipelines + mix as the scaling strategy.

### 3.9 Semantic edges: nil vs eof, closed-channel puts

These aren't new features but they're points of divergence that
porting-guide readers will trip over. Document them in the compat layer
header and in the doc produced by `(std csp clj)`'s docstrings.

**nil vs eof.** In Clojure, `(<! closed-chan)` returns `nil`. In Jerboa
it returns `(eof-object)`. Port idiom:

```
Clojure: (if (nil? v) ... (use v))
Jerboa:  (if (eof-object? v) ... (use v))
```

The rationale is that Jerboa has no universally-nullable base type;
`#f` is a valid payload for many channels (lookups, predicates) so
using it as "channel closed" is wrong. `eof-object` is unambiguous.

**Closed-channel put.** In Clojure, `(>! closed-chan v)` returns `false`
and drops the value. In Jerboa, `chan-put!` raises
`(error 'chan-put! "channel is closed")`. This is more pedantic but
matches Jerboa's general "fail fast on misuse" stance. Port idiom:

```
Clojure: (>! ch v)                 ; silent false on closed
Jerboa:  (or (chan-try-put! ch v)  ; #f on closed or full
             (handle-put-failure))
```

or wrap in a guard to match Clojure's silent-drop semantics:

```scheme
(define (put-or-drop ch v)
  (guard (exn [else #f])
    (chan-put! ch v) #t))
```

**`offer!` / `poll!` semantics.** Clojure's `offer!` returns
`(chan-try-put! ch v)` — `#t` on success, `#f` on full or closed. Jerboa
matches exactly. `poll!` is `(chan-try-get ch)` — returns the value or
`#f` when empty. Matches exactly.

---

## 4. PersistentHashMap family — remaining gaps

### 4.1 Transducer ↔ pmap/pset bridge

**Status.** The `(std transducer)` library (469 lines at
`lib/std/transducer.sls`) already provides full Clojure-parity
transducers — `mapping`, `filtering`, `taking`, `dropping`,
`flat-mapping`, `taking-while`, `dropping-while`, `cat`, `deduplicate`,
`partitioning-by`, `windowing`, `indexing`, composition, `transduce`,
`into`, `sequence`, `eduction`.

**The gap.** `transduce` only accepts a proper list as its source; `into`
only supports `'()`, `#()`, and `""` as destinations. Persistent maps
and sets are not integrated on either end.

**Design.**

1. **Pmap/pset as source.** Extend `transduce` with polymorphic
   iteration:

   ```scheme
   (define (transduce xf rf init coll)
     (let ([xrf (apply-xf xf rf)])
       (cond
         [(persistent-map? coll)
          (call/cc
            (lambda (k)
              (let ([final
                     (persistent-map-fold
                       (lambda (key val acc)
                         (let ([r (xrf acc (cons key val))])
                           (if (reduced? r)
                               (k (xrf (reduced-box-val r)))
                               r)))
                       init coll)])
                (xrf final))))]
         [(persistent-set? coll)
          ... same pattern via persistent-set-fold ...]
         [(persistent-vector? coll)
          ... same pattern via pvec-fold ...]
         [else
          ;; fall through to existing list case
          (let loop ([acc init] [lst coll]) ...)])))
   ```

   Note: pmaps yield `(key . val)` pairs when transduced, matching
   Clojure's `(seq {:a 1})` → `([:a 1])` semantics. Destructuring works
   with `(lambda ((k . v)) ...)` in Jerboa `match`.

2. **Pmap/pset as destination.** Add reducing functions and `into`
   branches:

   ```scheme
   (define (rf-into-pmap)
     (case-lambda
       [()     (transient-map (pmap-empty))]
       [(t)    (persistent-map! t)]
       [(t kv) (tmap-set! t (car kv) (cdr kv)) t]))

   (define (rf-into-pset)
     (case-lambda
       [()    (pset-transient (pset-empty))]
       [(t)   (pset-persistent! t)]
       [(t x) (pset-t-add! t x) t]))

   (define (rf-into-pvec)
     (case-lambda
       [()    (transient (pvec-empty))]
       [(t)   (persistent! t)]
       [(t x) (transient-append! t x) t]))

   (define (into dest xf coll)
     (cond
       [(null? dest)           (sequence xf coll)]
       [(vector? dest)         (transduce xf (rf-into-vector)
                                         ((rf-into-vector)) coll)]
       [(string? dest)         (list->string (sequence xf coll))]
       [(persistent-map? dest) (transduce xf (rf-into-pmap)
                                         ((rf-into-pmap)) coll)]
       [(persistent-set? dest) (transduce xf (rf-into-pset)
                                         ((rf-into-pset)) coll)]
       [(persistent-vector? dest) (transduce xf (rf-into-pvec)
                                         ((rf-into-pvec)) coll)]
       [else (error 'into "unsupported destination type" dest)]))
   ```

   The transients path means bulk ingestion is O(n) rather than
   O(n log32 n) — a meaningful speedup for wide pipes.

3. **Channel bridge.** Once §3.1 lands, `transduce` also accepts a
   `channel?` source that drains via `chan-get!` until eof. This gives
   Clojure's `async/transduce` for free.

**Exports.** Add to `(std transducer)`:
```
rf-into-pmap rf-into-pset rf-into-pvec
```
(existing `into` and `transduce` gain polymorphism — no API change.)

**Effort:** ~80 lines + tests. Two hours.

**Risks.** None — pure wrappers over existing primitives.

### 4.2 Persistent queue (`clojure.lang.PersistentQueue`)

**Status.** `(srfi 134)` at `lib/std/srfi/srfi-134.sls` provides
`ideque` with O(1) amortized `ideque-add-back`, `ideque-remove-front`,
`ideque-front`, `ideque-back` — functionally equivalent to Clojure's
`PersistentQueue` on the relevant operations. Not exposed via
`(std clojure)`.

**The gap.** Clojure programmers write:

```clojure
(def q clojure.lang.PersistentQueue/EMPTY)
(def q2 (conj q 1))
(def q3 (pop q2))
(peek q2) ; => 1
```

Jerboa needs:

1. A polymorphic-`conj` branch for `ideque` that maps to `ideque-add-back`.
2. A `peek` polymorphism (currently undefined for ideque).
3. A `pop` polymorphism (same).
4. A constructor alias: `persistent-queue` / `pqueue`.
5. Re-exports in `(std clojure)`.

**Design.**

New file: `lib/std/pqueue.sls` (thin compat wrapper over srfi 134)

```scheme
(library (std pqueue)
  (export persistent-queue pqueue-empty pqueue?
          pqueue-conj pqueue-peek pqueue-pop
          pqueue-count pqueue->list)

  (import (chezscheme) (std srfi srfi-134))

  (define (persistent-queue . items) (list->ideque items))
  (define pqueue-empty (list->ideque '()))
  (define pqueue?      ideque?)
  (define (pqueue-conj q x) (ideque-add-back q x))
  (define (pqueue-peek q)   (ideque-front q))
  (define (pqueue-pop q)    (ideque-remove-front q))
  (define pqueue-count      ideque-length)
  (define pqueue->list      ideque->list))
```

Extend `(std clojure)`:

```scheme
(define (conj coll x . more)
  (cond
    [(null? coll)              (cons x more)]
    [(pair? coll)              (cons x coll)]
    [(persistent-map? coll)    (persistent-map-set coll (car x) (cdr x))]
    [(persistent-set? coll)    (pset-add coll x)]
    [(persistent-vector? coll) (pvec-append coll x)]
    [(pqueue? coll)            (pqueue-conj coll x)]     ;; new
    ...))

(define (peek coll)
  (cond
    [(pair? coll)              (car coll)]
    [(pqueue? coll)            (pqueue-peek coll)]       ;; new
    [(persistent-vector? coll)
     (if (> (persistent-vector-length coll) 0)
         (persistent-vector-ref coll (- (persistent-vector-length coll) 1))
         #f)]
    ...))

(define (pop coll)
  (cond
    [(pair? coll)              (cdr coll)]
    [(pqueue? coll)            (pqueue-pop coll)]        ;; new
    [(persistent-vector? coll) (persistent-vector-drop-last coll)]
    ...))
```

**Exports.** Add to `(std clojure)`:
```
persistent-queue pqueue-empty peek pop
```

**Effort:** ~80 lines + tests. Two hours.

### 4.3 Persistent sorted-set

**Status.** [landed] `(std sorted-set)` now wraps `(std ds sorted-map)`
(red-black tree) and exposes Clojure's `sorted-set` surface. The module
is re-exported from `(std clojure)` with polymorphic `conj` / `disj` /
`contains?` / `count` / `first` / `last` / `seq` dispatch plus the
`clojure.set` algebra (`union` / `intersection` / `difference` /
`subset?` / `superset?`) that now preserves sorted-set identity when
the first operand is a sorted set. See
`tests/test-sorted-set.ss` for coverage of the primitives and the
polymorphic surface.

**Design.**

New file: `lib/std/sorted-set.sls`

```scheme
(library (std sorted-set)
  (export sorted-set sorted-set? sorted-set-empty
          sorted-set-add sorted-set-remove
          sorted-set-contains? sorted-set-size
          sorted-set-min sorted-set-max
          sorted-set-range sorted-set->list
          sorted-set-fold)

  (import (chezscheme) (std ds sorted-map))

  ;; Implementation strategy: a sorted-set is a sorted-map where every
  ;; key maps to #t. All operations defer to sorted-map.

  (define-record-type sorted-set
    (fields (immutable sm)))

  (define (make-sorted-set)
    (make-sorted-set (make-sorted-map)))

  (define (sorted-set-add ss x)
    (make-sorted-set (sorted-map-insert (sorted-set-sm ss) x #t)))

  (define (sorted-set-contains? ss x)
    (not (not (sorted-map-lookup (sorted-set-sm ss) x #f))))

  (define (sorted-set-range ss lo hi)
    (map car (sorted-map-range (sorted-set-sm ss) lo hi)))

  ... etc
)
```

Then extend `(std clojure)` with polymorphic dispatch for
`sorted-set` in `conj`, `contains?`, `count`, `disj`, `union`,
`intersection`, `difference`, `seq`, `first`, `last`.

Clojure name: `sorted-set`. Constructor takes variadic elements.

**Exports.** Add to `(std clojure)`:
```
sorted-set sorted-set?
```

**Effort:** ~150 lines + tests. Half a day.

**Risks.** None — thin wrapper.

### 4.4 Metadata system (`with-meta` / `meta` / `vary-meta`)

**The gap.** Clojure values can carry an immutable metadata map that
doesn't affect equality or hash but can be queried and updated. Used for
type hints, docstrings, line-number tracking in macros, spec annotations,
cache keys, and so on.

```clojure
(def m (with-meta {:x 1} {:source "input.edn"}))
(meta m)                              ; => {:source "input.edn"}
(= m {:x 1})                          ; => true (metadata not in equality)
(vary-meta m assoc :line 42)          ; => new map with merged metadata
```

**Why it's hard.** Metadata in Clojure is *universal* — every reference
value potentially has it. Strings, numbers, keywords, persistent
collections, records. In Jerboa, only records can carry arbitrary
fields; strings are flat. Short of wrapping every value, we can't
universally attach metadata.

**Pragmatic design.**

Support metadata on **persistent collections only** (pmap, pset, pvec,
ideque). This covers 95% of actual Clojure metadata use cases (macro
source tracking uses metadata on forms, which are lists/vectors; spec
attaches to fnmap/keyword, so that case needs a separate approach).

Option 1 — **field addition.** Add a mutable `meta` field to each
persistent collection record. This is simple but:
- Adds a slot to every instance (memory cost ~8 bytes per map).
- Breaks existing `make-persistent-map` call sites.

Option 2 — **companion weak hash table.** Keep a weak-keyed hash table
`*metadata-table*` mapping object → metadata map. `(with-meta obj m)`
returns a fresh collection (deep structural copy of the immediate node)
and registers metadata. `(meta obj)` does a lookup.

- Pros: no record-layout churn; opt-in; zero overhead when unused.
- Cons: Chez doesn't have weak hash tables in portable form; needs
  `(chezscheme)` internals. Also creating a "fresh" persistent collection
  with the same structural sharing is tricky without internal access.

Option 3 — **wrapper records.** Define a generic `(meta-wrapped value m)`
record that wraps any value with metadata. All polymorphic dispatches
in `(std clojure)` learn to unwrap and delegate:

```scheme
(define-record-type meta-wrapped
  (fields (immutable val) (immutable meta)))

(define (meta x)
  (if (meta-wrapped? x) (meta-wrapped-meta x) #f))

(define (with-meta x m)
  (make-meta-wrapped (if (meta-wrapped? x) (meta-wrapped-val x) x) m))

(define (strip-meta x)
  (if (meta-wrapped? x) (meta-wrapped-val x) x))

;; Every polymorphic op gains a meta-wrapped branch:
(define (count c) (count-impl (strip-meta c)))
(define (get c k) (get-impl (strip-meta c) k))
...
```

Option 3 is the cleanest for Jerboa because it's opt-in (only wrap when
you actually use metadata), zero-cost when not used, and doesn't need
weak refs. The downside is each op needs a dispatch dance to unwrap,
which adds ~2 nsec per call. Probably acceptable.

**Exports.** Add to `(std clojure)`:
```
with-meta meta vary-meta meta-wrapped?
```

**Effort:** ~100 lines of core + ~50 lines of dispatch additions + tests.
Half a day.

**Risks:**

- **Identity semantics.** `(eq? (with-meta x m) x)` is `#f`. Clojure
  users expect `identical?` to distinguish metadata-different-but-
  otherwise-equal values, so this is actually correct. Document it.
- **Hash and equality.** `(equal? (with-meta x m) x)` must return `#t`
  (metadata doesn't affect equality). Implement by unwrapping in the
  equality path.
- **Macro form metadata.** If we later want reader source-tracking
  metadata on syntax objects, that's a separate mechanism that likely
  can't use this wrapper. Note as follow-up work.

### 4.5 Value-dispatched multimethods (`defmulti` / `defmethod`)

**The gap.** Jerboa has `defmethod` in the prelude, but it dispatches on
**struct type** — you write `(defmethod (area (c circle)) ...)` and it
registers a method against the `circle` record type. Clojure's
`defmulti` is orthogonal: the user specifies a *dispatch function* that
returns an arbitrary value, and each `defmethod` binds a dispatch value
to a method implementation.

```clojure
(defmulti area :shape)       ; dispatch on the :shape key
(defmethod area :circle [c]  (* Math/PI (square (:r c))))
(defmethod area :square [s]  (square (:side s)))
(defmethod area :default [x] (throw ...))

(area {:shape :circle :r 3}) ; => 28.27...
```

**Design.**

New file: `lib/std/multi.sls`

```scheme
(library (std multi)
  (export defmulti defmethod remove-method methods
          prefer-method get-method)

  (import (chezscheme))

  ;; A multimethod is a record holding:
  ;; - dispatch-fn      : value → dispatch-key
  ;; - methods          : hash-table of dispatch-key → procedure
  ;; - default-method   : fallback procedure (or error)
  ;; - hierarchy        : optional hierarchy for isa? checks (phase 2)
  (define-record-type multimethod
    (fields (immutable name)
            (immutable dispatch-fn)
            (mutable   methods)
            (mutable   default-method)))

  (define-syntax defmulti
    (syntax-rules ()
      [(_ name dispatch-fn)
       (define name
         (let ([mm (make-multimethod 'name dispatch-fn
                                     (make-hash-table)
                                     (lambda args
                                       (error 'name
                                         "no method for dispatch value"
                                         (apply dispatch-fn args))))])
           (lambda args
             (let* ([k  (apply (multimethod-dispatch-fn mm) args)]
                    [m  (hash-ref (multimethod-methods mm) k #f)])
               (if m
                   (apply m args)
                   (apply (multimethod-default-method mm) args))))))]))

  (define-syntax defmethod
    (syntax-rules ()
      [(_ name dispatch-val (arg ...) body ...)
       (hash-put!
         (multimethod-methods (closure-data name))
         'dispatch-val
         (lambda (arg ...) body ...))])))
```

The trick is that `defmulti` has to define `name` as a procedure that,
when called, looks up the method in the associated multimethod record.
But the record also needs to be mutable so `defmethod` can add entries.
Use a closure over a module-level hash table keyed by name.

**Advanced features to land in a second phase:**

- `isa?` hierarchy for inheritance-style dispatch (`(derive :shape/circle :shape)`).
- `prefer-method` for disambiguation.
- `methods` introspection.

**Exports.** Already listed above.

**Effort:** ~120 lines for the core multi-method dispatcher + ~50 for
tests. Half a day for the basic version; another half-day for hierarchies.

**Risks:**

- **Name clash with prelude's `defmethod`.** The prelude already exports
  a `defmethod` bound to struct-typed dispatch. Rename this module's
  macro to `defmulti-method` or route via `(rename ...)` in `(std clojure)`
  — have `(std clojure)` shadow the struct-typed one. Alternatively,
  teach the prelude's `defmethod` to dispatch on *either* a struct type
  *or* a multimethod name: if the first arg after `defmethod` is a
  multimethod, treat this as a Clojure-style definition.

### 4.6 Protocols (`defprotocol` / `extend-protocol` / `extend-type`)

**The gap.** Clojure protocols are open-world method sets. You define
the set of methods a protocol requires, then any number of types can
opt in by providing implementations:

```clojure
(defprotocol Shape
  (area [self])
  (perimeter [self]))

(extend-type Circle
  Shape
  (area [c] (* Math/PI (square (:r c))))
  (perimeter [c] (* 2 Math/PI (:r c))))

(extend-protocol Shape
  Square     (area [s] (square (:side s)))
             (perimeter [s] (* 4 (:side s)))
  Rectangle  (area [r] (* (:w r) (:h r)))
             (perimeter [r] (* 2 (+ (:w r) (:h r)))))
```

This is the bedrock of Clojure's polymorphism. Spec, core.async, the
persistent collections themselves — everything internally uses protocols.

**Design.**

A protocol is essentially a named bundle of multimethods, each
dispatching on the **type** of their first argument. Given `(std clos)`
already provides `define-generic` / `define-method` with type-based
dispatch, we can build `defprotocol` as a thin layer:

```scheme
(define-syntax defprotocol
  (syntax-rules ()
    [(_ name (fn-name (self arg ...)) ...)
     (begin
       (define-generic fn-name (self arg ...)) ...
       (define name (list 'fn-name ...)))]))

(define-syntax extend-type
  (syntax-rules ()
    [(_ type-class protocol-name (fn-name (self arg ...) body ...) ...)
     (begin
       (define-method fn-name ((self type-class) arg ...) body ...)
       ...)]))

(define-syntax extend-protocol
  (syntax-rules ()
    [(_ protocol-name (type-class (fn-name (self arg ...) body ...) ...) ...)
     (begin
       (extend-type type-class protocol-name
         (fn-name (self arg ...) body ...) ...)
       ...)]))

(define (satisfies? protocol x)
  (for-all
    (lambda (fn-name)
      (not (null? (compute-applicable-methods
                    (symbol-value fn-name)
                    (list x)))))
    protocol))
```

Because `define-generic` is open (`add-method!` can be called at any
time), protocols compose naturally. Existing built-in classes like
`<string>`, `<vector>`, `<pair>` can participate via `extend-type` just
like user records.

**Exports.** Add to `(std clojure)`:
```
defprotocol extend-type extend-protocol satisfies?
```

**Effort:** ~150 lines macro + plumbing + ~80 lines of tests. One day.

**Risks:**

- **Method caching.** CLOS generic dispatch has a cost — per call it
  computes applicable methods. For hot paths (which protocols often
  are) this needs a per-call-site inline cache. `(std clos)` may or
  may not have one; check before committing to this as *the* protocol
  implementation.
- **Cross-type dispatch performance.** If not fast enough, fall back to
  a per-protocol hash-table keyed on record-type-descriptor.

### 4.7 Atom watches + volatiles

**Watches — the gap.** Clojure atoms support `add-watch` and
`remove-watch`: register a callback that fires after every successful
swap with the key, the atom, the old value, and the new value. Used for
reactive UI, log-forwarding, state-change debugging. Missing entirely
from `(std misc atom)`.

**Volatiles — the gap.** Clojure's `volatile!` is a lightweight cell
intended for single-threaded transient accumulators inside transducers.
It has `vswap!` and `vreset!` but **no CAS, no watchers, no
thread-safety**. Meant specifically for `(partition-by)` and friends
where the cell is captured in a closure that's single-threaded by
construction. Missing from `(std misc atom)`.

**Design.**

Extend `(std misc atom)`:

```scheme
(define-record-type atom
  (fields (mutable val)
          (immutable mutex)
          (mutable watches))  ;; new: alist of (key . (old new -> any))
  ...)

(define (add-watch! atom key fn)
  (with-mutex (atom-mutex atom)
    (atom-watches-set! atom
      (cons (cons key fn) (atom-watches atom)))))

(define (remove-watch! atom key)
  (with-mutex (atom-mutex atom)
    (atom-watches-set! atom
      (filter (lambda (w) (not (equal? (car w) key)))
              (atom-watches atom)))))

;; swap! is modified to notify watches after the update.
(define (swap! atom f . args)
  (let-values ([(old new)
                (with-mutex (atom-mutex atom)
                  (let* ([o (atom-val atom)]
                         [n (apply f o args)])
                    (atom-val-set! atom n)
                    (values o n)))])
    (for-each
      (lambda (w) ((cdr w) (car w) atom old new))
      (atom-watches atom))
    new))
```

Watches run **outside** the mutex (after the update is committed) to
avoid holding the lock during user callbacks that might themselves call
back into the atom and deadlock.

For volatiles, add a separate, simpler record:

```scheme
(define-record-type volatile
  (fields (mutable val))
  (sealed #t))

(define (volatile! v) (make-volatile v))
(define (vreset! vol v) (volatile-val-set! vol v) v)
(define (vswap! vol f . args)
  (let ([new (apply f (volatile-val vol) args)])
    (volatile-val-set! vol new)
    new))
(define (vderef vol) (volatile-val vol))
```

No mutex, no watches — this is the whole point.

**Exports.** Add to prelude re-exports and `(std clojure)`:
```
add-watch! remove-watch!
volatile! volatile? vreset! vswap! vderef
```

`@vol` for volatile deref uses `vderef` (same `@`-reader-sugar
limitation applies).

**Effort:** ~80 lines + tests. Two hours.

**Risks:**

- **Atom compatibility.** Adding the `watches` slot to the existing atom
  record changes its layout. Every caller of `make-atom` needs to pass
  an empty watches list. Alternative: put watches in a separate weak
  table to avoid layout churn. Given that all `atom` constructors go
  through `(std misc atom)`, direct field addition is probably cleanest.

### 4.8 Agents

**The gap.** Clojure's agent is an asynchronous state cell with an
action queue: you `(send agent fn args)` and the function is applied to
the current agent value on a background thread pool. Errors put the
agent into an error state that must be cleared via `restart-agent`.

Agents are used for:

1. Accumulating state from many threads without contention on a single
   mutex. (Each send is queued; processing is serialized.)
2. Background I/O coalescing.
3. Actor-like message passing without the full actor-model stack.

**Design.**

Build on top of `(std csp)` — each agent is a channel + a worker thread:

```scheme
(library (std agent)
  (export agent send send-off agent-error clear-agent-errors
          await agent-value)

  (import (chezscheme) (std csp))

  (define-record-type agent
    (fields (mutable val)
            (mutable error)
            action-ch
            worker-thread))

  (define (agent initial-value)
    (let* ([ch (make-channel 64)]
           [a  (make-agent initial-value #f ch #f)]
           [th (fork-thread
                 (lambda ()
                   (let loop ()
                     (let ([action (chan-get! ch)])
                       (unless (eof-object? action)
                         (guard (exn [else (agent-error-set! a exn)])
                           (let ([new-val (apply (car action)
                                                 (agent-val a)
                                                 (cdr action))])
                             (agent-val-set! a new-val)))
                         (loop))))))])
      (agent-worker-thread-set! a th)
      a))

  (define (send ag fn . args)
    (unless (agent-error ag)
      (chan-put! (agent-action-ch ag) (cons fn args)))
    ag)

  ;; send-off uses a dedicated I/O thread pool rather than the default.
  ;; In Jerboa we just alias to send since we don't distinguish thread
  ;; pools.
  (define send-off send)

  (define (await ag)
    ;; Wait for all currently-queued actions to complete.
    ;; Implementation: send a sentinel, block on its completion.
    (let ([done (make-channel 1)])
      (chan-put! (agent-action-ch ag)
                 (cons (lambda (v) (chan-put! done 'done) v) '()))
      (chan-get! done)
      (agent-val ag))))
```

**Exports.** New module `(std agent)` with `agent`, `send`, `send-off`,
`await`, `agent-value`, `agent-error`, `clear-agent-errors`.

**Effort:** ~150 lines + tests. Half a day.

**Risks:**

- **Actor-vs-agent confusion.** `(std actor)` exists for a different
  purpose (supervised message-passing hierarchies). Agent is simpler
  and targets a different use case. Cross-reference in both modules'
  headers.

### 4.9 Reader literals (`{}`, `#{}`, `[v]`, `:kw`)

**The gap.** Clojure's reader supports four shorthand literals that have
no direct Jerboa equivalent:

| Clojure | Meaning | Jerboa workaround |
|---|---|---|
| `{:a 1 :b 2}` | persistent map | `(hash-map 'a 1 'b 2)` |
| `#{:a :b :c}` | persistent set | `(hash-set 'a 'b 'c)` |
| `[1 2 3]` | persistent vector | `(vec 1 2 3)` |
| `:keyword` | keyword | `'keyword` (symbol), or `keyword:` in Jerboa reader form |

**Why this is "non-goal" territory.** Every `[...]` in Jerboa code is
already a parenthesis. Every `{...}` is reserved. Leading `:x` is
already "module path". Changing any of these would break the existing
codebase.

**What we can do instead.**

1. **A reader-mode switch at file scope.** Add a file-local reader
   directive `#!clojure-reader` that, when seen as the first token of
   a `.ss` file, enables:

   - `[1 2 3]` reads as `(persistent-vector 1 2 3)` instead of `(1 2 3)`
   - `{k v}` reads as `(hash-map k v)`
   - `#{a b}` reads as `(hash-set a b)`
   - `:kw` reads as `'kw` (a symbol)

   This is opt-in per file. Existing files stay unchanged. Users who
   want Clojure-literal ergonomics add the directive to the top of the
   file.

2. **Reader macros.** Use Jerboa's reader-extension API (if one exists
   — the current `lib/jerboa/reader.sls` is hand-written and not obviously
   extensible; this may require teaching the reader new productions).
   Gated on the directive above.

**Effort:** ~300 lines of reader work + ~50 lines of tests.
Realistically one to two days, mostly reading the existing reader to
understand the architecture and testing edge cases around error
reporting.

**Risks:**

- **File-local state in a reader.** Most Scheme readers are re-entrant
  and don't track file-scoped directives. Jerboa's reader would need a
  dynamic parameter that's set by `#!clojure-reader` and remains in
  effect for the rest of the file.
- **Interaction with `#!chezscheme` / `#!r6rs`.** These are existing
  file-local switches — `#!clojure-reader` would layer on top.
- **Debuggability.** Error messages get confusing when `[x y]` means
  different things in different files. Document loudly.
- **Could be deferred forever.** If we conclude the ergonomics cost
  isn't worth the reader complexity, skip it and document the
  constructor forms as the permanent Jerboa idiom.

### 4.10 Record-as-map (`defrecord` map interface)

**The gap.** In Clojure, `(defrecord Point [x y])` creates a type whose
instances are **also** persistent maps. You can `(get p :x)`, `(assoc
p :z 10)` (returns a regular map), `(keys p)`, iterate, etc. Jerboa's
`defrecord` creates a struct but the instance isn't a map.

**Design.**

Extend `defrecord` (or add a new `defclojure-record`) so that each
record instance auto-participates in the polymorphic collection API:

```scheme
;; Add a branch to `get`:
(define (get coll key [default #f])
  (cond
    [(record? coll)
     (let ([rtd (record-rtd coll)])
       (let ([field-idx (rtd-field-index rtd key)])
         (if field-idx
             ((record-accessor rtd field-idx) coll)
             default)))]
    ...))
```

This makes `(get point 'x)` work even for plain Jerboa records. For
`assoc` returning a "regular map" version, Clojure's behaviour is that
`assoc` on a record with a known key returns a record; with an unknown
key returns a regular hash-map with all the record fields plus the new
key. We can match this:

```scheme
(define (assoc coll key val . more)
  (cond
    [(record? coll)
     (let* ([rtd (record-rtd coll)]
            [fields (record-fields rtd)])
       (if (memq key fields)
           ;; Known field — return a modified record (requires mutable-
           ;; field support or full reconstruction).
           (reconstruct-record coll key val)
           ;; Unknown field — fall back to pmap.
           (record->pmap-with coll key val)))]
    ...))
```

**Effort:** ~120 lines + tests. Half a day. But note the reconstruction
path is tricky for sealed/immutable records — it might need per-record-
type reconstruction code, which Jerboa doesn't provide out of the box.
Fallback: return a pmap for every assoc, including known fields. Loses
type information but is uniform.

**Risks:** Substantial. Clojure's semantics here are subtle and most
users rely on them. Probably best tackled as a separate design round.

### 4.11 IReduce and seq-over-map fast paths

**The gap.** Clojure's `reduce` dispatches to an `IReduce` protocol
implementation when available for O(1) overhead; otherwise it builds a
lazy seq. This is invisible performance tuning — users never see it —
but it's the difference between "reduce is fast" and "reduce is
allocation-heavy".

Jerboa's `(std clojure)` `reduce` already branches on collection type
and uses the fastest iteration primitive per type (pmap uses
`persistent-map-fold`, vector uses a for loop, etc.). That's basically
what IReduce buys you.

**Verification task.** Benchmark `reduce + 0 (range 1_000_000)` on a
list vs a pvec vs a pmap and confirm the overhead is comparable. If
not, identify the missing fast paths.

**Effort:** ~30 minutes of benchmarking + potentially more if there are
gaps. Probably a 1-hour task total.

---

## 5. Implementation phases and sequencing

Recommended ordering by value-per-hour and dependency graph:

### Phase A — Transducer integration (highest value, smallest scope)

1. **§4.1 transducer ↔ pmap/pset/pvec bridge** (~2 hours)
   - Unlocks Clojure's `(into m xform src)` idiom universally.
   - Zero new concepts for users — just fills in missing edges.

2. **§3.1 `(chan n xform)` transducer-backed channels** (~half day)
   - Biggest single core.async gap for porters.
   - Must come after §4.1 so the xform path is already battle-tested.

### Phase B — Persistent queue and sorted-set (round out the data
structure family)

3. **§4.2 persistent queue** (~2 hours) — wrap ideque, extend `conj`/
   `peek`/`pop` dispatch.

4. **§4.3 persistent sorted-set** (~half day) — wrap sorted-map.

### Phase C — core.async polish

5. **§3.4 put!/take! with callbacks** (~1-2 hours)
6. **§3.5 async/reduce + onto-chan!** (~1 hour)
7. **§3.6 split classifier** (~1 hour)
8. **§3.7 mult slow-subscriber policy** (~2 hours)

These round out the surface for mid-sized porting efforts without
touching any hard problems.

### Phase D — Mix and timer wheel (larger core.async pieces)

9. **§3.2 mix/admix/unmix/toggle** (~1 day)
10. **§3.3 timer wheel for timeout** (~half day)

Both of these are real work but well-bounded.

### Phase E — Polymorphism (Clojure idioms that unlock a lot)

11. **§4.7 atom watches + volatiles** (~2 hours)
12. **§4.5 defmulti value-dispatched multimethods** (~half day)
13. **§4.6 defprotocol over (std clos)** (~1 day)
14. **§4.4 metadata system** (~half day)
15. **§4.8 agents** (~half day)

Phase E is roughly 3 days of work and is the payoff phase — it unlocks
porting of any Clojure library that uses metadata, protocols, or
multimethods, which is almost all of them.

### Phase F — Records as maps, reader literals

16. **§4.10 defrecord map interface** (~half day, plus design debate)
17. **§4.9 Clojure reader-mode switch** (~1-2 days, separate track)

These are the high-cost, high-risk items and should be scheduled
deliberately.

### Phase G — Parking go (indefinitely deferred)

18. **§3.8 CPS-transformed parking go** (research project)

### Totals

| Phase | Items | Estimate |
|---|---|---|
| A — Transducer bridges | 2 | ~1 day |
| B — Queue + sorted-set | 2 | ~1 day |
| C — core.async polish | 4 | ~1 day |
| D — Mix + timer wheel | 2 | ~1.5 days |
| E — Polymorphism | 5 | ~3 days |
| F — Records + reader | 2 | ~2 days |
| **Phases A-E** | **15** | **~7.5 days** |
| F | 2 | ~2 days (or skipped) |
| G | 1 | deferred |

A focused week lands Phases A-E. Phase F is a judgment call. Phase G is
a research project that isn't on the roadmap.

---

## 6. Non-goals

The following are explicitly **not** on the compatibility roadmap:

1. **CPS-transformed parked `go`** (§3.8). We keep OS-thread `go` and
   document the few-thousand scaling ceiling.
2. **Collection literal readers (`{}`, `#{}`, `[v]`, `:kw`)** without the
   opt-in `#!clojure-reader` directive in §4.9. The base reader stays
   Jerboa-native.
3. **`nil` as a universal falsy/missing sentinel.** Jerboa uses `#f`
   for false and `eof-object` for "end of channel / input". Clojure's
   `nil?` checks `(eq? x #f)`; this is the pragmatic compromise.
4. **Clojure STM on top of Clojure's snapshot semantics.** Jerboa has
   `(std concur stm)` but it's a different implementation with
   different guarantees. `ref`/`alter`/`dosync` can be aliased on top
   but the underlying semantics will not be byte-compatible.
5. **Loading `.clj` files.** This is a porting layer, not an interop
   shim. `.clj` files stay on the JVM.
6. **`clojure.spec`** in full. Spec has surface-level helpers that can
   be ported (`def`, `valid?`, `explain`) but the full generative
   testing and conform-unform round-trip machinery is out of scope.
7. **Transient thread-safety checks.** Clojure's transients throw if
   used from a non-owning thread. Jerboa's transients are currently
   best-effort (using them from multiple threads produces undefined
   behaviour but doesn't assert). Adding the check is straightforward
   but not on the critical path.

---

## 7. Summary table

Items marked **[current]** are fully landed. **[gap]** items are scoped
in this doc. **[deferred]** items are non-goals.

### core.async

| Feature | Status | Section |
|---|---|---|
| Fixed/sliding/dropping buffers | [current] | — |
| `>!!`/`<!!`/`close!`/`poll!`/`offer!` | [current] | — |
| `alts!`/`alt!` with priority/default | [current] | — |
| `timeout` channel | [current] (thread-per-timeout) | §3.3 improves |
| `go` / `go-loop` | [current] (OS threads) | §3.8 deferred |
| `to-chan`/`onto-chan`/`chan-reduce` | [current] | — |
| `merge`/`split`/`pipe` | [current] | §3.6 landed |
| `mult`/`tap`/`untap` | [current] | §3.7 slow-sub policy |
| `pub`/`sub`/`unsub` | [current] | — |
| `pipeline`/`pipeline-async` | [current] | — |
| `promise-chan` | [current] | — |
| `(chan n xform)` | [current] `(std csp clj)` | §3.1 landed |
| `mix`/`admix`/`toggle` | [gap] | §3.2 |
| Timer wheel | [gap] | §3.3 |
| `put!`/`take!` with callbacks | [current] `(std csp ops)` | §3.4 landed |
| `async/reduce`, `onto-chan!` | [current] `(std csp ops)` | §3.5 landed |
| `split` n-way | [current] `(std csp ops)` | §3.6 landed |
| Mult slow-sub policies | [gap] | §3.7 |
| Parked `go` (CPS) | [deferred] | §3.8 |
| Transducer error handler on chan | [current] `(std csp clj)` | §3.1 landed |

### Persistent data structures and Clojure idioms

| Feature | Status | Section |
|---|---|---|
| PersistentHashMap (HAMT) | [current] `(std pmap)` | — |
| PersistentHashSet (HAMT) | [current] `(std pset)` | — |
| PersistentVector (BVT) | [current] `(std pvec)` | — |
| PersistentTreeMap | [current] `(std ds sorted-map)` | — |
| Lazy sequences | [current] `(std seq)` | — |
| Transducers | [current] `(std transducer)` | §4.1 bridges |
| Transients | [current] (pmap/pvec/pset) | — |
| Structural equality + hash | [current] | — |
| `in-pmap`/`in-pset`/iterators | [current] | — |
| `get`/`assoc`/`dissoc`/`merge` | [current] `(std clojure)` | — |
| `get-in`/`assoc-in`/`update-in` | [current] `(std misc nested)` | — |
| `conj`/`peek`/`pop` polymorphism | [current] (list/pvec/pqueue/set/map) | §4.2 landed |
| `first`/`rest`/`next`/`last` | [current] | — |
| `reduce`/`into`/`range`/`seq` | [current] | §4.1 into-pmap |
| `inc`/`dec`/`count`/`empty?` | [current] | — |
| `hash-map`/`hash-set`/`vec` constructors | [current] | — |
| Atoms + deref/swap!/reset!/CAS | [current] | — |
| Transducer ↔ pmap/pset bridge | [current] `(std transducer)` | §4.1 landed |
| PersistentQueue | [current] `(std pqueue)` | §4.2 landed |
| Sorted-set | [current] `(std sorted-set)` | §4.3 landed |
| Metadata (`with-meta`/`meta`) | [gap] | §4.4 |
| `defmulti`/`defmethod` value-dispatch | [gap] | §4.5 |
| `defprotocol`/`extend-type` | [gap] | §4.6 |
| Atom watches | [gap] | §4.7 |
| Volatiles | [gap] | §4.7 |
| Agents | [gap] | §4.8 |
| Record-as-map | [gap] | §4.10 |
| `#!clojure-reader` literal switch | [gap] (risky) | §4.9 |
| `{}`/`#{}`/`[]`/`:kw` default reader | [deferred] | §4.9 |
| CPS-transformed parked `go` | [deferred] | §3.8 |
| `.clj` source loading | [non-goal] | §6 |
| Full `clojure.spec` | [non-goal] | §6 |

---

*End of design doc.* When a gap in this list is implemented, move it to
the `[current]` row with a link to the landing commit, and update the
`§N.N` reference in §5 so the phase list reflects remaining work.
