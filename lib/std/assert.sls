#!chezscheme
;;; :std/assert -- Assertion library

(library (std assert)
  (export assert!
          assert-equal!
          assert-pred
          assert-exception)
  (import (chezscheme))

  ;; (assert! expr) or (assert! expr "message")
  ;; Raises an error with the expression text if expr is #f.
  (define-syntax assert!
    (syntax-rules ()
      [(_ expr)
       (unless expr
         (error 'assert! (format "assertion failed: ~s" 'expr)))]
      [(_ expr msg)
       (unless expr
         (error 'assert! (format "assertion failed: ~a (~s)" msg 'expr)))]))

  ;; (assert-equal! actual expected)
  ;; Compare with equal?, raise error showing both values on mismatch.
  (define (assert-equal! actual expected)
    (unless (equal? actual expected)
      (error 'assert-equal!
             (format "expected ~s, got ~s" expected actual))))

  ;; (assert-pred pred val)
  ;; Assert that (pred val) is true.
  (define (assert-pred pred val)
    (unless (pred val)
      (error 'assert-pred
             (format "predicate ~s failed for value ~s" pred val))))

  ;; (assert-exception thunk)
  ;; Assert that thunk raises an exception. Returns the raised condition.
  (define (assert-exception thunk)
    (let ([result (guard (e [#t (cons 'caught e)])
                    (thunk)
                    '(no-exception))])
      (if (and (pair? result) (eq? (car result) 'caught))
        (cdr result)
        (error 'assert-exception
               "expected an exception but none was raised"))))

  ) ;; end library
