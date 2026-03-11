#!chezscheme
;;; (std health) -- Health check framework
;;;
;;; Named checks return 'ok, 'degraded, or 'failing.
;;; run-checks executes all registered checks with duration tracking.
;;; health-status summarises to 'healthy, 'degraded, or 'failing.

(library (std health)
  (export
    ;; Registry
    make-health-registry health-registry? register-check!
    ;; Running checks
    run-checks health-status healthy?
    ;; Check result accessors
    check-result check-result-name check-result-status
    check-result-message check-result-duration
    ;; Check helpers
    make-check with-timeout-check)

  (import (chezscheme))

  ;;; ========== Check result record ==========
  ;; status  — 'ok | 'degraded | 'failing
  ;; message — string or #f
  ;; duration — milliseconds (exact integer)
  (define-record-type %check-result
    (fields name status message duration))

  (define (check-result? x) (%check-result? x))
  (define (check-result-name r)     (%check-result-name r))
  (define (check-result-status r)   (%check-result-status r))
  (define (check-result-message r)  (%check-result-message r))
  (define (check-result-duration r) (%check-result-duration r))

  ;; Public constructor used in tests / direct construction
  (define (check-result name status message duration)
    (make-%check-result name status message duration))

  ;;; ========== Registry ==========
  ;; checks — mutable alist of (name . thunk)
  (define-record-type %health-registry
    (fields (mutable checks))
    (protocol (lambda (new) (lambda () (new '())))))

  (define (health-registry? x) (%health-registry? x))
  (define (make-health-registry) (make-%health-registry))

  (define (register-check! reg name thunk)
    (%health-registry-checks-set! reg
      (cons (cons name thunk)
            (%health-registry-checks reg))))

  ;;; ========== make-check ==========
  ;; Wraps a thunk that should return 'ok, 'degraded, or 'failing.
  ;; The thunk may also signal an error → treated as 'failing.
  (define (make-check thunk) thunk)

  ;;; ========== with-timeout-check ==========
  ;; Returns a new thunk; if the inner thunk takes longer than
  ;; timeout-ms milliseconds, returns 'failing with a message.
  ;; Because Chez Scheme portable threads may not have wall-clock
  ;; preemption, we approximate using elapsed time after the call.
  (define (with-timeout-check thunk timeout-ms)
    (lambda ()
      (let* ([start   (current-time)]
             [result  (guard (exn [#t 'failing]) (thunk))]
             [end     (current-time)]
             [elapsed (time->ms end start)])
        (if (> elapsed timeout-ms)
          'failing
          result))))

  (define (time->ms t2 t1)
    (let ([ds  (- (time-second t2) (time-second t1))]
          [dns (- (time-nanosecond t2) (time-nanosecond t1))])
      (+ (* ds 1000) (div dns 1000000))))

  ;;; ========== run-checks ==========
  ;; Returns a list of check-result records.
  (define (run-checks reg)
    (map (lambda (entry)
           (let* ([name   (car entry)]
                  [thunk  (cdr entry)]
                  [start  (current-time)]
                  [status (guard (exn [#t 'failing])
                            (let ([r (thunk)])
                              (if (memq r '(ok degraded failing))
                                r
                                'failing)))]
                  [end    (current-time)]
                  [dur    (time->ms end start)]
                  [msg    (case status
                            ((ok)       "check passed")
                            ((degraded) "check degraded")
                            ((failing)  "check failed")
                            (else       "unknown status"))])
             (make-%check-result name status msg dur)))
         (reverse (%health-registry-checks reg))))

  ;;; ========== health-status ==========
  ;; 'healthy  — all ok
  ;; 'degraded — at least one degraded, none failing
  ;; 'failing  — at least one failing
  (define (health-status results)
    (let loop ([lst results] [worst 'healthy])
      (if (null? lst)
        worst
        (let ([s (%check-result-status (car lst))])
          (cond
            [(eq? s 'failing)  'failing]
            [(eq? s 'degraded) (loop (cdr lst) 'degraded)]
            [else              (loop (cdr lst) worst)])))))

  (define (healthy? results)
    (eq? (health-status results) 'healthy))

) ;; end library
