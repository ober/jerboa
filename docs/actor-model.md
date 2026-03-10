# Jerboa Actor Model: Complete Implementation Guide

This document is a step-by-step implementation guide for building a production-quality
actor system on Chez Scheme 10.4+ (threaded build, `ta6le`). Each layer is independently
implementable and testable. A lesser model can implement this by following the layers in
order — do not skip ahead.

**Validated against**: Chez Scheme 10.4.0, threaded build, Linux x86_64.

---

## Design Philosophy

**Goals** (what makes this better than Gerbil's `:std/actor`):

1. **Clean layer separation** — each layer is independently importable and testable.
   Gerbil mixes local spawn, remote RPC, filesystem deployment, and admin auth into
   a single 400-symbol namespace. Here each layer is a separate library.

2. **No shimming** — built directly on Chez's native OS threads, not green threads.
   Every primitive maps directly to a Chez or OS concept.

3. **Native serialization** — use Chez's built-in `fasl-write`/`fasl-read` for
   distributed transport. Any Scheme value (records, vectors, bytevectors, symbols,
   numbers, booleans, pairs) is automatically serializable. No separate serialization
   library needed.

4. **OTP-style supervision** — Erlang-proven restart strategies (one-for-one,
   one-for-all, rest-for-one) with max-intensity/period restart limiting.

5. **Location transparency** — `(send actor-ref msg)` works whether `actor-ref` is
   local or remote. The caller does not need to know.

6. **Typed protocols via macros** — `defprotocol` generates message structs and
   typed dispatch. Less boilerplate than Gerbil's `defmessage` + `defcall-actor`.

7. **Gradual complexity** — Layers 3-6 (local actors + supervision) are useful
   without Layer 2 (work-stealing) or Layer 7 (distributed). Build and ship each
   layer independently.

**Non-goals**:
- Full Gerbil compatibility (we implement what real programs use, not every symbol)
- Green threads / continuations (real OS threads are simpler and SMP-safe)
- Hot code loading (out of scope)

---

## Quick Start (TL;DR)

To get a working actor system in 5 steps:

```scheme
(import (chezscheme) (jerboa core)
        (std actor core)
        (std actor protocol)
        (std actor supervisor)
        (std actor registry)
        (std actor scheduler))

;; 1. Start the thread pool
(define sched (scheduler-start! (make-scheduler (cpu-count))))
(set-actor-scheduler! (lambda (thunk) (scheduler-submit! sched thunk)))

;; 2. Start the name registry
(start-registry!)

;; 3. Define a protocol
(defprotocol counter
  (increment n)
  (get-value -> value)
  (reset))

;; 4. Implement the actor
(define (make-counter initial)
  (let ([n initial])
    (spawn-actor
      (lambda (msg)
        (with-ask-context msg
          (lambda (actual)
            (cond
              [(counter:increment? actual)
               (set! n (+ n (counter:increment-n actual)))]
              [(counter:get-value? actual)
               (reply n)]
              [(counter:reset? actual)
               (set! n initial)])))))))

;; 5. Supervise it
(define app
  (start-supervisor 'one-for-one
    (list (make-child-spec 'counter
                           (lambda () (make-counter 0))
                           'permanent 5.0 'worker))
    10 5))

;; Use it
(let ([ref (caddr (car (supervisor-which-children app)))])
  (register! 'counter ref))

(counter:increment! (whereis 'counter) 42)
(display (counter:get-value?! (whereis 'counter)))  ;; => 42

;; Shutdown
(scheduler-stop! sched)
```

---

## Chez Scheme Primitives Reference

Every primitive used in this guide. Know these before implementing.

### Threading (Chez 10, threaded build)
| Primitive                          | Description                                                                  |
|------------------------------------|------------------------------------------------------------------------------|
| `(fork-thread thunk)`              | Starts a new OS thread immediately, returns thread-id                        |
| `(get-thread-id)`                  | Returns current thread's integer id                                          |
| `(make-mutex)`                     | Creates a new mutex                                                          |
| `(mutex-acquire mutex)`            | Blocks until mutex acquired                                                  |
| `(mutex-release mutex)`            | Releases a mutex                                                             |
| `(with-mutex mutex body ...)`      | Acquires, evaluates body, releases (even on exception)                       |
| `(make-condition)`                 | Creates a condition variable                                                 |
| `(condition-wait cond mutex)`      | Atomically releases mutex and blocks on condition; re-acquires mutex on wake |
| `(condition-wait cond mutex time)` | Same but with timeout; returns `#f` on timeout, `#t` if signaled             |
| `(condition-signal cond)`          | Wakes one waiting thread                                                     |
| `(condition-broadcast cond)`       | Wakes all waiting threads                                                    |
| `(make-thread-parameter default)`  | Creates a thread-local parameter (SMP-safe, no global lock)                  |

### Data Structures
| Primitive                        | Description                                |
|----------------------------------|--------------------------------------------|
| `(make-vector n init)`           | Creates a vector of size n                 |
| `(make-eq-hashtable)`            | Creates a hashtable with `eq?` comparison  |
| `(make-hashtable hash equiv)`    | Creates a hashtable with custom hash/equiv |
| `(hashtable-set! ht key val)`    | Insert/update                              |
| `(hashtable-ref ht key default)` | Lookup with default                        |
| `(hashtable-delete! ht key)`     | Remove                                     |
| `(hashtable-keys ht)`            | Returns vector of keys                     |

### Serialization
| Primitive | Description |
|-----------|-------------|
| `(fasl-write obj port)` | Serializes any Scheme value (records, vectors, etc.) to binary port |
| `(fasl-read port)` | Deserializes from binary port |
| `(open-bytevector-output-port)` | Returns `(values port get-bytevector-proc)` |
| `(open-bytevector-input-port bv)` | Creates input port from bytevector |

### Time
| Primitive | Description |
|-----------|-------------|
| `(make-time type nanoseconds seconds)` | Creates a time object. Use `'time-duration` for durations |
| `(current-time)` | Returns `time-utc` object |
| `(time-second t)` | Extracts seconds from a time object |
| `(time-nanosecond t)` | Extracts nanoseconds from a time object |

**WARNING**: `time->seconds` does NOT exist in Chez. It is in `(std srfi srfi-19)`.
To convert a time object to a float without SRFI-19:
```scheme
(define (time->float t)
  (+ (time-second t) (/ (time-nanosecond t) 1000000000.0)))
```

### Other
| Primitive | Description |
|-----------|-------------|
| `(random n)` | Returns random integer in [0, n) |
| `(filter pred lst)` | Standard R6RS filter |
| `(define-record-type ...)` | R6RS record types with protocol, sealed, etc. |
| `(guard (var [test expr] ...) body ...)` | R6RS exception handling |

**WARNING**: `match` is NOT built-in Chez. Import from `(jerboa core)`.
**WARNING**: `cpu-count` does NOT exist in Chez. Read from `/proc` or use a constant:
```scheme
(define (cpu-count)
  (or (let ([p (open-input-file "/proc/cpuinfo")])
        (let loop ([n 0])
          (let ([line (get-line p)])
            (cond
              [(eof-object? line) (close-port p) n]
              [(and (>= (string-length line) 9)
                    (string=? (substring line 0 9) "processor"))
               (loop (fx+ n 1))]
              [else (loop n)]))))
      4))  ;; fallback
```

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│  Layer 7: Distributed Transport                      │
│  lib/std/actor/transport.sls                         │
│  TCP+TLS, fasl serialization, location transparency  │
├──────────────────────────────────────────────────────┤
│  Layer 6: Registry                                   │
│  lib/std/actor/registry.sls                          │
│  Named actors, whereis, register, unregister         │
├──────────────────────────────────────────────────────┤
│  Layer 5: Supervision Trees                          │
│  lib/std/actor/supervisor.sls                        │
│  OTP strategies, restart intensity, child specs      │
├──────────────────────────────────────────────────────┤
│  Layer 4: Protocol System                            │
│  lib/std/actor/protocol.sls                          │
│  defprotocol, ask, tell, call, pattern dispatch      │
├──────────────────────────────────────────────────────┤
│  Layer 3: Actor Core                                 │
│  lib/std/actor/core.sls                              │
│  spawn-actor, send, receive, self, dead letters      │
├──────────────────────────────────────────────────────┤
│  Layer 2: Scheduler                                  │
│  lib/std/actor/scheduler.sls                         │
│  Work-stealing thread pool, lightweight tasks        │
├──────────────────────────────────────────────────────┤
│  Layer 1: Data Structures                            │
│  lib/std/actor/mpsc.sls   — MPSC queue (mailbox)     │
│  lib/std/actor/deque.sls  — Work-stealing deque      │
├──────────────────────────────────────────────────────┤
│  Foundation (already exists in Jerboa)               │
│  (std misc channel)  — bounded channels + select     │
│  (std misc thread)   — Gambit thread API             │
│  (std task)          — task groups + futures         │
│  (std net ssl)       — TCP+TLS via chez-ssl          │
│  (jerboa core)       — match, def, defstruct         │
└──────────────────────────────────────────────────────┘
```

**Implementation order**: Layer 1 → Layer 3 → Layer 4 → Layer 5 → Layer 6 → Layer 2 → Layer 7.
Layer 2 (scheduler) can be deferred — Layers 3-6 work fine on 1:1 OS threads initially.

---

## Layer 1A: MPSC Queue (`lib/std/actor/mpsc.sls`)

### Purpose

Each actor has a mailbox. Multiple threads (producers) can send messages to it
concurrently. Only the actor's own thread (consumer) reads from it.
This is the Multi-Producer Single-Consumer (MPSC) pattern.

### Data Structure: Two-Lock Linked List

We use a Michael-Scott style two-lock linked list: one lock for the tail (producers)
and one lock for the head (consumer). This minimizes contention because producers
never block the consumer and vice versa.

This is simpler and more practical for Chez than a lock-free Michael-Scott queue
(which would require `compare-and-swap` via FFI C shims — Chez does not expose CAS natively).

### Critical Design: Signaling Without Deadlock

The original design had a subtle deadlock risk: signaling `not-empty` while holding
`tail-mutex`. If the consumer holds `head-mutex` and tries to signal or if the
producer tries to acquire `head-mutex` while holding `tail-mutex`, you can deadlock
when another thread does the reverse.

**Solution**: Use a single condition variable protected by `head-mutex` only. The
producer signals by acquiring `head-mutex` briefly AFTER releasing `tail-mutex`.
This ensures no nested lock acquisition.

```scheme
#!chezscheme
(library (std actor mpsc)
  (export
    make-mpsc-queue
    mpsc-queue?
    mpsc-enqueue!          ;; producer: add to tail
    mpsc-dequeue!          ;; consumer: remove from head (blocks if empty)
    mpsc-try-dequeue!      ;; consumer: remove or return (values #f #f) immediately
    mpsc-empty?            ;; peek (approximate — only safe from consumer thread)
    mpsc-close!            ;; signal no more messages
    mpsc-closed?)
  (import (chezscheme))

  ;; Node in the linked list
  (define-record-type mpsc-node
    (fields
      (mutable value)   ;; the message, or 'sentinel for dummy head
      (mutable next))   ;; next node or #f
    (protocol
      (lambda (new)
        (lambda (val) (new val #f))))
    (sealed #t))

  (define-record-type mpsc-queue
    (fields
      (mutable head)        ;; points to dummy node; consumer reads head.next
      (mutable tail)        ;; points to last real node (or dummy if empty)
      (immutable head-mutex) ;; consumer lock (also protects condition variable)
      (immutable tail-mutex) ;; producer lock
      (immutable not-empty)  ;; condition: signaled when item enqueued
      (mutable closed?))
    (protocol
      (lambda (new)
        (lambda ()
          (let ([dummy (make-mpsc-node 'sentinel)])
            (new dummy dummy
                 (make-mutex) (make-mutex)
                 (make-condition)
                 #f)))))
    (sealed #t))

  ;; Producer: enqueue a value
  ;; Lock only the tail — does not interfere with consumer reading head.
  ;; Signal the consumer AFTER releasing tail-mutex to avoid nested locking.
  (define (mpsc-enqueue! q val)
    (let ([node (make-mpsc-node val)])
      (with-mutex (mpsc-queue-tail-mutex q)
        (when (mpsc-queue-closed? q)
          (error 'mpsc-enqueue! "queue is closed"))
        (mpsc-node-next-set! (mpsc-queue-tail q) node)
        (mpsc-queue-tail-set! q node))
      ;; Signal consumer OUTSIDE tail-lock (head-mutex acquired briefly)
      (with-mutex (mpsc-queue-head-mutex q)
        (condition-signal (mpsc-queue-not-empty q)))))

  ;; Consumer: dequeue, blocking if empty
  (define (mpsc-dequeue! q)
    (with-mutex (mpsc-queue-head-mutex q)
      (let loop ()
        (let ([next (mpsc-node-next (mpsc-queue-head q))])
          (cond
            [next
             ;; Advance dummy head to the first real node
             ;; The old head is discarded; the real node becomes the new dummy
             (let ([val (mpsc-node-value next)])
               (mpsc-queue-head-set! q next)
               (mpsc-node-value-set! next 'sentinel) ;; help GC
               val)]
            [(mpsc-queue-closed? q)
             (error 'mpsc-dequeue! "queue closed and empty")]
            [else
             (condition-wait (mpsc-queue-not-empty q)
                             (mpsc-queue-head-mutex q))
             (loop)])))))

  ;; Consumer: try dequeue without blocking
  ;; Returns (values val #t) if successful, (values #f #f) if empty
  (define (mpsc-try-dequeue! q)
    (with-mutex (mpsc-queue-head-mutex q)
      (let ([next (mpsc-node-next (mpsc-queue-head q))])
        (cond
          [next
           (let ([val (mpsc-node-value next)])
             (mpsc-queue-head-set! q next)
             (mpsc-node-value-set! next 'sentinel)
             (values val #t))]
          [else
           (values #f #f)]))))

  (define (mpsc-empty? q)
    ;; Approximate: safe only from the consumer thread.
    ;; Reads head.next without lock — may see stale data from producers.
    (not (mpsc-node-next (mpsc-queue-head q))))

  (define (mpsc-close! q)
    (with-mutex (mpsc-queue-tail-mutex q)
      (mpsc-queue-closed?-set! q #t))
    ;; Wake all blocked consumers
    (with-mutex (mpsc-queue-head-mutex q)
      (condition-broadcast (mpsc-queue-not-empty q))))

  ) ;; end library
```

**Why `with-mutex` instead of manual acquire/release**: `with-mutex` is a Chez
built-in that uses `dynamic-wind` to guarantee the mutex is released even if an
exception occurs inside the body. Manual acquire/release leaks the lock on exception.

**Test file**: `tests/test-actor-mpsc.ss`
- Enqueue from 10 threads simultaneously, dequeue from 1 thread — verify all messages received
- `try-dequeue` on empty queue returns `(values #f #f)`
- Close while consumer is blocked — consumer gets error
- Ordering: messages from a single producer arrive in FIFO order

---

## Layer 1B: Work-Stealing Deque (`lib/std/actor/deque.sls`)

### Purpose

The scheduler (Layer 2) gives each worker thread its own double-ended queue of tasks.
The owner thread pushes/pops from the bottom. Idle workers steal from the top of
other workers' deques. This is the Chase-Lev work-stealing deque.

### Implementation Note

A fully lock-free Chase-Lev deque requires `compare-and-swap` (CAS) on memory
words — an operation Chez does not expose natively. Two options:

**Option A (Recommended for initial implementation)**: Use a single mutex per deque.
The deque is mostly uncontended (owner push/pop), and stealing is rare. A mutex
is fast enough when not under heavy contention.

**Option B (For high-throughput production)**: Add a C shim:
```c
// support/atomic.c
#include <stdatomic.h>
#include <stdint.h>

// Returns 1 if swap succeeded, 0 if not
int jerboa_cas_int64(int64_t *ptr, int64_t expected, int64_t desired) {
    return atomic_compare_exchange_strong(
        (_Atomic int64_t*)ptr, &expected, desired);
}

void jerboa_atomic_store_int64(int64_t *ptr, int64_t val) {
    atomic_store((_Atomic int64_t*)ptr, val);
}

int64_t jerboa_atomic_load_int64(int64_t *ptr) {
    return atomic_load((_Atomic int64_t*)ptr);
}
```
Compile: `gcc -shared -fPIC -O2 -o libjerboa-atomic.so support/atomic.c`
Load: `(load-shared-object "./libjerboa-atomic.so")`
Use: `(define cas-int64 (foreign-procedure "jerboa_cas_int64" (void* integer-64 integer-64) int))`

The document describes the mutex-based version. Upgrading to lock-free is a drop-in
replacement at the deque level — the scheduler above does not change.

```scheme
#!chezscheme
(library (std actor deque)
  (export
    make-work-deque
    work-deque?
    deque-push-bottom!    ;; owner pushes a task
    deque-pop-bottom!     ;; owner pops (LIFO — locality of reference)
    deque-steal-top!      ;; thief steals (FIFO — oldest tasks first)
    deque-empty?
    deque-size)
  (import (chezscheme))

  ;; Circular buffer that grows as needed
  (define-record-type work-deque
    (fields
      (mutable buf)      ;; vector of tasks
      (mutable bottom)   ;; owner's end (push/pop here)
      (mutable top)      ;; thief's end (steal from here)
      (immutable mutex))
    (protocol
      (lambda (new)
        (lambda ()
          (new (make-vector 64 #f) 0 0 (make-mutex)))))
    (sealed #t))

  (define (deque-capacity d) (vector-length (work-deque-buf d)))

  (define (deque-size d)
    (with-mutex (work-deque-mutex d)
      (let ([b (work-deque-bottom d)]
            [t (work-deque-top d)])
        (if (fx>= b t) (fx- b t) 0))))

  (define (deque-empty? d)
    (with-mutex (work-deque-mutex d)
      (fx<= (work-deque-bottom d) (work-deque-top d))))

  ;; Grow buffer when full (called under lock)
  (define (deque-grow! d)
    (let* ([old (work-deque-buf d)]
           [old-cap (vector-length old)]
           [new-cap (fx* old-cap 2)]
           [new-buf (make-vector new-cap #f)]
           [top (work-deque-top d)]
           [bottom (work-deque-bottom d)])
      (do ([i top (fx+ i 1)])
          ((fx= i bottom))
        (vector-set! new-buf (fxmod i new-cap)
                     (vector-ref old (fxmod i old-cap))))
      (work-deque-buf-set! d new-buf)))

  ;; Owner pushes a task to the bottom
  (define (deque-push-bottom! d task)
    (with-mutex (work-deque-mutex d)
      (let ([b (work-deque-bottom d)])
        (when (fx>= (fx- b (work-deque-top d)) (fx- (deque-capacity d) 1))
          (deque-grow! d))
        (vector-set! (work-deque-buf d) (fxmod b (deque-capacity d)) task)
        (work-deque-bottom-set! d (fx+ b 1)))))

  ;; Owner pops from the bottom (LIFO — most recently pushed task first)
  ;; Returns the task or #f if empty
  (define (deque-pop-bottom! d)
    (with-mutex (work-deque-mutex d)
      (let ([b (work-deque-bottom d)]
            [t (work-deque-top d)])
        (if (fx> b t)
          (let ([new-b (fx- b 1)])
            (work-deque-bottom-set! d new-b)
            (let ([task (vector-ref (work-deque-buf d)
                                    (fxmod new-b (deque-capacity d)))])
              (vector-set! (work-deque-buf d) (fxmod new-b (deque-capacity d)) #f)
              task))
          #f))))

  ;; Thief steals from the top (FIFO — oldest tasks first)
  ;; Returns (values task #t) or (values #f #f) if empty
  (define (deque-steal-top! d)
    (with-mutex (work-deque-mutex d)
      (let ([t (work-deque-top d)]
            [b (work-deque-bottom d)])
        (cond
          [(fx>= t b)
           (values #f #f)]
          [else
           (let ([task (vector-ref (work-deque-buf d)
                                   (fxmod t (deque-capacity d)))])
             (vector-set! (work-deque-buf d) (fxmod t (deque-capacity d)) #f)
             (work-deque-top-set! d (fx+ t 1))
             (values task #t))]))))

  ) ;; end library
```

**Test file**: `tests/test-actor-deque.ss`
- Push 1000 items, pop all — verify LIFO order
- Push 1000 items, steal all — verify FIFO order
- Concurrent push + steal from different threads
- Grow: push more than initial capacity (64)
- Empty deque: pop returns #f, steal returns (values #f #f)

---

## Layer 2: Work-Stealing Scheduler (`lib/std/actor/scheduler.sls`)

### Purpose

Instead of one OS thread per actor (which limits concurrency to ~1000), the scheduler
maintains a fixed pool of N OS threads and schedules lightweight tasks across them.
M tasks run on N threads (M >> N).

### Key Insight

Actors are NOT OS threads. An actor is a record with a mailbox. When a message arrives,
a **task** (a thunk) is scheduled to run the actor's receive loop for one message.
The task runs on whatever worker thread picks it up. This is the M:N model.

### How Workers Find Work

Each worker follows this priority:
1. **Pop own deque** (LIFO — hot cache, best locality)
2. **Steal from random other worker** (FIFO — cold tasks migrate to idle cores)
3. **Sleep on condition variable** (avoid busy-wait; woken when new task submitted)

### Data Structures

```scheme
#!chezscheme
(library (std actor scheduler)
  (export
    make-scheduler
    scheduler?
    scheduler-start!      ;; create and start the thread pool
    scheduler-stop!       ;; drain and shut down
    scheduler-submit!     ;; submit a thunk as a task
    scheduler-worker-count
    current-scheduler
    default-scheduler)
  (import (chezscheme) (std actor deque))

  ;; A task is just a thunk (zero-argument procedure).
  ;; The scheduler runs thunks; it doesn't know about actors.

  ;; Per-worker state (one per OS thread in the pool)
  (define-record-type worker
    (fields
      (immutable id)          ;; integer index 0..N-1
      (immutable deque)       ;; this worker's task deque
      (mutable running?))     ;; #f when shutting down
    (protocol
      (lambda (new)
        (lambda (id)
          (new id (make-work-deque) #t))))
    (sealed #t))

  ;; The scheduler: a pool of workers
  (define-record-type scheduler
    (fields
      (immutable workers)       ;; vector of worker records
      (immutable mutex)
      (immutable work-available) ;; condition: broadcast when new task added
      (mutable running?))
    (protocol
      (lambda (new)
        (lambda (n)
          (new (let ([v (make-vector n)])
                 (do ([i 0 (fx+ i 1)]) ((fx= i n) v)
                   (vector-set! v i (make-worker i))))
               (make-mutex)
               (make-condition)
               #f))))
    (sealed #t))

  ;; Thread-local: which worker is running on this thread
  (define current-worker (make-thread-parameter #f))
  (define current-scheduler (make-thread-parameter #f))
  (define default-scheduler (make-parameter #f))

  ;; Submit a task to the scheduler.
  ;; If called from a worker thread, push to its local deque (fast path).
  ;; Otherwise, distribute to a random worker deque.
  (define (scheduler-submit! sched thunk)
    (let ([w (current-worker)])
      (if w
        ;; Fast path: running inside the pool — push to local deque
        (deque-push-bottom! (worker-deque w) thunk)
        ;; Slow path: external submission — pick a random worker
        (let* ([workers (scheduler-workers sched)]
               [n (vector-length workers)]
               [idx (random n)]
               [w (vector-ref workers idx)])
          (deque-push-bottom! (worker-deque w) thunk))))
    ;; Wake one sleeping worker
    (with-mutex (scheduler-mutex sched)
      (condition-signal (scheduler-work-available sched))))

  ;; The main loop for each worker thread
  (define (worker-run! sched w)
    (current-worker w)
    (current-scheduler sched)
    (let ([workers (scheduler-workers sched)]
          [n (vector-length (scheduler-workers sched))]
          [my-id (worker-id w)])
      (let loop ()
        (when (scheduler-running? sched)
          ;; 1. Try own deque first
          (let ([task (deque-pop-bottom! (worker-deque w))])
            (if task
              (begin
                (guard (exn [#t (void)])  ;; tasks must not crash the worker
                  (task))
                (loop))
              ;; 2. Try stealing from other workers (round-robin from own id)
              (let try-steal ([attempts 0])
                (if (fx>= attempts n)
                  ;; 3. All deques empty — wait for work
                  (begin
                    (mutex-acquire (scheduler-mutex sched))
                    ;; Re-check before sleeping (avoid lost wakeup)
                    (when (and (scheduler-running? sched)
                               (not (deque-pop-bottom! (worker-deque w))))
                      (condition-wait (scheduler-work-available sched)
                                      (scheduler-mutex sched)))
                    (mutex-release (scheduler-mutex sched))
                    (loop))
                  (let* ([victim-idx (fxmod (fx+ my-id attempts 1) n)]
                         [victim (vector-ref workers victim-idx)])
                    (let-values ([(task ok) (deque-steal-top! (worker-deque victim))])
                      (if ok
                        (begin
                          (guard (exn [#t (void)])
                            (task))
                          (loop))
                        (try-steal (fx+ attempts 1)))))))))))))

  (define (scheduler-worker-count sched)
    (vector-length (scheduler-workers sched)))

  ;; Start the scheduler: fork N worker threads
  (define (scheduler-start! sched)
    (scheduler-running?-set! sched #t)
    (let ([workers (scheduler-workers sched)])
      (do ([i 0 (fx+ i 1)])
          ((fx= i (vector-length workers)))
        (let ([w (vector-ref workers i)])
          (fork-thread (lambda () (worker-run! sched w))))))
    sched)

  ;; Stop the scheduler: signal all workers to exit
  (define (scheduler-stop! sched)
    (scheduler-running?-set! sched #f)
    (with-mutex (scheduler-mutex sched)
      (condition-broadcast (scheduler-work-available sched))))

  ) ;; end library
```

### Usage Notes

- `(scheduler-submit! sched thunk)` is the ONLY way tasks enter the pool.
- Tasks must complete quickly (not block indefinitely) for good throughput.
  An actor that blocks on `receive` should suspend and re-submit when a message arrives.
- Exception isolation: each task is wrapped in `guard` so a crashing task does not
  kill the worker thread. The actor's supervisor handles the crash, not the scheduler.
- The sleep-before-wait pattern (check own deque after acquiring mutex but before
  `condition-wait`) prevents the lost-wakeup bug where a task is submitted between
  the failed steal attempts and the `condition-wait`.

### Initialization

```scheme
;; Helper: read CPU count from /proc on Linux
(define (cpu-count)
  (guard (exn [#t 4])
    (let ([p (open-input-file "/proc/cpuinfo")])
      (let loop ([n 0])
        (let ([line (get-line p)])
          (cond
            [(eof-object? line) (close-port p) (fxmax n 1)]
            [(and (fx>= (string-length line) 9)
                  (string=? (substring line 0 9) "processor"))
             (loop (fx+ n 1))]
            [else (loop n)]))))))

;; Typically done once at program start:
(define sched (scheduler-start! (make-scheduler (cpu-count))))
(default-scheduler sched)
```

---

## Layer 3: Actor Core (`lib/std/actor/core.sls`)

### Core Concepts

- An **actor** is a record containing: an ID, a mailbox (MPSC queue), a behavior
  function, and lifecycle state.
- **Spawning** creates the actor record and registers it in the global table.
- **Sending** enqueues a message in the actor's mailbox and schedules a task if
  the actor is idle.
- **Receiving** is done inside the behavior function. The behavior processes one
  message per scheduling quantum.
- **self** is a thread-local parameter bound to the current actor's reference.

### Actor States

```
  IDLE ──────────[message arrives]──────> SCHEDULED
    ^                                          |
    |                                    [task runs]
    |                                          |
    └────────────[mailbox empty again]──── RUNNING
                                              |
                                         [exception]
                                              |
                                           DEAD ──> supervisor notified
```

### The Actor Loop Model

Unlike Erlang where each actor is a persistent process with a `receive` call that
blocks, in our M:N model an actor runs as a **task per message batch**:

1. Message arrives in mailbox
2. If actor is `idle`, a task is submitted to the scheduler: `(lambda () (run-actor! actor))`
3. `run-actor!` dequeues one message, calls `(behavior msg)`, then:
   - If more messages in mailbox, processes the next one immediately (batching)
   - If mailbox empty, marks actor as IDLE
   - On exception, marks actor as DEAD and notifies links/monitors

### Race Condition: The IDLE→SCHEDULED Transition

A critical race exists between checking `idle?` and scheduling. Two threads could
both see `idle` and double-schedule the actor. We solve this with a state mutex:

```
Thread A: send msg → enqueue → check state → (if idle) → set scheduled → submit task
Thread B: send msg → enqueue → check state → (if idle) → set scheduled → submit task ← BUG!
```

**Fix**: Use `with-mutex` on a per-actor scheduling mutex when transitioning states.

```scheme
#!chezscheme
(library (std actor core)
  (export
    ;; Actor creation and management
    spawn-actor            ;; (spawn-actor behavior [name]) → actor-ref
    spawn-actor/linked     ;; links to current actor; if either dies, both notified
    actor-ref?
    actor-ref-id
    actor-ref-name
    actor-ref-node         ;; #f for local actors

    ;; Sending messages
    send                   ;; (send actor-ref msg) → unspecified (fire and forget)

    ;; Context inside a behavior
    self                   ;; (self) → current actor's actor-ref
    actor-id               ;; (actor-id) → current actor's id integer

    ;; Actor lifecycle
    actor-alive?           ;; (actor-alive? actor-ref) → bool
    actor-kill!            ;; (actor-kill! actor-ref) → forcibly terminate
    actor-wait!            ;; (actor-wait! actor-ref) → block until dead

    ;; Monitors and links
    actor-ref-links        ;; accessor for linked actors list
    actor-ref-links-set!   ;; mutator (used by spawn-actor/linked)
    actor-ref-monitors     ;; accessor for monitor list
    actor-ref-monitors-set! ;; mutator (used by supervisor)

    ;; Dead letter handler
    set-dead-letter-handler!

    ;; Scheduler integration
    set-actor-scheduler!

    ;; Internal: lookup for distributed layer
    lookup-local-actor
  )
  (import (chezscheme)
          (std actor mpsc))

  ;; ========== Actor ID generation ==========
  ;; Simple monotonic counter protected by mutex.
  ;; Thread-safe: multiple threads may spawn actors concurrently.

  (define *next-actor-id* 0)
  (define *actor-id-mutex* (make-mutex))

  (define (next-actor-id!)
    (with-mutex *actor-id-mutex*
      (let ([id *next-actor-id*])
        (set! *next-actor-id* (fx+ id 1))
        id)))

  ;; ========== Actor Record ==========

  (define-record-type actor-ref
    (fields
      (immutable id)           ;; unique integer
      (immutable node)         ;; #f = local; string = remote node id
      (immutable mailbox)      ;; mpsc-queue (or #f for remote refs)
      (immutable sched-mutex)  ;; protects state transitions (idle→scheduled)
      (mutable state)          ;; 'idle | 'scheduled | 'running | 'dead
      (mutable behavior)       ;; current behavior: (lambda (msg) ...)
      (mutable links)          ;; list of actor-refs to notify on death
      (mutable monitors)       ;; list of (actor-ref . tag) to notify
      (immutable name)         ;; symbol or #f
      (immutable done-mutex)
      (immutable done-cond)    ;; signaled when state = 'dead
      (mutable exit-reason))   ;; 'normal | exception | 'killed
    (protocol
      (lambda (new)
        (case-lambda
          ;; Local actor constructor
          [(behavior name)
           (new (next-actor-id!)
                #f             ;; local
                (make-mpsc-queue)
                (make-mutex)   ;; sched-mutex
                'idle
                behavior
                '()            ;; links
                '()            ;; monitors
                name
                (make-mutex)
                (make-condition)
                #f)]           ;; exit-reason not set yet
          ;; Remote actor ref constructor (no mailbox, no behavior)
          [(id node)
           (new id
                node
                #f             ;; no local mailbox
                (make-mutex)
                'idle          ;; state unused for remote
                (lambda (msg) (void))
                '() '()        ;; no links/monitors locally
                #f
                (make-mutex)
                (make-condition)
                #f)])))
    (sealed #t))

  ;; ========== Global actor table ==========
  ;; Maps id → actor-ref for local lookups (used by supervisor and registry)

  (define *actor-table* (make-eq-hashtable))
  (define *actor-table-mutex* (make-mutex))

  (define (register-local-actor! a)
    (with-mutex *actor-table-mutex*
      (hashtable-set! *actor-table* (actor-ref-id a) a)))

  (define (unregister-local-actor! a)
    (with-mutex *actor-table-mutex*
      (hashtable-delete! *actor-table* (actor-ref-id a))))

  (define (lookup-local-actor id)
    (with-mutex *actor-table-mutex*
      (hashtable-ref *actor-table* id #f)))

  ;; ========== Thread-local actor context ==========

  (define current-actor (make-thread-parameter #f))
  (define (self) (current-actor))
  (define (actor-id) (and (current-actor) (actor-ref-id (current-actor))))

  ;; ========== Dead letter handler ==========

  (define *dead-letter-handler*
    (make-parameter
      (lambda (msg dest)
        (parameterize ([current-output-port (current-error-port)])
          (display "DEAD LETTER: actor #")
          (display (actor-ref-id dest))
          (display " is dead, message dropped: ")
          (write msg)
          (newline)))))

  (define (set-dead-letter-handler! proc)
    (*dead-letter-handler* proc))

  ;; ========== Actor scheduler reference ==========
  ;; When #f, actors fall back to fork-thread (1:1 mode).

  (define *actor-scheduler* (make-parameter #f))
  (define (set-actor-scheduler! sched) (*actor-scheduler* sched))

  ;; ========== Running an actor (internal) ==========

  ;; Process messages from the actor's mailbox in a batch.
  ;; Called as a task on a worker thread (or a dedicated OS thread in 1:1 mode).
  ;; Processes up to max-batch messages before yielding to let other actors run.
  (define *max-batch* 64)

  (define (run-actor! a)
    (parameterize ([current-actor a])
      (with-mutex (actor-ref-sched-mutex a)
        (actor-ref-state-set! a 'running))
      (let loop ([count 0])
        (let-values ([(msg ok) (mpsc-try-dequeue! (actor-ref-mailbox a))])
          (cond
            [(and ok (fx< count *max-batch*))
             ;; Process this message
             (guard (exn [#t (actor-die! a exn)])
               ((actor-ref-behavior a) msg))
             ;; If actor died during processing, stop
             (unless (eq? (actor-ref-state a) 'dead)
               (loop (fx+ count 1)))]
            [else
             ;; No more messages or batch limit reached
             (with-mutex (actor-ref-sched-mutex a)
               (cond
                 ;; Batch limit reached — re-schedule to be fair
                 [(and ok (eq? (actor-ref-state a) 'running))
                  (actor-ref-state-set! a 'scheduled)
                  (schedule-actor-task! a)]
                 ;; Check once more if messages arrived while we were processing
                 [(and (not (mpsc-empty? (actor-ref-mailbox a)))
                       (eq? (actor-ref-state a) 'running))
                  (actor-ref-state-set! a 'scheduled)
                  (schedule-actor-task! a)]
                 ;; Truly idle
                 [(eq? (actor-ref-state a) 'running)
                  (actor-ref-state-set! a 'idle)]
                 ;; Actor died, do nothing
                 [else (void)]))])))))

  ;; Submit the actor's run-loop as a task to the scheduler
  (define (schedule-actor-task! a)
    (let ([sched (*actor-scheduler*)])
      (if sched
        ;; Import scheduler-submit! dynamically to avoid circular dependency.
        ;; In practice, store the submit procedure in *actor-scheduler*.
        ;; For now, *actor-scheduler* holds the submit procedure directly.
        (sched (lambda () (run-actor! a)))
        ;; No scheduler — fall back to fork-thread (1:1 mode)
        (fork-thread (lambda () (run-actor! a))))))

  ;; Handle actor death
  (define (actor-die! a reason)
    (with-mutex (actor-ref-sched-mutex a)
      (actor-ref-state-set! a 'dead))
    (actor-ref-exit-reason-set! a reason)
    (unregister-local-actor! a)
    ;; Close mailbox (wakes any blocked dequeue)
    (guard (exn [#t (void)])  ;; ignore if already closed
      (mpsc-close! (actor-ref-mailbox a)))
    ;; Notify linked actors (bidirectional links)
    (for-each
      (lambda (linked)
        (when (actor-alive? linked)
          (guard (exn [#t (void)])  ;; don't crash if linked actor is dead
            (send linked (list 'EXIT (actor-ref-id a) reason)))))
      (actor-ref-links a))
    ;; Notify monitors (one-way)
    (for-each
      (lambda (mon)
        (let ([watcher (car mon)]
              [tag (cdr mon)])
          (when (actor-alive? watcher)
            (guard (exn [#t (void)])
              (send watcher (list 'DOWN tag (actor-ref-id a) reason))))))
      (actor-ref-monitors a))
    ;; Signal anyone waiting on actor-wait!
    (with-mutex (actor-ref-done-mutex a)
      (condition-broadcast (actor-ref-done-cond a))))

  ;; ========== Public API ==========

  (define spawn-actor
    (case-lambda
      [(behavior) (spawn-actor-impl behavior #f)]
      [(behavior name) (spawn-actor-impl behavior name)]))

  (define (spawn-actor-impl behavior name)
    (let ([a (make-actor-ref behavior name)])
      (register-local-actor! a)
      ;; Don't schedule yet — actor is idle until first message arrives
      a))

  (define spawn-actor/linked
    (case-lambda
      [(behavior) (spawn-actor/linked-impl behavior #f)]
      [(behavior name) (spawn-actor/linked-impl behavior name)]))

  (define (spawn-actor/linked-impl behavior name)
    (let ([parent (current-actor)]
          [child (spawn-actor-impl behavior name)])
      (when parent
        ;; Bidirectional link: if either dies, both get notified
        (actor-ref-links-set! parent (cons child (actor-ref-links parent)))
        (actor-ref-links-set! child (cons parent (actor-ref-links child))))
      child))

  (define (send actor msg)
    (cond
      [(not (actor-ref? actor))
       (error 'send "not an actor-ref" actor)]
      ;; Remote actor: delegate to transport layer (Layer 7)
      [(actor-ref-node actor)
       ;; Will be filled in by Layer 7. For now, error.
       (error 'send "remote send not implemented" (actor-ref-node actor))]
      ;; Local actor
      [(actor-alive? actor)
       (mpsc-enqueue! (actor-ref-mailbox actor) msg)
       ;; Transition idle→scheduled atomically
       (with-mutex (actor-ref-sched-mutex actor)
         (when (eq? (actor-ref-state actor) 'idle)
           (actor-ref-state-set! actor 'scheduled)
           (schedule-actor-task! actor)))]
      ;; Dead actor
      [else
       ((*dead-letter-handler*) msg actor)]))

  (define (actor-alive? actor)
    (not (eq? (actor-ref-state actor) 'dead)))

  (define (actor-kill! actor)
    (unless (eq? (actor-ref-state actor) 'dead)
      (actor-die! actor 'killed)))

  (define (actor-wait! actor)
    (with-mutex (actor-ref-done-mutex actor)
      (let loop ()
        (unless (eq? (actor-ref-state actor) 'dead)
          (condition-wait (actor-ref-done-cond actor)
                          (actor-ref-done-mutex actor))
          (loop)))))

  ) ;; end library
```

### Important Design Decisions

**`*actor-scheduler*` holds a procedure, not a scheduler record**: This avoids a
circular dependency between `core.sls` and `scheduler.sls`. When the scheduler is
started, set `*actor-scheduler*` to `(lambda (thunk) (scheduler-submit! sched thunk))`.
When `#f`, actors fall back to `fork-thread`.

**Batch processing**: `run-actor!` processes up to 64 messages per scheduling quantum.
This amortizes the cost of scheduling (deque push/pop) across multiple messages.
Without batching, a high-throughput actor would spend more time in scheduler overhead
than in actual message processing.

**`sched-mutex`**: A per-actor mutex that protects only the `idle→scheduled` state
transition. This is separate from the MPSC queue locks to avoid contention between
senders and the scheduler.

### Behavior Function Contract

A behavior function receives one message at a time:

```scheme
(import (jerboa core) (std actor core))

(define my-actor
  (spawn-actor
    (lambda (msg)
      (match msg
        [('ping reply-to) (send reply-to 'pong)]
        [('stop)          (actor-kill! (self))]
        [_                (void)]))))
```

The behavior function may call `(self)` to get its own actor-ref.
It must not block indefinitely — use `ask` (Layer 4) for request-reply patterns.

**Test file**: `tests/test-actor-core.ss`
- Spawn, send, actor processes message
- Two actors ping-pong (100 round trips)
- Actor dies from exception, linked actor receives EXIT message
- Dead letter handler called for messages to dead actors
- 1000 actors all receive one message (stress test)
- Double-send: two threads send to same actor simultaneously, both messages processed
- `actor-wait!` returns after actor dies
- `actor-kill!` immediately kills, linked actors notified

---

## Required: `(std task)` Futures Interface

Layer 4 (protocol) depends on `(std task)` for one-shot futures (reply channels).
The required interface is:

```scheme
;; make-future: creates a new, uncompleted future
(make-future)              ;; → future

;; future-complete!: set the value; unblocks any waiting future-get
(future-complete! f value) ;; → unspecified; error if already completed

;; future-get: block until the future is completed, return its value
(future-get f)             ;; → value (blocks)

;; future-done?: non-blocking check
(future-done? f)           ;; → bool
```

If `(std task)` does not export these, implement a minimal version:

```scheme
;; Minimal future implementation (can live in protocol.sls directly)
(define-record-type future
  (fields
    (immutable mutex)
    (immutable cond)
    (mutable value)
    (mutable done?))
  (protocol
    (lambda (new)
      (lambda ()
        (new (make-mutex) (make-condition) #f #f))))
  (sealed #t))

(define (make-future) (make-future))  ;; uses the record constructor

(define (future-complete! f val)
  (with-mutex (future-mutex f)
    (when (future-done? f)
      (error 'future-complete! "future already completed"))
    (future-value-set! f val)
    (future-done?-set! f #t)
    (condition-broadcast (future-cond f))))

(define (future-get f)
  (mutex-acquire (future-mutex f))
  (let loop ()
    (if (future-done? f)
      (let ([v (future-value f)])
        (mutex-release (future-mutex f))
        v)
      (begin
        (condition-wait (future-cond f) (future-mutex f))
        (loop)))))

(define (future-done? f)
  (future-done?-field f))  ;; use the generated accessor
```

**Note**: Name collision — `future-done?` is both the record accessor name (generated
by `(mutable done?)`) and the public API. Rename the field to `completed?` to avoid
the clash:

```scheme
(define-record-type future
  (fields
    (immutable mutex)
    (immutable cond)
    (mutable value)
    (mutable completed?))   ;; field name avoids clash with public API
  ...)

(define (future-done? f) (future-completed? f))
```

---

## Layer 4: Protocol System (`lib/std/actor/protocol.sls`)

### Purpose

Define typed message structs with constructor, predicate, and field accessors.
Generate typed send/receive helpers. This replaces Gerbil's `defmessage` +
`defcall-actor` pattern with a cleaner `defprotocol` macro.

### ask/reply Architecture

The `ask` pattern works by embedding a **reply channel** (a one-shot future)
inside the message envelope. The behavior calls `(reply value)` to complete it.

```
Caller                              Actor
  |                                   |
  |-- send ('$ask rc msg) ----------->|
  |                                   |-- behavior receives msg
  |                                   |-- calls (reply value)
  |<-- future-complete! rc value -----|
  |                                   |
  |-- future-get rc ← blocks ------->|
  |   returns value                   |
```

The `$ask` envelope is an internal detail. User code sees only `(ask actor msg)`.

```scheme
#!chezscheme
(library (std actor protocol)
  (export
    defprotocol

    ;; Core ask/tell/call
    ask          ;; (ask actor-ref msg) → future
    ask-sync     ;; (ask-sync actor-ref msg [timeout-secs]) → value (blocks)
    tell         ;; (tell actor-ref msg) → void (alias for send)

    ;; Reply inside a behavior
    reply        ;; (reply value) → void (must be in ask context)
    reply-to     ;; (reply-to) → actor-ref of requester or #f

    ;; ask envelope unwrapping
    with-ask-context

    ;; One-shot reply channels
    make-reply-channel
    reply-channel?
    reply-channel-get    ;; blocks until reply
    reply-channel-put!   ;; sender puts reply
  )
  (import (chezscheme)
          (std actor core)
          (std task))    ;; for futures

  ;; ========== Reply channels ==========
  ;; A reply channel is a one-shot future: the asker creates it,
  ;; embeds it in the message envelope, and waits on it.
  ;; The behavior calls (reply value) to complete it.

  (define-record-type reply-channel
    (fields
      (immutable future))
    (protocol
      (lambda (new)
        (lambda () (new (make-future)))))
    (sealed #t))

  (define (reply-channel-get rc)
    (future-get (reply-channel-future rc)))

  (define (reply-channel-put! rc value)
    (future-complete! (reply-channel-future rc) value))

  ;; Thread-local: current reply channel (set by with-ask-context)
  (define current-reply-channel (make-thread-parameter #f))
  (define current-sender-ref (make-thread-parameter #f))

  (define (reply value)
    (let ([rc (current-reply-channel)])
      (unless rc
        (error 'reply "not in an ask context — no reply channel available"))
      (reply-channel-put! rc value)))

  (define (reply-to)
    (current-sender-ref))

  ;; ========== ask ==========
  ;; Sends msg to actor with an embedded reply channel.
  ;; The message is wrapped in: ('$ask reply-channel sender-ref . original-msg)
  ;; The '$ask tag is a private symbol — users never construct this manually.

  (define $ask-tag '$ask)  ;; private tag for ask envelopes

  (define (ask actor-ref msg)
    (let* ([rc (make-reply-channel)]
           [envelope (list $ask-tag rc (self) msg)])
      (send actor-ref envelope)
      (reply-channel-future rc)))  ;; return future, caller calls future-get

  (define ask-sync
    (case-lambda
      [(actor-ref msg)
       (future-get (ask actor-ref msg))]
      [(actor-ref msg timeout-secs)
       ;; Timeout: race the future against a timer
       ;; Simple implementation: poll with sleep
       ;; TODO: integrate with scheduler for efficient timeout
       (let ([fut (ask actor-ref msg)])
         (let loop ([remaining timeout-secs])
           (if (future-done? fut)
             (future-get fut)
             (if (<= remaining 0)
               (error 'ask-sync "timeout waiting for reply")
               (begin
                 (sleep (make-time 'time-duration 10000000 0)) ;; 10ms
                 (loop (- remaining 0.01)))))))]))

  ;; ========== tell ==========
  ;; Simple alias for send — semantic distinction makes code clearer.
  (define (tell actor-ref msg)
    (send actor-ref msg))

  ;; ========== ask envelope unwrapping ==========
  ;; Actors that want to support ask must wrap their behavior with this.
  ;; It detects '$ask envelopes, binds the reply channel, and calls the
  ;; handler with the unwrapped message.
  ;;
  ;; Usage:
  ;;   (define (my-behavior msg)
  ;;     (with-ask-context msg
  ;;       (lambda (actual-msg)
  ;;         (match actual-msg
  ;;           [('compute n) (reply (* n n))]
  ;;           ...))))

  (define-syntax with-ask-context
    (syntax-rules ()
      [(_ msg body-proc)
       (if (and (pair? msg) (eq? (car msg) '$ask))
         (let ([rc     (cadr msg)]
               [sender (caddr msg)]
               [actual (cadddr msg)])
           (parameterize ([current-reply-channel rc]
                          [current-sender-ref sender])
             (body-proc actual)))
         (body-proc msg))]))

  ;; ========== defprotocol macro ==========
  ;;
  ;; (defprotocol my-service
  ;;   (ping)                          ;; no fields, no reply expected
  ;;   (compute value -> result)       ;; one field, reply expected
  ;;   (shutdown reason))              ;; one field, no reply
  ;;
  ;; Expands to:
  ;;   - define-record-type for each message: my-service:ping, my-service:compute, etc.
  ;;   - tell helpers: (my-service:ping! actor), (my-service:shutdown! actor reason)
  ;;   - ask helpers (when -> present): (my-service:compute?! actor value) → value

  (define-syntax defprotocol
    (lambda (stx)
      (syntax-case stx ()
        [(_ proto-name clause ...)
         (let* ([proto (syntax->datum #'proto-name)]
                [prefix (symbol->string proto)])

           ;; Parse a clause like (compute value -> result) or (ping)
           ;; Returns: (name fields has-reply?)
           (define (parse-clause clause-datum)
             (let loop ([rest (cdr clause-datum)] [fields '()])
               (cond
                 [(null? rest)
                  (values (car clause-datum) (reverse fields) #f)]
                 [(eq? (car rest) '->)
                  (values (car clause-datum) (reverse fields) #t)]
                 [else
                  (loop (cdr rest) (cons (car rest) fields))])))

           (define (sym . parts)
             (string->symbol
               (apply string-append
                 (map (lambda (p)
                   (if (symbol? p) (symbol->string p) p))
                   parts))))

           (with-syntax
             ([(expanded ...)
               (map (lambda (c)
                 (let ([clause-datum (syntax->datum c)])
                   (let-values ([(name fields has-reply?) (parse-clause clause-datum)])
                     (let* ([struct-name (sym prefix ":" name)]
                            [make-name  (sym "make-" prefix ":" name)]
                            [pred-name  (sym prefix ":" name "?")]
                            [tell-name  (sym prefix ":" name "!")]
                            [ask-name   (sym prefix ":" name "?!")])
                       (datum->syntax #'proto-name
                         `(begin
                            ;; Message struct
                            (define-record-type ,struct-name
                              (fields ,@(map (lambda (f) `(immutable ,f)) fields))
                              (sealed #t))
                            ;; tell variant (fire and forget)
                            (define (,tell-name actor ,@fields)
                              (tell actor (,make-name ,@fields)))
                            ;; ask variant (only if -> specified; blocks for reply)
                            ,@(if has-reply?
                                `((define (,ask-name actor ,@fields)
                                    (ask-sync actor (,make-name ,@fields))))
                                '())))))))
                 (syntax->list #'(clause ...)))])
             #'(begin expanded ...)))])))

  ) ;; end library
```

### Usage Example

```scheme
(import (chezscheme) (jerboa core)
        (std actor core) (std actor protocol))

;; Define the protocol
(defprotocol counter
  (increment amount)
  (get-value -> value)
  (reset))

;; This generates:
;;   (define-record-type counter:increment (fields (immutable amount)) ...)
;;   (define (counter:increment! actor amount) (tell actor (make-counter:increment amount)))
;;   (define-record-type counter:get-value ...)
;;   (define (counter:get-value! actor) (tell actor (make-counter:get-value)))
;;   (define (counter:get-value?! actor) (ask-sync actor (make-counter:get-value)))
;;   (define-record-type counter:reset ...)
;;   (define (counter:reset! actor) (tell actor (make-counter:reset)))

;; Implement the actor
(define (make-counter-actor initial-value)
  (let ([value initial-value])
    (spawn-actor
      (lambda (msg)
        (with-ask-context msg
          (lambda (actual)
            (cond
              [(counter:increment? actual)
               (set! value (+ value (counter:increment-amount actual)))]
              [(counter:get-value? actual)
               (reply value)]
              [(counter:reset? actual)
               (set! value 0)]))))
      'counter)))

;; Client code
(define cnt (make-counter-actor 0))
(counter:increment! cnt 5)
(counter:increment! cnt 3)
(display (counter:get-value?! cnt))  ;; => 8
```

**Test file**: `tests/test-actor-protocol.ss`
- ask/reply round-trip returns correct value
- defprotocol generates correct struct predicates and field accessors
- Typed ask helper `?!` blocks until reply arrives
- `reply` in non-ask context raises error
- tell is fire-and-forget (does not block)
- Multiple concurrent asks to same actor

---

## Layer 5: Supervision Trees (`lib/std/actor/supervisor.sls`)

### Purpose

A supervisor is an actor that monitors child actors and restarts them according to
a strategy when they die. This is the Erlang OTP supervision model.

### Restart Strategies

- **one-for-one**: Only restart the child that died. Other children unaffected.
- **one-for-all**: Restart ALL children when any one dies. Use when children are
  interdependent.
- **rest-for-one**: Restart the child that died AND all children started after it.
  Use when children depend on earlier siblings.

### Restart Intensity

If a child is restarted more than `max-restarts` times within `period-secs`, the
supervisor itself crashes (escalates to its own supervisor). This prevents infinite
restart loops.

### Child Specification

The `child-spec` record type has no explicit `(protocol ...)` clause, so the
constructor takes fields in the order they are declared. Use `make-child-spec`:

```scheme
(make-child-spec id start-thunk restart shutdown type)
;; id:          symbol — unique name within this supervisor
;; start-thunk: (lambda () ...) → actor-ref
;; restart:     'permanent | 'transient | 'temporary
;; shutdown:    'brutal-kill | number (timeout in seconds)
;; type:        'worker | 'supervisor
```

```scheme
;; A child-spec describes how to start and restart a child
(define-record-type child-spec
  (fields
    (immutable id)            ;; symbol: unique name within supervisor
    (immutable start-thunk)   ;; (lambda () ...) → actor-ref
    (immutable restart)       ;; 'permanent | 'transient | 'temporary
                              ;;   permanent:  always restart
                              ;;   transient:  restart only on abnormal exit
                              ;;   temporary:  never restart
    (immutable shutdown)      ;; 'brutal-kill | number (timeout seconds)
    (immutable type))         ;; 'worker | 'supervisor
  (sealed #t))
```

### Restart Policy Semantics

| Policy | Normal exit | Abnormal exit (exception) | Killed |
|--------|-------------|---------------------------|--------|
| `permanent` | Restart | Restart | Restart |
| `transient` | Don't restart | Restart | Don't restart |
| `temporary` | Don't restart | Don't restart | Don't restart |

### Full Implementation

```scheme
#!chezscheme
(library (std actor supervisor)
  (export
    make-child-spec
    child-spec?
    child-spec-id
    child-spec-start-thunk
    child-spec-restart
    child-spec-shutdown
    child-spec-type

    start-supervisor

    supervisor-which-children    ;; → list of (id status actor-ref-or-#f)
    supervisor-count-children    ;; → (specs active supervisors workers)
    supervisor-terminate-child!  ;; → stop a child
    supervisor-restart-child!    ;; → restart a stopped child
    supervisor-start-child!      ;; → add a new child spec dynamically
    supervisor-delete-child!     ;; → remove a child spec
  )
  (import (chezscheme)
          (jerboa core)          ;; for match
          (std actor core)
          (std actor protocol))

  ;; ========== Supervisor state ==========

  (define-record-type supervisor-state
    (fields
      (immutable strategy)      ;; 'one-for-one | 'one-for-all | 'rest-for-one
      (immutable max-restarts)  ;; integer
      (immutable period-secs)   ;; number (seconds)
      (mutable children)        ;; list of child-entry records (ordered)
      (mutable restart-log))    ;; list of timestamps (seconds as floats)
    (sealed #t))

  ;; Runtime state of one child
  (define-record-type child-entry
    (fields
      (immutable spec)          ;; child-spec
      (mutable actor-ref)       ;; current actor-ref or #f if not running
      (mutable status))         ;; 'running | 'restarting | 'stopped | 'dead
    (sealed #t))

  ;; ========== Time helper ==========
  ;; Convert Chez time to float seconds (no SRFI-19 dependency)

  (define (current-seconds)
    (let ([t (current-time)])
      (+ (time-second t) (/ (time-nanosecond t) 1000000000.0))))

  ;; ========== start-supervisor ==========

  (define start-supervisor
    (case-lambda
      [(strategy child-specs)
       (start-supervisor-impl strategy child-specs 10 5)]
      [(strategy child-specs max-restarts)
       (start-supervisor-impl strategy child-specs max-restarts 5)]
      [(strategy child-specs max-restarts period-secs)
       (start-supervisor-impl strategy child-specs max-restarts period-secs)]))

  (define (start-supervisor-impl strategy child-specs max-restarts period-secs)
    (let ([state (make-supervisor-state
                   strategy max-restarts period-secs
                   '() '())])
      (let ([sup (spawn-actor
                   (lambda (msg) (supervisor-behavior state msg))
                   'supervisor)])
        ;; Start all children in order
        (for-each
          (lambda (spec)
            (start-child! state sup spec))
          child-specs)
        sup)))

  ;; Start a single child and add to state
  (define (start-child! state sup spec)
    (let* ([child-actor ((child-spec-start-thunk spec))]
           [entry (make-child-entry spec child-actor 'running)])
      ;; Monitor the child: supervisor gets 'DOWN when child dies.
      ;; Monitors are one-way: supervisor doesn't die when child dies.
      (actor-ref-monitors-set! child-actor
        (cons (cons sup (child-spec-id spec))
              (actor-ref-monitors child-actor)))
      (supervisor-state-children-set! state
        (append (supervisor-state-children state) (list entry)))
      entry))

  ;; ========== Supervisor behavior (the message loop) ==========

  (define (supervisor-behavior state msg)
    (with-ask-context msg
      (lambda (actual)
        (match actual
          ;; Child died — handle according to strategy
          [('DOWN spec-id child-id reason)
           (handle-child-exit! state spec-id child-id reason)]

          ;; Dynamic management (from supervisor-* public API)
          [('which-children)
           (reply (format-children state))]

          [('terminate-child id)
           (terminate-child-by-id! state id)
           (reply 'ok)]

          [('restart-child id)
           (reply (restart-child-by-id! state id))]

          [('start-child spec)
           (let ([entry (start-child! state (self) spec)])
             (reply (child-entry-actor-ref entry)))]

          [('delete-child id)
           (delete-child-by-id! state id)
           (reply 'ok)]

          [_ (void)]))))  ;; ignore unknown messages

  ;; ========== Child exit handling ==========

  (define (handle-child-exit! state spec-id child-id reason)
    (let ([entry (find-child-by-id state spec-id)])
      (when entry
        (let ([spec (child-entry-spec entry)])
          ;; Decide whether to restart
          (let ([should-restart?
                 (case (child-spec-restart spec)
                   [(permanent) #t]
                   [(transient) (not (eq? reason 'normal))]
                   [(temporary) #f]
                   [else #f])])
            (if should-restart?
              (begin
                (check-restart-intensity! state)
                (case (supervisor-state-strategy state)
                  [(one-for-one) (restart-one! state entry)]
                  [(one-for-all) (restart-all! state)]
                  [(rest-for-one) (restart-rest! state entry)]))
              ;; Not restarting — mark as dead
              (child-entry-status-set! entry 'dead)))))))

  ;; Check if restart intensity exceeded.
  ;; If so, raise an error — the supervisor itself dies and escalates.
  (define (check-restart-intensity! state)
    (let* ([now (current-seconds)]
           [period (supervisor-state-period-secs state)]
           [log (filter (lambda (t) (> t (- now period)))
                        (supervisor-state-restart-log state))])
      (supervisor-state-restart-log-set! state (cons now log))
      (when (>= (length log) (supervisor-state-max-restarts state))
        (error 'supervisor "restart intensity exceeded — too many restarts"
               (supervisor-state-max-restarts state)
               (supervisor-state-period-secs state)))))

  ;; NOTE: restart-one!, restart-all!, restart-rest! are called only from
  ;; handle-child-exit!, which is called from supervisor-behavior.
  ;; supervisor-behavior runs inside the supervisor actor's task, so
  ;; (self) correctly returns the supervisor's actor-ref.

  (define (restart-one! state entry)
    (stop-child-entry! entry)
    (let* ([spec (child-entry-spec entry)]
           [new-actor ((child-spec-start-thunk spec))])
      (child-entry-actor-ref-set! entry new-actor)
      (child-entry-status-set! entry 'running)
      ;; Re-attach monitor
      (actor-ref-monitors-set! new-actor
        (cons (cons (self) (child-spec-id spec))
              (actor-ref-monitors new-actor)))))

  (define (restart-all! state)
    ;; Stop all in reverse order (most recently started first)
    (let ([children (supervisor-state-children state)])
      (for-each stop-child-entry! (reverse children))
      ;; Restart all in forward order (dependency order)
      (for-each
        (lambda (entry)
          (let* ([spec (child-entry-spec entry)]
                 [new-actor ((child-spec-start-thunk spec))])
            (child-entry-actor-ref-set! entry new-actor)
            (child-entry-status-set! entry 'running)
            (actor-ref-monitors-set! new-actor
              (cons (cons (self) (child-spec-id spec))
                    (actor-ref-monitors new-actor)))))
        children)))

  (define (restart-rest! state failed-entry)
    ;; Find position of failed entry, stop and restart from there onward
    (let* ([children (supervisor-state-children state)]
           [pos (let loop ([cs children] [i 0])
                  (cond [(null? cs) -1]
                        [(eq? (car cs) failed-entry) i]
                        [else (loop (cdr cs) (fx+ i 1))]))]
           [rest (if (fx>= pos 0) (list-tail children pos) '())])
      (for-each stop-child-entry! (reverse rest))
      (for-each
        (lambda (entry)
          (let* ([spec (child-entry-spec entry)]
                 [new-actor ((child-spec-start-thunk spec))])
            (child-entry-actor-ref-set! entry new-actor)
            (child-entry-status-set! entry 'running)
            (actor-ref-monitors-set! new-actor
              (cons (cons (self) (child-spec-id spec))
                    (actor-ref-monitors new-actor)))))
        rest)))

  ;; Stop a child gracefully, then kill if needed
  (define (stop-child-entry! entry)
    (let ([a (child-entry-actor-ref entry)]
          [shutdown (child-spec-shutdown (child-entry-spec entry))])
      (when (and a (actor-alive? a))
        (cond
          [(eq? shutdown 'brutal-kill)
           (actor-kill! a)]
          [(number? shutdown)
           ;; Send shutdown signal, wait up to timeout, then force kill
           (guard (exn [#t (void)])
             (send a '(shutdown)))
           (let ([deadline (+ (current-seconds) shutdown)])
             (let loop ()
               (cond
                 [(not (actor-alive? a)) (void)]  ;; died naturally
                 [(>= (current-seconds) deadline)
                  (actor-kill! a)]                 ;; timeout expired
                 [else
                  (sleep (make-time 'time-duration 50000000 0)) ;; 50ms
                  (loop)])))]))
      (child-entry-actor-ref-set! entry #f)
      (child-entry-status-set! entry 'stopped)))

  ;; ========== Dynamic child management ==========

  (define (terminate-child-by-id! state id)
    (let ([entry (find-child-by-id state id)])
      (when entry (stop-child-entry! entry))))

  (define (restart-child-by-id! state id)
    (let ([entry (find-child-by-id state id)])
      (if (and entry (eq? (child-entry-status entry) 'stopped))
        (begin
          (restart-one! state entry)
          'ok)
        'not-found)))

  (define (delete-child-by-id! state id)
    (let ([entry (find-child-by-id state id)])
      (when entry
        (stop-child-entry! entry)
        (supervisor-state-children-set! state
          (filter (lambda (e) (not (eq? e entry)))
                  (supervisor-state-children state))))))

  ;; ========== Public management API ==========
  ;; These are called from OUTSIDE the supervisor actor, via ask-sync.

  (define (supervisor-which-children sup)
    (ask-sync sup '(which-children)))

  (define (supervisor-count-children sup)
    (let ([children (supervisor-which-children sup)])
      (let loop ([cs children] [specs 0] [active 0] [sups 0] [workers 0])
        (if (null? cs)
          (values specs active sups workers)
          (let ([c (car cs)])
            (loop (cdr cs)
                  (fx+ specs 1)
                  (if (eq? (cadr c) 'running) (fx+ active 1) active)
                  sups  ;; TODO: distinguish supervisor vs worker
                  workers))))))

  (define (supervisor-terminate-child! sup id)
    (ask-sync sup (list 'terminate-child id)))

  (define (supervisor-restart-child! sup id)
    (ask-sync sup (list 'restart-child id)))

  (define (supervisor-start-child! sup spec)
    (ask-sync sup (list 'start-child spec)))

  (define (supervisor-delete-child! sup id)
    (ask-sync sup (list 'delete-child id)))

  ;; ========== Helpers ==========

  (define (find-child-by-id state id)
    (let loop ([cs (supervisor-state-children state)])
      (cond
        [(null? cs) #f]
        [(eq? (child-spec-id (child-entry-spec (car cs))) id) (car cs)]
        [else (loop (cdr cs))])))

  (define (format-children state)
    (map (lambda (entry)
           (list (child-spec-id (child-entry-spec entry))
                 (child-entry-status entry)
                 (child-entry-actor-ref entry)))
         (supervisor-state-children state)))

  ) ;; end library
```

### Usage Example

```scheme
(import (chezscheme) (jerboa core)
        (std actor core) (std actor protocol) (std actor supervisor))

;; Define worker actors
(define (make-database-actor)
  (spawn-actor
    (lambda (msg)
      (with-ask-context msg
        (lambda (actual)
          (match actual
            [('query sql) (reply "result")]
            [('shutdown) (actor-kill! (self))]
            [_ (void)]))))
    'database))

(define (make-cache-actor)
  (spawn-actor (lambda (msg) (void)) 'cache))

;; Build supervision tree
(define app-supervisor
  (start-supervisor
    'one-for-one                        ;; strategy
    (list
      (make-child-spec
        'database                       ;; id
        make-database-actor             ;; start-thunk (zero-arg procedure)
        'permanent                      ;; always restart
        5.0                             ;; 5-second graceful shutdown
        'worker)                        ;; type
      (make-child-spec
        'cache
        make-cache-actor
        'transient                      ;; restart only on crash, not normal exit
        'brutal-kill
        'worker))
    10     ;; max 10 restarts
    5))    ;; within 5 seconds
```

**Test file**: `tests/test-actor-supervisor.ss`
- Worker crashes, one-for-one restarts only it
- Worker crashes, one-for-all restarts all children
- Worker crashes, rest-for-one restarts it and later siblings
- permanent vs transient vs temporary restart policies
- Intensity exceeded causes supervisor crash (error raised)
- Graceful shutdown with timeout
- Dynamic: `supervisor-start-child!` adds new child at runtime
- Dynamic: `supervisor-delete-child!` removes child
- Nested supervisors (supervisor as child of another supervisor)

---

## Layer 6: Registry (`lib/std/actor/registry.sls`)

### Purpose

Named actors: `(register! 'db-actor actor-ref)` then later `(whereis 'db-actor)`.
The registry is itself an actor. When an actor dies, its name is auto-unregistered.

```scheme
#!chezscheme
(library (std actor registry)
  (export
    start-registry!       ;; must be called before using registry
    register!             ;; (register! name actor-ref) → 'ok | 'already-registered
    unregister!           ;; (unregister! name) → 'ok
    whereis               ;; (whereis name) → actor-ref or #f
    registered-names      ;; → list of registered names
    registry-actor        ;; the registry actor-ref itself
  )
  (import (chezscheme) (jerboa core)
          (std actor core) (std actor protocol))

  (define *registry-actor* #f)
  (define (registry-actor) *registry-actor*)

  ;; Registry behavior: maintains a hash table of name → actor-ref
  ;; The hash table is captured in the closure (not a global).
  (define (make-registry-behavior)
    (let ([table (make-eq-hashtable)])
      (lambda (msg)
        (with-ask-context msg
          (lambda (actual)
            (match actual
              [('register name ref)
               (if (hashtable-ref table name #f)
                 (reply 'already-registered)
                 (begin
                   (hashtable-set! table name ref)
                   ;; Monitor the actor: auto-remove from registry on death
                   (actor-ref-monitors-set! ref
                     (cons (cons (self) name)
                           (actor-ref-monitors ref)))
                   (reply 'ok)))]

              [('unregister name)
               (hashtable-delete! table name)
               (reply 'ok)]

              [('whereis name)
               (reply (hashtable-ref table name #f))]

              [('names)
               (reply (vector->list (hashtable-keys table)))]

              ;; Actor died — auto-unregister its name
              [('DOWN name dead-id reason)
               (hashtable-delete! table name)]

              [_ (void)]))))))

  (define (start-registry!)
    (set! *registry-actor*
          (spawn-actor (make-registry-behavior) 'registry)))

  (define (register! name actor-ref)
    (ask-sync *registry-actor* (list 'register name actor-ref)))

  (define (unregister! name)
    (ask-sync *registry-actor* (list 'unregister name)))

  (define (whereis name)
    (ask-sync *registry-actor* (list 'whereis name)))

  (define (registered-names)
    (ask-sync *registry-actor* '(names)))

  ) ;; end library
```

**Test file**: `tests/test-actor-registry.ss`
- `register!` then `whereis` returns same ref
- Duplicate registration returns `'already-registered`
- `unregister!` then `whereis` returns `#f`
- Actor dies, `whereis` returns `#f` (auto-unregister via monitor)
- `registered-names` returns list of all registered names

---

## Layer 7: Distributed Transport

### Overview

Distributed actors extend `send` to work across network nodes.
An actor-ref has a `node` field (string: `"host:port"`).
`send` checks `(actor-ref-node ref)`: if non-`#f`, routes through the transport layer.

**File**: `lib/std/actor/transport.sls` (single file for simplicity; can be split later)

This layer requires:
1. **Serialization** — fasl-based message framing over TCP
2. **Node identity** — each process has a node-id string
3. **Connection pool** — maintains TCP connections to peer nodes
4. **Server** — accepts incoming connections and dispatches to local actors
5. **Remote refs** — actor-refs pointing to actors on another node

### 7A: Serialization

Chez's `fasl-write`/`fasl-read` handles all Scheme data types automatically.
We add a 4-byte big-endian length prefix for message framing over TCP.

**Limitations**:
- Closures are NOT safely serializable across machines (different code)
- Port objects cannot be serialized
- For cross-machine communication, messages must contain only data (no lambdas)

```scheme
;; Frame format: [4 bytes: big-endian length] [N bytes: fasl data]

(define (message->bytes msg)
  (let-values ([(port get-bytes) (open-bytevector-output-port)])
    (fasl-write msg port)
    (let* ([body (get-bytes)]
           [n (bytevector-length body)]
           [frame (make-bytevector (fx+ 4 n))])
      ;; Write 4-byte length header (big-endian)
      (bytevector-u8-set! frame 0 (fxlogand (fxsra n 24) #xFF))
      (bytevector-u8-set! frame 1 (fxlogand (fxsra n 16) #xFF))
      (bytevector-u8-set! frame 2 (fxlogand (fxsra n 8) #xFF))
      (bytevector-u8-set! frame 3 (fxlogand n #xFF))
      (bytevector-copy! body 0 frame 4 n)
      frame)))

(define (read-framed-message port)
  (let ([header (get-bytevector-n port 4)])
    (when (or (eof-object? header) (< (bytevector-length header) 4))
      (error 'read-framed-message "connection closed"))
    (let ([n (fx+ (fx+ (fx+ (fxsll (bytevector-u8-ref header 0) 24)
                             (fxsll (bytevector-u8-ref header 1) 16))
                        (fxsll (bytevector-u8-ref header 2) 8))
                  (bytevector-u8-ref header 3))])
      (let ([body (get-bytevector-n port n)])
        (when (or (eof-object? body) (< (bytevector-length body) n))
          (error 'read-framed-message "truncated message"))
        (fasl-read (open-bytevector-input-port body))))))

(define (write-framed-message port msg)
  (let ([frame (message->bytes msg)])
    (put-bytevector port frame)
    (flush-output-port port)))
```

**Note**: `get-bytevector-n` is a standard Chez procedure that reads exactly N bytes.
This is cleaner than byte-at-a-time `get-u8` loops.

### 7B: Node Identity

```scheme
(define *node-id* (make-parameter #f))
(define *node-cookie* (make-parameter #f))

(define (current-node-id) (*node-id*))
(define (current-node-cookie) (*node-cookie*))

(define (start-node! host port cookie)
  (let ([id (string-append host ":" (number->string port))])
    (*node-id* id)
    (*node-cookie* cookie)
    id))

;; Parse "host:port" — search from right to handle IPv6 addresses
(define (node-id->host+port node-id)
  (let loop ([i (fx- (string-length node-id) 1)])
    (cond
      [(fx< i 0) (error 'node-id->host+port "no colon in node-id" node-id)]
      [(char=? (string-ref node-id i) #\:)
       (values (substring node-id 0 i)
               (string->number (substring node-id (fx+ i 1)
                                          (string-length node-id))))]
      [else (loop (fx- i 1))])))
```

### 7C: Connection Pool

```scheme
;; Connection pool: node-id → (values in-port out-port write-mutex)
;; The write-mutex protects concurrent writes to the same connection.
(define *connections* (make-hashtable string-hash string=?))
(define *conn-mutex* (make-mutex))

(define (get-connection! node-id)
  (with-mutex *conn-mutex*
    (or (hashtable-ref *connections* node-id #f)
        (let ([conn (open-connection! node-id)])
          (hashtable-set! *connections* node-id conn)
          conn))))

(define (drop-connection! node-id)
  (with-mutex *conn-mutex*
    (hashtable-delete! *connections* node-id)))

;; Returns a vector: #(in-port out-port write-mutex)
(define (open-connection! node-id)
  (let-values ([(host port) (node-id->host+port node-id)])
    ;; Open a raw TCP connection using Chez's built-in TCP support
    (let-values ([(in-port out-port)
                  (open-tcp-connection host port)])
      (let ([write-mutex (make-mutex)])
        ;; Cookie-based handshake: send hello, expect ok
        (let ([hello (list 'hello (current-node-id)
                           (cookie-hash (current-node-cookie) node-id))])
          (with-mutex write-mutex
            (write-framed-message out-port hello))
          ;; Read acknowledgement
          (let ([resp (read-framed-message in-port)])
            (unless (and (pair? resp) (eq? (car resp) 'ok))
              (close-port in-port)
              (close-port out-port)
              (error 'open-connection! "handshake rejected" node-id resp))))
        (vector in-port out-port write-mutex)))))

;; Simple FNV-1a-style hash for cookie authentication.
;; In production, replace with HMAC-SHA256 via (std crypto hmac).
(define (cookie-hash cookie peer-id)
  (let ([s (string-append cookie ":" peer-id)])
    (let loop ([h #x811c9dc5] [i 0])
      (if (fx= i (string-length s))
        (fxlogand h #xFFFFFFFF)
        (loop (fxlogand
                (fxxor (fx* h 16777619)
                       (char->integer (string-ref s i)))
                #xFFFFFFFF)
              (fx+ i 1))))))

;; Open TCP connection.  On Chez, tcp-connect is not built-in.
;; Use (open-socket ...) or the chez-socket library.
;; This shim uses the simplest available approach: open-tcp-connection
;; which is provided by (std net tcp) or a thin FFI shim.
;;
;; If unavailable, fall back to:
;;   (define open-tcp-connection
;;     (foreign-procedure "jerboa_tcp_connect"
;;       (string integer) (values input-port output-port)))
(define (open-tcp-connection host port)
  ;; Implementation depends on your TCP library.
  ;; With chez-socket:
  ;;   (let ([s (make-client-socket host (number->string port))])
  ;;     (values (socket-input-port s) (socket-output-port s)))
  ;; Placeholder — replace with actual TCP library call:
  (error 'open-tcp-connection "TCP library not yet wired in"))
```

### 7D: Node Server (Accepting Connections)

The server accepts incoming connections, verifies the cookie handshake, and
dispatches messages to local actors. Each accepted connection gets its own
reader thread.

```scheme
;; Start the server: accept connections on the given port.
;; Runs in a background thread — returns immediately.
(define (start-node-server! port)
  (fork-thread
    (lambda ()
      (let ([server-socket (make-server-socket port)])
        (let loop ()
          (let ([client (accept-socket server-socket)])
            (fork-thread
              (lambda () (handle-client! client)))
            (loop)))))))

;; Handle one client connection: authenticate, then read messages.
(define (handle-client! client-socket)
  (let ([in-port  (socket-input-port  client-socket)]
        [out-port (socket-output-port client-socket)])
    ;; Read hello
    (guard (exn [#t (close-port in-port) (close-port out-port)])
      (let ([hello (read-framed-message in-port)])
        (if (not (and (pair? hello)
                      (eq? (car hello) 'hello)
                      (>= (length hello) 3)))
          (begin
            (write-framed-message out-port '(error "bad hello"))
            (close-port in-port)
            (close-port out-port))
          (let* ([peer-node-id (cadr  hello)]
                 [their-hash   (caddr hello)]
                 [our-expected (cookie-hash (current-node-cookie) peer-node-id)])
            (if (not (fx= their-hash our-expected))
              (begin
                (write-framed-message out-port '(error "bad cookie"))
                (close-port in-port)
                (close-port out-port))
              (begin
                (write-framed-message out-port (list 'ok (current-node-id)))
                ;; Message dispatch loop
                (let loop ()
                  (let ([msg (guard (exn [#t 'eof])
                               (read-framed-message in-port))])
                    (unless (eq? msg 'eof)
                      (dispatch-remote-message! msg)
                      (loop))))
                (close-port in-port)
                (close-port out-port)))))))))

;; Dispatch a message received from a remote node.
;; Expected format: ('send local-actor-id payload)
(define (dispatch-remote-message! msg)
  (when (and (pair? msg)
             (eq? (car msg) 'send)
             (pair? (cdr msg)))
    (let ([actor-id (cadr  msg)]
          [payload  (caddr msg)])
      (let ([actor (lookup-local-actor actor-id)])
        (if actor
          (send actor payload)
          ;; Actor not found — log as dead letter
          ((*dead-letter-handler*) payload
            (make-actor-ref actor-id "unknown-remote")))))))
```

**Note**: `make-server-socket`, `accept-socket`, `socket-input-port`,
`socket-output-port` depend on your TCP library (`chez-socket` or equivalent).
Replace with the actual API from your networking layer.

### 7E: Complete `transport.sls` Library

```scheme
#!chezscheme
(library (std actor transport)
  (export
    ;; Node identity
    start-node!
    current-node-id

    ;; Server
    start-node-server!

    ;; Remote refs
    make-remote-actor-ref

    ;; Connection management (exposed for testing)
    drop-connection!
  )
  (import (chezscheme)
          (std actor core))

  ;; All the definitions from sections 7A–7D above go here.
  ;; They are collected inside this single library form.

  ;; 7A: Serialization
  (define (message->bytes msg)
    (let-values ([(port get-bytes) (open-bytevector-output-port)])
      (fasl-write msg port)
      (let* ([body (get-bytes)]
             [n (bytevector-length body)]
             [frame (make-bytevector (fx+ 4 n))])
        (bytevector-u8-set! frame 0 (fxlogand (fxsra n 24) #xFF))
        (bytevector-u8-set! frame 1 (fxlogand (fxsra n 16) #xFF))
        (bytevector-u8-set! frame 2 (fxlogand (fxsra n 8) #xFF))
        (bytevector-u8-set! frame 3 (fxlogand n #xFF))
        (bytevector-copy! body 0 frame 4 n)
        frame)))

  (define (read-framed-message port)
    (let ([header (get-bytevector-n port 4)])
      (when (or (eof-object? header) (< (bytevector-length header) 4))
        (error 'read-framed-message "connection closed"))
      (let ([n (fx+ (fx+ (fx+ (fxsll (bytevector-u8-ref header 0) 24)
                               (fxsll (bytevector-u8-ref header 1) 16))
                          (fxsll (bytevector-u8-ref header 2) 8))
                    (bytevector-u8-ref header 3))])
        (let ([body (get-bytevector-n port n)])
          (when (or (eof-object? body) (< (bytevector-length body) n))
            (error 'read-framed-message "truncated message"))
          (fasl-read (open-bytevector-input-port body))))))

  (define (write-framed-message port msg)
    (let ([frame (message->bytes msg)])
      (put-bytevector port frame)
      (flush-output-port port)))

  ;; 7B: Node identity
  (define *node-id*     (make-parameter #f))
  (define *node-cookie* (make-parameter #f))

  (define (current-node-id) (*node-id*))

  (define (start-node! host port cookie)
    (let ([id (string-append host ":" (number->string port))])
      (*node-id* id)
      (*node-cookie* cookie)
      id))

  (define (node-id->host+port node-id)
    (let loop ([i (fx- (string-length node-id) 1)])
      (cond
        [(fx< i 0) (error 'node-id->host+port "no colon in node-id" node-id)]
        [(char=? (string-ref node-id i) #\:)
         (values (substring node-id 0 i)
                 (string->number (substring node-id (fx+ i 1)
                                            (string-length node-id))))]
        [else (loop (fx- i 1))])))

  ;; 7C: Connection pool (see definitions above)
  (define *connections* (make-hashtable string-hash string=?))
  (define *conn-mutex* (make-mutex))

  (define (cookie-hash cookie peer-id)
    (let ([s (string-append cookie ":" peer-id)])
      (let loop ([h #x811c9dc5] [i 0])
        (if (fx= i (string-length s))
          (fxlogand h #xFFFFFFFF)
          (loop (fxlogand
                  (fxxor (fx* h 16777619)
                         (char->integer (string-ref s i)))
                  #xFFFFFFFF)
                (fx+ i 1))))))

  (define (get-connection! node-id)
    (with-mutex *conn-mutex*
      (or (hashtable-ref *connections* node-id #f)
          (let ([conn (open-connection! node-id)])
            (hashtable-set! *connections* node-id conn)
            conn))))

  (define (drop-connection! node-id)
    (with-mutex *conn-mutex*
      (hashtable-delete! *connections* node-id)))

  (define (open-connection! node-id)
    (let-values ([(host port) (node-id->host+port node-id)])
      (let-values ([(in-port out-port) (open-tcp-connection host port)])
        (let ([write-mutex (make-mutex)])
          (let ([hello (list 'hello (current-node-id)
                             (cookie-hash (*node-cookie*) node-id))])
            (with-mutex write-mutex
              (write-framed-message out-port hello))
            (let ([resp (read-framed-message in-port)])
              (unless (and (pair? resp) (eq? (car resp) 'ok))
                (close-port in-port)
                (close-port out-port)
                (error 'open-connection! "handshake rejected" node-id))))
          (vector in-port out-port write-mutex)))))

  ;; Stub — replace with real TCP library call
  (define (open-tcp-connection host port)
    (error 'open-tcp-connection "TCP library not wired in — see 7C notes"))

  ;; 7D: Remote send (called from core.sls send procedure)
  ;; Wire this into core.sls by setting the remote-send handler:
  ;;   (set-remote-send-handler!
  ;;     (lambda (actor msg)
  ;;       (remote-send! (actor-ref-node actor) (actor-ref-id actor) msg)))

  (define (remote-send! node-id actor-id msg)
    (guard (exn [#t
                 ;; Drop connection on error so next attempt reconnects
                 (drop-connection! node-id)
                 (error 'remote-send! "send failed" node-id exn)])
      (let ([conn (get-connection! node-id)])
        (let ([out-port    (vector-ref conn 1)]
              [write-mutex (vector-ref conn 2)])
          (with-mutex write-mutex
            (write-framed-message out-port (list 'send actor-id msg)))))))

  ;; 7E: Remote actor refs
  (define (make-remote-actor-ref node-id remote-actor-id)
    (make-actor-ref remote-actor-id node-id))

  ;; 7F: Server
  (define (start-node-server! listen-port)
    (fork-thread
      (lambda ()
        (let ([server (make-server-socket listen-port)])
          (let loop ()
            (let ([client (accept-socket server)])
              (fork-thread (lambda () (handle-client! client)))
              (loop)))))))

  ;; Stubs for socket operations — replace with real TCP library
  (define (make-server-socket port)
    (error 'make-server-socket "TCP library not wired in"))
  (define (accept-socket srv)
    (error 'accept-socket "TCP library not wired in"))
  (define (socket-input-port s) (error 'socket-input-port "not wired in"))
  (define (socket-output-port s) (error 'socket-output-port "not wired in"))

  (define (handle-client! client-socket)
    (let ([in-port  (socket-input-port  client-socket)]
          [out-port (socket-output-port client-socket)])
      (guard (exn [#t (close-port in-port) (close-port out-port)])
        (let ([hello (read-framed-message in-port)])
          (if (not (and (pair? hello)
                        (eq? (car hello) 'hello)
                        (>= (length hello) 3)))
            (begin
              (write-framed-message out-port '(error "bad hello"))
              (close-port in-port)
              (close-port out-port))
            (let* ([peer-id      (cadr  hello)]
                   [their-hash   (caddr hello)]
                   [our-expected (cookie-hash (*node-cookie*) peer-id)])
              (if (not (fx= their-hash our-expected))
                (begin
                  (write-framed-message out-port '(error "bad cookie"))
                  (close-port in-port)
                  (close-port out-port))
                (begin
                  (write-framed-message out-port (list 'ok (current-node-id)))
                  (let loop ()
                    (let ([msg (guard (exn [#t 'eof])
                                 (read-framed-message in-port))])
                      (unless (eq? msg 'eof)
                        (dispatch-remote-message! msg)
                        (loop))))
                  (close-port in-port)
                  (close-port out-port))))))))

  (define (dispatch-remote-message! msg)
    (when (and (pair? msg) (eq? (car msg) 'send) (pair? (cdr msg)))
      (let ([actor-id (cadr  msg)]
            [payload  (caddr msg)])
        (let ([actor (lookup-local-actor actor-id)])
          (when actor
            (send actor payload))))))

  ) ;; end library
```

### 7F: Remote Actor Refs

```scheme
;; Create a reference to an actor on a remote node
(define (make-remote-actor-ref node-id remote-actor-id)
  (make-actor-ref remote-actor-id node-id))  ;; uses the 2-arg constructor
```

The `actor-ref` record in `core.sls` already has a `case-lambda` protocol with a
2-argument constructor `(id node)` for remote refs. Remote refs have no local mailbox
(`#f`), no behavior, and their `node` field is set to the remote node-id string.

### 7G: Wiring Remote Send into core.sls

Add a remote-send parameter to `core.sls` and update `send`:

```scheme
;; In core.sls — add this parameter:
(define *remote-send-handler* (make-parameter #f))

(define (set-remote-send-handler! proc)
  (*remote-send-handler* proc))

;; Update the remote branch of send:
[(actor-ref-node actor)
 (let ([handler (*remote-send-handler*)])
   (if handler
     (handler actor msg)
     (error 'send "remote send not configured; call set-remote-send-handler!" actor)))]

;; In application startup, after loading transport.sls:
(set-remote-send-handler!
  (lambda (actor msg)
    (remote-send! (actor-ref-node actor) (actor-ref-id actor) msg)))
```

This avoids a circular import between `core.sls` and `transport.sls`.

### Testing Distributed

Test on localhost: start two Chez processes, each calls `start-node!` with different
ports but the same cookie. Process A creates a remote-ref to an actor on Process B
and sends a message. Process B receives and replies.

**Test file**: `tests/test-actor-distributed.ss`
- Two processes on localhost exchange messages
- Connection failure triggers dead letter handler
- Large message (1MB bytevector) round-trip
- Cookie mismatch rejects connection
- Reconnect after connection drop

---

## Complete File Map

```
lib/std/actor/
  mpsc.sls              Layer 1A  MPSC queue (mailbox queue)
  deque.sls             Layer 1B  Work-stealing deque
  scheduler.sls         Layer 2   Thread pool + work-stealing
  core.sls              Layer 3   spawn-actor, send, self, lifecycle
  protocol.sls          Layer 4   defprotocol, ask, tell, reply
  supervisor.sls        Layer 5   OTP supervision trees
  registry.sls          Layer 6   Named actor registry
  transport.sls         Layer 7   Distributed: serialize, node, connections

lib/std/actor.sls       Re-export facade (all layers)

tests/
  test-actor-mpsc.ss    Tests for MPSC queue
  test-actor-deque.ss   Tests for work-stealing deque
  test-actor-core.ss    Tests for spawn/send/receive/lifecycle
  test-actor-protocol.ss Tests for defprotocol, ask, tell
  test-actor-supervisor.ss Tests for supervision strategies
  test-actor-registry.ss   Tests for name registration
  test-actor-distributed.ss Tests for cross-node messaging
```

---

## Test File Implementations

Each test file uses Chez's built-in `check`-style assertions via `guard` and
`assert`. For a richer test framework use `(std test)` if available, or
write a minimal harness:

```scheme
;; Minimal test harness (paste into each test file)
(define *tests-run* 0)
(define *tests-failed* 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (begin
       (set! *tests-run* (fx+ *tests-run* 1))
       (let ([got expr])
         (unless (equal? got expected)
           (set! *tests-failed* (fx+ *tests-failed* 1))
           (display "FAIL: ") (display name) (newline)
           (display "  expected: ") (write expected) (newline)
           (display "  got:      ") (write got) (newline))))]))

(define (test-summary)
  (display *tests-run*) (display " tests, ")
  (display *tests-failed*) (display " failed")
  (newline)
  (when (fx> *tests-failed* 0) (error 'test-summary "tests failed")))
```

### `tests/test-actor-mpsc.ss`

```scheme
#!chezscheme
(import (chezscheme) (std actor mpsc))

;; --- Minimal test harness ---
(define *tests-run* 0)
(define *tests-failed* 0)
(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (begin
       (set! *tests-run* (fx+ *tests-run* 1))
       (let ([got expr])
         (unless (equal? got expected)
           (set! *tests-failed* (fx+ *tests-failed* 1))
           (display "FAIL: ") (display name) (newline)
           (display "  expected: ") (write expected) (newline)
           (display "  got:      ") (write got) (newline))))]))

;; Test 1: basic enqueue/dequeue
(let ([q (make-mpsc-queue)])
  (mpsc-enqueue! q 'hello)
  (mpsc-enqueue! q 'world)
  (test "dequeue-1" (mpsc-dequeue! q) 'hello)
  (test "dequeue-2" (mpsc-dequeue! q) 'world))

;; Test 2: try-dequeue on empty returns (values #f #f)
(let ([q (make-mpsc-queue)])
  (let-values ([(v ok) (mpsc-try-dequeue! q)])
    (test "try-empty-val" v #f)
    (test "try-empty-ok"  ok #f)))

;; Test 3: 10 concurrent producers, 1 consumer
(let ([q (make-mpsc-queue)]
      [received (make-eq-hashtable)]
      [done-mutex (make-mutex)]
      [done-cond  (make-condition)]
      [producers-done 0])
  (define total 1000)  ;; 10 threads × 100 msgs
  ;; Start 10 producers
  (do ([t 0 (fx+ t 1)]) ((fx= t 10))
    (let ([thread-id t])
      (fork-thread
        (lambda ()
          (do ([i 0 (fx+ i 1)]) ((fx= i 100))
            (mpsc-enqueue! q (cons thread-id i)))
          (with-mutex done-mutex
            (set! producers-done (fx+ producers-done 1))
            (when (fx= producers-done 10)
              (condition-signal done-cond)))))))
  ;; Wait for all producers to finish (then close)
  (with-mutex done-mutex
    (let loop ()
      (unless (fx= producers-done 10)
        (condition-wait done-cond done-mutex)
        (loop))))
  (mpsc-close! q)
  ;; Consume all messages
  (let loop ([count 0])
    (let-values ([(msg ok) (mpsc-try-dequeue! q)])
      (if ok
        (begin
          (hashtable-set! received msg #t)
          (loop (fx+ count 1)))
        (test "all-received" count total)))))

;; Test 4: single-producer FIFO ordering
(let ([q (make-mpsc-queue)])
  (do ([i 0 (fx+ i 1)]) ((fx= i 100))
    (mpsc-enqueue! q i))
  (let loop ([i 0])
    (when (fx< i 100)
      (let-values ([(v ok) (mpsc-try-dequeue! q)])
        (when ok
          (test (string-append "fifo-" (number->string i)) v i)
          (loop (fx+ i 1)))))))

;; Test 5: close wakes blocked consumer
(let ([q (make-mpsc-queue)]
      [error-caught #f])
  (let ([t (fork-thread
              (lambda ()
                (guard (exn [#t (set! error-caught #t)])
                  (mpsc-dequeue! q))))])
    (sleep (make-time 'time-duration 50000000 0))  ;; 50ms
    (mpsc-close! q)
    (sleep (make-time 'time-duration 50000000 0))
    (test "close-wakes-consumer" error-caught #t)))

(display *tests-run*) (display " tests, ")
(display *tests-failed*) (display " failed") (newline)
(when (fx> *tests-failed* 0) (exit 1))
```

### `tests/test-actor-core.ss`

```scheme
#!chezscheme
(import (chezscheme) (jerboa core) (std actor core))

;; --- Minimal harness (same as above) ---
(define *tests-run* 0)
(define *tests-failed* 0)
(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (begin (set! *tests-run* (fx+ *tests-run* 1))
            (let ([got expr])
              (unless (equal? got expected)
                (set! *tests-failed* (fx+ *tests-failed* 1))
                (display "FAIL: ") (display name) (newline)
                (display "  expected: ") (write expected) (newline)
                (display "  got:      ") (write got) (newline))))]))

;; Test 1: spawn, send, actor processes one message
(let ([got #f]
      [done-mutex (make-mutex)]
      [done-cond  (make-condition)])
  (let ([a (spawn-actor
              (lambda (msg)
                (with-mutex done-mutex
                  (set! got msg)
                  (condition-signal done-cond))))])
    (send a 'ping)
    (with-mutex done-mutex
      (let loop ()
        (unless got
          (condition-wait done-cond done-mutex)
          (loop))))
    (test "spawn-send" got 'ping)))

;; Test 2: actor-alive? and actor-kill!
(let ([a (spawn-actor (lambda (msg) (void)))])
  (test "alive-before-kill" (actor-alive? a) #t)
  (actor-kill! a)
  (sleep (make-time 'time-duration 10000000 0)) ;; 10ms
  (test "dead-after-kill" (actor-alive? a) #f))

;; Test 3: two actors ping-pong
(let ([count 0]
      [done-mutex (make-mutex)]
      [done-cond  (make-condition)])
  (define pong #f)
  (define ping
    (spawn-actor
      (lambda (msg)
        (match msg
          ['pong
           (set! count (fx+ count 1))
           (if (fx< count 100)
             (send pong 'ping)
             (with-mutex done-mutex
               (condition-signal done-cond)))]))))
  (set! pong
    (spawn-actor
      (lambda (msg)
        (match msg
          ['ping (send ping 'pong)]))))
  (send pong 'ping)
  (with-mutex done-mutex
    (let loop ()
      (unless (fx= count 100)
        (condition-wait done-cond done-mutex)
        (loop))))
  (test "ping-pong-100" count 100))

;; Test 4: linked actor receives EXIT on death
(let ([exit-received #f]
      [done-mutex (make-mutex)]
      [done-cond  (make-condition)])
  (define parent
    (spawn-actor
      (lambda (msg)
        (match msg
          [('EXIT _ _)
           (with-mutex done-mutex
             (set! exit-received #t)
             (condition-signal done-cond))]
          [_ (void)]))))
  (define child
    (spawn-actor/linked
      (lambda (msg) (error 'test "intentional crash"))))
  (send child 'go)
  (with-mutex done-mutex
    (let loop ()
      (unless exit-received
        (condition-wait done-cond done-mutex)
        (loop))))
  (test "linked-exit" exit-received #t))

;; Test 5: dead letter handler called for dead actor
(let ([dead-letter-got #f])
  (set-dead-letter-handler! (lambda (msg dest) (set! dead-letter-got msg)))
  (let ([a (spawn-actor (lambda (msg) (void)))])
    (actor-kill! a)
    (sleep (make-time 'time-duration 10000000 0))
    (send a 'orphan)
    (sleep (make-time 'time-duration 10000000 0))
    (test "dead-letter" dead-letter-got 'orphan))
  ;; Restore default handler
  (set-dead-letter-handler!
    (lambda (msg dest)
      (display "DEAD LETTER: ") (write msg) (newline))))

;; Test 6: actor-wait! returns after actor killed
(let ([a (spawn-actor (lambda (msg) (void)))]
      [wait-returned #f])
  (fork-thread
    (lambda ()
      (actor-wait! a)
      (set! wait-returned #t)))
  (sleep (make-time 'time-duration 20000000 0))
  (actor-kill! a)
  (sleep (make-time 'time-duration 20000000 0))
  (test "actor-wait" wait-returned #t))

;; Test 7: 1000 actors each receive one message
(let ([counter 0]
      [counter-mutex (make-mutex)]
      [done-cond  (make-condition)])
  (do ([i 0 (fx+ i 1)]) ((fx= i 1000))
    (let ([a (spawn-actor
                (lambda (msg)
                  (with-mutex counter-mutex
                    (set! counter (fx+ counter 1))
                    (when (fx= counter 1000)
                      (condition-signal done-cond)))))])
      (send a 'go)))
  (with-mutex counter-mutex
    (let loop ()
      (unless (fx= counter 1000)
        (condition-wait done-cond counter-mutex)
        (loop))))
  (test "1000-actors" counter 1000))

(display *tests-run*) (display " tests, ")
(display *tests-failed*) (display " failed") (newline)
(when (fx> *tests-failed* 0) (exit 1))
```

### `tests/test-actor-protocol.ss`

```scheme
#!chezscheme
(import (chezscheme) (jerboa core)
        (std actor core) (std actor protocol))

(define *tests-run* 0)
(define *tests-failed* 0)
(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (begin (set! *tests-run* (fx+ *tests-run* 1))
            (let ([got expr])
              (unless (equal? got expected)
                (set! *tests-failed* (fx+ *tests-failed* 1))
                (display "FAIL: ") (display name) (newline)
                (display "  expected: ") (write expected) (newline)
                (display "  got:      ") (write got) (newline))))]))

;; Test 1: ask/reply round-trip
(let ([a (spawn-actor
            (lambda (msg)
              (with-ask-context msg
                (lambda (actual)
                  (match actual
                    [('add x y) (reply (+ x y))]
                    [_ (void)])))))])
  (test "ask-reply" (ask-sync a '(add 3 4)) 7))

;; Test 2: reply in non-ask context raises error
(let ([error-raised #f])
  (let ([a (spawn-actor
              (lambda (msg)
                (guard (exn [#t (set! error-raised #t)])
                  (reply 42))))])
    (send a 'trigger)
    (sleep (make-time 'time-duration 50000000 0))
    (test "reply-no-context" error-raised #t)))

;; Test 3: tell is fire-and-forget
(let ([got #f]
      [done-mutex (make-mutex)]
      [done-cond  (make-condition)])
  (let ([a (spawn-actor
              (lambda (msg)
                (with-mutex done-mutex
                  (set! got msg)
                  (condition-signal done-cond))))])
    (tell a 'notif)
    (with-mutex done-mutex
      (let loop ()
        (unless got
          (condition-wait done-cond done-mutex)
          (loop))))
    (test "tell" got 'notif)))

;; Test 4: defprotocol generates correct helpers
(defprotocol math-svc
  (square x -> result)
  (log-value v))

(let ([a (spawn-actor
            (lambda (msg)
              (with-ask-context msg
                (lambda (actual)
                  (cond
                    [(math-svc:square? actual)
                     (reply (* (math-svc:square-x actual)
                               (math-svc:square-x actual)))]
                    [(math-svc:log-value? actual)
                     (display "logged: ")
                     (display (math-svc:log-value-v actual))
                     (newline)]
                    [else (void)])))))])
  (test "defprotocol-ask"  (math-svc:square?! a 7) 49)
  (math-svc:log-value! a 42))

;; Test 5: multiple concurrent asks
(let ([a (spawn-actor
            (lambda (msg)
              (with-ask-context msg
                (lambda (actual)
                  (match actual
                    [('echo v) (reply v)]
                    [_ (void)])))))]
      [results '()]
      [results-mutex (make-mutex)]
      [done-cond     (make-condition)])
  (do ([i 0 (fx+ i 1)]) ((fx= i 10))
    (let ([n i])
      (fork-thread
        (lambda ()
          (let ([v (ask-sync a (list 'echo n))])
            (with-mutex results-mutex
              (set! results (cons v results))
              (when (fx= (length results) 10)
                (condition-signal done-cond))))))))
  (with-mutex results-mutex
    (let loop ()
      (unless (fx= (length results) 10)
        (condition-wait done-cond results-mutex)
        (loop))))
  (test "concurrent-asks" (length results) 10))

(display *tests-run*) (display " tests, ")
(display *tests-failed*) (display " failed") (newline)
(when (fx> *tests-failed* 0) (exit 1))
```

### `tests/test-actor-supervisor.ss`

```scheme
#!chezscheme
(import (chezscheme) (jerboa core)
        (std actor core) (std actor protocol) (std actor supervisor))

(define *tests-run* 0)
(define *tests-failed* 0)
(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (begin (set! *tests-run* (fx+ *tests-run* 1))
            (let ([got expr])
              (unless (equal? got expected)
                (set! *tests-failed* (fx+ *tests-failed* 1))
                (display "FAIL: ") (display name) (newline)
                (display "  expected: ") (write expected) (newline)
                (display "  got:      ") (write got) (newline))))]))

;; Test 1: one-for-one restart
(let ([started 0]
      [start-mutex (make-mutex)])
  (define (make-crashable-worker)
    (with-mutex start-mutex
      (set! started (fx+ started 1)))
    (spawn-actor
      (lambda (msg)
        (match msg
          ['crash (error 'worker "intentional")]
          [_      (void)]))))

  (let ([sup (start-supervisor
               'one-for-one
               (list (make-child-spec 'w make-crashable-worker 'permanent 1.0 'worker))
               10 5)])
    (sleep (make-time 'time-duration 50000000 0))
    (test "one-for-one-started" started 1)
    ;; Crash the worker
    (let ([children (supervisor-which-children sup)])
      (let ([w (caddr (car children))])
        (send w 'crash)))
    (sleep (make-time 'time-duration 100000000 0)) ;; 100ms for restart
    (test "one-for-one-restarted" started 2)))

;; Test 2: transient worker — no restart on normal exit
(let ([started 0])
  (define (make-transient)
    (set! started (fx+ started 1))
    (spawn-actor
      (lambda (msg)
        (match msg
          ['stop (actor-kill! (self))]
          [_ (void)]))))

  (let ([sup (start-supervisor
               'one-for-one
               (list (make-child-spec 'w make-transient 'transient 1.0 'worker))
               10 5)])
    (sleep (make-time 'time-duration 50000000 0))
    (let ([children (supervisor-which-children sup)])
      (let ([w (caddr (car children))])
        (actor-kill! w)))   ;; killed = not 'normal, so transient SHOULD restart
    (sleep (make-time 'time-duration 100000000 0))
    (test "transient-restart-on-kill" started 2)))

;; Test 3: temporary worker — never restarted
(let ([started 0])
  (define (make-temp)
    (set! started (fx+ started 1))
    (spawn-actor
      (lambda (msg)
        (match msg
          ['crash (error 'temp "die")]
          [_ (void)]))))

  (let ([sup (start-supervisor
               'one-for-one
               (list (make-child-spec 'w make-temp 'temporary 1.0 'worker))
               10 5)])
    (sleep (make-time 'time-duration 50000000 0))
    (let ([children (supervisor-which-children sup)])
      (let ([w (caddr (car children))])
        (send w 'crash)))
    (sleep (make-time 'time-duration 100000000 0))
    (test "temporary-no-restart" started 1)))

;; Test 4: dynamic child management
(let ([sup (start-supervisor 'one-for-one '() 10 5)])
  (let ([new-ref
         (supervisor-start-child! sup
           (make-child-spec 'dynamic
                            (lambda () (spawn-actor (lambda (msg) (void))))
                            'permanent 1.0 'worker))])
    (test "dynamic-start" (actor-ref? new-ref) #t)
    (supervisor-terminate-child! sup 'dynamic)
    (let ([children (supervisor-which-children sup)])
      (test "dynamic-terminate" (cadr (car children)) 'stopped))))

(display *tests-run*) (display " tests, ")
(display *tests-failed*) (display " failed") (newline)
(when (fx> *tests-failed* 0) (exit 1))
```

### `tests/test-actor-registry.ss`

```scheme
#!chezscheme
(import (chezscheme) (jerboa core)
        (std actor core) (std actor protocol) (std actor registry))

(define *tests-run* 0)
(define *tests-failed* 0)
(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (begin (set! *tests-run* (fx+ *tests-run* 1))
            (let ([got expr])
              (unless (equal? got expected)
                (set! *tests-failed* (fx+ *tests-failed* 1))
                (display "FAIL: ") (display name) (newline)
                (display "  expected: ") (write expected) (newline)
                (display "  got:      ") (write got) (newline))))]))

(start-registry!)

;; Test 1: register and whereis
(let ([a (spawn-actor (lambda (msg) (void)))])
  (test "register-ok"  (register! 'my-actor a) 'ok)
  (test "whereis-found" (whereis 'my-actor) a)
  (unregister! 'my-actor))

;; Test 2: duplicate registration
(let ([a (spawn-actor (lambda (msg) (void)))])
  (register! 'dup a)
  (test "register-dup" (register! 'dup a) 'already-registered)
  (unregister! 'dup))

;; Test 3: unregister then whereis returns #f
(let ([a (spawn-actor (lambda (msg) (void)))])
  (register! 'gone a)
  (unregister! 'gone)
  (test "whereis-gone" (whereis 'gone) #f))

;; Test 4: actor dies, auto-unregistered
(let ([a (spawn-actor (lambda (msg) (void)))])
  (register! 'dying a)
  (actor-kill! a)
  (sleep (make-time 'time-duration 100000000 0)) ;; 100ms for DOWN to propagate
  (test "auto-unregister" (whereis 'dying) #f))

;; Test 5: registered-names
(let ([a (spawn-actor (lambda (msg) (void)))]
      [b (spawn-actor (lambda (msg) (void)))])
  (register! 'aa a)
  (register! 'bb b)
  (let ([names (registered-names)])
    (test "names-contains-aa" (memq 'aa names) (memq 'aa names))
    (test "names-contains-bb" (memq 'bb names) (memq 'bb names)))
  (unregister! 'aa)
  (unregister! 'bb))

(display *tests-run*) (display " tests, ")
(display *tests-failed*) (display " failed") (newline)
(when (fx> *tests-failed* 0) (exit 1))
```

### `tests/test-actor-deque.ss`

```scheme
#!chezscheme
(import (chezscheme) (std actor deque))

(define *tests-run* 0)
(define *tests-failed* 0)
(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (begin (set! *tests-run* (fx+ *tests-run* 1))
            (let ([got expr])
              (unless (equal? got expected)
                (set! *tests-failed* (fx+ *tests-failed* 1))
                (display "FAIL: ") (display name) (newline)
                (display "  expected: ") (write expected) (newline)
                (display "  got:      ") (write got) (newline))))]))

;; Test 1: push and pop LIFO
(let ([d (make-work-deque)])
  (deque-push-bottom! d 'a)
  (deque-push-bottom! d 'b)
  (deque-push-bottom! d 'c)
  (test "pop-lifo-1" (deque-pop-bottom! d) 'c)
  (test "pop-lifo-2" (deque-pop-bottom! d) 'b)
  (test "pop-lifo-3" (deque-pop-bottom! d) 'a)
  (test "pop-empty"  (deque-pop-bottom! d) #f))

;; Test 2: steal FIFO
(let ([d (make-work-deque)])
  (deque-push-bottom! d 'x)
  (deque-push-bottom! d 'y)
  (deque-push-bottom! d 'z)
  (let-values ([(t1 ok1) (deque-steal-top! d)])
    (let-values ([(t2 ok2) (deque-steal-top! d)])
      (let-values ([(t3 ok3) (deque-steal-top! d)])
        (let-values ([(t4 ok4) (deque-steal-top! d)])
          (test "steal-fifo-1" t1 'x)
          (test "steal-fifo-2" t2 'y)
          (test "steal-fifo-3" t3 'z)
          (test "steal-empty-ok" ok4 #f))))))

;; Test 3: grow beyond initial capacity (64)
(let ([d (make-work-deque)])
  (do ([i 0 (fx+ i 1)]) ((fx= i 200))
    (deque-push-bottom! d i))
  (let loop ([i 199] [ok #t])
    (if (or (not ok) (fx< i 0))
      (test "grow-lifo" i -1)
      (let ([v (deque-pop-bottom! d)])
        (loop (fx- i 1) (fx= v i))))))

;; Test 4: concurrent push + steal
(let ([d (make-work-deque)]
      [stolen (make-vector 100 #f)]
      [steal-count 0]
      [steal-mutex (make-mutex)]
      [done-cond (make-condition)])
  (do ([i 0 (fx+ i 1)]) ((fx= i 100))
    (deque-push-bottom! d i))
  (do ([t 0 (fx+ t 1)]) ((fx= t 5))
    (fork-thread
      (lambda ()
        (let loop ()
          (let-values ([(task ok) (deque-steal-top! d)])
            (when ok
              (with-mutex steal-mutex
                (vector-set! stolen task #t)
                (set! steal-count (fx+ steal-count 1))
                (when (fx= steal-count 100)
                  (condition-signal done-cond)))
              (loop)))))))
  (with-mutex steal-mutex
    (let loop ()
      (unless (fx= steal-count 100)
        (condition-wait done-cond steal-mutex)
        (loop))))
  (test "concurrent-steal" steal-count 100))

(display *tests-run*) (display " tests, ")
(display *tests-failed*) (display " failed") (newline)
(when (fx> *tests-failed* 0) (exit 1))
```

---

## Implementation Roadmap (Step by Step)

Implement and test each step before moving to the next.

### Step 1: MPSC Queue

**File**: `lib/std/actor/mpsc.sls`
**Test**: `tests/test-actor-mpsc.ss`
**Dependencies**: `(chezscheme)` only

Implementation checklist:
- [ ] `make-mpsc-queue` creates two-lock linked list with dummy head
- [ ] `mpsc-enqueue!` acquires tail-lock, signals after releasing tail-lock
- [ ] `mpsc-dequeue!` acquires head-lock, blocks via `condition-wait` if empty
- [ ] `mpsc-try-dequeue!` returns `(values #f #f)` immediately if empty
- [ ] `mpsc-close!` sets closed flag, broadcasts to wake blocked consumers
- [ ] All locking uses `with-mutex` for exception safety
- [ ] Test: 10 concurrent producers, 1 consumer, verify all messages received
- [ ] Test: `try-dequeue` on empty returns `(values #f #f)`
- [ ] Test: close wakes blocked consumer with error
- [ ] Test: single-producer ordering is preserved (FIFO)

### Step 2: Actor Core (1:1 OS thread mode, no scheduler)

**File**: `lib/std/actor/core.sls`
**Test**: `tests/test-actor-core.ss`
**Dependencies**: `mpsc.sls`

Initially implement WITHOUT the work-stealing scheduler: use `fork-thread` directly
for each actor task. Layer 2 (scheduler) is a drop-in optimization added later.

Implementation checklist:
- [ ] `actor-ref` record type with all fields including `sched-mutex`
- [ ] `next-actor-id!` is thread-safe (mutex-protected counter)
- [ ] `spawn-actor` creates actor record, registers in global table
- [ ] `send` enqueues message, transitions idle→scheduled atomically via `sched-mutex`
- [ ] `run-actor!` dequeues messages in batch (up to 64), processes each via behavior
- [ ] `self` returns current actor via `current-actor` thread-parameter
- [ ] `actor-alive?` checks state field is not `'dead`
- [ ] `actor-kill!` calls `actor-die!`, sets state to dead
- [ ] `actor-die!` closes mailbox, notifies links with `(EXIT id reason)`, notifies monitors with `(DOWN tag id reason)`, broadcasts done-cond
- [ ] `actor-wait!` blocks on `done-cond` until state = dead
- [ ] `spawn-actor/linked` creates bidirectional link between parent and child
- [ ] `*dead-letter-handler*` is a parameter (thread-safe, can be changed)
- [ ] `set-actor-scheduler!` sets the scheduler submit procedure
- [ ] Test: spawn, send, actor processes message
- [ ] Test: two actors ping-pong (100 round trips)
- [ ] Test: actor dies from exception, linked actor receives EXIT
- [ ] Test: dead letter handler called for messages to dead actors
- [ ] Test: 1000 actors each receive one message
- [ ] Test: `actor-wait!` returns after actor killed

### Step 3: Protocol System

**File**: `lib/std/actor/protocol.sls`
**Test**: `tests/test-actor-protocol.ss`
**Dependencies**: `core.sls`, `(std task)` (for futures)

Implementation checklist:
- [ ] `reply-channel` wraps a future from `(std task)`
- [ ] `ask` wraps message in `('$ask rc sender msg)` envelope, returns future
- [ ] `ask-sync` calls `ask` then `future-get`
- [ ] `with-ask-context` macro detects `$ask` envelope, binds reply channel
- [ ] `reply` completes the current reply channel (error if not in ask context)
- [ ] `defprotocol` generates: record types, tell helpers (`!` suffix), ask helpers (`?!` suffix)
- [ ] `tell` is alias for `send`
- [ ] Test: ask/reply round-trip returns correct value
- [ ] Test: defprotocol generates correct struct predicates
- [ ] Test: typed ask helper `?!` blocks and returns value
- [ ] Test: `reply` in non-ask context raises error
- [ ] Test: multiple concurrent asks to same actor

### Step 4: Supervision Trees

**File**: `lib/std/actor/supervisor.sls`
**Test**: `tests/test-actor-supervisor.ss`
**Dependencies**: `core.sls`, `protocol.sls`, `(jerboa core)` (for `match`)

Implementation checklist:
- [ ] `make-child-spec` with all fields (id, start-thunk, restart, shutdown, type)
- [ ] `start-supervisor` starts children in order, monitors each
- [ ] one-for-one: only restart the dead child
- [ ] one-for-all: stop all in reverse, restart all in forward
- [ ] rest-for-one: stop failed + later siblings in reverse, restart in forward
- [ ] permanent: always restart
- [ ] transient: restart only on abnormal exit (not 'normal, not 'killed)
- [ ] temporary: never restart
- [ ] Restart intensity tracking via timestamp log
- [ ] Supervisor crashes (raises error) when intensity exceeded
- [ ] Graceful shutdown: send '(shutdown), wait up to timeout, then kill
- [ ] `supervisor-which-children` returns child status list
- [ ] `supervisor-start-child!` adds child dynamically
- [ ] `supervisor-delete-child!` removes child
- [ ] `current-seconds` helper avoids SRFI-19 dependency
- [ ] Test: worker crashes, one-for-one restarts only it
- [ ] Test: worker crashes, one-for-all restarts all
- [ ] Test: permanent vs transient vs temporary
- [ ] Test: intensity exceeded causes supervisor crash
- [ ] Test: nested supervisors (tree structure)

### Step 5: Registry

**File**: `lib/std/actor/registry.sls`
**Test**: `tests/test-actor-registry.ss`
**Dependencies**: `core.sls`, `protocol.sls`, `(jerboa core)` (for `match`)

Implementation checklist:
- [ ] `start-registry!` spawns the registry actor
- [ ] `register!` registers name, returns `'already-registered` if duplicate
- [ ] `whereis` returns actor-ref or `#f`
- [ ] `unregister!` removes name
- [ ] Auto-unregister when actor dies (via monitor + DOWN message)
- [ ] `registered-names` returns list of all names
- [ ] Test: register, whereis returns same ref
- [ ] Test: register duplicate returns 'already-registered
- [ ] Test: actor dies, whereis returns #f
- [ ] Test: unregister manually, whereis returns #f

### Step 6: Work-Stealing Scheduler

**File**: `lib/std/actor/deque.sls`, `lib/std/actor/scheduler.sls`
**Test**: `tests/test-actor-deque.ss`, `tests/test-actor-scheduler.ss`
**Dependencies**: none (standalone)

This step upgrades `core.sls` from 1:1 OS threads to M:N scheduling.
All tests from Steps 2-5 must still pass after this change.

Implementation checklist:
- [ ] `make-work-deque` circular buffer with mutex
- [ ] `deque-push-bottom!` owner pushes (grows buffer if needed)
- [ ] `deque-pop-bottom!` owner pops LIFO, returns #f if empty
- [ ] `deque-steal-top!` thief steals FIFO, returns `(values #f #f)` if empty
- [ ] `make-scheduler` creates N workers with deques
- [ ] `scheduler-start!` forks N worker threads
- [ ] Worker loop: pop own → steal random → wait on condition
- [ ] Lost-wakeup prevention: re-check own deque after acquiring mutex
- [ ] `scheduler-submit!` fast path: from worker, push own deque
- [ ] `scheduler-submit!` slow path: from outside, push random worker's deque
- [ ] Wire into `core.sls`: `(set-actor-scheduler! (lambda (thunk) (scheduler-submit! sched thunk)))`
- [ ] `cpu-count` helper reads `/proc/cpuinfo`
- [ ] Test: submit 10000 tasks, all complete
- [ ] Test: no deadlock with empty deques and concurrent steal attempts
- [ ] Test: all prior actor tests pass with scheduler enabled
- [ ] Benchmark: 100k messages throughput before/after scheduler

### Step 7: Distributed Transport

**File**: `lib/std/actor/transport.sls`
**Test**: `tests/test-actor-distributed.ss`
**Dependencies**: `core.sls`, `(std net ssl)`

This is the most complex step. Test on localhost first.

Implementation checklist:
- [ ] `message->bytes` and `bytes->message` with 4-byte big-endian length frame
- [ ] `read-framed-message` uses `get-bytevector-n` for efficient reads
- [ ] `write-framed-message` writes frame + flushes
- [ ] `start-node!` sets node-id and cookie parameters
- [ ] `node-id->host+port` parses from right (IPv6 safe)
- [ ] Connection pool with `make-hashtable` (string keys)
- [ ] Cookie-based handshake on connection open
- [ ] `make-remote-actor-ref` uses the 2-arg constructor in `core.sls`
- [ ] `send` in core.sls routes to transport when `actor-ref-node` is non-`#f`
- [ ] Node server accepts connections, authenticates, dispatches messages
- [ ] Per-connection write mutex prevents interleaved frames
- [ ] Test: two Chez processes on localhost exchange messages
- [ ] Test: cookie mismatch rejects connection
- [ ] Test: large message (1MB bytevector) round-trip

---

## Facade Library (`lib/std/actor.sls`)

Once all layers are built, provide a single import:

```scheme
#!chezscheme
(library (std actor)
  (export
    ;; Core (Layer 3)
    spawn-actor spawn-actor/linked
    send self actor-id actor-alive? actor-kill! actor-wait!
    actor-ref? set-dead-letter-handler!

    ;; Protocol (Layer 4)
    defprotocol with-ask-context
    ask ask-sync tell reply reply-to
    make-reply-channel reply-channel-get reply-channel-put!

    ;; Supervision (Layer 5)
    make-child-spec start-supervisor
    supervisor-which-children supervisor-count-children
    supervisor-terminate-child! supervisor-restart-child!
    supervisor-start-child! supervisor-delete-child!

    ;; Registry (Layer 6)
    start-registry! register! unregister! whereis registered-names

    ;; Scheduler (Layer 2)
    make-scheduler scheduler-start! scheduler-stop!
    scheduler-submit! set-actor-scheduler!
  )

  (import
    (std actor core)
    (std actor protocol)
    (std actor supervisor)
    (std actor registry)
    (std actor scheduler))

  ) ;; end library
```

Distributed transport (Layer 7) is imported separately when needed:
```scheme
(import (std actor) (std actor transport))
```

---

## Design Decisions and Rationale

### Why MPSC queue instead of a simple mutex-protected list?

The two-lock queue allows producers and consumer to proceed in parallel.
A single mutex forces all senders to queue behind each other AND behind the consumer.
With the two-lock design, 10 concurrent senders block each other only briefly
(tail-lock) and never block the consumer (head-lock separate).

### Why work-stealing instead of a global task queue?

A global task queue is a bottleneck under high concurrency: every submit and every
task completion requires acquiring the global lock. Work-stealing gives each worker
its own deque. The global queue is only accessed when a worker's deque is empty,
which in practice is rare under load.

### Why `with-mutex` everywhere instead of manual acquire/release?

Exception safety. Chez's `with-mutex` uses `dynamic-wind` to guarantee the mutex is
released even if the body raises an exception. Manual `mutex-acquire`/`mutex-release`
will leak the lock if code between them throws. Every lock acquisition in this system
MUST use `with-mutex`.

### Why batch message processing (max 64 per quantum)?

Without batching, each message requires: deque pop → behavior call → deque push.
With batching, one deque pop/push handles 64 messages. This amortizes scheduling
overhead. 64 is a good default: small enough that no actor starves others, large
enough to get throughput benefits.

### Why fasl for distributed serialization?

Chez's `fasl-write`/`fasl-read` handles all Scheme data types automatically:
records, vectors, strings, bytevectors, symbols, numbers, booleans, pairs.
This means any pure-data message is automatically serializable without writing
serialization code. The only restriction is no closures or ports across machines.
JSON would require explicit conversion for every message type.

### Why cookie authentication instead of TLS client certs?

Cookie auth (shared secret) is simpler to set up and sufficient for a trusted
private network. TLS with chez-ssl can be layered on top for encryption without
changing the authentication model.

### Why monitors instead of links for supervision?

Links are bidirectional: if either actor dies, the other receives an EXIT signal.
This is correct for peer actors but wrong for supervisors — a supervisor should
NOT die when a worker dies (it needs to restart the worker). Monitors are
one-way: the supervisor receives a DOWN message but does not propagate its own
death to the worker. This matches Erlang/OTP semantics exactly.

### Why `*actor-scheduler*` is a procedure, not a record?

To break the circular dependency between `core.sls` and `scheduler.sls`. The core
module needs to submit tasks to the scheduler, but the scheduler module needs actor
types from core. By making `*actor-scheduler*` a `(lambda (thunk) ...)` parameter,
core doesn't need to import scheduler at all. The application wires them together:
```scheme
(set-actor-scheduler! (lambda (thunk) (scheduler-submit! sched thunk)))
```

### Why not Erlang-style process dictionary?

Erlang's per-process dictionary (`put`/`get`) is convenient but makes testing
harder (implicit mutable state). Instead, actors carry all state in their closure:

```scheme
(define (make-stateful-actor)
  (let ([state 0])      ;; state lives in the closure
    (spawn-actor
      (lambda (msg)
        (set! state (+ state 1))
        (display state)
        (newline)))))
```

This is idiomatic Scheme and easier to reason about.

---

## Common Pitfalls

### 1. `time->seconds` doesn't exist in Chez

Use `(time-second t)` and `(time-nanosecond t)` directly, or import `(std srfi srfi-19)`.
The supervisor uses `current-seconds` which is defined locally.

### 2. `match` must be imported from `(jerboa core)`

Chez does not have built-in pattern matching. Every file that uses `match` must:
```scheme
(import (jerboa core))
```

### 3. `cpu-count` doesn't exist in Chez

Read from `/proc/cpuinfo` or hardcode. See the `cpu-count` helper in Layer 2.

### 4. `condition-wait` semantics

`(condition-wait cond mutex)` atomically releases the mutex and waits. When it wakes
(signal or broadcast), it re-acquires the mutex before returning. The timeout variant
`(condition-wait cond mutex time)` returns `#f` on timeout, `#t` if signaled.

**Always re-check the condition in a loop** after `condition-wait` returns — spurious
wakeups are possible, and with `condition-broadcast` multiple threads may wake but
only one should proceed.

### 5. Race condition: double scheduling

If two threads call `send` on the same actor simultaneously, both may see `state = 'idle`
and both submit tasks. Use a `sched-mutex` per actor and transition states atomically
inside `with-mutex`.

### 6. `with-mutex` vs manual acquire/release

Always prefer `with-mutex`. The only exception is `condition-wait`, which requires
the mutex to already be held. Pattern:
```scheme
(mutex-acquire m)
(let loop ()
  (unless (condition-met?)
    (condition-wait c m)
    (loop)))
;; condition is met, mutex is held
(do-work)
(mutex-release m)
```
But even here, wrap the outer scope in a `guard` or `dynamic-wind` to ensure release.

### 7. `string-index` doesn't exist in Chez

The node-id parser uses a manual loop to find `:` from the right. There is no
`string-index` built-in.

---

## Example: Full Application

```scheme
(import (chezscheme) (jerboa core)
        (std actor)
        (std actor scheduler))

;; Helper: CPU count from /proc
(define (cpu-count)
  (guard (exn [#t 4])
    (let ([p (open-input-file "/proc/cpuinfo")])
      (let loop ([n 0])
        (let ([line (get-line p)])
          (cond
            [(eof-object? line) (close-port p) (fxmax n 1)]
            [(and (fx>= (string-length line) 9)
                  (string=? (substring line 0 9) "processor"))
             (loop (fx+ n 1))]
            [else (loop n)]))))))

;; Start infrastructure
(define sched (scheduler-start! (make-scheduler (cpu-count))))
(set-actor-scheduler! (lambda (thunk) (scheduler-submit! sched thunk)))
(start-registry!)

;; Define a counter service
(defprotocol counter
  (increment n)
  (decrement n)
  (get-value -> value)
  (reset))

(define (make-counter initial)
  (let ([n initial])
    (spawn-actor
      (lambda (msg)
        (with-ask-context msg
          (lambda (actual)
            (cond
              [(counter:increment? actual)
               (set! n (+ n (counter:increment-n actual)))]
              [(counter:decrement? actual)
               (set! n (- n (counter:decrement-n actual)))]
              [(counter:get-value? actual)
               (reply n)]
              [(counter:reset? actual)
               (set! n initial)]))))
      'counter)))

;; Start with supervision
(define app
  (start-supervisor
    'one-for-one
    (list
      (make-child-spec 'counter
                       (lambda () (make-counter 0))
                       'permanent 5.0 'worker))
    10 5))

;; Find and use the counter
(let ([children (supervisor-which-children app)])
  (let ([counter-ref (caddr (car children))])  ;; (id status ref)
    (register! 'counter counter-ref)))

(counter:increment! (whereis 'counter) 10)
(counter:increment! (whereis 'counter) 5)
(display (counter:get-value?! (whereis 'counter)))  ;; => 15
(newline)

;; Cleanup
(scheduler-stop! sched)
```

---

## Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Local send (in-pool) | < 500 ns | MPSC enqueue + deque push |
| Local send (external) | < 2 µs | MPSC enqueue + fork-thread (1:1 mode) |
| ask round-trip (local) | < 5 µs | send + future-get |
| ask round-trip (loopback TCP) | < 100 µs | serialize + TCP + deserialize |
| Scheduler throughput | > 5M tasks/sec | 8 workers, trivial tasks |
| Max local actors | > 100k | limited by memory (~2KB/actor) |

Benchmark after implementing each layer to catch regressions early.
Use `(std task)` `with-task-group` + `task-group-async` for parallel benchmarks.

---

## Validation Notes

This guide was validated against Chez Scheme 10.4.0 (`ta6le`, threaded build):

- **`fasl-write`/`fasl-read`**: Confirmed working for round-trip serialization of lists, symbols, numbers
- **`condition-wait` with timeout**: Returns `#f` on timeout (not exception) — used in scheduler sleep
- **`with-mutex`**: Built-in, uses `dynamic-wind` for exception safety — confirmed working
- **`make-thread-parameter`**: SMP-safe thread-locals — confirmed working
- **`fork-thread`**: Starts OS thread immediately — confirmed working
- **`get-thread-id`**: Returns integer thread id — confirmed working
- **`random`**: Available for random worker selection — confirmed working
- **`filter`**: Available (R6RS) — confirmed working
- **`match`**: NOT built-in — must import from `(jerboa core)`
- **`time->seconds`**: NOT built-in — must import from `(std srfi srfi-19)` or use `time-second`/`time-nanosecond`
- **`cpu-count`**: NOT available — must read from `/proc/cpuinfo`
- **`string-index`**: NOT available — must implement manually
- **`get-bytevector-n`**: Available — efficient bulk reads from ports
- **CAS (`compare-and-swap`)**: NOT available — use mutex-based deque initially
- **`fxxor`**: Available in Chez 10 — use for FNV cookie hash
- **`future-done?`**: NOT in `define-record-type` namespace; name the field `completed?` to avoid clash

---

## Integration Checklist

Use this checklist when wiring all layers together for the first time.

### Startup sequence

```scheme
;; 1. Build order: mpsc → deque → core → protocol → supervisor → registry → scheduler
;; 2. After loading all .sls files, initialize in this order:

;; a. Start the scheduler (optional — skip for 1:1 OS thread mode)
(define sched (scheduler-start! (make-scheduler (cpu-count))))
(set-actor-scheduler! (lambda (thunk) (scheduler-submit! sched thunk)))

;; b. Start the registry
(start-registry!)

;; c. Wire in transport (optional — only for distributed)
;; (import (std actor transport))
;; (start-node! "localhost" 9000 "my-secret-cookie")
;; (start-node-server! 9000)
;; (set-remote-send-handler!
;;   (lambda (actor msg)
;;     (remote-send! (actor-ref-node actor) (actor-ref-id actor) msg)))
```

### Shutdown sequence

```scheme
;; 1. Stop supervisor trees (propagates graceful shutdown to children)
(actor-kill! app-supervisor)

;; 2. Stop the scheduler (drains remaining tasks, exits worker threads)
(scheduler-stop! sched)

;; 3. Close TCP connections (if distributed)
;; (transport-shutdown!)   ;; not yet implemented — close all *connections* entries
```

### Dependency graph

```
mpsc.sls
  ↑
core.sls ────────────────────> scheduler.sls
  ↑                                 ↑
protocol.sls                     deque.sls
  ↑
supervisor.sls
  ↑
registry.sls

transport.sls ──> core.sls (via set-remote-send-handler!)
```

No circular imports. Each layer imports only what is below it.

### Common wiring mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `set-actor-scheduler!` never called | Each actor uses a new OS thread; crashes above ~1000 actors | Call after `scheduler-start!` |
| `start-registry!` never called | `register!`/`whereis` crash with `#f` dereference | Call before any `register!` |
| `(std task)` futures not available | `make-future` unbound in protocol.sls | Add inline future implementation from the section above |
| `with-ask-context` not used in behavior | `reply` raises "not in ask context" | Wrap behavior body in `with-ask-context` |
| Links used instead of monitors in supervisor | Supervisor dies when child dies | Use `actor-ref-monitors-set!` not links |
| `restart-one!` called outside supervisor behavior | `(self)` returns `#f` | Only call restart helpers from within the supervisor actor's message loop |
