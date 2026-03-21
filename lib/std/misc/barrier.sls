#!chezscheme
;;; (std misc barrier) — Cyclic thread barrier
;;;
;;; All parties must call barrier-wait! before any can proceed.
;;; Automatically resets after all parties arrive (cyclic).
;;;
;;; (define b (make-barrier 3))
;;; ;; In 3 threads: (barrier-wait! b) — blocks until all 3 arrive

(library (std misc barrier)
  (export make-barrier barrier? barrier-wait!
          barrier-reset! barrier-parties barrier-waiting)

  (import (chezscheme))

  (define-record-type barrier
    (fields parties                      ;; total parties needed
            (mutable waiting)            ;; count currently waiting
            (mutable generation)         ;; increments each cycle
            mutex
            condvar)
    (protocol
     (lambda (new)
       (lambda (n)
         (unless (and (fixnum? n) (> n 0))
           (error 'make-barrier "parties must be a positive integer" n))
         (new n 0 0 (make-mutex) (make-condition))))))

  (define (barrier-wait! b)
    (mutex-acquire (barrier-mutex b))
    (let ([gen (barrier-generation b)])
      (barrier-waiting-set! b (+ (barrier-waiting b) 1))
      (if (= (barrier-waiting b) (barrier-parties b))
          ;; Last to arrive — release everyone
          (begin
            (barrier-waiting-set! b 0)
            (barrier-generation-set! b (+ gen 1))
            (condition-broadcast (barrier-condvar b))
            (mutex-release (barrier-mutex b)))
          ;; Wait for others
          (let loop ()
            (when (= gen (barrier-generation b))
              (condition-wait (barrier-condvar b) (barrier-mutex b))
              (loop))
            (mutex-release (barrier-mutex b))))))

  (define (barrier-reset! b)
    (mutex-acquire (barrier-mutex b))
    (barrier-waiting-set! b 0)
    (barrier-generation-set! b (+ (barrier-generation b) 1))
    (condition-broadcast (barrier-condvar b))
    (mutex-release (barrier-mutex b)))

) ;; end library
