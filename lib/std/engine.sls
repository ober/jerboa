#!chezscheme
;;; (std engine) — Preemptive evaluation engines
;;;
;;; Exposes Chez Scheme's unique engine system for time-sliced evaluation.
;;; Engines provide cooperative preemption at compiler-inserted safe points.
;;;
;;; (define eng (make-eval-engine (lambda () (fib 40))))
;;; (engine-run eng 1000000)
;;; (engine-result eng)

(library (std engine)
  (export make-eval-engine engine-run engine-result
          engine-expired? engine-map
          timed-eval fuel-eval)

  (import (chezscheme))

  ;; Wrapper around Chez's make-engine with a friendlier API
  (define-record-type eval-engine
    (fields thunk
            (mutable state)      ;; 'pending | 'completed | 'expired
            (mutable value)      ;; result value if completed
            (mutable chez-engine)) ;; the underlying engine
    (protocol
     (lambda (new)
       (lambda (thunk)
         (new thunk 'pending #f (make-engine thunk))))))

  ;; Run engine for N ticks. Returns #t if completed, #f if expired.
  (define (engine-run eng ticks)
    (when (eq? (eval-engine-state eng) 'pending)
      ((eval-engine-chez-engine eng) ticks
       ;; Completed
       (lambda (remaining val)
         (eval-engine-state-set! eng 'completed)
         (eval-engine-value-set! eng val))
       ;; Expired — save continuation engine
       (lambda (new-eng)
         (eval-engine-chez-engine-set! eng new-eng)
         (eval-engine-state-set! eng 'expired))))
    (eq? (eval-engine-state eng) 'completed))

  ;; Get result (or #f if not completed)
  (define (engine-result eng)
    (and (eq? (eval-engine-state eng) 'completed)
         (eval-engine-value eng)))

  ;; Check if engine ran out of fuel
  (define (engine-expired? eng)
    (eq? (eval-engine-state eng) 'expired))

  ;; Transform engine result
  (define (engine-map f eng)
    (make-eval-engine
     (lambda ()
       (f ((eval-engine-thunk eng))))))

  ;; Evaluate with a time budget (seconds). Returns (values result completed?)
  (define (timed-eval seconds thunk)
    (let* ([ticks (max 1 (inexact->exact (round (* seconds 10000000))))]
           [eng (make-engine thunk)])
      (eng ticks
        (lambda (remaining val) (values val #t))
        (lambda (new-eng) (values #f #f)))))

  ;; Evaluate with exact fuel (ticks). Returns (values result completed?)
  (define (fuel-eval ticks thunk)
    (let ([eng (make-engine thunk)])
      (eng ticks
        (lambda (remaining val) (values val #t))
        (lambda (new-eng) (values #f #f)))))

) ;; end library
