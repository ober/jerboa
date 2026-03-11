# Software Transactional Memory in Jerboa

`(std stm)` provides optimistic concurrency through transactional variables
(TVars). Transactions execute speculatively, validate their read-set at
commit time, and automatically retry on conflict — all without requiring the
programmer to acquire or release locks.

---

## Overview

Traditional lock-based concurrency is error-prone: locks must be acquired in
a consistent order to avoid deadlock, held for the right duration to avoid
races, and released even when exceptions occur. STM eliminates these problems
by treating shared state mutations as database transactions:

1. A thread **reads** TVars freely during a transaction. First reads are
   timestamped.
2. Writes are buffered in a **write-set** private to the thread.
3. At the end of `atomically`, the runtime acquires the **global commit
   mutex** and validates that every TVar read during the transaction still
   has the same version number it had at the time of the first read.
4. If valid, writes are applied atomically and version counters are
   incremented. A broadcast on the commit condition variable wakes any
   threads blocked in `retry`.
5. If any version has changed (conflict), the entire transaction is discarded
   and re-run from the beginning.

**Key properties:**

- **Composable**: two atomic operations can be composed into a larger atomic
  operation simply by nesting or sequencing inside `atomically`.
- **Deadlock-free**: there are no locks for application code to acquire; only
  the internal commit mutex is used, and it is held only for the validation
  and write phase.
- **No explicit cleanup**: exceptions inside a transaction leave no partial
  state behind. The write-set is simply discarded.

---

## Importing the Library

```scheme
(import (std stm))
```

---

## Core API

### `make-tvar` — create a transactional variable

```scheme
(make-tvar init) => tvar
```

Creates a new TVar holding `init` as its initial committed value with version
`0`.

```scheme
(define balance (make-tvar 1000))
(define inventory (make-tvar '()))
```

---

### `tvar?` — predicate

```scheme
(tvar? x) => boolean
```

Returns `#t` if `x` is a TVar.

---

### `tvar-ref` — read outside a transaction

```scheme
(tvar-ref tv) => value
```

Reads the current committed value of `tv` without starting a transaction.
Useful for observation and debugging. **Do not use inside `atomically`** —
use `tvar-read` instead, or the read will not be recorded in the
transaction's read-set and conflicts will go undetected.

```scheme
(display (tvar-ref balance))   ; safe outside transactions
```

---

### `atomically` — run a transaction

```scheme
(atomically body ...) => value
```

Evaluates `body ...` as a single atomic transaction and returns the value of
the last expression. The body runs speculatively: if the transaction
conflicts with a concurrent commit it is re-run automatically. If the body
calls `retry`, the thread blocks until at least one TVar in its read-set is
modified by another transaction, then re-runs.

**Nesting**: if `atomically` is called while already inside a transaction the
inner call flattens into the enclosing transaction — all reads and writes
participate in the same commit.

```scheme
(atomically
  (let ([bal (tvar-read balance)])
    (tvar-write! balance (- bal amount))))
```

---

### `tvar-read` — transactional read

```scheme
(tvar-read tv) => value
```

Reads `tv` inside a transaction. On the first read of a TVar the current
version is snapshotted into the transaction's read-set. Subsequent reads of
the same TVar return the current committed value (consistency is enforced at
commit time, not per-read). If the TVar has been written in the current
transaction, the buffered value is returned instead.

Called outside a transaction, `tvar-read` behaves like `tvar-ref` (direct
read, no recording).

---

### `tvar-write!` — transactional write

```scheme
(tvar-write! tv val)
```

Buffers a write to `tv` in the current transaction's write-set. The actual
committed value is not changed until the transaction commits successfully.
Multiple writes to the same TVar within one transaction are coalesced: only
the last write is applied.

Called outside a transaction, `tvar-write!` writes directly with the commit
mutex held and broadcasts on the condition variable.

---

### `retry` — block until something changes

```scheme
(retry)
```

Aborts the current transaction and blocks the calling thread until at least
one TVar that was read during this transaction is modified by another
committed transaction. The thread then re-runs the transaction from the
beginning.

`retry` is the STM equivalent of a condition wait, but it is entirely
declarative: you express _when_ to retry (a guard condition is not yet
satisfied) and the runtime figures out _what_ to wait for (the TVars whose
state determines the condition).

```scheme
(define (dequeue! q)
  (atomically
    (let ([items (tvar-read q)])
      (if (null? items)
        (retry)                          ; block until queue is non-empty
        (begin
          (tvar-write! q (cdr items))
          (car items))))))
```

---

### `or-else` — alternative on retry

```scheme
(or-else expr1 expr2)
```

Evaluates `expr1`. If `expr1` calls `retry`, evaluates `expr2` instead.
Both expressions run within the same enclosing transaction if one is active.
`or-else` allows you to try multiple strategies in priority order, falling
back gracefully when none is immediately satisfiable.

```scheme
(define (dequeue-any! high-priority-q low-priority-q)
  (atomically
    (or-else
      (dequeue-inner! high-priority-q)   ; try high-priority first
      (dequeue-inner! low-priority-q)))) ; fall back to low-priority
```

---

## How It Works Internally

### TVar structure

Each TVar holds:
- `stm-value`: the current committed value
- `stm-version`: a monotonically increasing integer, incremented on every
  successful write

### Transaction record

Each transaction maintains:
- `tx-read-set`: association list of `(tvar . version-at-first-read)`
- `tx-write-set`: association list of `(tvar . new-value)`

The read-set records the version seen the first time each TVar is read. The
write-set buffers pending writes.

### Commit protocol

1. Acquire `*commit-mutex*` (single global mutex).
2. Walk the read-set. For each entry, compare the TVar's current version
   against the snapshotted version. If any has changed: **conflict** —
   release mutex, discard state, re-run.
3. If all versions match: apply the write-set. For each written TVar,
   update `stm-value` and increment `stm-version`.
4. If any writes were applied, broadcast on `*commit-cond*` to wake threads
   blocked in `retry`.
5. Release the mutex.

### Retry blocking

When `retry` is called:
1. The `&stm-retry` condition is raised.
2. `atomically` catches it, acquires the commit mutex, and calls
   `condition-wait` on `*commit-cond*`.
3. When any transaction commits with writes, `condition-broadcast` wakes all
   waiting threads.
4. The thread re-acquires the mutex, releases it, and re-runs the entire
   transaction.

This is a coarse wake-up: all threads sleeping in `retry` wake when _any_
TVar changes, even one they did not read. The transaction's own guard will
simply call `retry` again if the relevant TVar still has an unsatisfactory
value, and the thread will sleep again.

---

## Complete Examples

### Bank account transfer

A classic problem: transfer funds between two accounts atomically. Without
STM this requires careful lock ordering. With STM you just read and write.

```scheme
(import (chezscheme) (std stm))

(define account-a (make-tvar 500))
(define account-b (make-tvar 300))

(define (transfer! from to amount)
  (atomically
    (let ([from-bal (tvar-read from)])
      (when (< from-bal amount)
        (error 'transfer! "insufficient funds" from-bal amount))
      (tvar-write! from (- from-bal amount))
      (tvar-write! to   (+ (tvar-read to) amount)))))

(transfer! account-a account-b 200)
(display (tvar-ref account-a))   ; => 300
(display (tvar-ref account-b))   ; => 500
```

The read of `from` and the read of `to` are both in the same transaction's
read-set. If another thread modifies either account concurrently, the commit
will fail and the entire transfer re-runs — the accounts are always
consistent.

---

### Bounded queue with STM

A thread-safe bounded queue where producers block when full and consumers
block when empty.

```scheme
(import (chezscheme) (std stm))

(define (make-stm-queue capacity)
  (cons (make-tvar '())         ; items (as a list)
        (make-tvar capacity)))  ; remaining capacity

(define (queue-push! q item)
  (let ([items-tv (car q)]
        [cap-tv   (cdr q)])
    (atomically
      (let ([cap (tvar-read cap-tv)])
        (when (fxzero? cap)
          (retry))                           ; block until space is available
        (tvar-write! items-tv (append (tvar-read items-tv) (list item)))
        (tvar-write! cap-tv   (fx- cap 1))))))

(define (queue-pop! q)
  (let ([items-tv (car q)]
        [cap-tv   (cdr q)])
    (atomically
      (let ([items (tvar-read items-tv)])
        (when (null? items)
          (retry))                           ; block until item is available
        (tvar-write! items-tv (cdr items))
        (tvar-write! cap-tv   (fx+ (tvar-read cap-tv) 1))
        (car items)))))

;; Usage
(define q (make-stm-queue 10))

(fork-thread (lambda ()
  (let loop ([i 0])
    (queue-push! q i)
    (loop (+ i 1)))))

(fork-thread (lambda ()
  (let loop ()
    (display (queue-pop! q))
    (loop))))
```

---

### Dining philosophers without deadlock

The classic dining philosophers problem has no deadlock with STM because
there are no locks to acquire in order.

```scheme
(import (chezscheme) (std stm))

;; Five forks; each TVar holds #t = in use, #f = available
(define fork-count 5)
(define forks-tv (map make-tvar (make-list fork-count #f)))

(define (pick-up-forks! i)
  (let ([left  (list-ref forks-tv i)]
        [right (list-ref forks-tv (modulo (+ i 1) fork-count))])
    (atomically
      (when (or (tvar-read left) (tvar-read right))
        (retry))                   ; both must be available simultaneously
      (tvar-write! left  #t)
      (tvar-write! right #t))))

(define (put-down-forks! i)
  (let ([left  (list-ref forks-tv i)]
        [right (list-ref forks-tv (modulo (+ i 1) fork-count))])
    (atomically
      (tvar-write! left  #f)
      (tvar-write! right #f))))

(define (philosopher i)
  (let loop ()
    (pick-up-forks! i)
    (display (string-append "Philosopher " (number->string i) " eating\n"))
    (put-down-forks! i)
    (loop)))

(for-each (lambda (i) (fork-thread (lambda () (philosopher i))))
          '(0 1 2 3 4))
```

No deadlock is possible: `retry` inside `pick-up-forks!` blocks until
_both_ forks are simultaneously available, and the runtime handles the
waiting without any locks in application code.

---

### Priority scheduling with `or-else`

```scheme
(import (chezscheme) (std stm))

(define urgent-queue  (make-tvar '()))
(define normal-queue  (make-tvar '()))

(define (enqueue! tv item)
  (atomically (tvar-write! tv (append (tvar-read tv) (list item)))))

(define (dequeue-inner! tv)
  ;; Must be called inside an enclosing atomically
  (let ([items (tvar-read tv)])
    (if (null? items)
      (retry)
      (begin (tvar-write! tv (cdr items)) (car items)))))

(define (next-task!)
  (atomically
    (or-else
      (dequeue-inner! urgent-queue)   ; always prefer urgent work
      (dequeue-inner! normal-queue))))

;; If urgent-queue is empty, dequeue-inner! calls retry and or-else
;; falls through to normal-queue. If both are empty, the whole
;; next-task! call blocks until either queue has an item.
```

---

## Performance

### When STM shines

- **Low contention**: when threads rarely conflict, transactions commit on
  the first attempt and the overhead is one read-set validation pass plus a
  mutex acquisition. For workloads with few writers and many readers this
  is very efficient.
- **Composability**: combining two independently correct atomic operations
  into a larger atomic operation requires no redesign. With locks you would
  need to expose and coordinate the internal locks, risking deadlock.
- **Complex multi-variable invariants**: maintaining invariants across
  several TVars is natural — either all writes commit or none do.

### When to prefer traditional locking

- **High contention with large write-sets**: when many threads frequently
  write to the same TVars, conflict rates rise and transactions must re-run
  repeatedly. A dedicated mutex or channel may perform better.
- **Very tight inner loops**: the read-set allocation (an assoc list) adds
  GC pressure. For sub-microsecond hot paths, fixnum-only `mutex` sections
  may be faster.
- **Write-heavy single-variable updates**: if you are just atomically
  incrementing a counter, a `mutex`-guarded increment is simpler and
  marginally faster than a full transaction.

---

## Pitfalls

### Side effects inside transactions

Transactions may run **more than once**. Any side effect in the body —
printing, writing to a file, sending a network packet — will be repeated on
each retry. Place side effects after `atomically` returns, not inside it.

```scheme
;; WRONG: display may run multiple times
(atomically
  (display "withdrawing...")      ; runs on every retry
  (tvar-write! balance (- (tvar-read balance) amount)))

;; CORRECT: side effect after the transaction
(atomically
  (tvar-write! balance (- (tvar-read balance) amount)))
(display "withdrawal complete")
```

### `tvar-ref` inside transactions

Using `tvar-ref` inside `atomically` bypasses the read-set recording. The
value is read from committed state but the version is not snapshotted, so
conflicting concurrent writes will not be detected at commit time. Always use
`tvar-read` inside transactions.

```scheme
;; WRONG: conflict on balance will not be caught
(atomically
  (let ([bal (tvar-ref balance)])   ; not recorded in read-set!
    (tvar-write! balance (- bal 10))))

;; CORRECT
(atomically
  (let ([bal (tvar-read balance)])
    (tvar-write! balance (- bal 10))))
```

### Infinite retry loops

If the condition guarded by `retry` can never become true, the thread will
block forever. Ensure that some other thread can plausibly modify the TVars
in the read-set and satisfy the guard.

### Coarse-grained wakeup

All threads sleeping in `retry` are woken whenever any transaction commits
with writes, not just those waiting for the specific TVars they read.
High-contention systems with many `retry`-blocked threads may see spurious
wakeups. Each spurious wakeup results in a transaction re-run that calls
`retry` again, so correctness is not affected — only efficiency. For very
large numbers of blocked threads, consider partitioning TVars into smaller
groups or using more targeted condition variables.

### `or-else` and write-set accumulation

Both branches of `or-else` run within the same enclosing transaction if
one exists. Writes buffered by a branch that subsequently calls `retry` are
_not_ rolled back before the alternative branch runs. Design `or-else`
branches to be independent or idempotent with respect to their writes.
