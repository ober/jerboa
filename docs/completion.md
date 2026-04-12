# Completion: Wiring Fibers into the Clojure Layer

**Goal:** Every Clojure concurrency primitive in Jerboa should be fiber-aware.
A `go` block should be a fiber, not an OS thread. `core.async` channels
should park fibers, not block threads. Atoms, STM, and the component system
should all work naturally inside `fiber-httpd` handlers without accidentally
blocking the scheduler.

**Status:** 2026-04-12 — All 6 phases implemented.

---

## The Problem

Jerboa has two concurrency worlds that don't talk to each other:

| | **Fiber world** | **Clojure world** |
|---|---|---|
| Unit of work | Fiber (engine-based green thread) | OS thread (`fork-thread`) |
| Channel | `fiber-channel` (parks fiber) | `(std csp)` channel (blocks OS thread) |
| Scheduling | M:N work-stealing on N workers | 1:1 OS threads, unbounded |
| I/O | epoll-integrated, non-blocking | Blocking syscalls |
| Atom | N/A (use raw Chez `box`) | `(std misc atom)` — mutex-locked |
| STM | N/A | `(std stm)` — global commit mutex |
| HTTP | `fiber-httpd` (one fiber/conn) | N/A |

**What breaks today:** If you call `(chan-get! ch)` inside a `fiber-httpd`
handler, it blocks the OS worker thread — starving every fiber on that worker.
If you call `(dosync ...)` from two fibers on the same worker, the commit
mutex can deadlock the scheduler.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  (std clojure)  +  (std csp clj)                │  ← Clojure API surface
│  get/assoc/atom/swap!/go/>!!/<!!                 │     (unchanged names)
├─────────────────────────────────────────────────┤
│  (std csp/fiber)  — fiber-aware CSP channels     │  ← NEW adapter layer
│  (std atom/fiber)  — fiber-safe atoms            │
│  (std stm/fiber)   — fiber-safe STM             │
├─────────────────────────────────────────────────┤
│  (std fiber)  — M:N scheduler + work-stealing    │  ← Foundation
│  (std net io) — epoll poller                     │
│  (std net fiber-httpd) — HTTP server             │
└─────────────────────────────────────────────────┘
```

The Clojure API surface stays identical. The backing implementations detect
whether they're running inside a fiber context (`current-fiber` returns
non-`#f`) and dispatch accordingly — fiber primitives when in a fiber, OS
thread primitives when not.

---

## Phase 1: Fiber-Aware core.async

**The single highest-impact change.** `go` becomes `fiber-spawn`, channels
become fiber-channels, and the entire CSP vocabulary works inside
`fiber-httpd` handlers.

### 1.1 — `go` spawns a fiber, not a thread

```scheme
;; Current (std csp clj):
(define-syntax go
  (syntax-rules ()
    [(_ body ...)
     (let ([ch (make-channel 1)])
       (fork-thread (lambda () ...))
       ch)]))

;; New:
(define-syntax go
  (syntax-rules ()
    [(_ body ...)
     (let ([rt (current-fiber-runtime)])
       (if rt
         ;; Inside fiber runtime: spawn a fiber
         (let ([ch (make-fiber-channel 1)])
           (fiber-spawn* (lambda ()
             (guard (exn [#t (fiber-channel-close ch)])
               (fiber-channel-send ch (begin body ...)))))
           ch)
         ;; Outside fiber runtime: fall back to OS thread (existing behavior)
         (let ([ch (make-channel 1)])
           (fork-thread (lambda () ...))
           ch)))]))
```

When running inside `fiber-httpd`, `(go ...)` creates a fiber that costs
~4KB. When running standalone (tests, scripts), it falls back to OS threads.
No user code changes needed.

### 1.2 — Unified channel type

Create `(std csp fiber-chan)` that wraps `fiber-channel` with the CSP
channel interface:

- `chan-put!` → `fiber-channel-send` (parks fiber if full)
- `chan-get!` → `fiber-channel-recv` (parks fiber if empty)
- `chan-try-put!` → `fiber-channel-try-send`
- `chan-try-get` → `fiber-channel-try-recv`
- `chan-close!` → `fiber-channel-close`
- Buffer policies: fixed (bounded fiber-channel), sliding, dropping

The Clojure aliases (`>!`, `<!`, `>!!`, `<!!`) all route through this.
Since fiber channels already support `fiber-select`, `alts!` maps directly.

### 1.3 — `alts!` via `fiber-select`

```scheme
;; Clojure:
(let [[val ch] (alts! [ch1 ch2 (timeout 1000)])]
  (println "got" val "from" ch))

;; Jerboa — maps to fiber-select:
(fiber-select
  [ch1 val => (values val ch1)]
  [ch2 val => (values val ch2)]
  [:timeout 1000 => (values nil :timeout)])
```

Provide an `alts!` function that builds the `fiber-select` call dynamically.
This replaces the current `(std csp select)` event-based implementation
when inside a fiber context.

### 1.4 — `timeout` channels

Already have `fiber-timeout` which creates a channel that fires after N ms.
Wire it into `(std csp clj)`:

```scheme
(define (timeout ms)
  (if (current-fiber-runtime)
    (fiber-timeout ms)
    (csp-timeout ms)))  ;; existing OS-thread version
```

### 1.5 — `pipeline` / `pipeline-blocking` / `pipeline-async`

These spawn parallel workers. Inside a fiber runtime, workers should be
fibers:

- `pipeline`: N fiber workers, all sharing a transducer
- `pipeline-blocking`: N OS-thread workers via `work-pool-submit!`
  (for blocking I/O that can't be fibered)
- `pipeline-async`: Each item gets its own fiber, user provides
  async-fn that puts result onto a channel

### Deliverable

`(std csp clj)` works identically from user code but runs fibers
inside `fiber-httpd`. Existing `go`-heavy code gets ~1000x concurrency
improvement (OS threads → fibers) with zero changes.

**Test:** Port the core.async test suite. Run 10K `go` blocks inside
a `fiber-httpd` handler. Verify no OS threads are leaked.

---

## Phase 2: Fiber-Safe Atoms and Watches

### 2.1 — Non-blocking atom operations

Current `(std misc atom)` uses `mutex-acquire` / `mutex-release`. Inside
a fiber, this blocks the OS worker thread. Replace with:

```scheme
(define (atom-swap! a f . args)
  (let loop ()
    (let* ([old (atom-deref a)]
           [new (apply f old args)])
      (if (atom-compare-and-set! a old new)
        (begin (run-watches! a old new) new)
        (loop)))))
```

Use CAS (compare-and-set) spin loop instead of mutex. Chez doesn't have
native CAS, but we can implement it with a short-held mutex that never
blocks fibers for more than a few instructions (no I/O or allocation
under the lock).

Alternatively, use `(std misc atom)` as-is but document that atom
contention is minimal (the mutex is held for nanoseconds, not
milliseconds). This may be good enough — profile before optimizing.

### 2.2 — Fiber-aware watches

When a watch callback does I/O (e.g., logging, sending a notification),
it must not block the atom's mutex. Current implementation already runs
watches outside the lock. Verify this works correctly inside fibers and
add a test.

### 2.3 — Agents backed by fibers

Clojure agents use a thread pool for `send` and a separate pool for
`send-off`. Map these to:

- `send` → submit to a bounded fiber pool (N fibers, shared channel)
- `send-off` → submit to `work-pool-submit!` (for blocking I/O)

Agent error handling (`agent-error`, `restart-agent`, `set-error-handler!`,
`set-error-mode!`) stays the same.

### Deliverable

Atoms, watches, and agents work safely inside fibers. No mutex
starvation, no worker-thread blocking.

---

## Phase 3: Fiber-Safe STM

### 3.1 — Replace global commit mutex

Current `(std stm)` uses a single global mutex for all commits. Two
fibers in `dosync` on the same worker thread will deadlock (fiber A
holds the mutex, fiber B on the same worker can't preempt A to release
it).

Options:

**Option A — Optimistic lock-free STM:**
Replace the commit mutex with a lock-free compare-and-swap on version
numbers. Each tvar has a version counter. `dosync` reads versions at
start, validates at commit by checking versions haven't changed, and
atomically bumps them. No mutex needed.

```scheme
(define (tvar-commit! tv expected-version new-val)
  ;; CAS: if version still matches, update value + version atomically
  (with-mutex (tvar-lock tv)  ;; per-tvar lock, not global
    (if (= (tvar-version tv) expected-version)
      (begin (tvar-version-set! tv (+ expected-version 1))
             (tvar-value-set! tv new-val)
             #t)
      #f)))
```

**Option B — Per-tvar locks (MVCC-style):**
Replace the single global mutex with per-tvar fine-grained locks. Only
lock the tvars actually written in the transaction. Conflict detection
via version stamps.

Recommend Option B — simpler, proven (this is what Clojure does), and
per-tvar locks are short-held so fiber starvation is unlikely.

### 3.2 — `retry` via fiber parking

Clojure's `retry` blocks the transaction until a referenced tvar changes.
Map this to:

```scheme
(define (stm-retry! read-set)
  ;; Park the fiber until any tvar in the read-set changes
  (let ([ch (make-fiber-channel 1)])
    ;; Register a one-shot watch on each read-set tvar
    (for-each (lambda (tv)
      (tvar-add-watch! tv ch)) read-set)
    ;; Park until any tvar fires
    (fiber-channel-recv ch)
    ;; Unregister watches and restart transaction
    (for-each (lambda (tv)
      (tvar-remove-watch! tv ch)) read-set)))
```

This gives real STM `retry` semantics — the fiber sleeps until it
has a reason to re-run, instead of busy-spinning.

### Deliverable

`(dosync (alter ref f))` works inside fibers without deadlocks. `retry`
parks the fiber efficiently. Multiple fibers can run concurrent
transactions on the same worker thread.

---

## Phase 4: Ring-Style HTTP Middleware

### 4.1 — Request and response as persistent maps

Clojure Ring represents requests and responses as maps. Jerboa's
`fiber-httpd` uses records. Bridge the gap:

```scheme
;; Wrap fiber-httpd request record as a Clojure-compatible map
(define (request->ring req)
  (hash-map
    :request-method (request-method req)
    :uri            (request-path req)
    :headers        (request-headers req)
    :body           (request-body req)
    :server-port    (or (request-header req "host") "")
    :scheme         :http))

;; Convert Ring-style response map back to fiber-httpd response
(define (ring->response m)
  (respond (get m :status 200)
           (get m :headers '())
           (get m :body "")))
```

### 4.2 — Middleware as function composition

```scheme
;; Ring middleware: (handler → handler)
(define (wrap-logging handler)
  (lambda (req)
    (let ([start (current-time 'time-utc)])
      (let ([resp (handler req)])
        (log-request req resp start)
        resp))))

;; Compose middleware (right to left, like Clojure ->):
(define (ring-app handler . middleware)
  (fold-left (lambda (h mw) (mw h)) handler middleware))

;; Usage:
(fiber-httpd-start 8080
  (ring-app my-handler
    wrap-logging
    wrap-json-content-type
    wrap-cors
    wrap-exception-handler))
```

### 4.3 — Standard middleware library

Port the most-used Ring middleware:

| Middleware | Purpose |
|---|---|
| `wrap-json-body` | Parse JSON request body into map |
| `wrap-json-response` | Serialize response body as JSON |
| `wrap-params` | Parse query params into `:params` |
| `wrap-cookies` | Parse/set cookies |
| `wrap-session` | Session management (in-memory or pluggable) |
| `wrap-cors` | CORS headers |
| `wrap-content-type` | Set default content-type |
| `wrap-not-modified` | 304 responses via ETag/Last-Modified |
| `wrap-head` | Convert HEAD requests to GET |
| `wrap-exception` | Catch exceptions, return 500 |

### 4.4 — Static file serving via sendfile

```scheme
(define (wrap-static prefix dir)
  (lambda (handler)
    (lambda (req)
      (let ([path (request-path req)])
        (if (string-prefix? prefix path)
          (let ([file (path-join dir (substring path (string-length prefix)))])
            (if (file-exists? file)
              (respond-file file)       ;; uses fiber-sendfile internally
              (handler req)))
          (handler req))))))
```

### Deliverable

A Clojure Ring-compatible middleware stack that runs on `fiber-httpd`.
Clojure web developers can port their middleware chains directly.

---

## Phase 5: Component System Integration

### 5.1 — Fiber-aware component lifecycle

The current `(std component)` starts/stops components in dependency order.
Add fiber-runtime as a first-class component:

```scheme
(define my-system
  (system-map
    :fiber-runtime (fiber-runtime-component 4)
    :http-server   (httpd-component 8080 handler)
    :db-pool       (db-pool-component "postgres://...")
    :worker        (worker-component)))

(start my-system)
;; - Creates fiber runtime (4 workers)
;; - Starts DB pool
;; - Starts HTTP server on fiber runtime
;; - Starts background worker fiber
```

### 5.2 — Graceful shutdown integration

Wire component `stop` into `fiber-httpd-stop!`:

- Stop accepting new connections
- Drain in-flight requests (configurable timeout)
- Close connection pools
- Stop fiber runtime

### 5.3 — Dependency injection via fiber parameters

Components that need access to shared resources (DB pool, config) can use
fiber parameters:

```scheme
(define *db-pool* (make-fiber-parameter #f))
(define *config*  (make-fiber-parameter #f))

;; In httpd handler:
(lambda (req)
  (let ([pool (*db-pool*)])
    (with-pooled-connection pool conn
      (query conn "SELECT ..."))))
```

### Deliverable

A production-ready application scaffold: fiber runtime + HTTP server +
DB pool + background workers, all managed by the component system with
clean startup/shutdown.

---

## Phase 6: Bonus — core.logic and Datalog

Low priority but high wow-factor. miniKanren was born in Scheme.

### 6.1 — miniKanren (core.logic subset)

```scheme
(import (std logic))

(run* (q)
  (fresh (x y)
    (== q (list x y))
    (membero x '(1 2 3))
    (membero y '(a b))
    (conde
      [(== x 1) (== y 'a)]
      [(== x 2) (== y 'b)])))
;; => ((1 a) (2 b))
```

Port `microKanren` (50 lines of Scheme!) then build the `core.logic`
sugar on top. This is a weekend project.

### 6.2 — Datalog query engine

Build on miniKanren + persistent maps for an in-memory Datalog:

```scheme
(import (std datalog))

(def db (-> (empty-db)
            (assert [:person/name "Alice" :person/age 30])
            (assert [:person/name "Bob"   :person/age 25])))

(query db
  '[:find ?name ?age
    :where [?e :person/name ?name]
           [?e :person/age ?age]
           [(> ?age 27)]])
;; => #{["Alice" 30]}
```

### Deliverable

In-process logic programming and Datalog queries. Makes Jerboa
interesting for rule engines and knowledge graphs.

---

## Priority Order

```
Phase 1  ██████████  — core.async on fibers. Unblocks everything else.
Phase 2  ████████    — Fiber-safe atoms. Required for real handlers.
Phase 4  ██████      — Ring middleware. The thing users actually want.
Phase 3  █████       — Fiber-safe STM. Needed for complex state.
Phase 5  ████        — Component system. Production scaffolding.
Phase 6  ███         — core.logic/Datalog. Differentiator.
```

## Success Criteria

**We win when:**

```scheme
(import (jerboa prelude))
(import (std clojure))
(import (std csp clj))
(import (std net fiber-httpd))

(def state (atom {}))

(fiber-httpd-start 8080
  (lambda (req)
    (go
      (let [result (<! (async-fetch-data))]
        (swap! state assoc :last-result result)
        (respond-json 200 result)))))
```

One import. Fibers, channels, atoms, HTTP — all wired together.
No thread starvation. No deadlocks. 100K concurrent connections.
