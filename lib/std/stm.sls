#!chezscheme
;;; (std stm) — Software Transactional Memory
;;;
;;; Optimistic concurrency using versioned transactional variables (TVars).
;;; Transactions run speculatively, validate their read-set at commit time,
;;; and retry on conflict. Lock-free reads, single global commit mutex.
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
    or-else)

  (import (chezscheme))

  ;; ========== TVar ==========

  (define-record-type (stm-tvar %make-tvar tvar?)
    (fields
      (mutable   stm-value)    ; current committed value
      (mutable   stm-version)) ; monotonically increasing version counter
    (sealed #t))

  (define (make-tvar init)
    (%make-tvar init 0))

  ;; Read the current value of a TVar outside a transaction.
  ;; Not safe to use inside atomically (use tvar-read instead).
  (define (tvar-ref tv) (stm-tvar-stm-value tv))

  ;; ========== Global Commit Infrastructure ==========
  ;;
  ;; Single global mutex serialises all commit attempts.
  ;; After each successful commit we broadcast on *commit-cond*
  ;; so that threads blocked in retry can wake up and re-run.

  (define *commit-mutex* (make-mutex))
  (define *commit-cond*  (make-condition))

  ;; ========== Transaction State ==========
  ;;
  ;; read-set  : assoc list of (tvar . version-seen-at-first-read)
  ;; write-set : assoc list of (tvar . new-value)

  (define-record-type tx-rec
    (fields
      (mutable tx-read-set)
      (mutable tx-write-set))
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
        ;; Outside transaction: direct read (not transactional)
        (stm-tvar-stm-value tv)
        ;; 1. Check write-set (our own writes take priority)
        (let ([we (assq tv (tx-rec-tx-write-set tx))])
          (if we
            (cdr we)
            ;; 2. Check read-set (already snapshotted this tvar)
            (let ([re (assq tv (tx-rec-tx-read-set tx))])
              (if re
                ;; Return current value (version mismatch is caught at commit)
                (stm-tvar-stm-value tv)
                ;; 3. First read: snapshot version + value
                (let* ([ver (stm-tvar-stm-version tv)]
                       [val (stm-tvar-stm-value tv)])
                  (tx-rec-tx-read-set-set! tx
                    (cons (cons tv ver) (tx-rec-tx-read-set tx)))
                  val))))))))

  ;; ========== tvar-write! ==========

  (define (tvar-write! tv val)
    (let ([tx (*current-tx*)])
      (if (not tx)
        ;; Outside transaction: direct (non-transactional) write
        (with-mutex *commit-mutex*
          (stm-tvar-stm-value-set! tv val)
          (stm-tvar-stm-version-set! tv (+ (stm-tvar-stm-version tv) 1))
          (condition-broadcast *commit-cond*))
        ;; Inside transaction: buffer in write-set
        (let ([entry (assq tv (tx-rec-tx-write-set tx))])
          (if entry
            (set-cdr! entry val)
            (tx-rec-tx-write-set-set! tx
              (cons (cons tv val) (tx-rec-tx-write-set tx))))))))

  ;; ========== Commit ==========
  ;;
  ;; Acquires *commit-mutex*, validates read-set, applies writes.
  ;; Returns #t on success, #f on conflict.

  (define (tx-commit! tx)
    (with-mutex *commit-mutex*
      (let ([read-set  (tx-rec-tx-read-set tx)]
            [write-set (tx-rec-tx-write-set tx)])
        ;; Validate: check that all snapshotted versions are still current
        (let ([valid? (for-all (lambda (entry)
                                 (= (stm-tvar-stm-version (car entry))
                                    (cdr entry)))
                               read-set)])
          (when valid?
            ;; Apply writes and bump versions
            (for-each (lambda (entry)
                        (stm-tvar-stm-value-set!   (car entry) (cdr entry))
                        (stm-tvar-stm-version-set! (car entry)
                          (+ (stm-tvar-stm-version (car entry)) 1)))
                      write-set)
            ;; Wake all threads waiting in retry
            (when (not (null? write-set))
              (condition-broadcast *commit-cond*)))
          valid?))))

  ;; ========== atomically ==========
  ;;
  ;; Runs thunk speculatively; commits on success; retries on conflict.
  ;; Nested atomically flattens into the enclosing transaction.

  (define (%run-atomically thunk)
    (if (*current-tx*)
      ;; Already in a transaction: flatten (run in enclosing tx)
      (thunk)
      ;; New transaction
      (let loop ()
        (let ([tx (make-tx)])
          (parameterize ([*current-tx* tx])
            (guard (exn
                    [(stm-retry? exn)
                     ;; Block until some TVar is modified, then retry
                     (mutex-acquire *commit-mutex*)
                     (condition-wait *commit-cond* *commit-mutex*)
                     (mutex-release *commit-mutex*)
                     (loop)]
                    [#t (raise exn)])
              (let ([result (thunk)])
                (if (tx-commit! tx)
                  result
                  ;; Conflict: retry immediately
                  (loop)))))))))

  (define-syntax atomically
    (syntax-rules ()
      [(_ body ...)
       (%run-atomically (lambda () body ...))]))

  ;; ========== or-else ==========
  ;;
  ;; Try the first expression; if it calls retry, try the second.
  ;; Both run within the same enclosing transaction (if any).

  (define-syntax or-else
    (syntax-rules ()
      [(_ expr1 expr2)
       (guard (exn [(stm-retry? exn) expr2])
         expr1)]))

  ) ;; end library
