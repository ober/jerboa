;;; Async/Await with Structured Concurrency — Phase 5d (Track 17.3)
;;;
;;; Provides promise-based async/await backed by Chez Scheme threads.
;;; Promises carry a value or an exception; await blocks until resolved.
;;;
;;; API:
;;;   (make-promise)                       — create an unfulfilled promise
;;;   (promise? x)                         — type predicate
;;;   (promise-resolve! p val)             — fulfill with value
;;;   (promise-reject!  p exn)             — fulfill with error
;;;   (promise-await    p)                 — block until fulfilled; re-raise errors
;;;   (promise-resolved? p)                — #t if already resolved
;;;   (async thunk)                        — spawn thunk in background thread, return promise
;;;   (await expr)                         — inside async context: wait for promise
;;;   (await-all p ...)                    — wait for all promises; return list of values
;;;   (await-any p ...)                    — wait for first fulfilled promise
;;;   (define-async (name args ...) body .) — define async function returning promise
;;;   (make-cancellation-token-source)     — create a cancellation source
;;;   (cts-token cts)                      — extract token from source
;;;   (cts-cancel! cts)                    — signal cancellation
;;;   (cancellation-token? t)              — type predicate
;;;   (check-cancellation! t)              — raise if cancelled

(library (std concur async-await)
  (export
    ;; Promises
    make-promise
    promise?
    promise-resolve!
    promise-reject!
    promise-await
    promise-resolved?

    ;; Async execution
    async
    await
    await-all
    await-any
    define-async

    ;; Cancellation
    make-cancellation-token-source
    cts-token
    cts-cancel!
    cancellation-token?
    check-cancellation!)

  (import (chezscheme))

  ;; -----------------------------------------------------------------------
  ;; Promise implementation
  ;;
  ;; A promise is a record holding:
  ;;   state:  'pending | 'resolved | 'rejected
  ;;   value:  the resolved value (when state = 'resolved)
  ;;   error:  the exception (when state = 'rejected)
  ;;   mutex:  protects state transitions
  ;;   cond:   waited on by promise-await
  ;; -----------------------------------------------------------------------

  (define-record-type promise-record
    (fields (mutable state  promise-state  set-promise-state!)
            (mutable value  promise-value  set-promise-value!)
            (mutable error  promise-error  set-promise-error!)
            (immutable mutex promise-mutex)
            (immutable cond  promise-cond))
    (protocol
      (lambda (new)
        (lambda ()
          (new 'pending #f #f (make-mutex) (make-condition))))))

  (define (make-promise) (make-promise-record))
  (define (promise? x)   (promise-record? x))

  (define (promise-resolved? p)
    (not (eq? (promise-state p) 'pending)))

  (define (promise-resolve! p val)
    (let ([m (promise-mutex p)])
      (mutex-acquire m)
      (when (eq? (promise-state p) 'pending)
        (set-promise-value! p val)
        (set-promise-state! p 'resolved)
        (condition-broadcast (promise-cond p)))
      (mutex-release m)))

  (define (promise-reject! p exn)
    (let ([m (promise-mutex p)])
      (mutex-acquire m)
      (when (eq? (promise-state p) 'pending)
        (set-promise-error! p exn)
        (set-promise-state! p 'rejected)
        (condition-broadcast (promise-cond p)))
      (mutex-release m)))

  (define (promise-await p)
    "Block until P is resolved; return value or re-raise error"
    (let ([m (promise-mutex p)])
      (mutex-acquire m)
      (let loop ()
        (cond
          [(eq? (promise-state p) 'resolved)
           (let ([v (promise-value p)])
             (mutex-release m)
             v)]
          [(eq? (promise-state p) 'rejected)
           (let ([e (promise-error p)])
             (mutex-release m)
             (raise e))]
          [else
           (condition-wait (promise-cond p) m)
           (loop)]))))

  ;; -----------------------------------------------------------------------
  ;; async — spawn a thunk in a background thread, return a promise
  ;; -----------------------------------------------------------------------

  (define (async thunk)
    "Spawn THUNK in a background thread; return a promise for its result"
    (let ([p (make-promise)])
      (fork-thread
        (lambda ()
          (call-with-current-continuation
            (lambda (k)
              (with-exception-handler
                (lambda (e)
                  (promise-reject! p e)
                  (k (void)))
                (lambda ()
                  (let ([v (thunk)])
                    (promise-resolve! p v))))))))
      p))

  ;; -----------------------------------------------------------------------
  ;; await — within an async context, block on a promise
  ;; -----------------------------------------------------------------------

  (define (await p)
    "Wait for promise P and return its value (or re-raise its error)"
    (cond
      [(promise? p) (promise-await p)]
      [else p]))  ; already a plain value — return as-is

  ;; -----------------------------------------------------------------------
  ;; await-all — wait for all promises, return list of results
  ;; -----------------------------------------------------------------------

  (define (await-all . promises)
    "Wait for all PROMISES; return list of values in order"
    (map promise-await promises))

  ;; -----------------------------------------------------------------------
  ;; await-any — return value of first promise to resolve
  ;; -----------------------------------------------------------------------

  (define (await-any . promises)
    "Return value of the first promise in PROMISES to resolve"
    (let ([winner-p (make-promise)]
          [done (list #f)])  ; one-shot flag
      ;; Attach a waiter thread to each promise
      (for-each
        (lambda (p)
          (fork-thread
            (lambda ()
              (call-with-current-continuation
                (lambda (k)
                  (with-exception-handler
                    (lambda (e)
                      ;; If winner not yet chosen, propagate rejection
                      (mutex-acquire (promise-mutex winner-p))
                      (when (not (car done))
                        (set-car! done #t)
                        (mutex-release (promise-mutex winner-p))
                        (promise-reject! winner-p e))
                      (when (car done) (mutex-release (promise-mutex winner-p)))
                      (k (void)))
                    (lambda ()
                      (let ([v (promise-await p)])
                        (mutex-acquire (promise-mutex winner-p))
                        (when (not (car done))
                          (set-car! done #t)
                          (mutex-release (promise-mutex winner-p))
                          (promise-resolve! winner-p v))
                        (when (car done)
                          (mutex-release (promise-mutex winner-p)))))))))))
        promises)
      (promise-await winner-p)))

  ;; -----------------------------------------------------------------------
  ;; define-async macro
  ;; -----------------------------------------------------------------------

  (define-syntax define-async
    (syntax-rules ()
      [(_ (name args ...) body ...)
       (define (name args ...)
         (async (lambda () body ...)))]))

  ;; -----------------------------------------------------------------------
  ;; Cancellation tokens
  ;; -----------------------------------------------------------------------

  (define-record-type cancellation-token
    (fields (mutable cancelled? ct-cancelled? set-ct-cancelled!))
    (protocol (lambda (new) (lambda () (new #f)))))

  (define-record-type cts-record
    (fields (immutable token cts-token))
    (protocol (lambda (new) (lambda () (new (make-cancellation-token))))))

  (define (make-cancellation-token-source) (make-cts-record))

  (define (cts-cancel! cts)
    (set-ct-cancelled! (cts-token cts) #t))

  (define (check-cancellation! token)
    (when (ct-cancelled? token)
      (raise (condition
               (make-message-condition "operation cancelled")))))

) ;; end library
