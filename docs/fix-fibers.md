# Fiber Gaps — Implementation Plan

Status: **draft** (2026-04-11)

The `(std fiber)` core (668 lines, 18 tests) is solid: M:N scheduling, engine-based preemption, cooperative yield, fiber-aware channels, sleep with timer queue. This document covers the gaps and how to fill them, ordered by value.

---

## 1. Fix `cpu-count` (trivial)

**Gap**: `fiber.sls:221-222` hardcodes `(if (threaded?) 4 1)`.

**Fix**: Reuse the real detection from `actor/scheduler.sls:135-146`, which reads `/proc/cpuinfo` with a fallback to 4.

Options:
- (a) Factor the scheduler's `cpu-count` into a shared `(std misc cpu)` module that both import.
- (b) Inline the same `/proc/cpuinfo` reader into `fiber.sls`.

Prefer (a) — one source of truth, and other modules (engine pool, task groups) can use it too.

**Effort**: ~30 minutes. **Tests**: Verify `(make-fiber-runtime)` picks up actual core count.

---

## 2. Fiber-local storage

**Gap**: No per-fiber variable bindings. `current-fiber` and `current-fiber-runtime` are `make-thread-parameter`, which is OS-thread-scoped. Since multiple fibers share one OS worker thread, a fiber-local needs its own mechanism.

**Design**: A `fiber-parameter` that stores values keyed by fiber ID.

```scheme
(define (make-fiber-parameter default)
  (let ([store (make-eq-hashtable)]
        [mx (make-mutex)])
    (case-lambda
      [()    ;; read
       (let ([f (current-fiber)])
         (if f
           (begin (mutex-acquire mx)
                  (let ([v (hashtable-ref store (fiber-id f) default)])
                    (mutex-release mx) v))
           default))]
      [(val) ;; write
       (let ([f (current-fiber)])
         (unless f (error 'fiber-parameter "not in a fiber"))
         (mutex-acquire mx)
         (hashtable-set! store (fiber-id f) val)
         (mutex-release mx))])))
```

**Cleanup**: When a fiber completes (`mark-fiber-done!`), sweep its entries from all registered fiber-parameters. Keep a global weak list of all live fiber-parameters, or add a per-fiber cleanup hook list.

**Convenience macro**:
```scheme
(define-syntax fiber-parameterize
  (syntax-rules ()
    [(_ ([fp val] ...) body ...)
     (let ([old-fp (fp)] ...)
       (dynamic-wind
         (lambda () (fp val) ...)
         (lambda () body ...)
         (lambda () (fp old-fp) ...)))]))
```

**Effort**: ~2 hours. **Tests**: fiber-local isolation across concurrent fibers on same worker thread, cleanup after fiber completion.

---

## 3. Fiber cancellation

**Gap**: No way to cancel a running fiber from outside. Once spawned, a fiber runs until its thunk returns or raises.

**Design**: Cooperative cancellation via a cancel token (same pattern as `task.sls:36-53`).

Add to the fiber record:
```scheme
(mutable cancelled?)   ;; boolean, checked at yield/sleep/channel-wait
```

API:
```scheme
(fiber-cancel! f)          ;; set cancelled? flag, wake if parked
(fiber-cancelled? f)       ;; check flag
(fiber-check-cancelled!)   ;; called inside fiber — raises &fiber-cancelled if set
```

**Cancellation points**: `fiber-yield`, `fiber-sleep`, `fiber-channel-recv`, and `fiber-channel-send` all check the cancelled flag before parking. Raise `&fiber-cancelled` condition.

**Force-cancel after timeout**: Like the actor supervisor's graceful shutdown (`supervisor.sls:215-240`), allow a deadline after which the fiber's engine is simply not resumed.

```scheme
(fiber-cancel! f)                ;; cooperative — sets flag
(fiber-cancel! f timeout-ms)     ;; cooperative, then force-abandon after timeout
```

**Condition type**:
```scheme
(define-condition-type &fiber-cancelled &serious
  make-fiber-cancelled fiber-cancelled?
  (fiber-id cancelled-fiber-id))
```

**Effort**: ~3 hours. **Tests**: cancel parked fiber, cancel running fiber at yield point, cancel with timeout, double-cancel idempotent.

---

## 4. Error propagation

**Gap**: Exceptions in a fiber are silently captured in `fiber-result` (`fiber.sls:436-441`). No notification to parent or supervisor.

**Design**: Two mechanisms, matching the actor system's patterns.

### 4a. fiber-join (blocking result retrieval)

```scheme
(fiber-join f)             ;; block current fiber until f completes, return result
(fiber-join f timeout-ms)  ;; with timeout, raises &fiber-timeout on expiry
```

If `f` completed with an exception, `fiber-join` re-raises it in the joining fiber. Implementation: add a "join-waiters" list to the fiber record; `mark-fiber-done!` wakes them.

### 4b. fiber-link (Erlang-style crash propagation)

```scheme
(fiber-link! f)      ;; link current fiber to f — if f dies with error, current fiber gets &fiber-linked-crash
(fiber-unlink! f)
```

When a linked fiber crashes, all linked fibers receive a `&fiber-linked-crash` condition at their next cancellation point. Simpler than full OTP monitors but covers the "if my child dies, I die" use case.

**Condition types**:
```scheme
(define-condition-type &fiber-timeout &serious
  make-fiber-timeout fiber-timeout?
  (fiber-id timeout-fiber-id))

(define-condition-type &fiber-linked-crash &serious
  make-fiber-linked-crash fiber-linked-crash?
  (source-fiber-id linked-crash-source)
  (original-condition linked-crash-condition))
```

**Effort**: 4a ~2 hours, 4b ~3 hours. **Tests**: join on completed fiber, join on crashed fiber re-raises, join timeout, link propagation.

---

## 5. Fiber-channel select (`fiber-select`)

**Gap**: No way to wait on multiple fiber-channels simultaneously.

**Design**: Adapt the CSP select spin-poll pattern (`csp/select.sls:166-174`) for fiber-channels.

```scheme
(fiber-select
  [ch1 val => (handle-val val)]           ;; recv from ch1
  [ch2 :send msg => (handle-sent)]        ;; send msg to ch2
  [:timeout 5000 => (handle-timeout)]     ;; optional timeout clause
  [:default => (handle-none)])            ;; optional non-blocking clause
```

**Implementation**: Macro expands to a loop that:
1. Try each clause's channel with `fiber-channel-try-recv` / `fiber-channel-try-send`.
2. If any succeeds, evaluate its body and return.
3. If `:default` clause exists and nothing ready, run it.
4. Otherwise, park the fiber on all channels' waiter lists, use a shared gate so that whichever channel fires first wakes the fiber.

The shared-gate approach avoids the spin-poll cost: register the fiber on multiple channels, first one to wake it wins, others remove the stale waiter entry.

**Alternative**: Integrate with `(std event)` by providing `fiber-recv-evt` / `fiber-send-evt` that return event objects compatible with `choice` and `sync`. This is cleaner but couples the two modules.

Recommend: start with the macro (self-contained in `(std fiber)`), add event integration later.

**Effort**: ~4 hours. **Tests**: select across 2+ channels, select with timeout, select with default, select with send+recv mix.

---

## 6. Structured concurrency (`with-fiber-group`)

**Gap**: No scoped lifecycle management. Fibers spawned with `fiber-spawn*` are fire-and-forget; no automatic cleanup, no "wait for all children" scope.

**Design**: Follows the pattern from `task.sls` and `concur/structured.sls`.

```scheme
(with-fiber-group
  (lambda (group)
    (fiber-group-spawn group (lambda () (do-work-a)))
    (fiber-group-spawn group (lambda () (do-work-b)))
    ;; implicit: waits for all children to complete
    ;; if any child raises, cancels siblings, re-raises in parent
    ))
```

**Semantics**:
- `with-fiber-group` creates a group, evaluates the body, then blocks until all spawned fibers complete.
- If any fiber in the group raises an unhandled exception, all other fibers in the group are cancelled (cooperative), and the exception is re-raised in the calling fiber.
- If the calling fiber is itself cancelled, all children are cancelled.
- Cleanup is guaranteed via `dynamic-wind`.

**Group record**:
```scheme
(define-record-type fiber-group
  (fields
    (mutable fibers)        ;; list of child fibers
    (mutable first-exn)     ;; first exception, or #f
    (mutable cancelled?)
    (immutable mutex)
    (immutable all-done)    ;; condition variable
    (mutable done-count)
    (mutable total-count)))
```

**Effort**: ~4 hours. **Tests**: all-succeed, first-error-cancels-rest, parent-cancel-propagates, nested groups.

---

## 7. Fiber-aware timeouts

**Gap**: `fiber-sleep` parks for a duration, but there's no "do X or timeout" pattern.

**Design**: Build on `fiber-select` (gap 5) plus a timeout channel.

```scheme
(define (fiber-timeout ms)
  ;; Returns a fiber-channel that receives (void) after ms milliseconds.
  ;; Uses the existing timer-queue infrastructure.
  (let ([ch (make-fiber-channel 1)]
        [rt (current-fiber-runtime)])
    (let* ([now (current-time 'time-utc)]
           [deadline (add-duration now
                       (make-time 'time-duration
                                  (* (fxmod ms 1000) 1000000)
                                  (fxquotient ms 1000)))])
      ;; Spawn a tiny fiber that sleeps then sends
      (fiber-spawn* (lambda ()
        (fiber-sleep ms)
        (fiber-channel-try-send ch (void)))))
    ch))
```

Usage with `fiber-select`:
```scheme
(fiber-select
  [work-ch result => (process result)]
  [(fiber-timeout 5000) _ => (error 'timeout "took too long")])
```

Better approach (no extra fiber): register directly on the timer queue, wake a channel when the deadline fires. Requires a small extension to the timer queue to fire arbitrary callbacks, not just wake fibers.

**Effort**: ~1 hour (spawn approach), ~2 hours (timer-queue callback approach). **Tests**: timeout fires, timeout not needed (work completes first).

---

## Implementation Order

| Priority | Gap | Effort | Dependencies |
|----------|-----|--------|--------------|
| 1 | cpu-count fix | 30 min | none |
| 2 | Fiber cancellation | 3 hours | none |
| 3 | Fiber-local storage | 2 hours | none |
| 4 | Error propagation (fiber-join) | 2 hours | cancellation (for timeout variant) |
| 5 | Fiber-channel select | 4 hours | none (but better with timeouts) |
| 6 | Fiber-aware timeouts | 2 hours | select |
| 7 | Structured concurrency | 4 hours | cancellation + error propagation |
| 8 | Error propagation (fiber-link) | 3 hours | cancellation |

**Total**: ~20 hours of implementation.

Gaps 1-4 are independent and can be done in any order. Gap 5 (select) unlocks gap 6 (timeouts). Gap 7 (structured concurrency) needs gaps 2 + 4.

---

## Existing Infrastructure to Reuse

| Need | Source | Path |
|------|--------|------|
| Real CPU detection | actor scheduler | `lib/std/actor/scheduler.sls:135-146` |
| Cancel tokens | task groups | `lib/std/task.sls:36-53` |
| Supervision patterns | actor supervisor | `lib/std/actor/supervisor.sls` |
| Spin-poll select | CSP select | `lib/std/csp/select.sls:166-174` |
| Timer wheel | CSP select | `lib/std/csp/select.sls:299-410` |
| Event abstraction | event system | `lib/std/event.sls:43-61` |
| Error aggregation | task groups | `lib/std/task.sls:121-149` |
| Hierarchical cleanup | custodians | `lib/std/misc/custodian.sls` |

---

## What's NOT in scope

- **Work stealing**: The current run-queue is a single shared FIFO. A per-worker deque with stealing (like `actor/scheduler.sls`) would improve cache locality under heavy load, but the current design works well up to ~10K fibers. Optimize later if profiling shows contention.
- **Fiber migration**: Moving a parked fiber from one worker to another. Engine continuations are not trivially portable across threads in Chez. Not needed for correctness, only for load balancing (which work-stealing would address).
- **Async I/O integration**: Tying fiber parking to epoll/kqueue so that file/socket readiness wakes a fiber. This is a large project (essentially an event loop runtime) and orthogonal to the gaps above.
