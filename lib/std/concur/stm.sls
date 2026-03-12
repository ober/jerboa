;;; Software Transactional Memory — Phase 5d (Track 17.1)
;;;
;;; Optimistic concurrency with transactional variables (TVars).
;;; Supports nested transactions, retry, and or-else.

(library (std concur stm)
  (export
    make-tvar tvar? tvar-get tvar-set!
    atomically retry or-else)
  (import (chezscheme))

  ;; -----------------------------------------------------------------------
  ;; TVar — a versioned mutable cell
  ;; -----------------------------------------------------------------------

  (define-record-type tvar
    (fields (mutable val  tvar-val  set-tvar-val!)
            (mutable ver  tvar-ver  set-tvar-ver!))
    (protocol (lambda (new) (lambda (init) (new init 0)))))

  ;; Global version clock
  (define *global-version* 0)

  ;; -----------------------------------------------------------------------
  ;; Transaction context (thread-local)
  ;; -----------------------------------------------------------------------
  ;; Each transaction has:
  ;;   read-set:  eq-hashtable tvar → observed-version
  ;;   write-set: eq-hashtable tvar → new-value
  ;;   parent:    outer transaction or #f

  (define-record-type txn
    (fields (immutable read-set  txn-read-set)
            (immutable write-set txn-write-set)
            (mutable   parent    txn-parent set-txn-parent!))
    (protocol
      (lambda (new)
        (lambda (parent)
          (new (make-eq-hashtable) (make-eq-hashtable) parent)))))

  (define *current-txn* (make-thread-parameter #f))

  ;; -----------------------------------------------------------------------
  ;; Global commit mutex
  ;; -----------------------------------------------------------------------

  (define *stm-mutex* (make-mutex))
  (define *stm-cond*  (make-condition))

  ;; -----------------------------------------------------------------------
  ;; tvar-get — read TVar in transaction context
  ;; -----------------------------------------------------------------------

  (define (tvar-get tv)
    (let ([txn (*current-txn*)])
      (if txn
          ;; Inside transaction
          (let ([ws (txn-write-set txn)]
                [rs (txn-read-set txn)])
            (cond
              ;; Written in this txn → return pending value
              [(hashtable-contains? ws tv)
               (hashtable-ref ws tv #f)]
              ;; First read → record version + return current value
              [else
               (let ([v (tvar-val tv)]
                     [ver (tvar-ver tv)])
                 (hashtable-set! rs tv ver)
                 v)]))
          ;; Outside transaction → direct read
          (tvar-val tv))))

  ;; -----------------------------------------------------------------------
  ;; tvar-set! — write TVar in transaction context
  ;; -----------------------------------------------------------------------

  (define (tvar-set! tv val)
    (let ([txn (*current-txn*)])
      (if txn
          (hashtable-set! (txn-write-set txn) tv val)
          ;; Direct write outside transaction
          (begin
            (mutex-acquire *stm-mutex*)
            (set-tvar-val! tv val)
            (set-tvar-ver! tv (+ *global-version* 1))
            (set! *global-version* (+ *global-version* 1))
            (condition-broadcast *stm-cond*)
            (mutex-release *stm-mutex*)))))

  ;; -----------------------------------------------------------------------
  ;; Validation — check all read TVars are still current
  ;; -----------------------------------------------------------------------

  (define (validate-read-set! txn)
    "Return #t if all read TVars still have observed versions"
    (let-values ([(tvs vers) (hashtable-entries (txn-read-set txn))])
      (let loop ([i 0])
        (or (= i (vector-length tvs))
            (and (= (tvar-ver (vector-ref tvs i)) (vector-ref vers i))
                 (loop (+ i 1)))))))

  ;; -----------------------------------------------------------------------
  ;; Commit — write all write-set values atomically
  ;; -----------------------------------------------------------------------

  (define (commit-txn! txn)
    "Attempt to commit TXN; return #t on success, #f on conflict"
    (mutex-acquire *stm-mutex*)
    (let ([ok (validate-read-set! txn)])
      (when ok
        (let-values ([(tvs vals) (hashtable-entries (txn-write-set txn))])
          (let ([new-ver (+ *global-version* 1)])
            (set! *global-version* new-ver)
            (vector-for-each
              (lambda (tv val)
                (set-tvar-val! tv val)
                (set-tvar-ver! tv new-ver))
              tvs vals)))
        (condition-broadcast *stm-cond*))
      (mutex-release *stm-mutex*)
      ok))

  ;; -----------------------------------------------------------------------
  ;; atomically — run a transaction
  ;; -----------------------------------------------------------------------

  ;; Retry sentinel
  (define *retry-tag* (list 'retry))

  (define (atomically thunk)
    (let ([outer (*current-txn*)])
      (if outer
          ;; Nested: create child txn, merge into outer on success
          (let ([child (make-txn outer)])
            (parameterize ([*current-txn* child])
              (let ([result (thunk)])
                ;; Merge child write-set into outer
                (let-values ([(tvs vals) (hashtable-entries (txn-write-set child))])
                  (vector-for-each
                    (lambda (tv v) (hashtable-set! (txn-write-set outer) tv v))
                    tvs vals))
                result)))
          ;; Top-level: run with retry loop
          (call-with-current-continuation
            (lambda (k-done)
              (let loop ()
                (let ([txn (make-txn #f)])
                  (parameterize ([*current-txn* txn])
                    (call-with-current-continuation
                      (lambda (k-escape)
                        (with-exception-handler
                          (lambda (e)
                            (if (eq? e *retry-tag*)
                                ;; retry: block until some TVar changes
                                (begin
                                  (mutex-acquire *stm-mutex*)
                                  (condition-wait *stm-cond* *stm-mutex*)
                                  (mutex-release *stm-mutex*)
                                  (k-escape 'retry))
                                (raise e)))
                          (lambda ()
                            (let ([result (thunk)])
                              (when (commit-txn! txn)
                                (k-done result)))))))))
                ;; retry or conflict: run again
                (loop)))))))

  ;; -----------------------------------------------------------------------
  ;; retry — abort and wait for change
  ;; -----------------------------------------------------------------------

  (define (retry)
    (raise *retry-tag*))

  ;; -----------------------------------------------------------------------
  ;; or-else — try first transaction; if it retries, try second
  ;; -----------------------------------------------------------------------

  (define-syntax or-else
    (syntax-rules ()
      [(_ thunk1 thunk2)
       (let ([succeeded #f]
             [result    #f])
         (call-with-current-continuation
           (lambda (k)
             (with-exception-handler
               (lambda (e)
                 (if (eq? e *retry-tag*)
                     (k 'retry-first)
                     (raise e)))
               (lambda ()
                 (set! result (thunk1))
                 (set! succeeded #t)))))
         (if succeeded
             result
             (thunk2)))]))

)
