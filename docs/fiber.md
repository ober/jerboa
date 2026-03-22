# Green Threads / Fibers

The `(std fiber)` library provides M:N green thread scheduling for Jerboa, mapping N lightweight fibers to M OS worker threads.

## Features

- **Lightweight fibers**: ~continuation + small record per fiber (4µs spawn overhead)
- **Cooperative yield**: `(fiber-yield)` via `(set-timer 1)` for near-instant preemption
- **Preemptive time-slicing**: Chez engines with configurable fuel quanta
- **M:N scheduling**: N fibers across M worker threads (defaults to CPU count - 1)
- **Fiber-aware channels**: send/recv suspend the fiber, not the OS thread
- **fiber-sleep**: suspend for a duration without blocking the worker

## Quick Start

```scheme
(import (std fiber))

;; Simple — run fibers to completion
(with-fibers
  (fiber-spawn* (lambda ()
    (display "hello ")
    (fiber-yield)
    (display "world\n")))
  (fiber-spawn* (lambda ()
    (display "from fiber 2\n"))))

;; Explicit runtime control
(define rt (make-fiber-runtime 4))        ;; 4 worker threads
(fiber-spawn rt (lambda () (display "hi\n")))
(fiber-runtime-run! rt)                    ;; blocks until all done
```

## API Reference

### Runtime

| Function | Description |
|---|---|
| `(make-fiber-runtime)` | Create runtime with default workers (CPU-1) and fuel (10000) |
| `(make-fiber-runtime nworkers)` | Create runtime with N worker threads |
| `(make-fiber-runtime nworkers fuel)` | Create with N workers and custom fuel per time slice |
| `(fiber-runtime-run! rt)` | Start workers, block until all fibers complete |
| `(fiber-runtime-stop! rt)` | Stop workers |
| `(fiber-runtime-fiber-count rt)` | Count of active (non-done) fibers |

### Fiber Operations

| Function | Description |
|---|---|
| `(fiber-spawn rt thunk)` | Spawn a fiber on runtime `rt` |
| `(fiber-spawn rt thunk name)` | Spawn a named fiber |
| `(fiber-spawn* thunk)` | Spawn on `current-fiber-runtime` |
| `(fiber-yield)` | Cooperatively yield to other fibers |
| `(fiber-sleep ms)` | Suspend fiber for `ms` milliseconds |
| `(fiber-self)` | Get the current fiber record |

### Fiber State

| Function | Description |
|---|---|
| `(fiber? x)` | Is x a fiber? |
| `(fiber-state f)` | Current state: `'ready`, `'running`, `'parked`, `'done` |
| `(fiber-name f)` | Fiber's name (or #f) |
| `(fiber-done? f)` | Is the fiber complete? |

### Channels

Fiber-aware channels suspend the calling fiber (not the OS thread) when blocking.

| Function | Description |
|---|---|
| `(make-fiber-channel)` | Unbounded channel |
| `(make-fiber-channel cap)` | Bounded channel with capacity `cap` |
| `(fiber-channel-send ch val)` | Send value (blocks if full) |
| `(fiber-channel-recv ch)` | Receive value (blocks if empty) |
| `(fiber-channel-try-send ch val)` | Non-blocking send, returns #t/#f |
| `(fiber-channel-try-recv ch)` | Non-blocking recv, returns `(values val #t)` or `(values #f #f)` |
| `(fiber-channel-close ch)` | Close channel, wake all waiters |

### Parameters

| Parameter | Description |
|---|---|
| `current-fiber-runtime` | Thread-parameter: active runtime |
| `current-fiber` | Thread-parameter: running fiber |

### Convenience

```scheme
(with-fibers body ...)
;; Creates a runtime, evaluates body (spawn fibers here),
;; runs until all complete.
```

## Design Notes

### Engine-Based Preemption

Each fiber runs inside a Chez `make-engine` with a fuel quota. Non-yielding fibers are automatically preempted when fuel is exhausted. The preempted engine continuation is stored and resumed on the next scheduling round.

### Cooperative Yield via set-timer

When a fiber yields, sleeps, or blocks on a channel, it calls `(set-timer 1)` to force immediate engine preemption (costs ~1 tick instead of burning a full fuel quantum). The engine's complete-proc then either:
- Opens the gate (cooperative yield → immediate re-enqueue)
- Parks the fiber (sleep/channel → waits for timer or sender to wake it)

### Per-Fiber Mutex for M:N Safety

A per-fiber mutex coordinates between `handle-complete` (worker thread) and `wake-fiber!` (potentially different worker thread) to prevent double-enqueue when a fiber is both preempted and woken simultaneously.

## Performance

Benchmarks on a multi-core system:

| Operation | Time |
|---|---|
| Spawn + complete (noop) | 4µs/fiber |
| Cooperative yield | 10µs/yield |
| Channel send+recv | 5.4µs/message |
| 1000-fiber ring, 10 passes | 135ms |
| 100 busy fibers, 1M iter each | 143ms |
| vs OS threads (10K spawn) | **9x faster** |
