#!chezscheme
;;; (std misc retry) -- Retry with Exponential Backoff
;;;
;;; Features:
;;;   - retry: retry a thunk with configurable policy
;;;   - retry/backoff: exponential backoff with jitter
;;;   - retry/predicate: retry only on matching exceptions
;;;   - circuit-breaker: trip after N failures, reset after timeout
;;;
;;; Usage:
;;;   (import (std misc retry))
;;;
;;;   ;; Simple retry (3 attempts, 1s delay)
;;;   (retry (lambda () (http-get url)))
;;;
;;;   ;; Exponential backoff
;;;   (retry/backoff (lambda () (api-call))
;;;     max-attempts: 5
;;;     base-delay: 0.5
;;;     max-delay: 30.0)
;;;
;;;   ;; Circuit breaker
;;;   (define breaker (make-circuit-breaker 5 60))
;;;   (circuit-breaker-call breaker (lambda () (db-query)))

(library (std misc retry)
  (export
    retry
    retry/backoff
    retry/predicate
    make-retry-policy
    retry-policy?
    retry-policy-max-attempts
    retry-policy-base-delay
    retry-policy-max-delay
    retry-policy-jitter?

    ;; Circuit breaker
    make-circuit-breaker
    circuit-breaker?
    circuit-breaker-state
    circuit-breaker-call
    circuit-breaker-reset!
    circuit-breaker-stats)

  (import (chezscheme))

  ;; ========== Retry Policy ==========
  (define-record-type retry-policy
    (fields (immutable max-attempts)
            (immutable base-delay)     ; seconds (flonum)
            (immutable max-delay)      ; seconds (flonum)
            (immutable jitter?)        ; add randomness?
            (immutable on-retry)       ; (lambda (attempt delay exn) ...) or #f
            (immutable retry-if))      ; (lambda (exn) -> bool) or #f (retry all)
    (protocol (lambda (new)
      (case-lambda
        [() (new 3 1.0 30.0 #t #f #f)]
        [(max) (new max 1.0 30.0 #t #f #f)]
        [(max base) (new max base 30.0 #t #f #f)]
        [(max base maxd) (new max base maxd #t #f #f)]
        [(max base maxd jitter?) (new max base maxd jitter? #f #f)]
        [(max base maxd jitter? on-retry) (new max base maxd jitter? on-retry #f)]
        [(max base maxd jitter? on-retry retry-if) (new max base maxd jitter? on-retry retry-if)]))))

  ;; ========== Simple Retry ==========
  (define retry
    (case-lambda
      [(thunk) (retry thunk 3 1.0)]
      [(thunk max-attempts) (retry thunk max-attempts 1.0)]
      [(thunk max-attempts delay-secs)
       (let loop ([attempt 1])
         (guard (exn
                  [#t (if (>= attempt max-attempts)
                        (raise exn)
                        (begin
                          (sleep-seconds delay-secs)
                          (loop (+ attempt 1))))])
           (thunk)))]))

  ;; ========== Retry with Exponential Backoff ==========
  (define retry/backoff
    (case-lambda
      [(thunk) (retry/backoff thunk (make-retry-policy))]
      [(thunk policy)
       (let loop ([attempt 1])
         (guard (exn
                  [#t (if (>= attempt (retry-policy-max-attempts policy))
                        (raise exn)
                        (let* ([should-retry (or (not (retry-policy-retry-if policy))
                                                 ((retry-policy-retry-if policy) exn))]
                               [delay (compute-delay attempt policy)])
                          (if (not should-retry)
                            (raise exn)
                            (begin
                              (when (retry-policy-on-retry policy)
                                ((retry-policy-on-retry policy) attempt delay exn))
                              (sleep-seconds delay)
                              (loop (+ attempt 1))))))])
           (thunk)))]))

  ;; ========== Retry with Predicate ==========
  (define (retry/predicate thunk pred . rest)
    ;; Only retry when (pred exn) returns #t
    (let ([max-attempts (if (pair? rest) (car rest) 3)]
          [delay-secs (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) 1.0)])
      (let loop ([attempt 1])
        (guard (exn
                 [#t (if (or (>= attempt max-attempts) (not (pred exn)))
                       (raise exn)
                       (begin
                         (sleep-seconds delay-secs)
                         (loop (+ attempt 1))))])
          (thunk)))))

  ;; ========== Circuit Breaker ==========
  ;; States: closed (normal), open (failing), half-open (testing)

  (define-record-type circuit-breaker
    (fields (immutable failure-threshold)  ; trips after N failures
            (immutable reset-timeout)       ; seconds before half-open
            (mutable state)                 ; 'closed, 'open, 'half-open
            (mutable failure-count)
            (mutable last-failure-time)
            (mutable success-count)
            (mutable total-calls)
            (mutable total-failures))
    (protocol (lambda (new)
      (lambda (threshold timeout)
        (new threshold timeout 'closed 0 0 0 0 0)))))

  (define (circuit-breaker-call breaker thunk)
    (let ([state (circuit-breaker-state breaker)])
      (circuit-breaker-total-calls-set! breaker
        (+ (circuit-breaker-total-calls breaker) 1))
      (case state
        [(open)
         ;; Check if reset timeout has passed
         (if (>= (- (current-seconds) (circuit-breaker-last-failure-time breaker))
                  (circuit-breaker-reset-timeout breaker))
           (begin
             ;; Transition to half-open
             (circuit-breaker-state-set! breaker 'half-open)
             (try-call breaker thunk))
           (error 'circuit-breaker-call "circuit breaker is open"))]
        [(half-open)
         (try-call breaker thunk)]
        [(closed)
         (try-call breaker thunk)])))

  (define (try-call breaker thunk)
    (guard (exn
             [#t (record-failure! breaker)
                 (raise exn)])
      (let ([result (thunk)])
        (record-success! breaker)
        result)))

  (define (record-failure! breaker)
    (circuit-breaker-failure-count-set! breaker
      (+ (circuit-breaker-failure-count breaker) 1))
    (circuit-breaker-total-failures-set! breaker
      (+ (circuit-breaker-total-failures breaker) 1))
    (circuit-breaker-last-failure-time-set! breaker (current-seconds))
    (when (>= (circuit-breaker-failure-count breaker)
              (circuit-breaker-failure-threshold breaker))
      (circuit-breaker-state-set! breaker 'open)))

  (define (record-success! breaker)
    (circuit-breaker-success-count-set! breaker
      (+ (circuit-breaker-success-count breaker) 1))
    (circuit-breaker-failure-count-set! breaker 0)
    (when (eq? (circuit-breaker-state breaker) 'half-open)
      (circuit-breaker-state-set! breaker 'closed)))

  (define (circuit-breaker-reset! breaker)
    (circuit-breaker-state-set! breaker 'closed)
    (circuit-breaker-failure-count-set! breaker 0))

  (define (circuit-breaker-stats breaker)
    ;; Returns alist of stats
    `((state . ,(circuit-breaker-state breaker))
      (failure-count . ,(circuit-breaker-failure-count breaker))
      (success-count . ,(circuit-breaker-success-count breaker))
      (total-calls . ,(circuit-breaker-total-calls breaker))
      (total-failures . ,(circuit-breaker-total-failures breaker))))

  ;; ========== Helpers ==========
  (define (compute-delay attempt policy)
    (let* ([base (retry-policy-base-delay policy)]
           [exp-delay (* base (expt 2 (- attempt 1)))]
           [capped (min exp-delay (retry-policy-max-delay policy))]
           [jittered (if (retry-policy-jitter? policy)
                       (* capped (+ 0.5 (random-real)))  ; 0.5x to 1.5x
                       capped)])
      jittered))

  (define (current-seconds)
    (let ([t (current-time)])
      (+ (time-second t)
         (/ (time-nanosecond t) 1000000000.0))))

  (define (sleep-seconds secs)
    (let* ([whole (exact (floor secs))]
           [frac (- secs whole)]
           [nanos (exact (round (* frac 1000000000)))])
      (sleep (make-time 'time-duration nanos whole))))

  (define (random-real)
    ;; Simple random float in [0, 1)
    (/ (random 1000000) 1000000.0))

) ;; end library
