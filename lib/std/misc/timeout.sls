#!chezscheme
;;; (std misc timeout) — Timeout-wrapped operations using Chez engines
;;;
;;; Leverages Chez Scheme's unique engine system for preemptive time-slicing.
;;; Engines provide tick-based fuel at compiler-inserted safe points.
;;;
;;; (with-timeout 1.0 'timed-out (lambda () (long-computation)))
;;; => result or 'timed-out

(library (std misc timeout)
  (export with-timeout make-timeout-value timeout-value timeout-value?
          timeout-value-message call-with-timeout)

  (import (chezscheme))

  ;; Sentinel for timeout
  (define-record-type timeout-value
    (fields message)
    (protocol
     (lambda (new)
       (case-lambda
         [() (new "operation timed out")]
         [(msg) (new msg)]))))

  ;; Run thunk with a timeout using Chez engines.
  ;; seconds: time limit (inexact, in seconds)
  ;; default: value returned on timeout
  ;; thunk: computation to run
  (define (with-timeout seconds default thunk)
    ;; Convert seconds to ticks (rough estimate: ~10M ticks/second)
    (let* ([ticks (max 1 (inexact->exact (round (* seconds 10000000))))]
           [eng (make-engine thunk)])
      (eng ticks
        ;; completed: (ticks-left value)
        (lambda (ticks-left value) value)
        ;; expired: (new-engine)
        (lambda (new-engine) default))))

  ;; Procedural variant returning (values result timed-out?)
  (define (call-with-timeout seconds thunk)
    (let* ([ticks (max 1 (inexact->exact (round (* seconds 10000000))))]
           [eng (make-engine thunk)])
      (eng ticks
        (lambda (ticks-left value) (values value #f))
        (lambda (new-engine) (values (make-timeout-value) #t)))))

) ;; end library
