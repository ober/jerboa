# Algebraic Effects — `(std effect)`

**Source:** `lib/std/effect.sls`

---

## Table of Contents

1. [Overview](#1-overview)
2. [Core API](#2-core-api)
3. [How It Works](#3-how-it-works)
4. [Examples](#4-examples)
5. [Combining Effects](#5-combining-effects)
6. [Common Patterns](#6-common-patterns)
7. [Limitations](#7-limitations)
8. [Integration with Async](#8-integration-with-async)

---

## 1. Overview

Algebraic effects are a structured mechanism for writing code that performs side effects — I/O, state, non-determinism, early exit, generators — while keeping the *definition* of the effect separate from its *interpretation*.

A piece of code performs an effect by name. A handler somewhere up the call stack intercepts the operation and decides what to do, including whether to resume the code where it left off. This is the critical difference from exceptions:

| Mechanism | Can resume after handling? | Caller decides behavior? |
|-----------|---------------------------|--------------------------|
| Exceptions (`raise`/`guard`) | No — stack is unwound | No — callee raises a fixed type |
| Callbacks | N/A — caller provides the hook | Yes, but via inversion of control |
| **Effects** | **Yes — `resume k val`** | **Yes — handler is separate from performer** |

### Why effects are better than callbacks

Consider a generator. With callbacks you either push (the generator calls you) or pull (you call the generator through a closure). Both approaches tangle the generator logic with its consumer. With effects, the generator body reads like normal sequential code calling `(Yield yield item)`, and the consumer's `with-handler` wraps around it, collecting items as they arrive. The body has no idea whether the handler will collect all values, take only a few, or abort early.

### Why effects are better than exceptions for control flow

Exceptions cannot return a value to the point where `raise` was called. An effect handler can call `(resume k 42)` to inject the value `42` back at the `perform` site, continuing execution as if the operation had returned `42` normally. This enables patterns like "ask the handler for the current value of a mutable cell" without any shared mutable state inside the computation itself.

---

## 2. Core API

```scheme
(import (chezscheme) (std effect))
```

---

### `defeffect`

```
(defeffect EffectName (op-name arg ...) ...)
```

Defines an effect named `EffectName` with one or more operations. This macro produces:

- `EffectName::descriptor` — a unique `effect-descriptor` value identifying this effect. You rarely need to use this directly, but it is exported for advanced use (e.g., inspecting conditions, building handlers programmatically).
- `EffectName` — a syntax transformer. Writing `(EffectName op-name arg ...)` performs the named operation with the given arguments.

**Example:**

```scheme
(defeffect State
  (get)
  (put val))

; Now (State get) and (State put 42) are valid perform expressions.
```

Each operation name is a symbol. Arguments listed in the operation clause are the arguments that callers pass at perform time. The handler receives them after the continuation `k`.

---

### `perform`

```
(perform expr)
```

`perform` is a thin syntax alias that passes its argument through unchanged. Its purpose is readability: writing `(perform (State get))` signals to the reader that this expression is an effect operation, not a plain function call.

```scheme
(perform (State get))      ; same as (State get)
(perform (Log emit "hi"))  ; same as (Log emit "hi")
```

---

### `with-handler`

```
(with-handler
  ([EffectName
    (op-name (k arg ...) body ...)
    ...]
   ...)
  body ...)
```

Installs handlers for one or more effects for the duration of `body ...`. Each operation clause:

- `op-name` — the operation to handle (must match one defined in `defeffect`).
- `(k arg ...)` — `k` is the one-shot continuation captured at the `perform` site; `arg ...` are the values passed by the performer.
- `body ...` — handler body. To continue the computation, call `(resume k val)`. To abort, do not call `resume`.

Multiple effects can be handled in a single `with-handler` form by listing multiple `[EffectName ...]` clauses.

Handlers are scoped to the dynamic extent of `body ...`. When the body returns normally, the handler frame is popped.

**Example — two effects in one handler:**

```scheme
(with-handler
  ([State
    (get (k) (resume k current-state))
    (put (k v) (set! current-state v) (resume k (void)))]
   [Log
    (emit (k msg) (set! log-list (cons msg log-list)) (resume k (void)))])
  ... body ...)
```

---

### `resume`

```
(resume k val)
```

Invokes the one-shot continuation `k` with the value `val`, resuming the computation at the `perform` site. The call to `resume` does not return to the handler body — control passes directly back into the resumed computation.

Because `k` is a one-shot continuation (created by `call/1cc`), calling `resume` more than once on the same `k` is an error. See [Limitations](#7-limitations).

---

### `run-with-handler`

```
(run-with-handler frame thunk)
```

Lower-level procedure. Installs an already-constructed handler frame (an `eq-hashtable` mapping `effect-descriptor` to operation alist) and calls `thunk`. The `with-handler` macro compiles down to a call to `run-with-handler`. You only need this directly when building handler frames programmatically.

---

### `effect-not-handled?`

```
(effect-not-handled? obj) => boolean
```

Predicate for the `&effect-not-handled` condition type. When an effect operation is performed and no handler is found anywhere on the dynamic handler stack, a compound condition is raised containing:

- A `&message` with the text `"effect not handled: EffectName/op-name"`.
- An `&effect-not-handled` field with the `effect-descriptor` and operation symbol.
- An `&irritants` field with `(op-name arg ...)`.

Use `guard` to catch unhandled effects:

```scheme
(guard (exn [(effect-not-handled? exn)
             (display "no handler installed\n")])
  (MyEffect some-op))
```

---

### `*effect-handlers*`

```
(*effect-handlers*) => list
```

Thread-local parameter holding the current handler stack as a list of `eq-hashtable` frames. Each `with-handler` form pushes a new frame at the front for the duration of its body. You rarely need to read this directly, but it is exported so that advanced use cases (like manually saving and restoring the handler environment) are possible.

---

## 3. How It Works

### Effect descriptors

`defeffect` creates a single `effect-descriptor` record (a sealed record with one field: the effect's name symbol). This record is allocated once at module load time and is used as an `eq?`-comparable identity token.

### Handler stack

The global handler stack lives in `*effect-handlers*`, a thread-local parameter (Chez Scheme's `make-thread-parameter`). Each `with-handler` form creates an `eq-hashtable` frame mapping `effect-descriptor -> alist-of-(op-sym . handler-proc)`. `with-handler` uses `parameterize` to push the frame for the dynamic extent of its body, which is safe even in the presence of threads and unwind forms.

### Dispatch — O(1)

When `effect-perform` is called, it walks the handler stack (a list of frames). For each frame it does an `eq-hashtable-ref` lookup keyed on the descriptor — O(1) per frame. It then does an `assq` on the operation alist within that frame. Because the alist is short (one entry per operation in the effect), this is effectively O(1) in practice. Finding the right frame is O(depth-of-nested-handlers), which is typically small.

### One-shot continuations

`effect-perform` uses `call/1cc` (Chez Scheme's one-shot continuation operator) rather than the general `call/cc`. One-shot continuations are significantly cheaper: they do not need to copy the stack, only capture a pointer to the current continuation frame chain. The trade-off is that each captured continuation may only be invoked once.

### Parameterize and thread safety

Because `*effect-handlers*` is a thread-local parameter, each OS thread has its own handler stack. Spawning a new OS thread starts with an empty stack. The `(std async)` library's spawn handler explicitly re-installs handlers in the new thread's context. See [Integration with Async](#8-integration-with-async).

---

## 4. Examples

All examples use:

```scheme
(import (chezscheme) (std effect))
```

### 4.1 Early Return / Abort

An abort effect lets inner code short-circuit its containing computation without exceptions. Unlike `raise`, the handler can inspect the value and decide where control goes.

```scheme
(defeffect Abort
  (abort val))

; Returns 'done without reaching 'never-reached.
(call-with-current-continuation
  (lambda (escape)
    (with-handler
      ([Abort
        (abort (k v) (escape v))])   ; don't resume — just escape
      (Abort abort 'done)
      'never-reached)))
; => done

; Abort partway through a loop.
(define (find-first pred lst)
  (call-with-current-continuation
    (lambda (return)
      (with-handler
        ([Abort
          (abort (k v) (return v))])
        (for-each (lambda (x)
                    (when (pred x)
                      (Abort abort x)))
                  lst)
        #f))))  ; not found

(find-first even? '(1 3 5 4 7))  ; => 4
(find-first even? '(1 3 5))      ; => #f
```

Note that the abort handler does not call `resume`. The continuation `k` is simply discarded — the remaining computation is abandoned.

### 4.2 Generator / Iterator (Yield)

A yield effect turns a producer body into a lazy sequence. The producer calls `(Yield yield item)` each time it has a value; the handler decides what to do with the item and whether to ask for more.

```scheme
(defeffect Yield
  (yield val))

; Collect all yielded values into a list.
(define (collect-yields thunk)
  (let ([results '()])
    (with-handler
      ([Yield
        (yield (k v)
          (set! results (append results (list v)))
          (resume k (void)))])   ; ask producer for the next item
      (thunk))
    results))

; The producer body — looks like normal sequential code.
(define (range-producer lo hi)
  (let loop ([i lo])
    (when (< i hi)
      (Yield yield i)
      (loop (+ i 1)))))

(collect-yields (lambda () (range-producer 0 5)))
; => (0 1 2 3 4)

; Take only the first N yields — abort the rest.
(define (take-yields n thunk)
  (let ([results '()] [count 0])
    (call-with-current-continuation
      (lambda (done)
        (with-handler
          ([Yield
            (yield (k v)
              (set! results (append results (list v)))
              (set! count (+ count 1))
              (if (= count n)
                (done results)      ; stop — don't resume
                (resume k (void))))])
          (thunk))))
    results))

(take-yields 3 (lambda () (range-producer 0 100)))
; => (0 1 2)
```

### 4.3 Logging Effect

A logging effect intercepts log calls without changing the return value of the body. The handler stores messages and then resumes the computation transparently.

```scheme
(defeffect Log
  (emit msg))

; Capture all log messages; return (values body-result messages).
(define (with-log-capture thunk)
  (let ([messages '()])
    (let ([result
           (with-handler
             ([Log
               (emit (k msg)
                 (set! messages (append messages (list msg)))
                 (resume k (void)))])   ; resume with void — caller ignores it
             (thunk))])
      (values result messages))))

(define-values (result log)
  (with-log-capture
    (lambda ()
      (Log emit "starting computation")
      (let ([x (* 6 7)])
        (Log emit (string-append "result is " (number->string x)))
        x))))

result  ; => 42
log     ; => ("starting computation" "result is 42")

; Alternatively, suppress all logging in production.
(define (with-silent-log thunk)
  (with-handler
    ([Log (emit (k msg) (resume k (void)))])   ; discard message, resume
    (thunk)))
```

### 4.4 State Effect

The state effect threads a mutable cell through pure code without passing it as an argument or using a top-level variable.

```scheme
(defeffect State
  (get)
  (put val))

; Interpret the state effect by closing over a mutable variable.
(define (run-state initial thunk)
  (let ([cell initial])
    (with-handler
      ([State
        (get (k)   (resume k cell))
        (put (k v) (set! cell v) (resume k (void)))])
      (thunk))))

; Stateful counter — body has no knowledge of how state is stored.
(run-state 0
  (lambda ()
    (State put (+ (State get) 1))
    (State put (+ (State get) 1))
    (State put (+ (State get) 1))
    (State get)))
; => 3

; State accumulator — build a result list.
(define (run-accumulator thunk)
  (let ([acc '()])
    (with-handler
      ([State
        (get (k) (resume k acc))
        (put (k v) (set! acc (cons v acc)) (resume k (void)))])
      (thunk)
      (reverse acc))))

(run-accumulator
  (lambda ()
    (State put 10)
    (State put 20)
    (State put 30)))
; => (10 20 30)
```

### 4.5 Exception Handling Comparison

This example shows why effects are better than exceptions for recoverable errors. With `raise`/`guard`, you cannot supply a default value back to the raise site. With effects you can.

**With exceptions (caller cannot recover inline):**

```scheme
; lookup must either return a value or raise — no way to ask caller for a default.
(define (lookup key alist)
  (let ([pair (assq key alist)])
    (if pair
      (cdr pair)
      (error "lookup" "key not found" key))))

; Caller wraps in guard, but loses the original computation context.
(guard (exn [#t 'default-value])
  (lookup 'missing '((a . 1) (b . 2))))
; => default-value (but we're out of context now)
```

**With effects (handler injects the default at the call site):**

```scheme
(defeffect Missing
  (key-not-found key))

(define (lookup/effect key alist)
  (let ([pair (assq key alist)])
    (if pair
      (cdr pair)
      (Missing key-not-found key))))   ; asks handler what to return

; Handler provides a default — computation continues with that value.
(with-handler
  ([Missing
    (key-not-found (k key)
      (resume k 'default-value))])    ; inject default at the call site
  (let* ([a (lookup/effect 'a '((a . 1) (b . 2)))]
         [z (lookup/effect 'z '((a . 1) (b . 2)))]  ; missing — gets default
         [b (lookup/effect 'b '((a . 1) (b . 2)))])
    (list a z b)))
; => (1 default-value 2)
; The entire let* completes — not aborted.
```

---

## 5. Combining Effects

A single `with-handler` form can handle multiple effects simultaneously. The inner body may perform any mix of operations from any of the listed effects.

```scheme
(defeffect State  (get) (put val))
(defeffect Log    (emit msg))
(defeffect Abort  (abort val))

(define (run-with-state-log-abort initial thunk)
  (let ([cell initial] [messages '()])
    (call-with-current-continuation
      (lambda (escape)
        (with-handler
          ([State
            (get (k)   (resume k cell))
            (put (k v) (set! cell v) (resume k (void)))]
           [Log
            (emit (k msg)
              (set! messages (cons msg messages))
              (resume k (void)))]
           [Abort
            (abort (k v) (escape (list 'aborted v messages)))])
          (let ([result (thunk)])
            (list 'ok result (reverse messages) cell)))))))

(run-with-state-log-abort 0
  (lambda ()
    (Log emit "step 1")
    (State put 10)
    (Log emit "step 2")
    (State put (+ (State get) 5))
    (State get)))
; => (ok 15 ("step 1" "step 2") 15)

(run-with-state-log-abort 0
  (lambda ()
    (Log emit "before abort")
    (State put 99)
    (Abort abort 'early-exit)
    (Log emit "never reached")))
; => (aborted early-exit ("before abort"))
```

### Nested handlers

Handlers can be nested. The innermost handler for an effect wins. Once the inner handler's body exits, the outer handler resumes responsibility.

```scheme
(defeffect Counter (tick))

(with-handler ([Counter (tick (k) (resume k 'outer))])
  (let ([from-inner
         (with-handler ([Counter (tick (k) (resume k 'inner))])
           (Counter tick))])        ; handled by inner => 'inner
    (list from-inner (Counter tick))))  ; outer takes over => 'outer
; => (inner outer)
```

This is how libraries can install default handlers while application code installs overrides.

---

## 6. Common Patterns

### Pattern: run-X wrapping thunk

The standard idiom is a `run-X` procedure that installs handlers and executes a thunk.

```scheme
(define (run-state initial thunk)
  (let ([cell initial])
    (with-handler
      ([State
        (get (k)   (resume k cell))
        (put (k v) (set! cell v) (resume k (void)))])
      (thunk))))
```

Callers pass a zero-argument lambda:

```scheme
(run-state 0 (lambda ()
  (State put (+ (State get) 1))
  (State get)))
; => 1
```

### Pattern: Effect as circuit breaker

Perform an abort effect when a resource limit is exceeded, without exceptions that would unwind useful context.

```scheme
(defeffect Budget (exceeded amount))

(define (with-budget limit thunk)
  (let ([spent 0])
    (define (spend! n)
      (set! spent (+ spent n))
      (when (> spent limit)
        (Budget exceeded spent)))
    ; return both the thunk result and total spent
    (call-with-current-continuation
      (lambda (escape)
        (with-handler
          ([Budget
            (exceeded (k total)
              (escape (list 'budget-exceeded total)))])
          (list 'ok (thunk spend!) spent))))))

(with-budget 100 (lambda (spend!)
  (spend! 30)
  (spend! 50)
  (spend! 10)
  'done))
; => (ok done 90)

(with-budget 100 (lambda (spend!)
  (spend! 30)
  (spend! 80)   ; exceeds 100
  'unreachable))
; => (budget-exceeded 110)
```

### Pattern: Dependency injection via effects

Instead of passing a database connection or configuration through every function call, define an effect for it. Any code in the handler's dynamic extent can access the dependency.

```scheme
(defeffect Config (read-key key))

(define (with-config-map table thunk)
  (with-handler
    ([Config
      (read-key (k key)
        (resume k (hashtable-ref table key #f)))])
    (thunk)))

; Deep inside application logic — no config arg needed.
(define (build-greeting)
  (let ([name (Config read-key 'user-name)]
        [lang (Config read-key 'language)])
    (if (equal? lang "es")
      (string-append "Hola, " (or name "world") "!")
      (string-append "Hello, " (or name "world") "!"))))

(let ([cfg (make-eq-hashtable)])
  (hashtable-set! cfg 'user-name "Alice")
  (hashtable-set! cfg 'language "es")
  (with-config-map cfg build-greeting))
; => "Hola, Alice!"
```

### Pattern: Catching unhandled effects

Always guard against unhandled effects at the top of a program or test runner so you get a meaningful error rather than an unspecified condition object.

```scheme
(guard (exn
        [(effect-not-handled? exn)
         (fprintf (current-error-port)
           "Unhandled effect: ~a\n"
           (condition-message exn))])
  (run-my-program))
```

---

## 7. Limitations

### One-shot continuations

The fundamental restriction of `(std effect)` is that every captured continuation `k` is one-shot: **it can only be invoked once**. Calling `(resume k val)` a second time on the same `k` has undefined behavior — Chez Scheme's `call/1cc` does not protect against this.

Practical consequences:

- **Cannot implement multi-shot nondeterminism.** A true backtracking `Choose` effect (resuming `k` with both `#t` and `#f` to collect all paths) is not possible. The one-shot `Choose` in the tests returns only one branch.
- **Cannot memoize continuations.** Storing `k` in a data structure and replaying it later will corrupt the runtime.
- **Cannot implement coroutines with `resume` called from multiple sites.** Each `k` is consumed by the first `resume`.

If you need multi-shot continuations, you must use Chez Scheme's general `call-with-current-continuation` (`call/cc`) and build a different dispatch mechanism. The trade-off is cost: general continuations copy the full stack.

### No built-in effect signatures

`defeffect` does not enforce that a handler handles all declared operations. If you define `(defeffect Foo (bar) (baz))` but only handle `bar` in `with-handler`, a `(Foo baz)` call will walk up the stack looking for a handler and raise `&effect-not-handled` if none is found.

### Handler must be in the dynamic extent

Handlers only intercept performs that occur while the `with-handler` body is executing. A thunk that captures an effect call and invokes it after the handler exits will get an unhandled-effect error (or find an outer handler, if one exists).

### Thread boundaries

`*effect-handlers*` is a thread-local parameter. Effects performed in a new OS thread (spawned via `fork-thread`) cannot be caught by a handler installed in the parent thread. Each thread must install its own handlers. The `(std async)` library handles this automatically for tasks spawned with `(Async spawn thunk)`.

---

## 8. Integration with Async

The `(std async)` library (`lib/std/async.sls`) is built directly on top of `(std effect)`. The `Async` effect is defined using `defeffect`:

```scheme
(defeffect Async
  (await promise)
  (spawn thunk)
  (sleep ms))
```

`run-async` installs handlers for all three operations using `with-handler`. The handlers use OS-level thread blocking rather than continuation storage:

- `(await (k promise) ...)` — blocks the current OS thread with a mutex/condition until the promise resolves, then calls `(resume k value)` to return the resolved value to the `await` call site.
- `(spawn (k thunk) ...)` — calls `fork-thread` to start a new OS thread with its own copy of the `Async` handlers, then immediately resumes `k` with `(void)` (spawn is non-blocking for the caller).
- `(sleep (k ms) ...)` — calls Chez Scheme's `sleep` procedure on the current thread, then resumes `k` with `(void)`.

This design means async code written as:

```scheme
(run-async (lambda ()
  (let ([p (async-task (lambda ()
                         (async-sleep 100)
                         42))])
    (Async await p))))
```

...reads as ordinary sequential Scheme. The effect system handles all the suspension and resumption machinery. The `Async` body has no callbacks, no explicit continuation threading, and no distinction between synchronous and asynchronous calls at the syntax level.

### Replacing the async interpreter

Because the async behavior is entirely in the handler, you can swap interpretations. For testing, you could install a synchronous stub handler that runs all `spawn` thunks eagerly and satisfies all `await` calls immediately from a pre-populated table — without changing any async application code.

```scheme
; Synchronous test interpreter for Async (sketch)
(define (run-async-sync thunk)
  (with-handler
    ([Async
      (await (k promise)
        ; In a real stub: look up pre-seeded result
        (resume k (async-promise-value promise)))
      (spawn (k task-thunk)
        ; Run inline before resuming
        (task-thunk)
        (resume k (void)))
      (sleep (k ms)
        ; Skip sleep in tests
        (resume k (void)))])
    (thunk)))
```

This is the composability benefit of effects: the interpreter is a first-class, replaceable component.
