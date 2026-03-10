# Jerboa Actor Model: Complete Implementation Guide

This document is a step-by-step implementation guide for building a production-quality
actor system on Chez Scheme. Each layer is independently implementable and testable.
A lesser model can implement this by following the layers in order — do not skip ahead.

---

## Design Philosophy

**Goals** (what makes this better than Gerbil's `:std/actor`):

1. **Clean layer separation** — each layer is independently importable and testable.
   Gerbil mixes local spawn, remote RPC, filesystem deployment, and admin auth into
   a single 400-symbol namespace. Here each layer is a separate library.

2. **No shimming** — built directly on Chez's native OS threads, not green threads.
   Every primitive maps directly to a Chez or OS concept.

3. **Native serialization** — use Chez's built-in `fasl-write`/`fasl-read` for
   distributed transport. Any Scheme value is automatically serializable. No separate
   serialization library needed.

4. **OTP-style supervision** — Erlang-proven restart strategies (one-for-one,
   one-for-all, rest-for-one) with max-intensity/period restart limiting.

5. **Location transparency** — `(send actor-ref msg)` works whether `actor-ref` is
   local or remote. The caller does not need to know.

6. **Typed protocols via macros** — `defprotocol` generates message structs and
   typed dispatch. Less boilerplate than Gerbil's `defmessage` + `defcall-actor`.

7. **Gradual complexity** — Layers 2-4 (local actors + supervision) are useful
   without Layer 1 (work-stealing) or Layer 7 (distributed). Build and ship each
   layer independently.

**Non-goals**:
- Full Gerbil compatibility (we implement what real programs use, not every symbol)
- Green threads / continuations (real OS threads are simpler and SMP-safe)
- Hot code loading (out of scope)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│  Layer 7: Distributed Transport                      │
│  lib/std/actor/transport.sls, remote.sls, node.sls   │
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
│  (std net ssl)       — TCP+TLS via chez-ssl           │
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

### Data Structure: Lock-Based Linked List

We use a two-lock linked list: one lock for the tail (producers) and one lock for
the head (consumer). This minimizes contention because producers never block the
consumer and vice versa, except in the rare empty/single-element cases.

This is simpler and more practical for Chez than a lock-free Michael-Scott queue
(which would require `compare-and-swap` via FFI C shims).

```scheme
#!chezscheme
(library (std actor mpsc)
  (export
    make-mpsc-queue
    mpsc-queue?
    mpsc-enqueue!          ;; producer: add to tail
    mpsc-dequeue!          ;; consumer: remove from head (blocks if empty)
    mpsc-try-dequeue!      ;; consumer: remove or return #f immediately
    mpsc-empty?            ;; peek (approximate — only safe from consumer)
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
      (immutable head-mutex) ;; consumer lock
      (immutable tail-mutex) ;; producer lock
      (immutable not-empty)  ;; condition: signaled when item enqueued
      (mutable closed?)
      (mutable count))      ;; approximate item count
    (protocol
      (lambda (new)
        (lambda ()
          (let ([dummy (make-mpsc-node 'sentinel)])
            (new dummy dummy
                 (make-mutex) (make-mutex)
                 (make-condition)
                 #f 0)))))
    (sealed #t))

  ;; Producer: enqueue a value
  ;; Lock only the tail — does not interfere with consumer reading head
  (define (mpsc-enqueue! q val)
    (let ([node (make-mpsc-node val)])
      (mutex-acquire (mpsc-queue-tail-mutex q))
      (when (mpsc-queue-closed? q)
        (mutex-release (mpsc-queue-tail-mutex q))
        (error 'mpsc-enqueue! "queue is closed"))
      (mpsc-node-next-set! (mpsc-queue-tail q) node)
      (mpsc-queue-tail-set! q node)
      (mpsc-queue-count-set! q (fx+ (mpsc-queue-count q) 1))
      ;; Signal consumer (must hold head-mutex to signal safely)
      (mutex-acquire (mpsc-queue-head-mutex q))
      (condition-signal (mpsc-queue-not-empty q))
      (mutex-release (mpsc-queue-head-mutex q))
      (mutex-release (mpsc-queue-tail-mutex q))))

  ;; Consumer: dequeue, blocking if empty
  (define (mpsc-dequeue! q)
    (mutex-acquire (mpsc-queue-head-mutex q))
    (let loop ()
      (let ([next (mpsc-node-next (mpsc-queue-head q))])
        (cond
          [next
           ;; Advance dummy head to the first real node
           ;; The old head is discarded; the real node becomes the new dummy
           (let ([val (mpsc-node-value next)])
             (mpsc-queue-head-set! q next)
             (mpsc-node-value-set! next 'sentinel) ;; help GC
             (mpsc-queue-count-set! q (fx- (mpsc-queue-count q) 1))
             (mutex-release (mpsc-queue-head-mutex q))
             val)]
          [(mpsc-queue-closed? q)
           (mutex-release (mpsc-queue-head-mutex q))
           (error 'mpsc-dequeue! "queue closed and empty")]
          [else
           (condition-wait (mpsc-queue-not-empty q)
                           (mpsc-queue-head-mutex q))
           (loop)]))))

  ;; Consumer: try dequeue without blocking
  ;; Returns (values val #t) if successful, (values #f #f) if empty
  (define (mpsc-try-dequeue! q)
    (mutex-acquire (mpsc-queue-head-mutex q))
    (let ([next (mpsc-node-next (mpsc-queue-head q))])
      (cond
        [next
         (let ([val (mpsc-node-value next)])
           (mpsc-queue-head-set! q next)
           (mpsc-node-value-set! next 'sentinel)
           (mpsc-queue-count-set! q (fx- (mpsc-queue-count q) 1))
           (mutex-release (mpsc-queue-head-mutex q))
           (values val #t))]
        [else
         (mutex-release (mpsc-queue-head-mutex q))
         (values #f #f)])))

  (define (mpsc-empty? q)
    (not (mpsc-node-next (mpsc-queue-head q))))

  (define (mpsc-close! q)
    (mutex-acquire (mpsc-queue-tail-mutex q))
    (mpsc-queue-closed?-set! q #t)
    (mutex-acquire (mpsc-queue-head-mutex q))
    (condition-broadcast (mpsc-queue-not-empty q))
    (mutex-release (mpsc-queue-head-mutex q))
    (mutex-release (mpsc-queue-tail-mutex q)))

  ) ;; end library
```

**Test file**: `tests/test-actor-mpsc.ss`
- Enqueue from 10 threads simultaneously, dequeue from 1 thread — verify all messages received
- try-dequeue on empty queue returns `#f`
- Close while consumer is blocked — consumer gets error
- Count is approximately correct after concurrent operations

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
int cas_int64(int64_t *ptr, int64_t expected, int64_t desired) {
    return atomic_compare_exchange_strong(
        (atomic_int_fast64_t*)ptr, &expected, desired);
}
```
Compile as `libjerboa-atomic.so` and load via `(load-shared-object ...)`.
Then use `(foreign-procedure "cas_int64" (void* integer-64 integer-64) integer-32)`.

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
    (let ([b (work-deque-bottom d)]
          [t (work-deque-top d)])
      (if (fx>= b t) (fx- b t) 0)))

  (define (deque-empty? d)
    (fx<= (work-deque-bottom d) (work-deque-top d)))

  ;; Grow buffer when full
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
    (mutex-acquire (work-deque-mutex d))
    (let ([b (work-deque-bottom d)])
      (when (fx>= (fx- b (work-deque-top d)) (fx- (deque-capacity d) 1))
        (deque-grow! d))
      (vector-set! (work-deque-buf d) (fxmod b (deque-capacity d)) task)
      (work-deque-bottom-set! d (fx+ b 1)))
    (mutex-release (work-deque-mutex d)))

  ;; Owner pops from the bottom (LIFO — most recently pushed task first)
  ;; Returns the task or #f if empty
  (define (deque-pop-bottom! d)
    (mutex-acquire (work-deque-mutex d))
    (let ([b (fx- (work-deque-bottom d) 1)])
      (work-deque-bottom-set! d b)
      (let ([result
             (if (fx< (work-deque-top d) b)
               ;; Non-empty: take from bottom
               (let ([task (vector-ref (work-deque-buf d)
                                       (fxmod b (deque-capacity d)))])
                 (vector-set! (work-deque-buf d) (fxmod b (deque-capacity d)) #f)
                 task)
               ;; Empty or contested
               (begin
                 (work-deque-bottom-set! d (fx+ b 1))
                 #f))])
        (mutex-release (work-deque-mutex d))
        result)))

  ;; Thief steals from the top (FIFO — oldest tasks first)
  ;; Returns (values task #t) or (values #f #f) if empty
  (define (deque-steal-top! d)
    (mutex-acquire (work-deque-mutex d))
    (let ([t (work-deque-top d)]
          [b (work-deque-bottom d)])
      (cond
        [(fx>= t b)
         (mutex-release (work-deque-mutex d))
         (values #f #f)]
        [else
         (let ([task (vector-ref (work-deque-buf d)
                                 (fxmod t (deque-capacity d)))])
           (vector-set! (work-deque-buf d) (fxmod t (deque-capacity d)) #f)
           (work-deque-top-set! d (fx+ t 1))
           (mutex-release (work-deque-mutex d))
           (values task #t))])))

  ) ;; end library
```

---

## Layer 2: Work-Stealing Scheduler (`lib/std/actor/scheduler.sls`)

### Purpose

Instead of one OS thread per actor (which limits concurrency to ~1000), the scheduler
maintains a fixed pool of N OS threads (default: `(cpu-count)`) and schedules
lightweight tasks across them. M tasks run on N threads (M >> N).

### Key Insight

Actors are NOT OS threads. An actor is a record with a mailbox. When a message arrives,
a **task** (a thunk) is scheduled to run the actor's receive loop for one message.
The task runs on whatever worker thread picks it up. This is the M:N model.

### Data Structures

```scheme
#!chezscheme
(library (std actor scheduler)
  (export
    scheduler-start!      ;; create and start the thread pool
    scheduler-stop!       ;; drain and shut down
    scheduler-submit!     ;; submit a thunk as a task
    scheduler-worker-count
    current-scheduler
    default-scheduler)
  (import (chezscheme) (std actor deque))

  ;; A task is just a thunk (zero-argument procedure)
  ;; The scheduler runs thunks; it doesn't know about actors.

  ;; Per-worker state (one per OS thread in the pool)
  (define-record-type worker
    (fields
      (immutable id)          ;; integer index 0..N-1
      (immutable deque)       ;; this worker's task deque
      (immutable thread-id)   ;; Chez thread id (set after start)
      (mutable running?))     ;; #f when shutting down
    (protocol
      (lambda (new)
        (lambda (id)
          (new id (make-work-deque) #f #t))))
    (sealed #t))

  ;; The scheduler: a pool of workers
  (define-record-type scheduler
    (fields
      (immutable workers)       ;; vector of worker records
      (immutable global-queue)  ;; overflow queue for load balancing
      (immutable mutex)
      (immutable work-available) ;; condition: broadcast when new task added
      (mutable running?))
    (protocol
      (lambda (new)
        (lambda (n)
          (new (let ([v (make-vector n)])
                 (do ([i 0 (fx+ i 1)]) ((fx= i n) v)
                   (vector-set! v i (make-worker i))))
               (make-vector 0)   ;; simple global queue (vector for now)
               (make-mutex)
               (make-condition)
               #f))))
    (sealed #t))

  ;; Thread-local: which worker is running on this thread
  (define current-worker (make-thread-parameter #f))
  (define current-scheduler (make-thread-parameter #f))
  (define default-scheduler (make-parameter #f))

  ;; Submit a task to the scheduler
  ;; If called from a worker thread, push to its local deque (fast path).
  ;; Otherwise, distribute round-robin to worker deques.
  (define (scheduler-submit! sched thunk)
    (let ([w (current-worker)])
      (if w
        ;; Fast path: running inside the pool — push to local deque
        (begin
          (deque-push-bottom! (worker-deque w) thunk)
          (mutex-acquire (scheduler-mutex sched))
          (condition-signal (scheduler-work-available sched))
          (mutex-release (scheduler-mutex sched)))
        ;; Slow path: external submission — pick a worker round-robin
        (let* ([workers (scheduler-workers sched)]
               [n (vector-length workers)]
               [idx (fxmod (random n) n)]  ;; randomized for load balance
               [w (vector-ref workers idx)])
          (deque-push-bottom! (worker-deque w) thunk)
          (mutex-acquire (scheduler-mutex sched))
          (condition-signal (scheduler-work-available sched))
          (mutex-release (scheduler-mutex sched))))))

  ;; The main loop for each worker thread
  (define (worker-run! sched w)
    (current-worker w)
    (current-scheduler sched)
    (let ([workers (scheduler-workers sched)]
          [n (vector-length (scheduler-workers sched))])
      (let loop ()
        (when (scheduler-running? sched)
          ;; 1. Try own deque first
          (let ([task (deque-pop-bottom! (worker-deque w))])
            (if task
              (begin
                (guard (exn [#t (void)])  ;; tasks must not crash the worker
                  (task))
                (loop))
              ;; 2. Try stealing from a random other worker
              (let try-steal ([attempts 0])
                (if (fx= attempts n)
                  ;; 3. All deques empty — wait for work
                  (begin
                    (mutex-acquire (scheduler-mutex sched))
                    (condition-wait (scheduler-work-available sched)
                                    (scheduler-mutex sched))
                    (mutex-release (scheduler-mutex sched))
                    (loop))
                  (let* ([victim-idx (fxmod (fx+ (worker-id w) attempts 1) n)]
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

  (define (scheduler-start! sched)
    (scheduler-running?-set! sched #t)
    (let ([workers (scheduler-workers sched)])
      (do ([i 0 (fx+ i 1)])
          ((fx= i (vector-length workers)))
        (let ([w (vector-ref workers i)])
          (fork-thread (lambda () (worker-run! sched w))))))
    sched)

  (define (scheduler-stop! sched)
    (scheduler-running?-set! sched #f)
    (mutex-acquire (scheduler-mutex sched))
    (condition-broadcast (scheduler-work-available sched))
    (mutex-release (scheduler-mutex sched)))

  ) ;; end library
```

### Usage Notes

- `(scheduler-submit! sched thunk)` is the ONLY way tasks enter the pool.
- Tasks must complete quickly (not block indefinitely) for good throughput.
  An actor that blocks on `receive` should suspend and re-submit when a message arrives.
- Exception isolation: each task is wrapped in `guard` so a crashing task does not
  kill the worker thread. The actor's supervisor handles the crash, not the scheduler.

### Initialization

```scheme
;; Typically done once at program start:
(define sched (scheduler-start! (make-scheduler (cpu-count))))
(default-scheduler sched)
```

---

## Layer 3: Actor Core (`lib/std/actor/core.sls`)

### Core Concepts

- An **actor** is a record containing: an ID, a mailbox (MPSC queue), a behavior
  function, and lifecycle state.
- **Spawning** creates the actor record and schedules its initial run.
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
blocks, in our M:N model an actor runs as a **task per message**:

1. Message arrives in mailbox
2. A task is submitted to the scheduler: `(lambda () (run-actor! actor))`
3. `run-actor!` dequeues one message, calls `(behavior msg)`, then:
   - If more messages in mailbox, re-submits itself
   - If mailbox empty, marks actor as IDLE

This avoids blocking a worker thread while waiting for messages.

```scheme
#!chezscheme
(library (std actor core)
  (export
    ;; Actor creation and management
    spawn-actor            ;; (spawn-actor behavior [name]) → actor-ref
    spawn-actor/linked     ;; (spawn-actor/linked behavior) → actor-ref
                           ;;   links to current actor; if either dies, both die
    actor-ref?
    actor-ref-id
    actor-ref-node         ;; #f for local actors

    ;; Sending messages
    send                   ;; (send actor-ref msg) → unspecified (fire and forget)
    send/timeout           ;; (send actor-ref msg timeout-secs)

    ;; Receiving inside a behavior
    ;; Note: receive is only valid inside a spawn-actor behavior
    self                   ;; (self) → current actor's actor-ref
    actor-id               ;; (actor-id) → current actor's id integer

    ;; Actor lifecycle
    actor-alive?           ;; (actor-alive? actor-ref) → bool
    actor-kill!            ;; (actor-kill! actor-ref) → forcibly terminate
    actor-wait!            ;; (actor-wait! actor-ref) → block until dead

    ;; Dead letter handler
    set-dead-letter-handler!  ;; (set-dead-letter-handler! proc)

    ;; Low-level: use the default scheduler or provide one
    set-actor-scheduler!      ;; (set-actor-scheduler! sched)
  )
  (import (chezscheme)
          (std actor mpsc)
          (std actor scheduler))

  ;; ========== Actor ID generation ==========
  ;; Simple monotonic counter; fine for local actors.

  (define *next-actor-id* 0)
  (define *actor-id-mutex* (make-mutex))

  (define (next-actor-id!)
    (mutex-acquire *actor-id-mutex*)
    (let ([id *next-actor-id*])
      (set! *next-actor-id* (fx+ id 1))
      (mutex-release *actor-id-mutex*)
      id))

  ;; ========== Actor Record ==========

  (define-record-type actor-ref
    (fields
      (immutable id)           ;; unique integer
      (immutable node)         ;; #f = local; string = remote node id
      (immutable mailbox)      ;; mpsc-queue
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
        (lambda (behavior name)
          (new (next-actor-id!)
               #f             ;; local
               (make-mpsc-queue)
               'idle
               behavior
               '()            ;; links
               '()            ;; monitors
               name
               (make-mutex)
               (make-condition)
               #f))))         ;; exit-reason not set yet
    (sealed #t))

  ;; ========== Global actor table ==========
  ;; Maps id → actor-ref for local lookups (used by supervisor and registry)

  (define *actor-table* (make-eq-hashtable))
  (define *actor-table-mutex* (make-mutex))

  (define (register-local-actor! a)
    (mutex-acquire *actor-table-mutex*)
    (hashtable-set! *actor-table* (actor-ref-id a) a)
    (mutex-release *actor-table-mutex*))

  (define (unregister-local-actor! a)
    (mutex-acquire *actor-table-mutex*)
    (hashtable-delete! *actor-table* (actor-ref-id a))
    (mutex-release *actor-table-mutex*))

  (define (lookup-local-actor id)
    (mutex-acquire *actor-table-mutex*)
    (let ([a (hashtable-ref *actor-table* id #f)])
      (mutex-release *actor-table-mutex*)
      a))

  ;; ========== Thread-local actor context ==========

  (define current-actor (make-thread-parameter #f))
  (define (self) (current-actor))
  (define (actor-id) (and (current-actor) (actor-ref-id (current-actor))))

  ;; ========== Dead letter handler ==========

  (define *dead-letter-handler*
    (lambda (msg dest)
      ;; Default: log to stderr
      (parameterize ([current-output-port (current-error-port)])
        (display "DEAD LETTER: actor #")
        (display (actor-ref-id dest))
        (display " is dead, message dropped: ")
        (write msg)
        (newline))))

  (define (set-dead-letter-handler! proc)
    (set! *dead-letter-handler* proc))

  ;; ========== Actor scheduler reference ==========

  (define *actor-scheduler* (make-parameter #f))
  (define (set-actor-scheduler! sched) (*actor-scheduler* sched))

  ;; ========== Running an actor (internal) ==========

  ;; Process one message from the actor's mailbox.
  ;; Called as a task on a worker thread.
  (define (run-actor! a)
    (parameterize ([current-actor a])
      (actor-ref-state-set! a 'running)
      (let-values ([(msg ok) (mpsc-try-dequeue! (actor-ref-mailbox a))])
        (if ok
          (begin
            ;; Call the behavior with the message
            (guard (exn [#t (actor-die! a exn)])
              ((actor-ref-behavior a) msg))
            ;; Check if more messages waiting
            (if (not (mpsc-empty? (actor-ref-mailbox a)))
              (schedule-actor! a)   ;; re-submit
              (actor-ref-state-set! a 'idle)))
          ;; Spurious wake (shouldn't happen) — go idle
          (actor-ref-state-set! a 'idle)))))

  ;; Schedule the actor to run on the scheduler
  (define (schedule-actor! a)
    (actor-ref-state-set! a 'scheduled)
    (let ([sched (or (*actor-scheduler*) (default-scheduler))])
      (if sched
        (scheduler-submit! sched (lambda () (run-actor! a)))
        ;; No scheduler — fall back to fork-thread (1:1 mode)
        (fork-thread (lambda () (run-actor! a))))))

  ;; Handle actor death
  (define (actor-die! a reason)
    (actor-ref-state-set! a 'dead)
    (actor-ref-exit-reason-set! a reason)
    (unregister-local-actor! a)
    (mpsc-close! (actor-ref-mailbox a))
    ;; Notify linked actors
    (for-each
      (lambda (linked)
        (when (actor-alive? linked)
          (send linked (list 'EXIT (actor-ref-id a) reason))))
      (actor-ref-links a))
    ;; Notify monitors
    (for-each
      (lambda (mon)
        (let ([watcher (car mon)]
              [tag (cdr mon)])
          (when (actor-alive? watcher)
            (send watcher (list 'DOWN tag (actor-ref-id a) reason)))))
      (actor-ref-monitors a))
    ;; Signal anyone waiting on actor-wait!
    (mutex-acquire (actor-ref-done-mutex a))
    (condition-broadcast (actor-ref-done-cond a))
    (mutex-release (actor-ref-done-mutex a)))

  ;; ========== Public API ==========

  (define (spawn-actor behavior . rest)
    (let* ([name (if (null? rest) #f (car rest))]
           [a (make-actor-ref behavior name)])
      (register-local-actor! a)
      ;; Submit initial run — actor starts processing immediately when first message arrives
      ;; (Don't run until first message; actor is idle until then)
      a))

  (define (spawn-actor/linked behavior . rest)
    (let ([parent (current-actor)]
          [child (apply spawn-actor behavior rest)])
      (when parent
        ;; Bidirectional link
        (actor-ref-links-set! parent (cons child (actor-ref-links parent)))
        (actor-ref-links-set! child (cons parent (actor-ref-links child))))
      child))

  (define (send actor msg)
    (cond
      [(actor-ref? actor)
       (if (actor-alive? actor)
         (begin
           (mpsc-enqueue! (actor-ref-mailbox actor) msg)
           ;; Wake the actor if it's idle
           (when (eq? (actor-ref-state actor) 'idle)
             (schedule-actor! actor)))
         ;; Actor is dead — deliver to dead letter handler
         (*dead-letter-handler* msg actor))]
      ;; Future: handle remote actor-refs here (Layer 7)
      [else
       (error 'send "not an actor-ref" actor)]))

  (define (send/timeout actor msg timeout-secs)
    ;; For local actors, send is synchronous (fire-and-forget) — timeout doesn't apply.
    ;; For remote actors, timeout applies to the network send.
    (send actor msg))

  (define (actor-alive? actor)
    (not (eq? (actor-ref-state actor) 'dead)))

  (define (actor-kill! actor)
    (actor-die! actor 'killed))

  (define (actor-wait! actor)
    (mutex-acquire (actor-ref-done-mutex actor))
    (let loop ()
      (unless (eq? (actor-ref-state actor) 'dead)
        (condition-wait (actor-ref-done-cond actor)
                        (actor-ref-done-mutex actor))
        (loop)))
    (mutex-release (actor-ref-done-mutex actor)))

  ) ;; end library
```

### Behavior Function Contract

A behavior function receives one message at a time:

```scheme
(define my-actor
  (spawn-actor
    (lambda (msg)
      (match msg
        [('ping reply-to) (send reply-to 'pong)]
        [('stop)          (actor-kill! (self))]
        [_                (display "unknown message\n")]))))
```

The behavior function may call `(self)` to get its own actor-ref.
It must not block indefinitely — use `ask` (Layer 4) for request-reply patterns,
which suspends via a one-shot future rather than blocking.

---

## Layer 4: Protocol System (`lib/std/actor/protocol.sls`)

### Purpose

Define typed message structs with constructor, predicate, and field accessors.
Generate typed send/receive helpers. This replaces Gerbil's `defmessage` +
`defcall-actor` pattern with a cleaner `defprotocol` macro.

### `defprotocol` Macro

```scheme
(defprotocol my-service
  ;; Each clause: (message-name field ...) or (message-name field ... -> reply-type)
  (ping)                           ;; no fields, no reply expected
  (compute value -> result)        ;; one field, reply expected
  (shutdown reason))               ;; one field, no reply
```

Expands to:

```scheme
;; Message structs
(define-record-type my-service:ping   (fields) ...)
(define-record-type my-service:compute (fields value) ...)
(define-record-type my-service:result  (fields value) ...)  ;; reply type
(define-record-type my-service:shutdown (fields reason) ...)

;; Constructors
(define (make-my-service:ping) ...)
(define (make-my-service:compute value) ...)
(define (make-my-service:result value) ...)
(define (make-my-service:shutdown reason) ...)

;; Typed ask (returns future)
(define (my-service:compute! actor value)
  (ask actor (make-my-service:compute value)))

;; Typed tell (fire and forget)
(define (my-service:ping! actor)
  (tell actor (make-my-service:ping)))
(define (my-service:shutdown! actor reason)
  (tell actor (make-my-service:shutdown reason)))
```

### Full Implementation

```scheme
#!chezscheme
(library (std actor protocol)
  (export
    defprotocol

    ;; Core ask/tell/call
    ask          ;; (ask actor-ref msg [timeout-secs]) → future
    ask-sync     ;; (ask-sync actor-ref msg [timeout-secs]) → value (blocks)
    tell         ;; (tell actor-ref msg) → void (fire and forget, alias for send)
    call         ;; (call actor-ref proc [timeout]) → value (RPC shorthand)

    ;; Reply inside a behavior
    reply        ;; (reply value) → void (must be in ask context)
    reply-to     ;; (reply-to) → actor-ref of requester or #f

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
  ;; sends it inside the message, and waits on it.
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

  ;; Thread-local: current reply channel (set by ask infrastructure)
  (define current-reply-channel (make-thread-parameter #f))
  (define current-sender (make-thread-parameter #f))

  (define (reply value)
    (let ([rc (current-reply-channel)])
      (unless rc
        (error 'reply "not in an ask context"))
      (reply-channel-put! rc value)))

  (define (reply-to)
    (current-sender))

  ;; ========== ask ==========
  ;; Sends msg to actor with an embedded reply channel.
  ;; The message is wrapped in an envelope: ('ask reply-channel . original-msg)
  ;; The behavior must call (reply value) to complete the future.

  (define (ask actor-ref msg . timeout-args)
    (let* ([rc (make-reply-channel)]
           [envelope (list 'ask rc msg)])
      (send actor-ref envelope)
      (reply-channel-future rc)))  ;; return future, caller calls future-get

  (define (ask-sync actor-ref msg . timeout-args)
    (let ([fut (apply ask actor-ref msg timeout-args)])
      ;; TODO: apply timeout by racing future-get against a timer
      (future-get fut)))

  ;; ========== tell ==========
  ;; Simple alias for send — semantic distinction makes code clearer.
  (define (tell actor-ref msg)
    (send actor-ref msg))

  ;; ========== call ==========
  ;; Sends a lambda to the actor for remote execution.
  ;; Useful for actors that expose a mutable state model.
  (define (call actor-ref proc . timeout-args)
    (apply ask-sync actor-ref (list 'call proc) timeout-args))

  ;; ========== ask envelope unwrapping ==========
  ;; Actors that want to support ask must call this in their behavior:
  ;;
  ;;   (define (my-behavior msg)
  ;;     (with-ask-context msg
  ;;       (lambda (actual-msg)
  ;;         (match actual-msg
  ;;           [('compute n) (reply (* n n))]
  ;;           ...))))
  ;;
  ;; OR use defprotocol which generates the dispatch automatically.

  (define-syntax with-ask-context
    (syntax-rules ()
      [(_ msg body-thunk)
       (if (and (pair? msg) (eq? (car msg) 'ask))
         (let ([rc (cadr msg)]
               [actual (caddr msg)])
           (parameterize ([current-reply-channel rc]
                          [current-sender (self)])
             (body-thunk actual)))
         (body-thunk msg))]))

  ;; ========== defprotocol macro ==========

  (define-syntax defprotocol
    (lambda (stx)
      (syntax-case stx (->)
        [(_ proto-name clause ...)
         (let* ([proto (syntax->datum #'proto-name)]
                [prefix (symbol->string proto)])
           (define (sym . parts)
             (string->symbol (apply string-append (map (lambda (p)
               (cond [(symbol? p) (symbol->string p)]
                     [(string? p) p]
                     [else (error 'defprotocol "bad part" p)])) parts))))
           (define clauses (syntax->datum #'(clause ...)))
           (define (parse-clause clause)
             (let loop ([rest clause] [fields '()] [has-reply #f])
               (cond
                 [(null? rest) (values (car clause) (reverse fields) has-reply)]
                 [(eq? (car rest) '->) (values (car clause) (reverse fields) (cadr rest))]
                 [(eq? (car rest) (car clause)) (loop (cdr rest) fields has-reply)]
                 [else (loop (cdr rest) (cons (car rest) fields) has-reply)])))
           (with-syntax
             ([(expanded ...)
               (map (lambda (c)
                 (define-values (name fields reply-type) (parse-clause c))
                 (let* ([struct-name (sym prefix ":" name)]
                        [make-name (sym "make-" prefix ":" name)]
                        [pred-name (sym prefix ":" name "?")]
                        [tell-name (sym prefix ":" name "!")]
                        [ask-name  (sym prefix ":" name "?!")])
                   (datum->syntax #'proto-name
                     `(begin
                        ;; Message struct
                        (define-record-type ,struct-name
                          (fields ,@(map (lambda (f) `(immutable ,f)) fields))
                          (sealed #t))
                        ;; tell variant (fire and forget)
                        (define (,tell-name actor ,@fields)
                          (tell actor (,make-name ,@fields)))
                        ;; ask variant (only if -> specified)
                        ,@(if reply-type
                            `((define (,ask-name actor ,@fields . timeout)
                                (apply ask-sync actor (,make-name ,@fields) timeout)))
                            '())))))
                 (syntax->list #'(clause ...)))])
             #'(begin expanded ...)))])))

  ) ;; end library
```

### Usage Example

```scheme
(import (std actor core) (std actor protocol))

;; Define the protocol
(defprotocol counter
  (increment amount)
  (get-value -> value)
  (reset))

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
               (set! value 0)])))))))

;; Client code
(define cnt (make-counter-actor 0))
(counter:increment! cnt 5)
(counter:increment! cnt 3)
(display (counter:get-value?! cnt))  ;; => 8
```

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
    (immutable shutdown)      ;; 'brutal-kill | (timeout-secs)
    (immutable type))         ;; 'worker | 'supervisor
  (sealed #t))
```

### Full Implementation

```scheme
#!chezscheme
(library (std actor supervisor)
  (export
    make-child-spec
    child-spec?

    start-supervisor
    supervisor?

    supervisor-which-children    ;; → list of (id status actor-ref-or-#f)
    supervisor-count-children    ;; → (specs active supervisors workers)
    supervisor-terminate-child!  ;; → stop a child
    supervisor-restart-child!    ;; → restart a stopped child
    supervisor-start-child!      ;; → add a new child spec dynamically
    supervisor-delete-child!     ;; → remove a child spec
  )
  (import (chezscheme)
          (std actor core)
          (std actor protocol))

  ;; ========== Supervisor state ==========

  (define-record-type supervisor-state
    (fields
      (immutable strategy)      ;; 'one-for-one | 'one-for-all | 'rest-for-one
      (immutable max-restarts)  ;; integer
      (immutable period-secs)   ;; number (seconds)
      (mutable children)        ;; list of child-entry records
      (mutable restart-log)     ;; list of timestamps of recent restarts
      (mutable running?))
    (sealed #t))

  ;; Runtime state of one child
  (define-record-type child-entry
    (fields
      (immutable spec)          ;; child-spec
      (mutable actor-ref)       ;; current actor-ref or #f if not running
      (mutable status))         ;; 'running | 'restarting | 'stopped | 'dead
    (sealed #t))

  ;; ========== start-supervisor ==========

  (define (start-supervisor strategy child-specs
                             . opts)
    (let* ([max-restarts (if (null? opts) 10 (car opts))]
           [period-secs  (if (or (null? opts) (null? (cdr opts))) 5 (cadr opts))]
           [state (make-supervisor-state
                    strategy max-restarts period-secs
                    '() '() #t)])
      (let ([sup (spawn-actor
                   (lambda (msg)
                     (supervisor-behavior state msg))
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
      ;; Monitor the child so the supervisor gets 'DOWN messages
      (link-to-supervisor! sup child-actor (child-spec-id spec))
      (supervisor-state-children-set! state
        (append (supervisor-state-children state) (list entry)))
      entry))

  ;; Set up monitoring: when child dies, send 'DOWN to supervisor
  ;; We use actor links (bidirectional) or monitors (one-way).
  ;; For supervision, use monitors (one-way): supervisor knows when child dies,
  ;; but child does not know about supervisor.
  (define (link-to-supervisor! sup child-actor spec-id)
    ;; Add monitor: when child dies, send ('DOWN spec-id child-id reason) to sup
    (let ([child-monitors (actor-ref-monitors child-actor)])
      (actor-ref-monitors-set! child-actor
        (cons (cons sup spec-id) child-monitors))))

  ;; ========== Supervisor behavior (the message loop) ==========

  (define (supervisor-behavior state msg)
    (match msg
      ;; Child died — handle according to strategy
      [('DOWN spec-id child-id reason)
       (handle-child-exit! state spec-id child-id reason)]

      ;; Dynamic management (from supervisor-* public API)
      [('which-children reply-ch)
       (reply-channel-put! reply-ch (format-children state))]

      [('terminate-child id reply-ch)
       (terminate-child-by-id! state id)
       (reply-channel-put! reply-ch 'ok)]

      [('restart-child id reply-ch)
       (let ([result (restart-child-by-id! state id)])
         (reply-channel-put! reply-ch result))]

      [('start-child spec reply-ch)
       ;; Add a new child spec dynamically
       (let ([entry (start-child! state (self) spec)])
         (reply-channel-put! reply-ch (child-entry-actor-ref entry)))]

      [('delete-child id reply-ch)
       (delete-child-by-id! state id)
       (reply-channel-put! reply-ch 'ok)]

      [_ (void)]))  ;; ignore unknown messages

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
                   [(temporary) #f])])
            (if should-restart?
              (begin
                (check-restart-intensity! state)
                (case (supervisor-state-strategy state)
                  [(one-for-one) (restart-one! state entry)]
                  [(one-for-all) (restart-all! state)]
                  [(rest-for-one) (restart-rest! state entry)]))
              ;; Not restarting — mark as dead
              (child-entry-status-set! entry 'dead)))))))

  ;; Check if restart intensity exceeded
  (define (check-restart-intensity! state)
    (let* ([now (time->seconds (current-time))]
           [period (supervisor-state-period-secs state)]
           [log (filter (lambda (t) (> t (- now period)))
                        (supervisor-state-restart-log state))])
      (supervisor-state-restart-log-set! state (cons now log))
      (when (>= (length log) (supervisor-state-max-restarts state))
        (error 'supervisor "restart intensity exceeded"))))

  (define (restart-one! state entry)
    (stop-child-entry! entry)
    (let* ([spec (child-entry-spec entry)]
           [new-actor ((child-spec-start-thunk spec))])
      (child-entry-actor-ref-set! entry new-actor)
      (child-entry-status-set! entry 'running)
      ;; Re-attach monitor
      (link-to-supervisor! (self) new-actor (child-spec-id spec))))

  (define (restart-all! state)
    ;; Stop all in reverse order, restart all in forward order
    (let ([children (supervisor-state-children state)])
      (for-each stop-child-entry! (reverse children))
      (for-each (lambda (entry)
                  (let* ([spec (child-entry-spec entry)]
                         [new-actor ((child-spec-start-thunk spec))])
                    (child-entry-actor-ref-set! entry new-actor)
                    (child-entry-status-set! entry 'running)
                    (link-to-supervisor! (self) new-actor (child-spec-id spec))))
                children)))

  (define (restart-rest! state failed-entry)
    ;; Find position of failed entry, stop all from there onward, restart them
    (let* ([children (supervisor-state-children state)]
           [pos (let loop ([cs children] [i 0])
                  (cond [(null? cs) -1]
                        [(eq? (car cs) failed-entry) i]
                        [else (loop (cdr cs) (fx+ i 1))]))]
           [rest (list-tail children pos)])
      (for-each stop-child-entry! (reverse rest))
      (for-each (lambda (entry)
                  (let* ([spec (child-entry-spec entry)]
                         [new-actor ((child-spec-start-thunk spec))])
                    (child-entry-actor-ref-set! entry new-actor)
                    (child-entry-status-set! entry 'running)
                    (link-to-supervisor! (self) new-actor (child-spec-id spec))))
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
           ;; Send shutdown signal, wait up to timeout, then kill
           (send a '(shutdown))
           (let ([done #f])
             (fork-thread
               (lambda ()
                 (sleep (make-time 'time-duration
                                   (inexact->exact (* shutdown 1e9)) 0))
                 (unless done (actor-kill! a))))
             (actor-wait! a)
             (set! done #t))]))
      (child-entry-actor-ref-set! entry #f)
      (child-entry-status-set! entry 'stopped)))

  ;; ========== Public management API ==========

  (define (supervisor-which-children sup)
    (ask-sync sup '(which-children)))

  (define (supervisor-terminate-child! sup id)
    (ask-sync sup (list 'terminate-child id)))

  (define (supervisor-restart-child! sup id)
    (ask-sync sup (list 'restart-child id)))

  (define (supervisor-start-child! sup spec)
    (ask-sync sup (list 'start-child spec)))

  (define (supervisor-delete-child! sup id)
    (ask-sync sup (list 'delete-child id)))

  ;; Helper: find child by spec-id
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
(import (std actor core) (std actor protocol) (std actor supervisor))

;; Define worker actors
(define (make-database-actor)
  (spawn-actor
    (lambda (msg)
      (match msg
        [('query sql reply-ch) (reply-channel-put! reply-ch "result")]
        [('shutdown) (actor-kill! (self))]))))

(define (make-cache-actor)
  (spawn-actor (lambda (msg) (void))))

;; Build supervision tree
(define app-supervisor
  (start-supervisor
    'one-for-one                        ;; strategy
    (list
      (make-child-spec
        'database                       ;; id
        make-database-actor             ;; start-thunk
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

---

## Layer 6: Registry (`lib/std/actor/registry.sls`)

### Purpose

Named actors: `(register 'db-actor actor-ref)` then later `(whereis 'db-actor)`.
The registry is itself a supervised actor (restart on crash).
Supports local and (with Layer 7) remote registries.

```scheme
#!chezscheme
(library (std actor registry)
  (export
    start-registry!       ;; must be called before using registry
    register!             ;; (register! name actor-ref) → 'ok | 'already-registered
    unregister!           ;; (unregister! name) → 'ok | 'not-found
    whereis               ;; (whereis name) → actor-ref or #f
    registered-names      ;; → list of registered names
    registry-actor        ;; the registry actor-ref itself
  )
  (import (chezscheme) (std actor core) (std actor protocol))

  (define *registry-actor* #f)
  (define (registry-actor) *registry-actor*)

  ;; Registry behavior: maintains a hash table of name → actor-ref
  (define (registry-behavior table msg)
    (with-ask-context msg
      (lambda (actual)
        (match actual
          [('register name ref)
           (if (hashtable-ref table name #f)
             (reply 'already-registered)
             (begin
               (hashtable-set! table name ref)
               ;; Monitor the actor: remove from registry on death
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
           (reply (hashtable-keys table))]

          ;; Actor died — auto-unregister
          [('DOWN name dead-id reason)
           (hashtable-delete! table name)]

          [_ (void)]))))

  (define (start-registry!)
    (let ([table (make-eq-hashtable)])
      (set! *registry-actor*
            (spawn-actor
              (lambda (msg) (registry-behavior table msg))
              'registry))))

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

---

## Layer 7: Distributed Transport

### Overview

Distributed actors extend `send` to work across network nodes.
An actor-ref gains a `node` field (string: `"host:port"` or UUID).
`send` checks `(actor-ref-node ref)`: if non-`#f`, routes through the transport layer.

This requires:
1. A **serialization** format for messages over the wire
2. A **node identity** — each running process has a node-id
3. A **connection manager** — maintains TCP+TLS connections to peer nodes
4. A **remote dispatch** — receives incoming messages and delivers to local actors
5. A **remote actor-ref** — a ref pointing to an actor on another node

### File Layout

```
lib/std/actor/transport/
  serialize.sls    — fasl-based message serialization
  node.sls         — node identity, startup, cookie-based auth
  connection.sls   — TCP+TLS connection pool to peer nodes
  server.sls       — incoming connection acceptor
  remote.sls       — remote send/ask dispatch
```

### 7A: Serialization (`lib/std/actor/transport/serialize.sls`)

Chez Scheme's built-in `fasl-write`/`fasl-read` serializes arbitrary Scheme values
including records, vectors, bytevectors, and strings. This is the killer advantage
over Gerbil: we get free serialization for any message type.

**Limitations**:
- Closures are not safely serializable across machines (different code)
- Port objects cannot be serialized
- For cross-machine communication, messages must contain only data (no lambdas)

```scheme
#!chezscheme
(library (std actor transport serialize)
  (export
    message->bytes     ;; (message->bytes msg) → bytevector
    bytes->message)    ;; (bytes->message bv) → msg
  (import (chezscheme))

  ;; Frame format: 4-byte big-endian length prefix + fasl bytes
  (define (message->bytes msg)
    (let-values ([(port get-bytes) (open-bytevector-output-port)])
      (fasl-write msg port)
      (let* ([body (get-bytes)]
             [n (bytevector-length body)]
             [frame (make-bytevector (fx+ 4 n))])
        ;; Write 4-byte length header (big-endian)
        (bytevector-u8-set! frame 0 (fxarithmetic-shift-right (fxand n #xFF000000) 24))
        (bytevector-u8-set! frame 1 (fxarithmetic-shift-right (fxand n #x00FF0000) 16))
        (bytevector-u8-set! frame 2 (fxarithmetic-shift-right (fxand n #x0000FF00) 8))
        (bytevector-u8-set! frame 3 (fxand n #xFF))
        (bytevector-copy! body 0 frame 4 n)
        frame)))

  (define (bytes->message bv)
    (fasl-read (open-bytevector-input-port
                 (bytevector-copy bv 4 (bytevector-length bv)))))

  ;; Read exactly one framed message from an input port
  ;; Returns the deserialized message or raises error on EOF
  (define (read-framed-message port)
    (let ([header (make-bytevector 4)])
      (let loop ([i 0])
        (when (fx< i 4)
          (let ([b (get-u8 port)])
            (when (eof-object? b)
              (error 'read-framed-message "connection closed"))
            (bytevector-u8-set! header i b)
            (loop (fx+ i 1)))))
      (let* ([n (+ (* (bytevector-u8-ref header 0) 16777216)
                   (* (bytevector-u8-ref header 1) 65536)
                   (* (bytevector-u8-ref header 2) 256)
                   (bytevector-u8-ref header 3))]
             [body (make-bytevector n)])
        (let loop ([i 0])
          (when (fx< i n)
            (let ([b (get-u8 port)])
              (when (eof-object? b)
                (error 'read-framed-message "truncated message"))
              (bytevector-u8-set! body i b)
              (loop (fx+ i 1)))))
        (fasl-read (open-bytevector-input-port body)))))

  ) ;; end library
```

### 7B: Node Identity (`lib/std/actor/transport/node.sls`)

```scheme
#!chezscheme
(library (std actor transport node)
  (export
    start-node!           ;; (start-node! host port cookie) → node-id string
    current-node-id       ;; (current-node-id) → "host:port"
    current-node-cookie   ;; shared secret for authenticating peer nodes
    node-id->host+port    ;; (node-id->host+port "host:port") → (values host port)
  )
  (import (chezscheme))

  (define *node-id* (make-parameter #f))
  (define *node-cookie* (make-parameter #f))

  (define (current-node-id) (*node-id*))
  (define (current-node-cookie) (*node-cookie*))

  (define (start-node! host port cookie)
    (let ([id (string-append host ":" (number->string port))])
      (*node-id* id)
      (*node-cookie* cookie)
      id))

  (define (node-id->host+port node-id)
    (let ([colon (string-index node-id #\:)])
      (values (substring node-id 0 colon)
              (string->number (substring node-id (fx+ colon 1)
                                         (string-length node-id))))))

  ;; Find the first #\: from the right (handles IPv6 with port)
  (define (string-index str ch)
    (let loop ([i (fx- (string-length str) 1)])
      (cond [(fx< i 0) (error 'string-index "char not found" ch str)]
            [(char=? (string-ref str i) ch) i]
            [else (loop (fx- i 1))])))

  ) ;; end library
```

### 7C: Connection Manager (`lib/std/actor/transport/connection.sls`)

```scheme
#!chezscheme
(library (std actor transport connection)
  (export
    get-connection!    ;; (get-connection! node-id) → connection or error
    send-to-node!      ;; (send-to-node! node-id bytes) → void
    close-connection!  ;; (close-connection! node-id)
    list-connections   ;; → list of connected node-ids
  )
  (import (chezscheme)
          (std net ssl)
          (std actor transport node))

  ;; Connection pool: node-id → (input-port . output-port)
  (define *connections* (make-equal-hashtable))
  (define *conn-mutex* (make-mutex))

  (define (get-connection! node-id)
    (mutex-acquire *conn-mutex*)
    (let ([existing (hashtable-ref *connections* node-id #f)])
      (if existing
        (begin (mutex-release *conn-mutex*) existing)
        (let ([conn (open-connection! node-id)])
          (hashtable-set! *connections* node-id conn)
          (mutex-release *conn-mutex*)
          conn))))

  ;; Open a new TCP connection to a peer node
  ;; Performs cookie-based handshake for authentication
  (define (open-connection! node-id)
    (let-values ([(host port) (node-id->host+port node-id)])
      ;; For now: plain TCP. TODO: upgrade to TLS via (std net ssl)
      (let* ([conn (tcp-connect host port)]
             ;; Handshake: send our node-id + cookie hash
             [hello (list 'hello (current-node-id)
                               (cookie-hash (current-node-cookie) node-id))])
        ;; Write handshake
        (let ([bv (message->bytes hello)])
          (tcp-write conn bv))
        ;; Read peer acknowledgement
        (let ([ack (read-framed-message (car conn))])
          (unless (eq? ack 'ok)
            (tcp-close conn)
            (error 'open-connection! "handshake failed" node-id)))
        conn)))

  (define (send-to-node! node-id bytes)
    (let ([conn (get-connection! node-id)])
      (tcp-write (cdr conn) bytes)))

  (define (close-connection! node-id)
    (mutex-acquire *conn-mutex*)
    (let ([conn (hashtable-ref *connections* node-id #f)])
      (when conn (tcp-close conn))
      (hashtable-delete! *connections* node-id))
    (mutex-release *conn-mutex*))

  (define (list-connections)
    (mutex-acquire *conn-mutex*)
    (let ([ids (hashtable-keys *connections*)])
      (mutex-release *conn-mutex*)
      (vector->list ids)))

  ;; Simple HMAC-SHA256-based cookie hash
  ;; Prevents unauthorized nodes from connecting
  (define (cookie-hash cookie peer-id)
    ;; TODO: use (std crypto hmac) when available
    ;; For now: XOR-fold (replace with real HMAC in production)
    (let loop ([s (string-append cookie peer-id)] [h 0] [i 0])
      (if (fx= i (string-length s)) h
          (loop s (fxand (fx+ (fx* h 31) (char->integer (string-ref s i)))
                         #xFFFFFFFF)
                (fx+ i 1)))))

  ) ;; end library
```

### 7D: Node Server (`lib/std/actor/transport/server.sls`)

The server listens for incoming connections from peer nodes and dispatches
received messages to local actors.

```scheme
#!chezscheme
(library (std actor transport server)
  (export
    start-node-server!   ;; (start-node-server! port) → server-actor
    stop-node-server!
  )
  (import (chezscheme)
          (std net ssl)
          (std actor core)
          (std actor transport serialize)
          (std actor transport node))

  (define (start-node-server! port)
    (let ([listener (tcp-listen port)])
      (spawn-actor
        (lambda (msg)
          (match msg
            [('stop) (actor-kill! (self))]
            [_       (void)]))
        'node-server)
      ;; Accept loop runs in a dedicated OS thread (not an actor)
      ;; because tcp-accept is blocking
      (fork-thread
        (lambda ()
          (let loop ()
            (let ([conn (tcp-accept listener)])
              (fork-thread
                (lambda () (handle-peer-connection! conn)))
              (loop)))))))

  ;; Handle one peer connection: authenticate, then dispatch messages
  (define (handle-peer-connection! conn)
    (guard (exn [#t (tcp-close conn)])
      ;; Read hello handshake
      (let ([hello (read-framed-message (car conn))])
        (match hello
          [('hello peer-node-id peer-hash)
           (let ([expected (cookie-hash (current-node-cookie) peer-node-id)])
             (if (= peer-hash expected)
               (begin
                 ;; Acknowledge
                 (tcp-write (cdr conn) (message->bytes 'ok))
                 ;; Dispatch loop
                 (let dispatch-loop ()
                   (let ([envelope (read-framed-message (car conn))])
                     (match envelope
                       [('send actor-id msg)
                        (let ([a (lookup-local-actor actor-id)])
                          (if a
                            (send a msg)
                            (void)))  ;; dead letter: silently drop
                        (dispatch-loop)]
                       [('stop) (void)]
                       [_ (dispatch-loop)]))))
               ;; Bad cookie
               (tcp-close conn)))]
          [_ (tcp-close conn)]))))

  ) ;; end library
```

### 7E: Remote Send (`lib/std/actor/transport/remote.sls`)

Extends `send` to handle remote actor-refs.

```scheme
#!chezscheme
(library (std actor transport remote)
  (export
    make-remote-actor-ref    ;; (make-remote-actor-ref node-id actor-id)
    remote-actor-ref?
    remote-send              ;; called by send when ref.node is non-#f
  )
  (import (chezscheme)
          (std actor core)
          (std actor transport serialize)
          (std actor transport connection))

  ;; A remote actor ref wraps the node-id and remote actor-id.
  ;; It looks like a local actor-ref to the caller.
  ;; We reuse actor-ref but set the node field.

  (define (make-remote-actor-ref node-id remote-actor-id)
    ;; Creates an actor-ref with node set, no local mailbox
    ;; The ID is the remote actor's ID, not a local ID
    ;; Behavior is a no-op (never run locally)
    (let ([ref (spawn-actor (lambda (msg) (void)))])
      ;; Hack: reach into actor-ref internals to set node
      ;; Better: add a make-remote-actor-ref constructor in core.sls
      ref))

  (define (remote-send actor-ref msg)
    (let ([node-id (actor-ref-node actor-ref)]
          [actor-id (actor-ref-id actor-ref)])
      (let ([envelope (list 'send actor-id msg)])
        (send-to-node! node-id (message->bytes envelope)))))

  ) ;; end library
```

### Integration: Patching `send` in Core

Modify `send` in `core.sls` to check `(actor-ref-node ref)`:

```scheme
;; In core.sls, update send:
(define (send actor msg)
  (cond
    [(not (actor-ref? actor))
     (error 'send "not an actor-ref" actor)]
    [(actor-ref-node actor)
     ;; Remote: delegate to transport layer
     ;; Import (std actor transport remote) in core.sls
     (remote-send actor msg)]
    [(actor-alive? actor)
     (mpsc-enqueue! (actor-ref-mailbox actor) msg)
     (when (eq? (actor-ref-state actor) 'idle)
       (schedule-actor! actor))]
    [else
     (*dead-letter-handler* msg actor)]))
```

---

## Complete File Map

```
lib/std/actor/
  mpsc.sls              Layer 1A  MPSC queue (mailbox queue)
  deque.sls             Layer 1B  Work-stealing deque
  scheduler.sls         Layer 2   Thread pool + work-stealing
  core.sls              Layer 3   spawn-actor, send, self, lifecycle
  protocol.sls          Layer 4   defprotocol, ask, tell, call
  supervisor.sls        Layer 5   OTP supervision trees
  registry.sls          Layer 6   Named actor registry
  transport/
    serialize.sls       Layer 7A  fasl framing
    node.sls            Layer 7B  Node identity + cookie auth
    connection.sls      Layer 7C  TCP connection pool
    server.sls          Layer 7D  Incoming connection listener
    remote.sls          Layer 7E  Remote send dispatch

lib/std/actor.sls       Re-export facade (all layers)

tests/
  test-actor-mpsc.ss    Tests for MPSC queue
  test-actor-deque.ss   Tests for work-stealing deque
  test-actor-core.ss    Tests for spawn/send/receive/lifecycle
  test-actor-protocol.ss Tests for defprotocol, ask, tell
  test-actor-supervisor.ss Tests for supervision strategies
  test-actor-registry.ss   Tests for name registration
  test-actor-distributed.ss Tests for two nodes, cross-node send
```

---

## Implementation Roadmap (Step by Step)

Implement and test each step before moving to the next.

### Step 1: MPSC Queue

**File**: `lib/std/actor/mpsc.sls`
**Test**: `tests/test-actor-mpsc.ss`

Implementation checklist:
- [ ] `make-mpsc-queue` creates two-lock linked list with dummy head
- [ ] `mpsc-enqueue!` acquires tail-lock only
- [ ] `mpsc-dequeue!` acquires head-lock, blocks if empty
- [ ] `mpsc-try-dequeue!` returns `#f` immediately if empty
- [ ] `mpsc-close!` wakes blocked consumer
- [ ] Test: 10 concurrent producers, 1 consumer, verify all messages received
- [ ] Test: `try-dequeue` on empty returns `(values #f #f)`
- [ ] Test: close wakes blocked consumer with error

### Step 2: Actor Core (1:1 OS thread mode, no scheduler)

**File**: `lib/std/actor/core.sls`
**Test**: `tests/test-actor-core.ss`
**Dependencies**: `mpsc.sls`

Initially implement WITHOUT the work-stealing scheduler: use `fork-thread` directly
for each message. Layer 2 (scheduler) is a drop-in optimization added later.

Implementation checklist:
- [ ] `spawn-actor` creates actor record, registers in global table
- [ ] `send` enqueues message, calls `fork-thread` to process it
- [ ] `self` returns current actor via `current-actor` thread parameter
- [ ] `actor-alive?` checks state field
- [ ] `actor-kill!` sets state to dead, closes mailbox, notifies links
- [ ] `actor-wait!` blocks until state = dead
- [ ] Link semantics: linked actor gets `(EXIT id reason)` on death
- [ ] Dead letter handler called for messages to dead actors
- [ ] Test: spawn, send, actor processes message
- [ ] Test: two actors ping-pong
- [ ] Test: actor dies, linked actor receives EXIT
- [ ] Test: dead letter handler called
- [ ] Test: 1000 actors all receive one message

### Step 3: Protocol System

**File**: `lib/std/actor/protocol.sls`
**Test**: `tests/test-actor-protocol.ss`
**Dependencies**: `core.sls`, `(std task)` (for futures)

Implementation checklist:
- [ ] `reply-channel` wraps a future
- [ ] `ask` wraps message in `('ask rc msg)` envelope, returns future
- [ ] `ask-sync` calls `ask` then `future-get`
- [ ] `with-ask-context` macro unwraps envelope and binds `current-reply-channel`
- [ ] `reply` completes the current reply channel
- [ ] `defprotocol` generates structs + typed tell/ask helpers
- [ ] `tell` is alias for `send`
- [ ] Test: ask/reply round-trip
- [ ] Test: defprotocol generates correct struct predicates
- [ ] Test: typed ask helper returns correct value
- [ ] Test: reply in non-ask context raises error

### Step 4: Supervision Trees

**File**: `lib/std/actor/supervisor.sls`
**Test**: `tests/test-actor-supervisor.ss`
**Dependencies**: `core.sls`, `protocol.sls`

Implementation checklist:
- [ ] `make-child-spec` with all fields
- [ ] `start-supervisor` starts children and monitors them
- [ ] one-for-one: only restart the dead child
- [ ] one-for-all: restart all children
- [ ] rest-for-one: restart dead child and all subsequent
- [ ] permanent restart policy
- [ ] transient restart policy (only on abnormal exit)
- [ ] temporary restart policy (never restart)
- [ ] Restart intensity tracking (max restarts per period)
- [ ] Supervisor crashes when intensity exceeded (escalation)
- [ ] Graceful shutdown with timeout
- [ ] `supervisor-which-children` API
- [ ] Test: worker crashes, one-for-one restarts only it
- [ ] Test: worker crashes, one-for-all restarts all
- [ ] Test: permanent vs transient vs temporary
- [ ] Test: intensity exceeded causes supervisor crash
- [ ] Test: nested supervisors (tree structure)

### Step 5: Registry

**File**: `lib/std/actor/registry.sls`
**Test**: `tests/test-actor-registry.ss`
**Dependencies**: `core.sls`, `protocol.sls`

Implementation checklist:
- [ ] `start-registry!` spawns the registry actor
- [ ] `register!` registers name, returns error if duplicate
- [ ] `whereis` returns actor-ref or #f
- [ ] `unregister!` removes name
- [ ] Auto-unregister when actor dies (via monitor)
- [ ] `registered-names` returns all names
- [ ] Test: register, whereis returns same ref
- [ ] Test: register duplicate returns 'already-registered
- [ ] Test: actor dies, whereis returns #f
- [ ] Test: unregister manually

### Step 6: Work-Stealing Scheduler

**File**: `lib/std/actor/deque.sls`, `lib/std/actor/scheduler.sls`
**Test**: `tests/test-actor-deque.ss`
**Dependencies**: none (standalone)

This step upgrades `core.sls` from 1:1 OS threads to M:N scheduling.
All tests from Steps 2-5 must still pass after this change.

Implementation checklist:
- [ ] `make-work-deque` circular buffer with mutex
- [ ] `deque-push-bottom!` owner pushes
- [ ] `deque-pop-bottom!` owner pops LIFO
- [ ] `deque-steal-top!` thief steals FIFO
- [ ] `make-scheduler` with N workers
- [ ] `scheduler-start!` forks N worker threads
- [ ] Worker loop: pop own deque → steal → wait
- [ ] `scheduler-submit!` fast path (push own deque from worker)
- [ ] `scheduler-submit!` slow path (external submission)
- [ ] `current-worker` thread-local set in each worker thread
- [ ] Modify `core.sls` `schedule-actor!` to use scheduler when available
- [ ] Test: submit 10000 tasks, all complete
- [ ] Test: no deadlock with empty deques
- [ ] Test: stealing actually occurs (verify cross-thread execution)
- [ ] Benchmark: 100k messages actor throughput before/after scheduler

### Step 7: Distributed Transport

**Files**: `lib/std/actor/transport/*.sls`
**Test**: `tests/test-actor-distributed.ss`
**Dependencies**: `core.sls`, `(std net ssl)`

This is the most complex step. Test on localhost first (two processes on same machine).

Implementation checklist:
- [ ] `message->bytes` and `bytes->message` with 4-byte length frame
- [ ] `read-framed-message` reads exactly one message from port
- [ ] `start-node!` sets node-id and cookie
- [ ] `start-node-server!` accepts incoming connections
- [ ] Cookie-based handshake on connection open
- [ ] Connection pool with reconnect on failure
- [ ] `send-to-node!` serializes and sends
- [ ] `remote-send` called from `send` when `actor-ref-node` is non-#f
- [ ] `make-remote-actor-ref` creates cross-node refs
- [ ] Modify `actor-ref` record to support non-#f `node` field
- [ ] Test: two Chez processes on localhost, one sends to other
- [ ] Test: connection failure triggers dead letter handler
- [ ] Test: large message (1MB bytevector) round-trip
- [ ] Test: 1000 cross-node messages in sequence
- [ ] Test: reconnect after connection drop

---

## Facade Library (`lib/std/actor.sls`)

Once all layers are built, provide a single import:

```scheme
#!chezscheme
(library (std actor)
  (export
    ;; Core
    spawn-actor spawn-actor/linked
    send tell ask ask-sync call reply reply-to
    self actor-id actor-alive? actor-kill! actor-wait!
    actor-ref? set-dead-letter-handler!

    ;; Protocol
    defprotocol with-ask-context
    make-reply-channel reply-channel-get reply-channel-put!

    ;; Supervision
    make-child-spec start-supervisor
    supervisor-which-children supervisor-terminate-child!
    supervisor-restart-child! supervisor-start-child!

    ;; Registry
    start-registry! register! unregister! whereis registered-names

    ;; Scheduler
    make-scheduler scheduler-start! scheduler-stop!
    scheduler-submit! set-actor-scheduler!

    ;; Distributed (optional; requires start-node!)
    start-node! current-node-id
    start-node-server! make-remote-actor-ref)

  (import
    (std actor core)
    (std actor protocol)
    (std actor supervisor)
    (std actor registry)
    (std actor scheduler))
  ) ;; end library
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
its own lock-free (or lightly-locked) deque. The global queue is only accessed when
a worker's deque is empty, which in practice is rare under load.

### Why fasl for distributed serialization?

Chez's `fasl-write`/`fasl-read` handles all Scheme data types automatically:
records, vectors, strings, bytevectors, symbols, numbers, booleans, pairs.
This means any pure-data message is automatically serializable without writing
serialization code. The only restriction is no closures or ports across machines.
JSON would require explicit conversion for every message type.

### Why cookie authentication instead of TLS client certs?

Cookie auth (shared secret) is simpler to set up and sufficient for a trusted
private network. Nodes that share a cookie can connect to each other.
TLS with chez-ssl can be layered on top for encryption without changing the
authentication model. The connection manager wraps raw TCP; upgrading to TLS
is a one-line change in `open-connection!`.

### Why monitors instead of links for supervision?

Links are bidirectional: if either actor dies, the other receives an EXIT signal.
This is correct for peer actors but wrong for supervisors — a supervisor should
NOT die when a worker dies (it needs to restart the worker). Monitors are
one-way: the supervisor receives a DOWN message but does not propagate its own
death to the worker. This matches Erlang/OTP semantics exactly.

### Why OTP restart strategies?

After years of production use in Erlang/Elixir, OTP's three strategies cover
virtually all real-world supervision needs:
- **one-for-one**: Independent workers (HTTP handlers, DB connection pool entries)
- **one-for-all**: Tightly coupled workers (a codec paired with a network connection)
- **rest-for-one**: Pipeline stages (worker N depends on worker N-1 being alive)

Adding more strategies creates API complexity without solving new problems.

### Why not Erlang-style process dictionary?

Erlang's per-process dictionary (`put`/`get`) is convenient but makes testing
harder (implicit mutable state). Instead, actors carry all state in their closure:

```scheme
(define (make-stateful-actor)
  (let ([state 0])      ;; state lives in the closure
    (spawn-actor
      (lambda (msg)
        (set! state (+ state 1))
        (displayln state)))))
```

This is idiomatic Scheme and easier to reason about.

---

## Example: Full Application

```scheme
(import (chezscheme) (std actor))

;; Start infrastructure
(define sched (scheduler-start! (make-scheduler (cpu-count))))
(set-actor-scheduler! sched)
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
               (set! n initial)])))))))

;; Start with supervision
(define app
  (start-supervisor
    'one-for-one
    (list
      (make-child-spec 'counter
                       (lambda () (make-counter 0))
                       'permanent 5.0 'worker))
    10 5))

;; Find and use the counter via registry
(register! 'counter (car (map caddr (supervisor-which-children app))))
(counter:increment! (whereis 'counter) 10)
(counter:increment! (whereis 'counter) 5)
(display (counter:get-value?! (whereis 'counter)))  ;; => 15
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
