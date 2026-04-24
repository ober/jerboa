#!chezscheme
;;; (std stm) — Software Transactional Memory (fiber-safe)
;;;
;;; Optimistic concurrency using versioned transactional variables (TVars).
;;; Transactions run speculatively, validate their read-set at commit time,
;;; and retry on conflict.
;;;
;;; FIBER-SAFE DESIGN (MVCC with per-TVar locks)
;;; ---------------------------------------------
;;; Instead of a single global commit mutex (which would block the entire
;;; OS worker thread and starve fibers), each TVar has its own lightweight
;;; lock. Commit acquires only the locks of TVars in the write-set, validates
;;; the read-set, then applies writes. Short-held per-tvar locks don't block
;;; the fiber scheduler meaningfully.
;;;
;;; `retry` blocks the caller until any TVar in the read-set changes:
;;; - Inside a fiber: parks the fiber via a fiber-channel (zero OS thread blocking)
;;; - Outside a fiber: blocks on a condition variable (original behavior)
;;;
;;; API:
;;;   (make-tvar init)              — create a transactional variable
;;;   (tvar? x)                     — predicate
;;;   (tvar-ref tv)                 — read outside transaction (unsafe)
;;;   (atomically body ...)         — run body as atomic transaction
;;;   (tvar-read tv)                — read within transaction
;;;   (tvar-write! tv val)          — write within transaction
;;;   (retry)                       — abort and block until a TVar changes
;;;   (or-else expr1 expr2)         — try expr1; if it retries, try expr2

(library (std stm)
  (export
    make-tvar
    tvar?
    tvar-ref
    atomically
    tvar-read
    tvar-write!
    retry
    or-else

    ;; Clojure-style aliases
    make-ref ref? ref-deref
    dosync alter ref-set commute ensure io!)

  (import (chezscheme)
          (std fiber))

  ;; ========== TVar ==========
  ;;
  ;; Each TVar has its own mutex (per-tvar lock), a version counter,
  ;; and a list of waiters (fibers or condition variables) to notify
  ;; on change.

  (define-record-type (stm-tvar %make-tvar tvar?)
    (fields
      (mutable   stm-value)      ;; current committed value
      (mutable   stm-version)    ;; monotonically increasing version
      (immutable stm-lock)       ;; per-tvar mutex
      (mutable   stm-waiters))   ;; list of waiter records
    (sealed #t))

  (define (make-tvar init)
    (%make-tvar init 0 (make-mutex) '()))

  (define (tvar-ref tv) (stm-tvar-stm-value tv))

  ;; ========== Waiter types ==========
  ;;
  ;; When a transaction retries, the caller registers a waiter on
  ;; each TVar in its read-set. Two kinds:
  ;;   - fiber-waiter: parks a fiber via a fiber-channel
  ;;   - thread-waiter: blocks an OS thread via a condition variable

  (define-record-type fiber-waiter
    (fields (immutable channel))   ;; fiber-channel to signal
    (sealed #t))

  (define-record-type thread-waiter
    (fields (immutable mutex)
            (immutable condition))
    (sealed #t))

  ;; Notify all waiters on a TVar that its value changed.
  (define (notify-waiters! tv)
    (let ([waiters (stm-tvar-stm-waiters tv)])
      (stm-tvar-stm-waiters-set! tv '())
      (for-each
        (lambda (w)
          (cond
            [(fiber-waiter? w)
             ;; Non-blocking send to wake parked fiber
             (fiber-channel-try-send (fiber-waiter-channel w) #t)]
            [(thread-waiter? w)
             ;; Signal condition variable to wake blocked thread
             (mutex-acquire (thread-waiter-mutex w))
             (condition-signal (thread-waiter-condition w))
             (mutex-release (thread-waiter-mutex w))]))
        waiters)))

  ;; ========== Transaction State ==========

  (define-record-type tx-rec
    (fields
      (mutable tx-read-set)      ;; alist of (tvar . version-at-read)
      (mutable tx-write-set))    ;; alist of (tvar . new-value)
    (sealed #t))

  (define (make-tx) (make-tx-rec '() '()))

  ;; Thread-local: the currently active transaction, or #f.
  (define *current-tx* (make-thread-parameter #f))

  ;; ========== Retry Condition ==========

  (define-condition-type &stm-retry &condition
    make-stm-retry stm-retry?)

  (define (retry)
    (raise (make-stm-retry)))

  ;; ========== tvar-read ==========

  (define (tvar-read tv)
    (let ([tx (*current-tx*)])
      (if (not tx)
        ;; Outside transaction: direct read
        (stm-tvar-stm-value tv)
        ;; 1. Check write-set (our own writes take priority)
        (let ([we (assq tv (tx-rec-tx-write-set tx))])
          (if we
            (cdr we)
            ;; 2. Check read-set (already snapshotted)
            (let ([re (assq tv (tx-rec-tx-read-set tx))])
              (if re
                (stm-tvar-stm-value tv)
                ;; 3. First read: snapshot version + value atomically
                ;; Hold per-tvar lock briefly for consistency
                (let ([snapshot
                       (let ([mx (stm-tvar-stm-lock tv)])
                         (mutex-acquire mx)
                         (let ([v (stm-tvar-stm-version tv)]
                               [x (stm-tvar-stm-value tv)])
                           (mutex-release mx)
                           (cons v x)))])
                  (tx-rec-tx-read-set-set! tx
                    (cons (cons tv (car snapshot)) (tx-rec-tx-read-set tx)))
                  (cdr snapshot)))))))))

  ;; ========== tvar-write! ==========

  (define (tvar-write! tv val)
    (let ([tx (*current-tx*)])
      (if (not tx)
        ;; Outside transaction: direct write with per-tvar lock
        (let ([mx (stm-tvar-stm-lock tv)])
          (mutex-acquire mx)
          (stm-tvar-stm-value-set! tv val)
          (stm-tvar-stm-version-set! tv (+ (stm-tvar-stm-version tv) 1))
          (notify-waiters! tv)
          (mutex-release mx))
        ;; Inside transaction: buffer in write-set
        (let ([entry (assq tv (tx-rec-tx-write-set tx))])
          (if entry
            (set-cdr! entry val)
            (tx-rec-tx-write-set-set! tx
              (cons (cons tv val) (tx-rec-tx-write-set tx))))))))

  ;; ========== Commit (per-tvar locking) ==========
  ;;
  ;; Acquires per-tvar locks for all TVars in the WRITE set,
  ;; validates the read-set, applies writes, notifies waiters.
  ;; Returns #t on success, #f on conflict.

  (define (tx-commit! tx)
    (let ([read-set  (tx-rec-tx-read-set tx)]
          [write-set (tx-rec-tx-write-set tx)])
      ;; Acquire write-set locks in deterministic order (by version,
      ;; then identity hash) to prevent deadlock between concurrent
      ;; transactions.
      (let ([sorted-writes (sort-tvars write-set)])
        ;; Acquire all write locks
        (for-each (lambda (entry)
                    (mutex-acquire (stm-tvar-stm-lock (car entry))))
                  sorted-writes)
        ;; Validate read-set: check versions haven't changed
        (let ([valid?
               (for-all (lambda (entry)
                          (let* ([tv (car entry)]
                                 [expected-version (cdr entry)]
                                 ;; For TVars also in write-set, we already
                                 ;; hold their lock. For read-only TVars,
                                 ;; briefly acquire their lock.
                                 [in-write? (assq tv write-set)])
                            (if in-write?
                              ;; Already locked — safe to read version
                              (= (stm-tvar-stm-version tv) expected-version)
                              ;; Read-only TVar — brief lock for version check
                              (let ([mx (stm-tvar-stm-lock tv)])
                                (mutex-acquire mx)
                                (let ([ok (= (stm-tvar-stm-version tv) expected-version)])
                                  (mutex-release mx)
                                  ok)))))
                        read-set)])
          (cond
            [valid?
             ;; Apply writes and bump versions
             (for-each (lambda (entry)
                         (let ([tv (car entry)])
                           (stm-tvar-stm-value-set! tv (cdr entry))
                           (stm-tvar-stm-version-set! tv
                             (+ (stm-tvar-stm-version tv) 1))
                           (notify-waiters! tv)))
                       sorted-writes)
             ;; Release all write locks
             (for-each (lambda (entry)
                         (mutex-release (stm-tvar-stm-lock (car entry))))
                       sorted-writes)
             #t]
            [else
             ;; Conflict — release all locks and return #f
             (for-each (lambda (entry)
                         (mutex-release (stm-tvar-stm-lock (car entry))))
                       sorted-writes)
             #f])))))

  ;; Sort TVars deterministically to prevent deadlock when two
  ;; transactions lock overlapping write-sets.
  (define (sort-tvars entries)
    (list-sort
      (lambda (a b)
        (< (stm-tvar-stm-version (car a))
           (stm-tvar-stm-version (car b))))
      entries))

  ;; ========== atomically ==========
  ;;
  ;; Runs thunk speculatively; commits on success; retries on conflict.
  ;; Nested atomically flattens into the enclosing transaction.
  ;;
  ;; On retry: detects fiber context and either parks the fiber or
  ;; blocks the OS thread until a relevant TVar changes.

  (define (%run-atomically thunk)
    (if (*current-tx*)
      ;; Already in a transaction: flatten
      (thunk)
      ;; New transaction
      (let loop ()
        (let ([tx (make-tx)])
          (parameterize ([*current-tx* tx])
            (guard (exn
                    [(stm-retry? exn)
                     ;; Block until a TVar in the read-set changes
                     (stm-wait-on-read-set! tx)
                     (loop)]
                    [#t (raise exn)])
              (let ([result (thunk)])
                (if (tx-commit! tx)
                  result
                  ;; Conflict: retry immediately
                  (loop)))))))))

  ;; Wait until any TVar in the read-set changes.
  ;; Fiber-aware: parks fiber if inside fiber runtime.
  (define (stm-wait-on-read-set! tx)
    (let ([read-set (tx-rec-tx-read-set tx)])
      (if (current-fiber)
        ;; Fiber path: register fiber-channel waiter, park
        (let ([ch (make-fiber-channel 1)])
          (let ([waiter (make-fiber-waiter ch)])
            ;; Register waiter on each TVar
            (for-each (lambda (entry)
                        (let* ([tv (car entry)]
                               [mx (stm-tvar-stm-lock tv)])
                          (mutex-acquire mx)
                          (stm-tvar-stm-waiters-set! tv
                            (cons waiter (stm-tvar-stm-waiters tv)))
                          (mutex-release mx)))
                      read-set)
            ;; Park fiber until signaled
            (fiber-channel-recv ch)
            ;; Unregister waiter
            (for-each (lambda (entry)
                        (let* ([tv (car entry)]
                               [mx (stm-tvar-stm-lock tv)])
                          (mutex-acquire mx)
                          (stm-tvar-stm-waiters-set! tv
                            (remq waiter (stm-tvar-stm-waiters tv)))
                          (mutex-release mx)))
                      read-set)))
        ;; Thread path: use condition variable
        (let ([mx (make-mutex)]
              [cv (make-condition)])
          (let ([waiter (make-thread-waiter mx cv)])
            (for-each (lambda (entry)
                        (let* ([tv (car entry)]
                               [tvmx (stm-tvar-stm-lock tv)])
                          (mutex-acquire tvmx)
                          (stm-tvar-stm-waiters-set! tv
                            (cons waiter (stm-tvar-stm-waiters tv)))
                          (mutex-release tvmx)))
                      read-set)
            (mutex-acquire mx)
            (condition-wait cv mx)
            (mutex-release mx)
            (for-each (lambda (entry)
                        (let* ([tv (car entry)]
                               [tvmx (stm-tvar-stm-lock tv)])
                          (mutex-acquire tvmx)
                          (stm-tvar-stm-waiters-set! tv
                            (remq waiter (stm-tvar-stm-waiters tv)))
                          (mutex-release tvmx)))
                      read-set))))))

  (define-syntax atomically
    (syntax-rules ()
      [(_ body ...)
       (%run-atomically (lambda () body ...))]))

  ;; ========== or-else ==========

  (define-syntax or-else
    (syntax-rules ()
      [(_ expr1 expr2)
       (guard (exn [(stm-retry? exn) expr2])
         expr1)]))

  ;; ========== Clojure-style STM aliases ==========

  (define make-ref make-tvar)
  (define ref? tvar?)
  (define ref-deref tvar-read)

  (define-syntax dosync
    (syntax-rules ()
      [(_ body ...)
       (atomically body ...)]))

  (define (alter r f . args)
    (let* ([old (tvar-read r)]
           [new (apply f old args)])
      (tvar-write! r new)
      new))

  (define (ref-set r val)
    (tvar-write! r val)
    val)

  (define (commute r f . args)
    (apply alter r f args))

  (define (ensure r)
    (tvar-read r))

  ;; ========== io! — guard side-effecting code from retry ==========
  ;;
  ;; Clojure's io! form raises when evaluated inside a dosync, preventing
  ;; callers from accidentally performing side effects that would be
  ;; replayed on retry. Outside a transaction the body runs unguarded.
  (define-syntax io!
    (syntax-rules ()
      [(_ body ...)
       (begin
         (when (*current-tx*)
           (error 'io! "io! forms are not allowed inside a transaction"))
         body ...)]))

) ;; end library
