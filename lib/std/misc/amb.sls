#!chezscheme
;;; (std misc amb) — Non-deterministic backtracking with amb
;;;
;;; The amb operator enables constraint solving and search:
;;;   (amb 1 2 3) — tries each value; backtracks on failure
;;;   (amb-assert condition) — prunes search if condition is false
;;;   (amb-fail) — explicitly fail and backtrack
;;;
;;; Usage:
;;;   (with-amb
;;;     (let ([x (amb 1 2 3 4 5)]
;;;           [y (amb 1 2 3 4 5)])
;;;       (amb-assert (= (+ x y) 7))
;;;       (cons x y)))
;;;   => (2 . 5)  ; or another pair summing to 7

(library (std misc amb)
  (export amb amb-assert amb-fail with-amb amb-collect)
  (import (chezscheme))

  ;; The failure continuation stack
  (define *amb-fail* (make-parameter #f))

  ;; Signal failure — backtrack to previous choice point
  (define (amb-fail)
    (let ([f (*amb-fail*)])
      (if f
          (f)
          (error 'amb-fail "no more alternatives"))))

  ;; Assert a condition; fail if false
  (define (amb-assert condition)
    (unless condition (amb-fail)))

  ;; Choose one of the alternatives. On failure, try the next.
  (define-syntax amb
    (syntax-rules ()
      [(_) (amb-fail)]
      [(_ x) x]
      [(_ x rest ...)
       (call/cc
         (lambda (k)
           (let ([prev (*amb-fail*)])
             (call/cc
               (lambda (fail-k)
                 (*amb-fail* (lambda ()
                               (*amb-fail* prev)
                               (fail-k #f)))
                 (k x)))
             ;; If we get here, x failed — try rest
             (k (amb rest ...)))))]))

  ;; Run an amb computation, returning the first successful result
  ;; or #f if no solution exists
  (define-syntax with-amb
    (syntax-rules ()
      [(_ body ...)
       (call/cc
         (lambda (exit)
           (parameterize ([*amb-fail* (lambda () (exit #f))])
             (let ([result (begin body ...)])
               (exit result)))))]))

  ;; Collect ALL solutions (not just the first)
  (define-syntax amb-collect
    (syntax-rules ()
      [(_ body ...)
       (let ([results '()])
         (call/cc
           (lambda (exit)
             (parameterize ([*amb-fail* (lambda () (exit (reverse results)))])
               (let ([result (begin body ...)])
                 (set! results (cons result results))
                 (amb-fail))))))]))

) ;; end library
