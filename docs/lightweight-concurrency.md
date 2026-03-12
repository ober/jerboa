# Lightweight Concurrency Guide

Jerboa provides several concurrency models beyond raw OS threads (`fork-thread`).
This guide explains each option, when to use it, and how to access it programmatically.

**Key design decision**: Jerboa does not implement green threads or userland M:N
scheduling with continuation-based context switching. Instead, it builds lightweight
abstractions on top of Chez Scheme's native OS threads. The two lightest options —
the work-stealing actor scheduler and the engine pool — multiplex many tasks onto a
fixed-size thread pool without spawning a new OS thread per task.

---

## At a Glance

| Approach | Import | Thread Model | Preemption | Best For |
|---|---|---|---|---|
| [Actor Scheduler (M:N)](#1-actor-scheduler-mn-work-stealing) | `(std actor scheduler)` | M:N pool | No | Many concurrent tasks (goroutine-like) |
| [Engine Pool](#2-engine-pool-preemptive-time-slicing) | `(std actor engine)` | M:N pool | Yes (fuel ticks) | CPU-bound work that must not starve |
| [Channels + Select](#3-channels-with-select) | `(std misc channel)` | Any | No | Go-style message passing |
| [Async/Await](#4-asyncawait) | `(std async)` | 1:1 per spawn | No | Sequential async code, timeouts |
| [STM](#5-software-transactional-memory) | `(std stm)` | Any | No | Lock-free shared state |
| [Raw Threads](#6-raw-os-threads) | `(chezscheme)` | 1:1 | No | Full control, tight loops |

---

## 1. Actor Scheduler (M:N Work-Stealing)

**This is the closest analog to goroutines.** A fixed pool of OS worker threads
runs many tasks via a Chase-Lev work-stealing deque. Spawning a new actor does not
create a new OS thread — it pushes a task onto the pool.

### Setup

```scheme
(import (chezscheme)
        (std actor core)
        (std actor scheduler))

;; Create a pool with N worker threads (one per CPU core)
(define sched (scheduler-start! (make-scheduler 4)))

;; Tell the actor system to use the pool instead of fork-thread
(set-actor-scheduler! (lambda (thunk) (scheduler-submit! sched thunk)))
```

### Spawning tasks

Once the scheduler is installed, `spawn-actor` submits to the pool:

```scheme
;; These are pool tasks, NOT new OS threads
(spawn-actor (lambda (msg) (printf "actor 1 got: ~a~%" msg)))
(spawn-actor (lambda (msg) (printf "actor 2 got: ~a~%" msg)))
```

You can also submit plain thunks directly without the actor protocol:

```scheme
(scheduler-submit! sched (lambda () (printf "plain task~%")))
```

### Shutdown

```scheme
(scheduler-stop! sched)
```

### Key exports from `(std actor scheduler)`

| Symbol | Description |
|---|---|
| `make-scheduler` | Create a scheduler with N workers |
| `scheduler-start!` | Start the worker threads, returns scheduler |
| `scheduler-stop!` | Drain queue and shut down workers |
| `scheduler-submit!` | Submit a thunk to the pool |
| `scheduler-worker-count` | Number of worker threads |
| `current-scheduler` | Thread parameter for the active scheduler |

### How it works

Each worker thread owns a double-ended queue. The owner pushes/pops from the bottom.
Idle workers steal from the top of other workers' deques (Chase-Lev algorithm). This
gives excellent cache locality for the common case and load balancing for uneven work.

### When to use

- You have many (hundreds, thousands) of concurrent tasks
- Tasks are short-lived or I/O-bound
- You want goroutine-like "spawn and forget" semantics
- You don't need automatic preemption of CPU-bound tasks

---

## 2. Engine Pool (Preemptive Time-Slicing)

The engine pool wraps Chez Scheme's `make-engine` primitive to provide **preemptive
time-slicing**. Long-running computations are automatically interrupted after a fuel
quantum and re-queued, preventing any single task from starving the pool.

You do **not** need the actor protocol to use this — submit plain thunks.

### Usage

```scheme
(import (chezscheme) (std actor engine))

;; Create a pool: 2 OS worker threads, 5000 fuel ticks per time slice
(define pool (make-engine-pool 2 5000))

;; Submit work — if the thunk uses more than 5000 ticks, it gets
;; preempted and re-queued automatically
(engine-pool-submit! pool
  (lambda ()
    (let loop ([i 0])
      (when (< i 1000000)
        (loop (+ i 1))))))

;; Submit more tasks — they share the pool fairly
(engine-pool-submit! pool
  (lambda ()
    (display "I won't be starved by the loop above\n")))

;; Clean shutdown
(engine-pool-stop! pool)
```

### Key exports from `(std actor engine)`

| Symbol | Description |
|---|---|
| `make-engine-pool` | Create pool with N workers and fuel quantum |
| `engine-pool-submit!` | Submit a thunk to the pool |
| `engine-pool-stop!` | Shut down the pool |
| `default-fuel` | Default fuel quantum (10,000 ticks) |

### How it works

1. Each worker OS thread runs a loop: dequeue a thunk, wrap it in a Chez engine
   via `make-engine`, run it for N fuel ticks
2. If the engine completes within its fuel allotment, the result is delivered
3. If fuel is exhausted, the engine's continuation is captured and re-queued as
   a new thunk — the task resumes from where it left off on the next schedule
4. No explicit `yield` is needed — preemption is automatic

### Fuel tuning

- **Lower fuel** (e.g., 1000): more responsive interleaving, higher context-switch overhead
- **Higher fuel** (e.g., 50000): less overhead, but tasks run longer before yielding
- **Default**: 10,000 ticks — good starting point for mixed workloads

### When to use

- CPU-bound computations that could run for a long time
- You need fairness guarantees (no task starvation)
- You want preemption without requiring cooperative `yield` calls
- Workloads where Go's goroutines would need `runtime.Gosched()` — here it's automatic

---

## 3. Channels with Select

Go-style bounded channels with multiplexed receive via `channel-select`.

### Usage

```scheme
(import (chezscheme) (std misc channel))

(let ([ch1 (make-channel)]       ; unbounded
      [ch2 (make-channel 16)])    ; bounded, capacity 16

  ;; Producer threads
  (fork-thread (lambda () (channel-put ch1 "hello")))
  (fork-thread (lambda () (channel-put ch2 42)))

  ;; Multiplexed receive — like Go's select {}
  (channel-select
    ((ch1 msg) (printf "ch1: ~a~%" msg))
    ((ch2 msg) (printf "ch2: ~a~%" msg))))
```

### Key exports from `(std misc channel)`

| Symbol | Description |
|---|---|
| `make-channel` | Create a channel (optional capacity for bounding) |
| `channel-put` | Blocking put (blocks if bounded channel is full) |
| `channel-get` | Blocking get (blocks if empty) |
| `channel-try-get` | Non-blocking get, returns `(values val #t)` or `(values #f #f)` |
| `channel-select` | Multiplexed wait across multiple channels |

### Combining with the actor scheduler

Channels pair naturally with the M:N scheduler. Use the scheduler for lightweight
task spawning and channels for coordination:

```scheme
(import (chezscheme) (std actor scheduler) (std misc channel))

(define sched (scheduler-start! (make-scheduler 4)))
(define results (make-channel 100))

;; Fan out 100 tasks across the pool
(do ([i 0 (+ i 1)])
    ((= i 100))
  (let ([n i])
    (scheduler-submit! sched
      (lambda ()
        (channel-put results (* n n))))))

;; Gather results
(do ([i 0 (+ i 1)])
    ((= i 100))
  (let ([val (channel-get results)])
    (printf "~a " val)))

(scheduler-stop! sched)
```

---

## 4. Async/Await

Effect-based async runtime. Each `spawn` creates a real OS thread, so this is
heavier than the actor scheduler, but the API is ergonomic for sequential async code.

### Usage

```scheme
(import (chezscheme) (std effect) (std async))

(run-async
  (lambda ()
    ;; Spawn two parallel tasks
    (let ([p1 (async-task (lambda () (async-sleep 100) "fast"))]
          [p2 (async-task (lambda () (async-sleep 200) "slow"))])
      ;; Both run concurrently — total wall time ~200ms, not 300ms
      (printf "~a ~a~%" (Async await p1) (Async await p2)))))
```

### Fan-out / gather

```scheme
(define (gather thunks)
  (run-async
    (lambda ()
      (let ([promises (map async-task thunks)])
        (map (lambda (p) (Async await p)) promises)))))

(gather (list
  (lambda () (* 6 7))
  (lambda () (+ 10 32))
  (lambda () (string-length "hello"))))
;; => (42 42 5)
```

### When to use

- Sequential async code with natural await points
- You have fewer than ~1000 concurrent tasks (each is an OS thread)
- You want mockable/testable I/O via algebraic effect handlers
- Blocking FFI calls that need to run concurrently

See [async.md](async.md) for the full API reference.

---

## 5. Software Transactional Memory

Lock-free shared state via optimistic transactions. Reads and writes to transactional
variables (TVars) are buffered and committed atomically.

### Usage

```scheme
(import (chezscheme) (std stm))

(define balance (make-tvar 1000))

;; Atomic transfer (no locks needed)
(atomically
  (let ([current (tvar-ref balance)])
    (tvar-set! balance (- current 100))))

;; Blocking wait: retry until condition is met
(atomically
  (let ([b (tvar-ref balance)])
    (when (< b 500)
      (retry))    ; blocks until balance changes, then re-runs
    (tvar-set! balance (- b 500))))
```

### When to use

- Multiple threads read/write shared state
- Lock ordering is too complex or error-prone
- You need composable atomic operations

See [stm.md](stm.md) for the full API reference.

---

## 6. Raw OS Threads

Direct access to Chez Scheme's threading primitives. Maximum control, minimum
abstraction.

```scheme
(import (chezscheme))

(define mu (make-mutex))
(define cv (make-condition))
(define result #f)

(fork-thread
  (lambda ()
    (with-mutex mu
      (set! result (* 6 7))
      (condition-signal cv))))

(with-mutex mu
  (condition-wait cv mu)
  (printf "result: ~a~%" result))   ; => result: 42
```

### When to use

- You need fewer than ~64 concurrent tasks
- Ultra-low-latency loops where scheduler overhead matters
- You want full control over synchronization

---

## Choosing the Right Model

```
Do you need preemption of CPU-bound tasks?
├── Yes → Engine Pool (#2)
└── No
    ├── Many tasks (100+)?
    │   ├── Yes → Actor Scheduler M:N (#1)
    │   └── No
    │       ├── Need shared mutable state?
    │       │   ├── Yes → STM (#5)
    │       │   └── No → Channels (#3) or Async/Await (#4)
    │       └── Sequential async with timeouts? → Async/Await (#4)
    └── Few tasks, max control → Raw Threads (#6)
```

### Composing models

These models are not mutually exclusive. Common combinations:

- **Actor Scheduler + Channels**: M:N task pool with Go-style communication
- **Actor Scheduler + STM**: lightweight tasks with lock-free shared state
- **Engine Pool + Channels**: preemptive tasks feeding results through channels
- **Async/Await + Channels**: sequential async code coordinating via channels

---

## Comparison with Other Languages

| Feature | Jerboa | Go | Erlang |
|---|---|---|---|
| Lightweight spawn | Actor scheduler (M:N) | Goroutines (M:N) | Processes (M:N) |
| Preemption | Engine pool (fuel ticks) | Since Go 1.14 (async preemption) | Reduction counting |
| Channels | `(std misc channel)` | Built-in `chan` | Mailboxes |
| Select/multiplex | `channel-select` | `select {}` | `receive` |
| Shared state | STM (lock-free) | Mutexes, sync.Map | ETS, process dictionary |
| Supervision | OTP-style supervisors | Manual (context.Context) | OTP supervisors |

---

## Further Reading

- [actor-model.md](actor-model.md) — Full actor system guide with OTP supervision
- [async.md](async.md) — Async/await API reference
- [concurrency.md](concurrency.md) — Thread-safety annotations, deadlock detection
- [effects.md](effects.md) — Algebraic effects system (underlies async)
- [stm.md](stm.md) — Software transactional memory reference
