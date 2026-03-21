#!chezscheme
;;; (std misc wg) — Wait Groups (Go-style thread coordination)
;;;
;;; Dynamic counter-based synchronization:
;;; (wg-add wg n) increments, (wg-done wg) decrements,
;;; (wg-wait wg) blocks until counter reaches 0.

(library (std misc wg)
  (export make-wg wg? wg-add wg-done wg-wait)

  (import (chezscheme))

  (define-record-type wg
    (fields (mutable count)
            mutex
            condvar)
    (protocol
      (lambda (new)
        (lambda ()
          (new 0 (make-mutex) (make-condition))))))

  ;; Increment pending count
  (define wg-add
    (case-lambda
      [(wg) (wg-add wg 1)]
      [(wg n)
       (with-mutex (wg-mutex wg)
         (wg-count-set! wg (+ (wg-count wg) n)))]))

  ;; Signal one task complete
  (define (wg-done wg)
    (with-mutex (wg-mutex wg)
      (let ([new-count (- (wg-count wg) 1)])
        (wg-count-set! wg new-count)
        (when (<= new-count 0)
          (condition-broadcast (wg-condvar wg))))))

  ;; Block until count reaches 0
  (define (wg-wait wg)
    (with-mutex (wg-mutex wg)
      (let loop ()
        (unless (<= (wg-count wg) 0)
          (condition-wait (wg-condvar wg) (wg-mutex wg))
          (loop)))))

) ;; end library
