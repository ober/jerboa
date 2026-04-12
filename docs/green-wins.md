# Green Wins: Making Jerboa's Fibers World-Class for High-Scalability Servers

**Goal:** A Jerboa HTTP server handling 100K+ concurrent connections with the
ergonomics of Go goroutines, the safety of Erlang, and the raw speed of
io_uring — all in a language that fits in your head.

**Status:** 2026-04-11 — Roadmap. No phases started yet.

---

## Current Assets (what we already have)

| Asset | Location | State |
|-------|----------|-------|
| M:N fiber scheduler | `(std fiber)` — 1238 lines | Working. 100K fibers benchmarked. Preemptive via Chez engines. |
| Non-blocking TCP | `(std net tcp)` — 301 lines | Working. `O_NONBLOCK` + sleep-retry loop. GC-safe. |
| epoll (Rust native) | `(std os epoll-native)` — 86 lines | Working. `libjerboa_native.so`. Edge-triggered ready. |
| io_uring | `(std os iouring)` — 239 lines | Working. `liburing` FFI. Async read/write/accept via promises. |
| fcntl | `(std os fcntl)` — 112 lines | Working. `O_NONBLOCK`, `FD_CLOEXEC`. |
| Fiber channels | In `(std fiber)` | Buffered, bounded, select/multiplex, non-blocking variants. |
| Fiber timers | In `(std fiber)` | Sorted deadline queue, ms precision, integrated into worker loop. |
| Structured concurrency | In `(std fiber)` | `with-fiber-group`, `fiber-link!`, cancellation. |
| HTTP server | `(std net httpd)` | Thin wrapper around `chez-httpd`. Thread-based. Not fiber-aware. |

**The gap:** These pieces exist in isolation. epoll and io_uring don't talk to
the fiber scheduler. TCP does sleep-retry instead of parking fibers on fd
readiness. The HTTP server uses OS threads, not fibers.

---

## Architecture Overview

```
                    ┌─────────────��───────────────────────┐
                    │         Fiber Scheduler (M:N)        │
                    │  M worker threads × N fibers         │
                    │  run-queue + timer-queue              │
                    └──────┬──────────┬───────────┬────────┘
                           │          │           │
                    ┌──────▼──┐  ┌────▼────┐  ┌──▼────────┐
                    │  Poller  │  │  DNS    │  │  File I/O │
                    │  Thread  │  │  Pool   │  │  Pool     │
                    │ (epoll)  │  │ (2-4 T) │  │ (2-4 T)  │
                    └──────┬──┘  └────┬────┘  └──┬────────┘
                           │          │           │
                    ┌──────▼──────────▼───────────▼────────┐
                    │         wake-fiber! → run-queue       │
                    └───────────────────────────────────���──┘
```

**One poller thread** owns the epoll fd. Worker threads never call epoll_wait.
When a fiber parks on I/O, it registers its fd with the poller via a lock-free
command queue. The poller wakes fibers through the existing `wake-fiber!`
mechanism — the same path channels and timers already use.

**Blocking work** (DNS, regular-file I/O) goes to small dedicated thread pools.
Fibers park, the pool thread does the blocking call, then wakes the fiber.
Same pattern as Go's `netpoll` + `getaddrinfo` threads.

---

## Phase 1: Fiber-Aware I/O Core

**The foundation everything else builds on.**

### 1.1 — Poll descriptor table

```scheme
(define-record-type poll-desc
  (fields fd
          (mutable events)       ; EPOLLIN | EPOLLOUT
          (mutable reader-fiber) ; fiber parked for read, or #f
          (mutable writer-fiber) ; fiber parked for write, or #f
          (mutable deadline)))   ; timeout integration
```

A vector or eq-hashtable mapping fd → `poll-desc`. One entry per active fd.
When a fiber parks on read, `reader-fiber` is set. When epoll fires, the
poller looks up the poll-desc and calls `wake-fiber!` on the parked fiber.

This is exactly Go's `pollDesc` struct — the `rg`/`wg` fields that point to
the parked goroutine.

### 1.2 — Poller thread

A single OS thread running:

```
loop:
  epoll_wait(epfd, events, max_events, timeout=-1)
  for each event:
    poll-desc = fd-table[event.fd]
    if EPOLLIN  and poll-desc.reader-fiber → wake-fiber!(reader)
    if EPOLLOUT and poll-desc.writer-fiber → wake-fiber!(writer)
    if EPOLLERR or EPOLLHUP → wake both with error flag
```

Use **edge-triggered** epoll (`EPOLLET`) — one notification per state change,
no spurious wakeups, matches Go's proven model. Requires draining the fd on
each wakeup (read until `EAGAIN`).

Wake the poller via `eventfd` when new fds are registered, so it re-enters
`epoll_wait` with updated interest set.

### 1.3 — `fiber-wait-readable` / `fiber-wait-writable`

The core primitives. Analogous to how `fiber-sleep` parks and registers with
the timer queue:

```scheme
(define (fiber-wait-readable fd)
  (let ([pd (fd-table-ref fd)])
    (poll-desc-reader-fiber-set! pd (fiber-self))
    (poller-register! pd EPOLLIN)
    ;; Park: set gate, set-timer 1, spin until woken
    ...))
```

When woken by the poller, the fiber resumes and retries the non-blocking read.
If `EAGAIN` again (edge-triggered race), re-park.

### 1.4 — Fiber-aware socket ports

Replace the sleep-retry loop in `(std net tcp)` with fiber parking:

```scheme
;; BEFORE (current tcp.sls):
(let loop ()
  (let ([n (read fd buf size)])
    (if (= n -EAGAIN)
      (begin (sleep *retry-delay*) (loop))  ; 10ms poll!
      n)))

;; AFTER:
(let loop ()
  (let ([n (read fd buf size)])
    (if (= n -EAGAIN)
      (begin (fiber-wait-readable fd) (loop))  ; park until ready
      n)))
```

This alone eliminates the 10ms polling overhead and makes every socket op
fiber-friendly.

### 1.5 — Timeout integration

Unify fd timeouts with the existing timer queue. When parking a fiber on I/O,
optionally register a deadline:

```scheme
(define (fiber-wait-readable fd timeout-ms)
  (when timeout-ms
    (tq-add! timer-queue (deadline-from-now timeout-ms) (fiber-self)))
  (poll-desc-reader-fiber-set! pd (fiber-self))
  (poller-register! pd EPOLLIN)
  ;; Park...
  ;; On wake: check if woken by timer or by poller
  (when timeout-ms (tq-remove! timer-queue (fiber-self)))
  ...)
```

If the timer fires first, the fiber wakes with a timeout error. If the fd
becomes ready first, cancel the timer. This gives every I/O operation a
natural timeout mechanism.

### Deliverable

A new module `(std net io)` exporting:
- `fiber-wait-readable`, `fiber-wait-writable`
- `fiber-tcp-accept`, `fiber-tcp-read`, `fiber-tcp-write`
- `fiber-tcp-connect` with timeout
- `start-poller!`, `stop-poller!`

**Test:** 10K concurrent echo clients, single fiber per connection, verify no
fd leaks, measure latency p50/p99.

---

## Phase 2: Fiber-Native HTTP Server

### 2.1 — HTTP/1.1 parser

Write a zero-copy HTTP request parser. Read directly from fd into a bytevector
buffer. Parse request line, headers, and body boundaries without allocating
intermediate strings until needed.

Consider using `(std peg)` for the grammar, but benchmark against hand-rolled
state machine — HTTP parsing is hot path.

```scheme
(define (parse-request buf start end)
  ;; Returns: method, path, version, headers alist, body-start offset
  ...)
```

### 2.2 — HTTP response writer

Chunked transfer encoding, keep-alive support, streaming bodies via
fiber channels or lazy sequences.

```scheme
(define (write-response fd status headers body)
  ;; body can be: string, bytevector, port, fiber-channel, lazy-seq
  ...)
```

### 2.3 — Connection handler fiber

One fiber per connection. Accept loop spawns fibers:

```scheme
(define (serve-connection fd handler)
  (let loop ()
    (let ([req (read-request fd)])
      (when req
        (let ([resp (handler req)])
          (write-response fd resp)
          (when (keep-alive? req resp)
            (loop)))))))

(define (accept-loop listen-fd handler)
  (let loop ()
    (let ([client-fd (fiber-tcp-accept listen-fd)])
      (fiber-spawn* (lambda () (serve-connection client-fd handler)))
      (loop))))
```

### 2.4 — Routing

Simple, fast prefix-tree router:

```scheme
(define-httpd app
  (GET  "/health" (lambda (req) (respond 200 "ok")))
  (POST "/api/users" create-user-handler)
  (GET  "/api/users/:id" get-user-handler)
  (static "/assets" "./public"))
```

### 2.5 — Idle connection reaper

Use `fiber-sleep` + sweep to close connections that have been idle past a
configurable timeout. Alternatively, rely on per-connection read timeouts
from Phase 1.5.

### Deliverable

A new module `(std net fiber-httpd)` that:
- Handles 50K+ concurrent idle connections (one fiber each, parked on epoll)
- Saturates 10Gbps on simple JSON responses
- Supports keep-alive, chunked encoding, streaming
- Has request/response middleware model

**Benchmark:** Compare against Go `net/http`, nginx, and the current
`(std net httpd)` on:
- Connections/sec (wrk, 1K concurrent)
- Latency p99 under load
- Memory per connection
- Max concurrent idle connections before OOM

---

## Phase 3: Blocking Work Offload

### 3.1 — DNS resolver pool

`getaddrinfo` is blocking and can take seconds. Run it on a small pool of
dedicated OS threads (2-4, configurable):

```scheme
(define (fiber-resolve hostname)
  ;; Park fiber, queue (hostname . fiber) to DNS pool
  ;; Pool thread: getaddrinfo → wake-fiber! with result
  ...)
```

### 3.2 — File I/O pool

epoll returns "always ready" for regular files — useless. Two strategies:

**Strategy A — Thread pool (simple, portable):**
Same pattern as DNS. Park fiber, queue read/write request, pool thread does
blocking pread/pwrite, wakes fiber.

**Strategy B — io_uring (Linux, faster):**
We already have the FFI. Integrate `iouring-read!`/`iouring-write!` with the
fiber scheduler so completions wake fibers instead of resolving promises.

Ship Strategy A first (works everywhere), gate Strategy B on Linux 5.10+
detection at runtime.

### 3.3 — TLS integration

Options:
- **OpenSSL FFI** — proven, complex API surface
- **Rustls via libjerboa_native.so** — memory-safe, already have Rust build
  infrastructure
- **BoringSSL** — Google's OpenSSL fork, simpler API

TLS handshake and encryption must be non-blocking and fiber-aware. The TLS
library does its I/O through our fiber-aware read/write, not raw syscalls.

Recommended: **Rustls** via the existing `libjerboa_native.so` infrastructure.
Add `rustls-ffi` as a Rust dependency. Expose `tls-connect`, `tls-accept`,
`tls-read`, `tls-write` that internally call `fiber-wait-readable`/
`fiber-wait-writable` during handshake and data transfer.

### Deliverable

- `(std net dns)` — fiber-aware DNS resolution
- `(std io file)` — fiber-aware file read/write (thread pool + optional io_uring)
- `(std net tls)` — fiber-aware TLS via Rustls
- `fiber-tcp-connect` gains DNS resolution: `(fiber-tcp-connect "example.com" 443)`

---

## Phase 4: Production Hardening

### 4.1 — Backpressure and admission control

Without backpressure, a server accepting faster than it can process will OOM
from unbounded fiber creation. Implement:

- **Accept rate limiter:** Bounded channel between accept loop and handler
  fibers. When channel is full, accept loop parks — TCP backpressure propagates
  to clients via kernel listen queue.
- **Max concurrent connections:** Hard limit with graceful rejection (503).
- **Per-client rate limiting:** Token bucket per IP, fiber-aware sleep for
  throttling.

```scheme
(define (accept-loop listen-fd handler max-concurrent)
  (let ([sem (make-fiber-semaphore max-concurrent)])
    (let loop ()
      (fiber-semaphore-acquire! sem)  ; park if at limit
      (let ([client-fd (fiber-tcp-accept listen-fd)])
        (fiber-spawn*
          (lambda ()
            (unwind-protect
              (serve-connection client-fd handler)
              (fiber-semaphore-release! sem))))
        (loop)))))
```

### 4.2 — Graceful shutdown

- Stop accepting new connections
- Drain in-flight requests (configurable timeout)
- Cancel remaining fibers
- Close listener fd
- Signal shutdown complete

Integrate with `(std os signal)` for SIGTERM/SIGINT handling.

### 4.3 — Resource cleanup guarantees

Current problem: `fiber-cancel!` with forced timeout skips `dynamic-wind`
cleanup. For production servers, we need guaranteed cleanup:

- **Cooperative cancellation window:** Give the fiber N ms to notice
  cancellation and clean up. Only force-abandon after the window.
- **Fiber finalizers:** Register cleanup actions that run even on forced
  abandonment (close fds, release locks).
- **Connection-scoped resources:** `with-connection` macro that guarantees
  fd close even if the fiber is cancelled.

```scheme
(define-syntax with-connection
  (syntax-rules ()
    [(_ (fd client-fd) body ...)
     (let ([fd client-fd])
       (fiber-register-finalizer! (lambda () (close-fd fd)))
       (guard (exn [#t (close-fd fd) (raise exn)])
         body ...
         (close-fd fd)))]))
```

### 4.4 — Fiber-aware logging

Structured logging with fiber-id, connection-id, and request-id propagated
via fiber parameters:

```scheme
(define *request-id* (make-fiber-parameter #f))

(define (log-info msg . args)
  (let ([fid (fiber-id (fiber-self))]
        [rid (*request-id*)])
    (format (current-error-port) "[~a][~a] ~a~%" fid rid
            (apply format #f msg args))))
```

### 4.5 — Metrics and observability

Export runtime counters as an API and optionally as a Prometheus endpoint:

- `fiber-count` — active fibers
- `run-queue-depth` — fibers waiting to run
- `timer-queue-depth` — fibers sleeping
- `poller-fd-count` — fds registered with epoll
- `connections-active` / `connections-total`
- `request-latency-histogram`
- `gc-pause-duration`

### 4.6 — Health checks

Built-in `/health` and `/ready` endpoints that report:
- Server uptime
- Active connection count
- Whether the fiber scheduler is responsive (canary fiber)

### Deliverable

A production-grade server that can:
- Handle connection storms without OOM
- Shut down gracefully under SIGTERM
- Clean up all resources on fiber cancellation
- Expose metrics for monitoring
- Log structured, correlated request traces

---

## Phase 5: HTTP/2 and WebSockets

### 5.1 — HTTP/2 multiplexing

HTTP/2 maps naturally to fibers: one fiber per stream, all sharing one TCP
connection. The frame parser runs on the connection fiber, dispatching frames
to per-stream fibers via channels.

```
Connection fiber:
  loop: read-frame → route to stream fiber's channel

Stream fiber (one per request):
  recv headers from channel
  process request
  send response frames back to connection fiber's write channel

Write fiber:
  serialize frames, respect flow control windows, write to fd
```

This gives us free multiplexing — 100 concurrent requests on one TCP
connection, each as a lightweight fiber.

### 5.2 — WebSocket support

Upgrade from HTTP/1.1, then one fiber per WebSocket:

```scheme
(define (websocket-handler req ws)
  (let loop ()
    (let ([msg (ws-recv ws)])  ; parks fiber until frame arrives
      (ws-send ws (process msg))
      (loop))))
```

Natural fit for fibers — each WebSocket connection is a long-lived fiber
that parks between messages.

### 5.3 — Server-Sent Events

Streaming responses via fiber channels:

```scheme
(define (sse-handler req)
  (let ([ch (subscribe-events)])
    (respond-sse req
      (lambda (send!)
        (let loop ()
          (let ([event (fiber-channel-recv ch)])
            (send! event)
            (loop)))))))
```

---

## Phase 6: Advanced Optimizations

### 6.1 — io_uring for sockets

Replace epoll with io_uring for socket I/O on Linux 5.10+. Submission-based
model eliminates syscall overhead — batch multiple reads/writes into one
`io_uring_submit` call. The existing `(std os iouring)` FFI handles the
kernel interface; we just need to integrate completions with `wake-fiber!`.

**When:** Only after Phase 1-2 are stable. epoll is simpler and battle-tested.
io_uring is the optimization, not the foundation.

### 6.2 — Work-stealing scheduler

Current scheduler uses a single shared run queue with mutex. Under high
contention (many workers), this becomes a bottleneck. Replace with per-worker
local queues + work stealing:

- Each worker has a local deque
- Spawned fibers go to the spawning worker's local queue
- Idle workers steal from random other workers' queues
- Reduces mutex contention from O(M) to O(1) in the common case

This is Go's `P` (processor) model and Tokio's work-stealing scheduler.

### 6.3 — Zero-copy I/O

Use `splice(2)` and `sendfile(2)` for static file serving. For io_uring,
use registered buffers (`IORING_REGISTER_BUFFERS`) to avoid kernel copies.

### 6.4 — Connection pooling and reuse

For upstream connections (reverse proxy, database), maintain per-fiber-runtime
connection pools. Fibers acquire a connection, use it, return it. Pool manages
health checks and reconnection.

### 6.5 — NUMA-aware scheduling

Pin worker threads to CPU cores. Route fibers back to the worker that last ran
them (cache affinity). On NUMA systems, keep fibers and their data on the same
node.

---

## Priority Order

```
Phase 1  ██████████  — Foundation. Without this, nothing else works.
Phase 2  ████████    — The thing users actually see.
Phase 4  ██████      — The difference between demo and production.
Phase 3  █████       — Required for real-world servers (DNS, TLS, files).
Phase 5  ████        — Modern protocol support.
Phase 6  ███         — Performance ceiling. Do last.
```

## Success Criteria

**We win when:**

1. A trivial Jerboa HTTP handler outperforms Go `net/http` on connections/sec
   at 10K concurrent (Chez's compiler is faster than Go's; we just need the
   I/O layer to not be the bottleneck)

2. Memory per idle connection is < 4KB (fiber stack + poll-desc + buffers)

3. Tail latency (p99) under load stays under 10ms for simple handlers

4. A developer can write a concurrent WebSocket chat server in 30 lines

5. `(import (std net fiber-httpd))` is all you need — no configuration, no
   reactor pattern, no callback hell, no async/await coloring

```scheme
;; The dream:
(import (jerboa prelude))
(import (std net fiber-httpd))

(fiber-httpd-start 8080
  (lambda (req)
    (respond 200 '(("content-type" . "text/plain"))
      "Hello from 100K fibers")))
```

That's it. One import. One function. 100K concurrent connections.
