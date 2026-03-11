#!chezscheme
;;; (std circuit) -- Circuit breaker pattern
;;;
;;; Three states: closed (normal), open (failing), half-open (probing).
;;; Config controls failure threshold, success threshold, and timeout.

(library (std circuit)
  (export
    ;; Config
    make-circuit-config
    ;; Circuit breaker
    make-circuit-breaker circuit-breaker?
    circuit-call circuit-state circuit-reset!
    circuit-open? circuit-closed? circuit-half-open?
    circuit-stats)

  (import (chezscheme))

  ;;; ========== Config record ==========
  ;; failure-threshold  — consecutive failures before opening
  ;; success-threshold  — consecutive successes in half-open to close
  ;; timeout            — seconds before half-open after opening
  (define-record-type %circuit-config
    (fields failure-threshold success-threshold timeout)
    (protocol
      (lambda (new)
        (lambda args
          ;; (make-circuit-config)
          ;; (make-circuit-config failure-threshold success-threshold timeout)
          (cond
            [(null? args)
             (new 5 1 60)]
            [(= (length args) 3)
             (new (car args) (cadr args) (caddr args))]
            [else
             (error 'make-circuit-config "expected 0 or 3 arguments")])))))

  ;; Public constructor supports keyword-style too but we keep it simple:
  ;; (make-circuit-config) or (make-circuit-config ft st timeout)
  (define (make-circuit-config . args)
    (cond
      [(null? args)
       (make-%circuit-config 5 1 60)]
      [(= (length args) 3)
       (apply make-%circuit-config args)]
      [else
       (error 'make-circuit-config "expected 0 or 3 arguments")]))

  ;;; ========== Circuit breaker record ==========
  ;; state         — mutable: 'closed | 'open | 'half-open
  ;; failures      — mutable: consecutive failure count
  ;; successes     — mutable: consecutive success count in half-open
  ;; opened-at     — mutable: time when opened (or #f)
  ;; stats         — mutable hashtable
  (define-record-type %circuit-breaker
    (fields config
            (mutable state)
            (mutable failures)
            (mutable successes)
            (mutable opened-at)
            stats)
    (protocol
      (lambda (new)
        (lambda (config)
          (new config 'closed 0 0 #f
               (let ([h (make-eq-hashtable)])
                 (hashtable-set! h 'total-calls 0)
                 (hashtable-set! h 'total-failures 0)
                 (hashtable-set! h 'total-successes 0)
                 (hashtable-set! h 'state-transitions 0)
                 h))))))

  (define (circuit-breaker? x) (%circuit-breaker? x))

  (define (make-circuit-breaker . config-opt)
    (let ([cfg (if (pair? config-opt) (car config-opt) (make-circuit-config))])
      (make-%circuit-breaker cfg)))

  ;;; ========== State accessors ==========
  (define (circuit-state cb)      (%circuit-breaker-state cb))
  (define (circuit-open?      cb) (eq? (%circuit-breaker-state cb) 'open))
  (define (circuit-closed?    cb) (eq? (%circuit-breaker-state cb) 'closed))
  (define (circuit-half-open? cb) (eq? (%circuit-breaker-state cb) 'half-open))

  ;;; ========== Stats ==========
  (define (circuit-stats cb)
    (let ([h (%circuit-breaker-stats cb)])
      (list (cons 'total-calls       (hashtable-ref h 'total-calls 0))
            (cons 'total-failures    (hashtable-ref h 'total-failures 0))
            (cons 'total-successes   (hashtable-ref h 'total-successes 0))
            (cons 'state-transitions (hashtable-ref h 'state-transitions 0))
            (cons 'state             (%circuit-breaker-state cb)))))

  (define (stat-inc! cb key)
    (let ([h (%circuit-breaker-stats cb)])
      (hashtable-set! h key (+ (hashtable-ref h key 0) 1))))

  ;;; ========== State transitions ==========
  (define (transition! cb new-state)
    (%circuit-breaker-state-set! cb new-state)
    (stat-inc! cb 'state-transitions))

  (define (open-circuit! cb)
    (%circuit-breaker-opened-at-set! cb (current-time))
    (%circuit-breaker-successes-set! cb 0)
    (transition! cb 'open))

  (define (close-circuit! cb)
    (%circuit-breaker-failures-set!  cb 0)
    (%circuit-breaker-successes-set! cb 0)
    (%circuit-breaker-opened-at-set! cb #f)
    (transition! cb 'closed))

  (define (maybe-half-open! cb)
    ;; If open and timeout elapsed, move to half-open
    (when (circuit-open? cb)
      (let ([opened-at (%circuit-breaker-opened-at cb)])
        (when opened-at
          (let* ([now     (current-time)]
                 [elapsed (- (time-second now) (time-second opened-at))]
                 [timeout (%circuit-config-timeout (%circuit-breaker-config cb))])
            (when (>= elapsed timeout)
              (%circuit-breaker-failures-set! cb 0)
              (transition! cb 'half-open)))))))

  ;;; ========== circuit-call ==========
  ;; Executes thunk according to circuit state.
  ;; Returns thunk's value or raises on open circuit.
  (define (circuit-call cb thunk)
    (maybe-half-open! cb)
    (let ([state (%circuit-breaker-state cb)])
      (cond
        [(eq? state 'open)
         (error 'circuit-call "circuit is open")]
        [else
         ;; closed or half-open: attempt the call
         (stat-inc! cb 'total-calls)
         (guard (exn [#t
                      ;; Record failure
                      (%circuit-breaker-failures-set! cb
                        (+ (%circuit-breaker-failures cb) 1))
                      (stat-inc! cb 'total-failures)
                      (let* ([cfg  (%circuit-breaker-config cb)]
                             [ft   (%circuit-config-failure-threshold cfg)])
                        (cond
                          [(eq? state 'half-open)
                           ;; Failure in half-open → reopen
                           (open-circuit! cb)]
                          [(>= (%circuit-breaker-failures cb) ft)
                           (open-circuit! cb)]))
                      (raise exn)])
           (let ([result (thunk)])
             ;; Success
             (stat-inc! cb 'total-successes)
             (%circuit-breaker-failures-set! cb 0)
             (when (eq? state 'half-open)
               (%circuit-breaker-successes-set! cb
                 (+ (%circuit-breaker-successes cb) 1))
               (when (>= (%circuit-breaker-successes cb)
                         (%circuit-config-success-threshold
                           (%circuit-breaker-config cb)))
                 (close-circuit! cb)))
             result))])))

  ;;; ========== circuit-reset! ==========
  ;; Force the circuit back to closed state.
  (define (circuit-reset! cb)
    (close-circuit! cb))

) ;; end library
