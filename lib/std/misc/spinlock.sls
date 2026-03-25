#!chezscheme
;;; (std misc spinlock) -- CAS-based spin locks
;;;
;;; Ported from Gerbil v0.19 (vyzo). Uses Chez box-cas! instead of
;;; Gambit ##vector-cas!. Suitable for very short critical sections
;;; where mutex overhead is undesirable (e.g., object caches).

(library (std misc spinlock)
  (export make-spinlock spinlock? spin-lock! spin-unlock! with-spinlock)
  (import (chezscheme))

  ;; Internal record — constructor is %make-spinlock
  (define-record-type (%spinlock %make-spinlock spinlock?)
    (nongenerative spinlock-8f3a2b1c)
    (sealed #t)
    (fields (immutable lock)       ; box: #f or owner-thread-id
            (immutable max-spin))) ; fixnum

  (define make-spinlock
    (case-lambda
      (()         (%make-spinlock (box #f) 10))
      ((max-spin) (%make-spinlock (box #f) max-spin))))

  (define (spin-lock! lock)
    (let ((lk (%spinlock-lock lock))
          (max-spin (%spinlock-max-spin lock))
          (me (get-thread-id)))
      (let again ((spin 0))
        (cond
          ((box-cas! lk #f me)
           (void))  ; acquired
          ((fx< spin max-spin)
           (again (fx+ spin 1)))
          (else
           ;; Deadlock check: if we own it, error
           (let ((owner (unbox lk)))
             (when (eqv? owner me)
               (error 'spin-lock! "deadlock: current thread already holds spinlock" lock)))
           (sleep (make-time 'time-duration 0 0))
           (again 0))))))

  (define (spin-unlock! lock)
    (set-box! (%spinlock-lock lock) #f))

  ;; Macro: acquire, run body, release (even on exception).
  (define-syntax with-spinlock
    (lambda (stx)
      (syntax-case stx ()
        ((_ lock expr)
         #'(let ((lk lock))
             (spin-lock! lk)
             (let ((result (guard (e (else (spin-unlock! lk) (raise e)))
                             expr)))
               (spin-unlock! lk)
               result)))
        ((_ lock expr rest ...)
         #'(with-spinlock lock (begin expr rest ...))))))

) ;; end library
