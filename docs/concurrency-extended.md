# Concurrency & Control Flow Extensions

Advanced concurrency primitives, resource management, and control flow operators
for Jerboa's standard library.

## Table of Contents

- [Event System (`std misc event`)](#event-system)
- [Custodians (`std misc custodian`)](#custodians)
- [Resource Pool (`std misc pool`)](#resource-pool)
- [Delimited Continuations (`std misc delimited`)](#delimited-continuations)
- [Continuation Marks (`std misc cont-marks`)](#continuation-marks)
- [Non-deterministic Backtracking (`std misc amb`)](#non-deterministic-backtracking)

---

## Event System

**Module:** `(std misc event)`
**File:** `lib/std/misc/event.sls`

```scheme
(import (std misc event))
```

### Overview

Events are lazy values that may or may not be ready. They can be composed with
`choice`, transformed with `wrap`/`handle`, and synchronized with `sync` and
`sync/timeout`. Channels provide synchronous rendezvous-style communication
between threads, built on events.

The design follows the Concurrent ML (CML) model: events are first-class values
that represent potential communications. They are not "fired" until synchronized.

### API Reference

| Procedure | Signature | Description |
|-----------|-----------|-------------|
| `make-event` | `(make-event poll-thunk)` | Create an event from a poll thunk. The thunk must return `(values ready? value)`. |
| `event-ready?` | `(event-ready? evt)` | Poll the event once; returns `#t` if it is currently ready. |
| `event-value` | `(event-value evt)` | Block (spin-wait with backoff) until the event fires, then return its value. |
| `sync` | `(sync evt ...)` | Wait for any one of the given events to fire. Returns the value of the first ready event. Blocks indefinitely. |
| `sync/timeout` | `(sync/timeout timeout-ms evt ...)` | Like `sync` but returns `#f` if no event fires within `timeout-ms` milliseconds. |
| `choice` | `(choice evt ...)` | Combine multiple events into one. When polled, tries each in order and returns the first ready value. |
| `wrap` | `(wrap evt proc)` | Transform an event's value: when `evt` fires with value `v`, the wrapped event fires with `(proc v)`. |
| `handle` | `(handle evt proc)` | Alias for `wrap`. |
| `always-event` | `(always-event val)` | An event that is immediately ready with `val`. |
| `never-event` | `never-event` | A value (not a procedure). An event that is never ready. |
| `timer-event` | `(timer-event delay-ms)` | An event that fires with `#t` after `delay-ms` milliseconds. |
| `make-channel` | `(make-channel)` | Create a synchronous rendezvous channel. |
| `channel-send` | `(channel-send ch val)` | Blocking send: deposits `val` and waits until a receiver consumes it. |
| `channel-recv` | `(channel-recv ch)` | Blocking receive: waits for a sender and returns the sent value. |
| `channel-send-event` | `(channel-send-event ch val)` | An event for sending `val`. Fires (with `(void)`) when a receiver is waiting. |
| `channel-recv-event` | `(channel-recv-event ch)` | An event that fires with the received value when one is available. |

### Examples

**Basic event polling:**

```scheme
(import (std misc event))

;; An event that is always ready
(let ([e (always-event 42)])
  (event-ready? e))       ; => #t
  (event-value e))        ; => 42

;; never-event is never ready
(event-ready? never-event) ; => #f
```

**Timer with sync/timeout:**

```scheme
;; Wait up to 500ms for a timer that fires at 100ms
(sync/timeout 500 (timer-event 100))  ; => #t (the timer's value)

;; Timeout expires before the timer fires
(sync/timeout 10 (timer-event 5000))  ; => #f
```

**Choosing between events:**

```scheme
;; First-ready-wins: timer vs. channel receive
(let ([ch (make-channel)])
  ;; In another thread: (channel-send ch "hello")
  (sync
    (wrap (timer-event 1000) (lambda (v) 'timeout))
    (wrap (channel-recv-event ch) (lambda (msg) (list 'got msg)))))
;; => 'timeout if nothing sent within 1s, or '(got "hello") if sent
```

**Rendezvous channels between threads:**

```scheme
(import (std misc event) (chezscheme))

(let ([ch (make-channel)])
  ;; Producer thread
  (fork-thread
    (lambda ()
      (channel-send ch "hello")
      (channel-send ch "world")))
  ;; Consumer
  (let ([a (channel-recv ch)]
        [b (channel-recv ch)])
    (list a b)))
;; => ("hello" "world")
```

**Custom event from a poll thunk:**

```scheme
;; An event that fires when a file exists
(define (file-exists-event path)
  (make-event
    (lambda ()
      (if (file-exists? path)
          (values #t path)
          (values #f #f)))))

(sync/timeout 5000 (file-exists-event "/tmp/ready.flag"))
```

---

## Custodians

**Module:** `(std misc custodian)`
**File:** `lib/std/misc/custodian.sls`

```scheme
(import (std misc custodian))
```

### Overview

Custodians are hierarchical resource groups inspired by Racket's custodian
model. Every managed resource (ports, handles, custom objects) belongs to a
custodian. Shutting down a custodian recursively shuts down all its children and
releases all their resources. The `with-custodian` form provides automatic
cleanup on normal exit, exceptions, or continuation escapes.

### API Reference

| Procedure / Syntax | Signature | Description |
|--------------------|-----------|-------------|
| `make-custodian` | `(make-custodian)` or `(make-custodian parent)` | Create a child custodian. Defaults to `(current-custodian)` as parent. |
| `custodian?` | `(custodian? x)` | Returns `#t` if `x` is a custodian. |
| `current-custodian` | `(current-custodian)` | Parameter holding the current custodian. |
| `custodian-register!` | `(custodian-register! resource shutdown-proc)` or `(custodian-register! custodian resource shutdown-proc)` | Register a resource with a shutdown thunk. Returns the resource. If custodian is omitted, uses `(current-custodian)`. |
| `custodian-shutdown-all` | `(custodian-shutdown-all c)` | Recursively shut down custodian `c`: close all resources, shut down all children, remove from parent. Errors during individual resource cleanup are swallowed so one failure does not prevent others from cleaning up. |
| `custodian-managed-list` | `(custodian-managed-list c)` | Return a list of all managed resources and child custodians for `c`. |
| `custodian-open-input-file` | `(custodian-open-input-file path)` or `(custodian-open-input-file path custodian)` | Open an input port registered with the custodian for automatic cleanup. |
| `custodian-open-output-file` | `(custodian-open-output-file path)` or `(custodian-open-output-file path custodian)` | Open an output port registered with the custodian for automatic cleanup. |
| `with-custodian` | `(with-custodian body ...)` | Run `body ...` under a fresh custodian. The custodian is shut down when the body exits (normally, by exception, or by continuation escape). |

### Examples

**Automatic cleanup with `with-custodian`:**

```scheme
(import (std misc custodian))

(with-custodian
  (let ([p (custodian-open-input-file "data.txt")])
    (read p)))
;; Port is automatically closed when with-custodian exits
```

**Hierarchical resource management:**

```scheme
(let ([parent (make-custodian)])
  (parameterize ([current-custodian parent])
    (let ([child (make-custodian)])
      (parameterize ([current-custodian child])
        ;; Register resources under the child custodian
        (let ([handle (list 'connection)])
          (custodian-register! handle (lambda () (display "closed\n")))))
      ;; Inspect what the parent manages
      (custodian-managed-list parent)))
  ;; Shut down the parent — all children and their resources are cleaned up
  (custodian-shutdown-all parent))
```

**Registering custom resources:**

```scheme
(with-custodian
  ;; Register a custom handle with a cleanup procedure
  (let ([sock (open-tcp-connection "example.com" 80)])
    (custodian-register! sock (lambda () (close-port sock)))
    (put-bytevector sock #vu8(71 69 84))
    (get-bytevector-all sock)))
;; sock is closed automatically on exit
```

---

## Resource Pool

**Module:** `(std misc pool)`
**File:** `lib/std/misc/pool.sls`

```scheme
(import (std misc pool))
```

### Overview

A thread-safe, generic resource pool. Resources are created on demand up to a
configurable maximum, reused when idle, and optionally evicted after an idle
timeout. The pool uses a mutex and condition variable internally, so `pool-acquire`
can block without busy-waiting when the pool is full.

### API Reference

| Procedure / Syntax | Signature | Description |
|--------------------|-----------|-------------|
| `make-pool` | `(make-pool creator destroyer max-size)` or `(make-pool creator destroyer max-size idle-timeout)` | Create a pool. `creator` is a thunk returning a new resource. `destroyer` takes a resource and frees it. `max-size` is the maximum total resources (idle + in-use). `idle-timeout` is `#f` (no expiry) or a number of seconds after which idle resources are destroyed. |
| `pool?` | `(pool? x)` | Returns `#t` if `x` is a pool. |
| `pool-acquire` | `(pool-acquire p)` or `(pool-acquire p timeout)` | Get a resource from the pool. Reuses an idle resource if available, creates a new one if below max, or blocks. `timeout` is `#f` (block forever) or seconds. Returns the resource, or `#f` on timeout. |
| `pool-release` | `(pool-release p resource)` | Return a resource to the pool, making it available for others. |
| `with-resource` | `(with-resource pool (var) body ...)` | Acquire a resource, bind it to `var`, evaluate `body ...`, and release the resource on exit (even if an exception is raised). Uses `dynamic-wind`. |
| `pool-drain` | `(pool-drain p)` | Destroy all idle resources. In-use resources are not affected. |
| `pool-stats` | `(pool-stats p)` | Returns an alist: `((total . N) (idle . N) (in-use . N))`. Also evicts expired idle resources before counting. |

### Examples

**Basic connection pool:**

```scheme
(import (std misc pool))

(define db-pool
  (make-pool
    (lambda () (open-db-connection "localhost:5432"))  ; creator
    (lambda (c) (close-db-connection c))               ; destroyer
    10))                                                ; max 10 connections

;; Acquire, use, release
(let ([conn (pool-acquire db-pool)])
  (query conn "SELECT 1")
  (pool-release db-pool conn))
```

**Using `with-resource` for automatic release:**

```scheme
(with-resource db-pool (conn)
  (query conn "SELECT * FROM users WHERE id = 1"))
;; conn is released back to the pool even on error
```

**Acquire with timeout:**

```scheme
;; Wait at most 5 seconds for a resource
(let ([conn (pool-acquire db-pool 5)])
  (if conn
      (begin (query conn "SELECT 1")
             (pool-release db-pool conn))
      (display "pool exhausted, try again later\n")))
```

**Idle timeout for resource eviction:**

```scheme
;; Resources idle for more than 60 seconds are destroyed
(define pool
  (make-pool
    (lambda () (make-fresh-resource))
    (lambda (r) (destroy-resource r))
    20     ; max-size
    60))   ; idle-timeout in seconds
```

**Pool statistics:**

```scheme
(pool-stats db-pool)
;; => ((total . 3) (idle . 1) (in-use . 2))
```

**Drain idle resources:**

```scheme
(pool-drain db-pool)
;; All idle resources are destroyed; in-use resources are unaffected
(pool-stats db-pool)
;; => ((total . 2) (idle . 0) (in-use . 2))
```

---

## Delimited Continuations

**Module:** `(std misc delimited)`
**File:** `lib/std/misc/delimited.sls`

```scheme
(import (std misc delimited))
```

### Overview

Provides delimited continuations via `reset`/`shift` (Danvy and Filinski style)
and a prompt-based API (`call-with-prompt`/`abort-to-prompt`).

`reset` establishes a delimiter (prompt) around an expression. `shift` captures
the continuation up to the nearest enclosing `reset` as a procedure `k`. The
captured continuation can be called zero, one, or multiple times.

The implementation uses the Filinski encoding on top of `call/cc`.

### API Reference

| Procedure / Syntax | Signature | Description |
|--------------------|-----------|-------------|
| `reset` | `(reset body ...)` | Establish a continuation delimiter. Returns the value of `body ...`, or the value passed to `shift` if `shift` does not invoke `k`. |
| `shift` | `(shift k body ...)` | Capture the continuation up to the nearest `reset` as `k`, then evaluate `body ...`. If `k` is never called, the `reset` returns the result of `body ...`. |
| `make-prompt-tag` | `(make-prompt-tag)` or `(make-prompt-tag name)` | Create a prompt tag for use with `call-with-prompt`. |
| `call-with-prompt` | `(call-with-prompt tag thunk handler)` | Run `thunk` under a prompt identified by `tag`. If `abort-to-prompt` is called with the same `tag`, control returns to the prompt and the result is the value(s) passed to `abort-to-prompt`. |
| `abort-to-prompt` | `(abort-to-prompt tag val ...)` | Abort to the nearest prompt matching `tag`, returning `val ...`. Raises an error if no matching prompt is found. |

### Examples

**Basic reset/shift:**

```scheme
(import (std misc delimited))

;; shift captures the continuation (+ 1 []) up to reset
(reset (+ 1 (shift k (k 10))))    ; => 11

;; If k is not called, the reset returns the shift body's value
(reset (+ 1 (shift k 42)))        ; => 42

;; k can be called multiple times
(reset (+ 1 (shift k (+ (k 10) (k 20)))))  ; => 32
;; (k 10) => 11, (k 20) => 21, 11 + 21 = 32
```

**Building a list with shift:**

```scheme
;; Collect elements via shift
(reset
  (let ([x (shift k (cons 'a (k 'ignored)))])
    (let ([y (shift k (cons 'b (k 'ignored)))])
      '())))
;; => (a b)
```

**Prompt-based abort:**

```scheme
(let ([tag (make-prompt-tag 'my-prompt)])
  (call-with-prompt tag
    (lambda ()
      (+ 1 (abort-to-prompt tag 99)))
    (lambda (v) v)))
;; => 99
```

**Simulating exceptions with shift:**

```scheme
(define (try thunk handler)
  (reset
    (handler (shift k (k (thunk))))))

;; Not really needed with Chez's guard, but shows the pattern
```

---

## Continuation Marks

**Module:** `(std misc cont-marks)`
**File:** `lib/std/misc/cont-marks.sls`

```scheme
(import (std misc cont-marks))
```

### Overview

Continuation marks let you attach key-value metadata to continuation frames.
This module re-exports Chez Scheme's native continuation mark support with
SRFI 157 / Racket-compatible names. Continuation marks are useful for
implementing dynamic parameters, stack traces, profiling, and other
context-passing patterns without modifying function signatures.

**Important:** Chez Scheme uses `eq?` for key comparison. Use symbols or fixnums
as keys. String or pair keys only work if the exact same object is used for
both setting and lookup.

### API Reference

| Procedure / Syntax | Signature | Description |
|--------------------|-----------|-------------|
| `with-continuation-mark` | `(with-continuation-mark key val body)` | Evaluate `body` in a context where the current continuation frame has `key` mapped to `val`. If a mark for `key` already exists on this frame, it is replaced. |
| `current-continuation-marks` | `(current-continuation-marks)` | Capture the full set of continuation marks from the current continuation. |
| `continuation-mark-set->list` | `(continuation-mark-set->list mark-set key)` | Extract all values for `key` from the mark set as a list, innermost first. |
| `continuation-mark-set-first` | `(continuation-mark-set-first mark-set key)` | Return the first (innermost) value for `key` from the mark set, or `#f` if not found. `mark-set` can be `#f` to use the current continuation marks. |
| `continuation-marks?` | `(continuation-marks? x)` | Returns `#t` if `x` is a continuation mark set. |
| `call-with-immediate-continuation-mark` | `(call-with-immediate-continuation-mark key default proc)` | Call `proc` with the value of `key` in the immediately enclosing continuation frame, or `default` if no mark for `key` exists. Note the argument order: key, default, proc. |

### Examples

**Basic mark and lookup:**

```scheme
(import (std misc cont-marks))

(with-continuation-mark 'key 'val
  (continuation-mark-set->list
    (current-continuation-marks)
    'key))
;; => (val)
```

**Nested marks accumulate:**

```scheme
(with-continuation-mark 'depth 0
  (with-continuation-mark 'depth 1
    (with-continuation-mark 'depth 2
      (continuation-mark-set->list
        (current-continuation-marks)
        'depth))))
;; => (2 1 0)
```

**Tail-call mark replacement:**

When marks are set in tail position relative to an existing mark on the same
frame, the old value is replaced rather than accumulated:

```scheme
(with-continuation-mark 'k 'a
  (with-continuation-mark 'k 'b  ;; replaces 'a on the same frame
    (continuation-mark-set-first #f 'k)))
;; => b
```

**Implementing a call stack trace:**

```scheme
(define (traced name thunk)
  (with-continuation-mark 'trace name
    (thunk)))

(define (current-trace)
  (continuation-mark-set->list
    (current-continuation-marks)
    'trace))

(traced 'foo
  (lambda ()
    (traced 'bar
      (lambda ()
        (current-trace)))))
;; => (bar foo)
```

**Immediate continuation mark:**

```scheme
(with-continuation-mark 'ctx "request-123"
  (call-with-immediate-continuation-mark 'ctx #f
    (lambda (v) v)))
;; => "request-123"
```

---

## Non-deterministic Backtracking

**Module:** `(std misc amb)`
**File:** `lib/std/misc/amb.sls`

```scheme
(import (std misc amb))
```

### Overview

The `amb` operator implements McCarthy's ambiguous choice, enabling
non-deterministic programming with automatic backtracking. `amb` picks one of
its alternatives; if a later assertion fails, execution backtracks to the most
recent `amb` and tries the next alternative. This is useful for constraint
solving, search problems, and logic programming.

### API Reference

| Procedure / Syntax | Signature | Description |
|--------------------|-----------|-------------|
| `amb` | `(amb expr ...)` | Choose one of the expressions. If the current choice leads to failure, backtrack and try the next. `(amb)` with no arguments is equivalent to `(amb-fail)`. `(amb x)` with a single argument returns `x` directly. |
| `amb-fail` | `(amb-fail)` | Explicitly trigger backtracking. Raises an error if there are no remaining choice points. |
| `amb-assert` | `(amb-assert condition)` | If `condition` is `#f`, call `(amb-fail)` to backtrack. |
| `with-amb` | `(with-amb body ...)` | Run an amb computation. Returns the first successful result, or `#f` if no solution exists. |
| `amb-collect` | `(amb-collect body ...)` | Run an amb computation and collect all successful results into a list. |

### Examples

**Finding a solution:**

```scheme
(import (std misc amb))

(with-amb
  (let ([x (amb 1 2 3 4 5)]
        [y (amb 1 2 3 4 5)])
    (amb-assert (= (+ x y) 7))
    (cons x y)))
;; => (2 . 5)
```

**Collecting all solutions:**

```scheme
(amb-collect
  (let ([x (amb 1 2 3 4 5)]
        [y (amb 1 2 3 4 5)])
    (amb-assert (= (+ x y) 6))
    (cons x y)))
;; => ((1 . 5) (2 . 4) (3 . 3) (4 . 2) (5 . 1))
```

**No solution returns `#f`:**

```scheme
(with-amb
  (let ([x (amb 1 2 3)])
    (amb-assert (> x 10))
    x))
;; => #f
```

**Pythagorean triples:**

```scheme
(define (iota-from a b)
  ;; Returns list (a a+1 ... b)
  (if (> a b) '() (cons a (iota-from (+ a 1) b))))

(amb-collect
  (let* ([a (apply amb (iota-from 1 20))]
         [b (apply amb (iota-from a 20))]
         [c (apply amb (iota-from b 20))])
    (amb-assert (= (+ (* a a) (* b b)) (* c c)))
    (list a b c)))
;; => ((3 4 5) (5 12 13) (6 8 10) (8 15 17) (9 12 15) (12 16 20))
```

**Map coloring (constraint satisfaction):**

```scheme
(with-amb
  (let ([wa (amb 'red 'green 'blue)]
        [nt (amb 'red 'green 'blue)]
        [sa (amb 'red 'green 'blue)]
        [q  (amb 'red 'green 'blue)]
        [nsw (amb 'red 'green 'blue)]
        [v  (amb 'red 'green 'blue)]
        [t  (amb 'red 'green 'blue)])
    ;; Adjacent regions must differ
    (amb-assert (not (eq? wa nt)))
    (amb-assert (not (eq? wa sa)))
    (amb-assert (not (eq? nt sa)))
    (amb-assert (not (eq? nt q)))
    (amb-assert (not (eq? sa q)))
    (amb-assert (not (eq? sa nsw)))
    (amb-assert (not (eq? sa v)))
    (amb-assert (not (eq? q nsw)))
    (amb-assert (not (eq? nsw v)))
    (list (cons 'WA wa) (cons 'NT nt) (cons 'SA sa)
          (cons 'Q q) (cons 'NSW nsw) (cons 'V v) (cons 'T t))))
;; => ((WA . red) (NT . green) (SA . blue) (Q . red) (NSW . red) (V . green) (T . red))
```
