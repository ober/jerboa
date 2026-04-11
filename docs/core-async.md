# Clojure `core.async` on Jerboa — design & porting guide

## Goals

1. Let Clojure developers port `core.async` code to Jerboa with minimal rewrites.
2. Offer a Clojure-style channel API (`chan`, `>!!`, `<!!`, `alts!!`, `pub`, `sub`, `mult`, `tap`, `pipeline`, `promise-chan`, etc.) backed by Jerboa's primitives.
3. Achieve **functional parity**, not byte-level parity. Same mental model, same operator names, same argument order. If Jerboa is slower, that's acceptable as long as programs are usable.

## Non-goals

1. **CPS-transformed `go` blocks.** Clojure's `go` is a macro that rewrites code into a state machine so parks yield the scheduler thread. Chez has no built-in CPS transform, and writing one over the full Jerboa form language is a research project. We use real OS threads for `go`, period.
2. **Bytecode or wire compatibility** with Clojure's implementation.
3. **Loading unmodified `.clj` files.** This is a *porting* layer, not an interop shim.

---

## Current state of `(std csp)` — honest audit

Reading `lib/std/csp.sls` directly, the current implementation is a **minimum viable stub** whose docstring overstates what's shipped:

| Claimed in the header comment                      | Actually exported | Reality                                                                    |
|----------------------------------------------------|-------------------|----------------------------------------------------------------------------|
| "green threads scheduled via Chez's engine system" | `go`              | `go` is `fork-thread`. No scheduler, no engines. Pure OS threads.          |
| `(select clause ...)`                              | **not exported**  | No implementation at all. The header comment is lying.                     |
| `(yield)`                                          | exported          | `(sleep (make-time 'time-duration 1000000 0))` — a 1ms sleep. Not a yield. |
| `(make-channel/buf n)`                             | exported          | Works, but uses `append` to enqueue → **O(n) per put**. Real perf bug.     |
| `chan-try-get`                                     | exported          | OK. Returns `#f` on empty (matches core.async `poll!`).                    |
| `chan-try-put!`                                    | —                 | **Missing.** No `offer!` equivalent.                                       |
| Sliding / dropping buffers                         | —                 | **Missing.** `make-channel/buf` always blocks on full.                     |
| Timeout channels                                   | —                 | **Missing.**                                                               |

**Before building the Clojure layer**, `(std csp)` needs these fixes:

1. Replace the `append`-based queue with a proper FIFO (head+tail cons pointers, or a deque).
2. Delete the false "engines / green threads" claim from the docstring, or implement it for real.
3. Implement `select` since it's already promised in the header comment.
4. Add `chan-try-put!`.

Everything below assumes those fixes land first.

---

## Module layout

```
lib/std/csp.sls              — primary CSP API (Jerboa-native names)
lib/std/csp/select.sls       — select / alts! implementation
lib/std/csp/buffer.sls       — fixed / sliding / dropping buffers
lib/std/csp/mult.sls         — mult, tap, untap
lib/std/csp/pubsub.sls       — pub, sub
lib/std/csp/mix.sls          — mix, admix, unmix, toggle
lib/std/csp/pipeline.sls     — pipeline, pipeline-async, pipeline-blocking
lib/std/csp/clj.sls          — Clojure-compat re-exports (<!!, >!!, chan, etc.)
```

The Clojure-compat layer is a thin file that does nothing but `(import (std csp))` and re-export under Clojure names. Porting a `core.async` program becomes:

```scheme
(import (jerboa prelude))
(import (std csp clj))   ;; brings in chan, >!!, <!!, go, alts!!, pub, sub, mult, tap, ...

(def c (chan 10))
(go (>!! c "hello"))
(println (<!! c))
```

**Naming rule:** the Jerboa-native name is the one the rest of the stdlib uses.
The Clojure name is an alias. Both exist; pick whichever reads better. Mixing them in one file is legal but discouraged.

---

## Section 1 — Channel creation & buffers

### Clojure API

```clojure
(chan)                 ; unbuffered
(chan 10)              ; fixed buffer, blocks writer when full
(chan (buffer 10))     ; same thing
(chan (sliding-buffer 10))   ; drop oldest on full
(chan (dropping-buffer 10))  ; drop newest on full
(chan 10 xform)        ; buffer + transducer
(chan 10 xform ex-handler)   ; buffer + transducer + exception handler
```

### Jerboa mapping

| Clojure                      | Jerboa-native                  | Clojure alias                | Status                              |
|------------------------------|--------------------------------|------------------------------|-------------------------------------|
| `(chan)`                     | `(make-channel)`               | `(chan)`                     | **shipped**                         |
| `(chan n)`                   | `(make-channel/buf n)`         | `(chan n)`                   | **shipped** (fix O(n) queue)        |
| `(chan (sliding-buffer n))`  | `(make-channel/sliding n)`     | `(chan (sliding-buffer n))`  | **to add**                          |
| `(chan (dropping-buffer n))` | `(make-channel/dropping n)`    | `(chan (dropping-buffer n))` | **to add**                          |
| `(chan n xform)`             | `(make-channel/xform n xform)` | `(chan n xform)`             | **to add** (see transducer section) |

### Implementation notes

A *buffer* in core.async is just a strategy for `add!`/`remove!`. We introduce a small record:

```scheme
(defstruct chan-buffer (add! remove! full? empty? count))
```

- **Fixed**: `full?` when `count = capacity`.
- **Sliding**: `full?` is always `#f`; `add!` drops head when at capacity.
- **Dropping**: `full?` is always `#f`; `add!` discards the incoming value when at capacity.

Swap the current inlined buffer logic in `channel` for a `chan-buffer` field. `chan` itself stays a single record type.

---

## Section 2 — Take / put operations

Clojure exposes two parallel universes:

|                    | Parking (only inside `go`) | Blocking (outside `go`) |
|--------------------|----------------------------|-------------------------|
| Take               | `(<! ch)`                  | `(<!! ch)`              |
| Put                | `(>! ch v)`                | `(>!! ch v)`            |
| Select             | `(alts! ...)`              | `(alts!! ...)`          |
| Conditional select | `(alt! ...)`               | `(alt!! ...)`           |

In Jerboa, since `go` is a real OS thread, **parking and blocking collapse to the same operation**.
We still ship both names so Clojure code ports verbatim:

```scheme
(define <!  chan-get!)    ;; parking form — in Jerboa, same as blocking
(define <!! chan-get!)    ;; blocking form
(define >!  chan-put!)
(define >!! chan-put!)
```

Note: `>!`, `<!`, `>!!`, `<!!` are all valid Chez symbols. No reader changes needed.

### Non-blocking / polling

| Clojure         | Jerboa-native          | Clojure alias   | Status                                     |
|-----------------|------------------------|-----------------|--------------------------------------------|
| `(poll! ch)`    | `(chan-try-get ch)`    | `(poll! ch)`    | **shipped** (Jerboa native) — alias to add |
| `(offer! ch v)` | `(chan-try-put! ch v)` | `(offer! ch v)` | **to add**                                 |

`poll!` returns the value or `nil`; `chan-try-get` returns the value or `#f`. In Scheme, `#f` *is* the idiomatic "nothing," so the alias is literal.

### Close / closed?

| Clojure | Jerboa-native | Clojure alias | Status |
|---------|---------------|---------------|--------|
| `(close! ch)` | `(chan-close! ch)` | `(close! ch)` | **shipped** — alias to add |
| (no public `closed?`) | `(chan-closed? ch)` | — | **shipped** |

**Semantic quirk:** Clojure `<!` on a closed, drained channel returns `nil`.
Jerboa `chan-get!` returns `(eof-object)`. Under the Clojure-compat layer, `<!`/`<!!` must
translate `eof-object` → `#f` (or `'nil`, if we want exact Clojure-nil semantics — discuss below).

---

## Section 3 — `select` / `alts!`

This is the single most important gap. Without it, Clojure code using `alts!` for timeouts or fan-in can't be ported at all.

### Clojure API

```clojure
(alts!! [ch1 ch2 [ch3 value]])
;; → [value chan]  — the chan that won; if it was a put, value is true
(alts!! [ch1 ch2] :default :nothing)
;; → [:nothing :default] if nothing ready
(alts!! [ch1 ch2] :priority true)
;; → try in order instead of randomly

(alt!!
  ch1         ([v]      (handle-ch1 v))
  [ch2 :put]  ([ok?]    (handle-ch2))
  (timeout 1000) :timed-out
  :default    :nothing)
```

### Proposed Jerboa implementation

There's already `(std event)` with `sync`/`choice`/`select` that implements Racket-style first-class events. The cleanest path is to **bridge CSP channels into the event system**:

```scheme
;; In (std csp select):
(define (chan-recv-evt ch)
  (make-event
    (lambda ()                      ;; poll
      (let ([v (chan-try-get ch)])
        (if v (values #t v) (values #f #f))))
    (lambda ()                      ;; sync (block)
      (chan-get! ch))))

(define (chan-send-evt ch v)
  (make-event ... ))
```

Once channels expose themselves as events, `alts!!` is a one-liner:

```scheme
(define (alts!! specs)
  ;; specs = list of channels or (list chan value) for puts
  (apply select (map spec->event specs)))
```

The harder path is to add a **waiter list** to each channel and a dedicated scheduler
— lower latency, more code. Start with the event-bridge approach; measure; optimize if needed.

### Mapping

| Clojure          | Jerboa-native                  | Clojure alias    | Status     |
|------------------|--------------------------------|------------------|------------|
| `(alts! [...])`  | `(chan-select-recv chans)`     | `(alts! [...])`  | **to add** |
| `(alts!! [...])` | same (blocking = parking here) | `(alts!! [...])` | **to add** |
| `(alt! ...)`     | `chan-select` macro            | `(alt! ...)`     | **to add** |
| `(alt!! ...)`    | same                           | `(alt!! ...)`    | **to add** |
| `:priority true` | 2nd arg to `chan-select-recv`  | `:priority true` | **to add** |
| `:default`       | 2nd arg                        | `:default`       | **to add** |

---

## Section 4 — Timeouts

### Clojure API

```clojure
(timeout 5000)   ; a channel that closes itself after 5000ms
```

Used idiomatically in `alts!`:

```clojure
(alts!! [work-ch (timeout 1000)])
```

### Jerboa implementation

A timeout channel is just:

```scheme
(define (timeout ms)
  (let ([ch (make-channel)])
    (go (lambda ()
          (thread-sleep! (/ ms 1000.0))
          (chan-close! ch)))
    ch))
```

One OS thread per timeout is expensive at scale. A better impl uses a single timer-wheel thread that closes channels when their deadlines pass. For v1, the naive version is fine.

| Clojure        | Jerboa-native          | Clojure alias  | Status     |
|----------------|------------------------|----------------|------------|
| `(timeout ms)` | `(timeout-channel ms)` | `(timeout ms)` | **to add** |

---

## Section 5 — `go` and `thread`

### Clojure API

```clojure
(go body...)       ; state-machine rewrite; parks on <!/>!
(thread body...)   ; runs on a dedicated thread (no parking)
```

### Jerboa reality

Both forms compile to `fork-thread` in Jerboa.
They're aliases. We still ship both names because Clojure code distinguishes
"I expect this to do blocking I/O, put me on a real thread" (`thread`)
from "I expect to park on channels" (`go`). In Jerboa, they're identical.

```scheme
(define-syntax go
  (syntax-rules ()
    [(_ body ...) (fork-thread (lambda () body ...))]))

(define-syntax clj-thread   ;; don't shadow (std misc thread)
  (syntax-rules ()
    [(_ body ...) (fork-thread (lambda () body ...))]))
```

**Return value:** Clojure `go` and `thread` return a channel that will receive the body's result when done. This is cheap to emulate:

```scheme
(define-syntax go
  (syntax-rules ()
    [(_ body ...)
     (let ([result-ch (make-channel 1)])
       (fork-thread
         (lambda ()
           (let ([v (begin body ...)])
             (chan-put! result-ch v)
             (chan-close! result-ch))))
       result-ch)]))
```

Now `(<!! (go (expensive-calc)))` works as a Clojure dev expects.

### Go-loop

`(go-loop [bindings] body...)` expands to `(go (loop [bindings] body...))`. Trivial macro.

### The real cost

Every `go` is an OS thread.
A Clojure program that spawns 10,000 `go` blocks and has them park on channels runs happily on ~8 threads in core.async.
The same program on Jerboa spawns 10,000 OS threads. Linux can handle it, but:

- Each thread is ~2 MB stack by default.
- Context-switch cost is much higher than core.async's state-machine yielding.
- Chez's GC has to scan every thread's stack.

**This is the honest cost of functional parity without CPS.** Document it prominently.
Programs that use `go` like "a lightweight task" will be fine up to low thousands.
Programs that use `go` like "millions of actors" will not scale.

Future work: investigate Chez **engines** (`(chezscheme)` has a cooperative engine system) or **call/cc**-based coroutines for a real parking `go`. That's a v2 conversation.

| Clojure              | Jerboa-native                         | Clojure alias          | Status                                             |
|----------------------|---------------------------------------|------------------------|----------------------------------------------------|
| `(go body...)`       | `(go thunk)` exists but takes a thunk | `(go body...)` macro   | **to add macro**                                   |
| `(go-loop [b] body)` | —                                     | `(go-loop [b] body)`   | **to add**                                         |
| `(thread body...)`   | `(spawn thunk)`                       | `(clj-thread body...)` | **to add** (named `clj-thread` to avoid shadowing) |

---

## Section 6 — Collection interop

| Clojure                      | Jerboa-native                   | Clojure alias               | Status              |
|------------------------------|---------------------------------|-----------------------------|---------------------|
| `(to-chan coll)`             | `(list->chan lst)`              | `(to-chan lst)`             | **to add**          |
| `(onto-chan ch coll)`        | `(chan-put-all! ch lst)`        | `(onto-chan ch lst)`        | **to add**          |
| `(onto-chan ch coll close?)` | same, 3rd arg                   | `(onto-chan ch lst close?)` | **to add**          |
| `(into coll ch)`             | `(chan->list ch)` (lists only)  | `(into [] ch)`              | **shipped (lists)** |
| `(reduce f init ch)`         | `(chan-reduce f init ch)`       | `(reduce f init ch)`        | **to add**          |
| `(transduce xf f init ch)`   | `(chan-transduce xf f init ch)` | `(transduce xf f init ch)`  | **to add**          |

All of these are tiny. The pattern is always "spawn a go, loop over `<!`, apply f, repeat until eof." None of them need runtime support beyond what `(std csp)` already gives us.

---

## Section 7 — Channel composition

### `merge` — fan in

```clojure
(merge [ch1 ch2 ch3])     ; returns new ch that gets everything from all inputs
(merge [ch1 ch2] 10)      ; with buffer
```

```scheme
(define (chan-merge chans . buf)
  (let ([out (if (null? buf) (make-channel) (make-channel/buf (car buf)))]
        [remaining (length chans)]
        [lk (make-mutex)])
    (for-each
      (lambda (ch)
        (go (lambda ()
              (let loop ()
                (let ([v (chan-get! ch)])
                  (cond
                    [(eof-object? v)
                     (with-mutex lk
                       (set! remaining (- remaining 1))
                       (when (zero? remaining) (chan-close! out)))]
                    [else (chan-put! out v) (loop)]))))))
      chans)
    out))
```

### `pipe` — unidirectional forwarding

```clojure
(pipe from to)           ; pumps from → to, closes to when from closes
(pipe from to false)     ; don't close to
```

Jerboa already has `chan-pipe` but with a transform function. Split it:

```scheme
(define (chan-pipe from to . close?)
  (go (lambda ()
        (let loop ()
          (let ([v (chan-get! from)])
            (cond
              [(eof-object? v)
               (when (or (null? close?) (car close?))
                 (chan-close! to))]
              [else (chan-put! to v) (loop)]))))))
```

### `split` — conditional fan out

```clojure
(split pred ch)  ; returns [true-ch false-ch]
```

Straightforward — spawn one go, switch on `(pred v)`.

| Clojure           | Jerboa-native          | Clojure alias     | Status               |
|-------------------|------------------------|-------------------|----------------------|
| `(merge chans)`   | `(chan-merge chans)`   | `(merge chans)`   | **to add**           |
| `(merge chans n)` | `(chan-merge chans n)` | `(merge chans n)` | **to add**           |
| `(pipe from to)`  | `(chan-pipe from to)`  | `(pipe from to)`  | **rewrite existing** |
| `(split pred ch)` | `(chan-split pred ch)` | `(split pred ch)` | **to add**           |

---

## Section 8 — `mult` / `tap` / `untap`

Broadcast one channel to many dynamic subscribers. The most commonly used core.async composition operator after `alts!`.

```clojure
(def m (mult source-ch))
(def sub1 (chan))
(def sub2 (chan))
(tap m sub1)
(tap m sub2)
;; now every value put on source-ch shows up on sub1 AND sub2
(untap m sub1)
```

### Jerboa implementation

```scheme
(defstruct mult (source subs lock))

(define (make-mult source)
  (let ([m (mult source '() (make-mutex))])
    (go (lambda ()
          (let loop ()
            (let ([v (chan-get! source)])
              (cond
                [(eof-object? v)
                 ;; close all subs
                 (with-mutex (mult-lock m)
                   (for-each chan-close! (mult-subs m)))]
                [else
                 ;; fan out
                 (let ([subs (with-mutex (mult-lock m) (mult-subs m))])
                   (for-each (lambda (s) (chan-put! s v)) subs)
                   (loop))])))))
    m))

(define (tap! m ch)
  (with-mutex (mult-lock m)
    (mult-subs-set! m (cons ch (mult-subs m)))))

(define (untap! m ch)
  (with-mutex (mult-lock m)
    (mult-subs-set! m (remove (lambda (x) (eq? x ch)) (mult-subs m)))))
```

**Gotcha**: Clojure's `mult` uses a **non-blocking put with timeout** for slow subscribers —
a slow tap can be dropped. Our naive version blocks the fan-out on the slowest sub. Document this; add a `mult-with-policy` if it bites.

| Clojure         | Jerboa-native    | Clojure alias   | Status     |
|-----------------|------------------|-----------------|------------|
| `(mult ch)`     | `(make-mult ch)` | `(mult ch)`     | **to add** |
| `(tap m ch)`    | `(tap! m ch)`    | `(tap m ch)`    | **to add** |
| `(untap m ch)`  | `(untap! m ch)`  | `(untap m ch)`  | **to add** |
| `(untap-all m)` | `(untap-all! m)` | `(untap-all m)` | **to add** |

---

## Section 9 — `pub` / `sub`

Topic-routed fan out. Built on top of `mult`: one mult per distinct topic.

```clojure
(def p (pub source-ch :topic))         ; :topic is a fn that extracts topic from each msg
(def new-user-ch (chan))
(sub p :user/created new-user-ch)
```

Implementation is a hash of topic → mult, built on top of the `mult` primitive above.

| Clojure | Jerboa-native | Clojure alias | Status |
|---------|---------------|---------------|--------|
| `(pub ch topic-fn)` | `(make-pub ch topic-fn)` | `(pub ch topic-fn)` | **to add** |
| `(sub p topic ch)` | `(sub! p topic ch)` | `(sub p topic ch)` | **to add** |
| `(unsub p topic ch)` | `(unsub! p topic ch)` | `(unsub p topic ch)` | **to add** |
| `(unsub-all p)` | `(unsub-all! p)` | `(unsub-all p)` | **to add** |

---

## Section 10 — `mix` / `admix` / `unmix` / `toggle`

Dynamic fan-in with runtime control. Less commonly used than `mult`, but ships in core.async.

```clojure
(def out (chan))
(def m (mix out))
(admix m ch1)
(admix m ch2)
(toggle m {ch1 {:pause true}})
(unmix m ch2)
```

Layered on top of `merge` logic with a control channel. Build once the core pieces are stable.

| Clojure           | Jerboa-native          | Clojure alias     | Status          |
|-------------------|------------------------|-------------------|-----------------|
| `(mix out)`       | `(make-mix out)`       | `(mix out)`       | **to add (v2)** |
| `(admix m ch)`    | `(admix! m ch)`        | `(admix m ch)`    | **to add (v2)** |
| `(unmix m ch)`    | `(unmix! m ch)`        | `(unmix m ch)`    | **to add (v2)** |
| `(toggle m spec)` | `(mix-toggle! m spec)` | `(toggle m spec)` | **to add (v2)** |

---

## Section 11 — `promise-chan`

```clojure
(def p (promise-chan))
(>!! p 42)
(<!! p)   ; → 42
(<!! p)   ; → 42 (every taker gets the same value)
```

First put wins. Subsequent puts are dropped. The value is broadcast to all current and future takers. Once closed without a value, all takers get `nil`.

Implementation is small:

```scheme
(defstruct promise-chan (lock cond value set? closed?))

(define (make-promise-channel) ...)
(define (promise-chan-put! pc v) ...)   ;; first put sets, subsequent drop
(define (promise-chan-get! pc) ...)     ;; block until set or closed
```

| Clojure | Jerboa-native | Clojure alias | Status |
|---------|---------------|---------------|--------|
| `(promise-chan)` | `(make-promise-channel)` | `(promise-chan)` | **to add** |

---

## Section 12 — Pipelines

Core.async's `pipeline`, `pipeline-async`, and `pipeline-blocking` are N-worker processors that preserve ordering.

```clojure
(pipeline 4 out-ch (map inc) in-ch)
;; 4 workers, apply (map inc) transducer, preserve order
```

The ordering-preserving trick is non-trivial: each worker produces `(index, result)` pairs and a merger reassembles them. Port the algorithm directly.

| Clojure | Jerboa-native | Clojure alias | Status |
|---------|---------------|---------------|--------|
| `(pipeline n out xf in)` | `(chan-pipeline n out xf in)` | `(pipeline n out xf in)` | **to add** |
| `(pipeline-async n out af in)` | `(chan-pipeline-async n out af in)` | `(pipeline-async n out af in)` | **to add** |
| `(pipeline-blocking n out xf in)` | same as `pipeline` for us | `(pipeline-blocking n out xf in)` | **alias** |

Since Jerboa `go` is already an OS thread, `pipeline-blocking` and `pipeline` are the same thing. In Clojure they differ because `pipeline` runs on go's thread pool (bad for blocking I/O) while `pipeline-blocking` uses a dedicated thread pool. For us: one implementation, two names.

---

## Section 13 — Transducers on channels

Clojure's big trick: a channel can hold a transducer, so the value pipeline fuses in-place.

```clojure
(def c (chan 10 (comp (map inc) (filter even?))))
(>!! c 1)  ; dropped (2 is even but map/filter runs... wait, 1+1=2, even, passes)
(<!! c)    ; → 2
```

Jerboa has `(std transducer)`. The question is: do we make channels carry a transducer directly,
or do we tell users to compose with `chan-map`/`chan-filter`?

**Recommendation**: Ship the fused version. The user-visible payoff is large
(single allocation, single thread-hop) and the implementation is a couple dozen lines:

```scheme
(defstruct channel
  ... buffer xform xform-state ex-handler)

(define (chan-xform-put! ch v)
  ;; step xform state with v; if result is reduced, close channel;
  ;; if result is empty, no-op; otherwise enqueue each emitted item.
  ...)
```

The transducer protocol in `(std transducer)` already uses the same step-function shape as Clojure's, so this is mostly plumbing.

| Clojure | Jerboa-native | Clojure alias | Status |
|---------|---------------|---------------|--------|
| `(chan n xform)` | `(make-channel/xform n xform)` | `(chan n xform)` | **to add** |
| `(chan n xform eh)` | `(make-channel/xform n xform eh)` | `(chan n xform eh)` | **to add** |

---

## Section 14 — The nil question

Clojure `core.async` uses `nil` as the "channel closed" sentinel. You **cannot** put `nil` on a Clojure channel (it throws).
Jerboa uses `(eof-object)`.

Two options for the compat layer:

1. **Translate `eof-object` ↔ `#f` at the boundary.** `<!` returns `#f` for closed channels; `>!` rejects `#f`. Downside: you can't put `#f` on a channel under the compat layer, which is a Clojurism Scheme users will hate.
2. **Let `<!` return `eof-object` and document it.** Ported code needs a find-and-replace of `(nil? x)` → `(eof-object? x)`. Acceptable for most ports.

**Recommendation**: option 2. The compat layer is for porting, not for fooling you into thinking you're writing Clojure. Document the eof convention and move on.

---

## Section 15 — Porting cheat sheet

One-page reference for a Clojure developer with a `core.async` program in front of them.

| `core.async`                       | Jerboa `(std csp clj)`             | Notes                             |
|------------------------------------|------------------------------------|-----------------------------------|
| `(chan)`                           | `(chan)`                           | same                              |
| `(chan 10)`                        | `(chan 10)`                        | same                              |
| `(chan (sliding-buffer 10))`       | `(chan (sliding-buffer 10))`       | same                              |
| `(chan 10 xf)`                     | `(chan 10 xf)`                     | same                              |
| `(>!! c v)` / `(>! c v)`           | `(>!! c v)` / `(>! c v)`           | identical ops in Jerboa           |
| `(<!! c)` / `(<! c)`               | `(<!! c)` / `(<! c)`               | returns `eof-object` when closed  |
| `(close! c)`                       | `(close! c)`                       | same                              |
| `(poll! c)`                        | `(poll! c)`                        | returns `#f` if empty             |
| `(offer! c v)`                     | `(offer! c v)`                     | returns `#f` if full              |
| `(alts!! [c1 c2])`                 | `(alts!! [c1 c2])`                 | same; returns `(list val ch)`     |
| `(alts!! [c1 [c2 v]])`             | `(alts!! [c1 [c2 v]])`             | mixed take/put                    |
| `(alt!! c1 ([v] ...) :default :d)` | `(alt!! c1 ([v] ...) :default :d)` | same                              |
| `(timeout 1000)`                   | `(timeout 1000)`                   | ms                                |
| `(go body...)`                     | `(go body...)`                     | **real OS thread under the hood** |
| `(go-loop [...] ...)`              | `(go-loop [...] ...)`              | same                              |
| `(thread body...)`                 | `(clj-thread body...)`             | renamed to avoid shadow           |
| `(pipe from to)`                   | `(pipe from to)`                   | same                              |
| `(merge [c1 c2])`                  | `(merge [c1 c2])`                  | same                              |
| `(split pred c)`                   | `(split pred c)`                   | returns `(list true-ch false-ch)` |
| `(mult ch)`                        | `(mult ch)`                        | same                              |
| `(tap m ch)` / `(untap m ch)`      | `(tap m ch)` / `(untap m ch)`      | same                              |
| `(pub ch topic-fn)`                | `(pub ch topic-fn)`                | same                              |
| `(sub p topic ch)` / `(unsub ...)` | `(sub p topic ch)` / `(unsub ...)` | same                              |
| `(mix out)`                        | `(mix out)`                        | v2                                |
| `(admix m ch)` / `(unmix m ch)`    | `(admix m ch)` / `(unmix m ch)`    | v2                                |
| `(promise-chan)`                   | `(promise-chan)`                   | same                              |
| `(pipeline n out xf in)`           | `(pipeline n out xf in)`           | same                              |
| `(pipeline-blocking n out xf in)`  | `(pipeline-blocking n out xf in)`  | alias for `pipeline` here         |
| `(pipeline-async n out af in)`     | `(pipeline-async n out af in)`     | same                              |
| `(to-chan coll)`                   | `(to-chan coll)`                   | same                              |
| `(onto-chan ch coll)`              | `(onto-chan ch coll)`              | same                              |
| `(into [] ch)`                     | `(into '() ch)`                    | returns a list                    |
| `(reduce f init ch)`               | `(reduce f init ch)`               | same                              |
| `(transduce xf f init ch)`         | `(transduce xf f init ch)`         | same                              |

---

## Section 16 — Implementation phases

### Phase 0 — fix `(std csp)` foundations (blocker)
1. Replace `append`-based queue with real FIFO.
2. Remove or implement the false "green threads / engines" claim.
3. Add `chan-try-put!`.
4. Fix `yield` (or document it as a sleep).
5. Rewrite `(std csp)` docstring to match reality.

### Phase 1 — channel buffers + select (minimum for porting)
1. `chan-buffer` record + fixed/sliding/dropping implementations.
2. `(std csp select)` built on `(std event)` bridge.
3. `alts!` / `alts!!` / `alt!` / `alt!!` macros.
4. `timeout` channel (naive one-thread-per-timeout version).
5. `(std csp clj)` compat layer with Clojure names for everything in Phases 0-1.

### Phase 2 — collection + composition
1. `to-chan` / `onto-chan` / `into` / `reduce` / `transduce`.
2. `merge` / `pipe` / `split`.
3. `mult` / `tap` / `untap` / `untap-all`.
4. `pub` / `sub` / `unsub` / `unsub-all`.

### Phase 3 — pipelines and promise
1. `pipeline` with ordered output.
2. `pipeline-async`.
3. `promise-chan`.
4. `chan` with transducer argument.

### Phase 4 — deferred
1. `mix` / `admix` / `unmix` / `toggle`.
2. Real parking `go` — investigate Chez engines or call/cc coroutines.
3. Timer wheel for `timeout` scaling.
4. `mult` with slow-subscriber policy (drop / timeout / block).

---

## Section 17 — Worked example

A typical core.async program: scatter/gather with a timeout.

### Clojure

```clojure
(require '[clojure.core.async :as a :refer [chan go >! <! alts! timeout close!]])

(defn fetch [id]
  (let [c (chan)]
    (go (>! c {:id id :result (do-work id)}) (close! c))
    c))

(defn gather [ids timeout-ms]
  (let [chans (map fetch ids)
        t     (timeout timeout-ms)
        out   (atom [])]
    (loop [remaining chans]
      (if (empty? remaining)
        @out
        (let [[v ch] (alts!! (conj remaining t))]
          (cond
            (= ch t)   @out                         ; timed out
            (nil? v)   (recur (remove #{ch} remaining))  ; this one closed empty
            :else      (do (swap! out conj v)
                           (recur (remove #{ch} remaining)))))))))
```

### Jerboa (using `(std csp clj)`)

```scheme
(import (jerboa prelude))
(import (std csp clj))

(def (fetch id)
  (let ([c (chan)])
    (go (>! c (hash 'id id 'result (do-work id)))
        (close! c))
    c))

(def (gather ids timeout-ms)
  (let ([chans (map fetch ids)]
        [t     (timeout timeout-ms)]
        [out   (atom '())])
    (let loop ([remaining chans])
      (if (null? remaining)
        (deref out)
        (let* ([pick (alts!! (cons t remaining))]
               [v    (car pick)]
               [ch   (cadr pick)])
          (cond
            [(eq? ch t)        (deref out)]           ;; timed out
            [(eof-object? v)   (loop (remove (cut eq? <> ch) remaining))]
            [else              (swap! out (cut cons v <>))
                               (loop (remove (cut eq? <> ch) remaining))]))))))
```

Differences:
- `(hash-map :id id ...)` → `(hash 'id id ...)` — Clojure keywords become Scheme symbols.
- `(nil? v)` → `(eof-object? v)` — closed-channel sentinel.
- `(conj remaining t)` → `(cons t remaining)` — ordinary lists.
- `(atom [])` / `(deref out)` / `(swap! out conj v)` — **these work unchanged** thanks to the recent atom prelude aliases. Jerboa doesn't have Clojure's `@` reader sugar, so spell `@out` as `(deref out)`.
- Everything else is a near-verbatim port.

This is the porting experience we want.

---

## Open questions

1. **Should we use Clojure keyword syntax `:name`?** Jerboa already reads `:std/sort` as a module path. Keyword `:` collides. Either accept that Clojure keywords become Scheme symbols (`'name`), or add a reader mode switch.
2. **Should `<!` really error outside `go`?** Clojure forbids it. Since Jerboa collapses parking and blocking, there's no reason to enforce it. Leave the `<!` / `<!!` distinction purely cosmetic.
3. **Transducer interop**: are Jerboa transducers and Clojure transducers step-function-compatible? Need to verify before shipping `(chan n xform)`.
4. **nil vs eof**: option 2 above (keep eof) is the current recommendation, but a loud dissent is possible. Poll Clojure porters.
5. **`(std csp clj)` vs `(std clojure async)` vs `(std async clj)`** — pick a module path and commit.

---

## Summary

Shipping functional parity with Clojure's `core.async` on Jerboa is a **bounded**, **mostly straightforward** piece of work.
The hard parts are:

1. Fixing the existing `(std csp)` stub (half a day).
2. Bridging CSP channels to `(std event)` so `alts!` works (a day).
3. `mult` / `pub` / `pipeline` — fiddly but small (a few days total).
4. Accepting that `go` is an OS thread and documenting the consequences.

The easy parts are everything else — most operators are 10-30 lines each.

The one thing we **cannot** match without a CPS transform is Clojure's ability to
run millions of `go` blocks on a handful of threads. For the target audience (Clojure devs who want to try a Scheme, and Clojure programs of normal size), this is an acceptable tradeoff.
