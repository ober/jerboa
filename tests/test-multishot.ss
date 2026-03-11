#!chezscheme
;;; Tests for (std effect multishot) — Multishot continuations

(import (chezscheme)
        (std effect)
        (std effect multishot))

(define pass 0)
(define nfail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! nfail (+ nfail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! nfail (+ nfail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(printf "--- (std effect multishot) tests ---~%")

;;; ======== 1. Basic multishot-handler? predicate ========

(test "multishot-handler? is procedure"
  (procedure? multishot-handler?)
  #t)

(test "multishot-continuation? is procedure"
  (procedure? multishot-continuation?)
  #t)

;;; ======== 2. resume/multi basic ========

(test "resume/multi with raw proc"
  (resume/multi (lambda (x) (* x 2)) 5)
  10)

;;; ======== 3. choose / all-solutions — basic ========

(test "all-solutions single value"
  (all-solutions (lambda () 42))
  '(42))

(test "all-solutions empty choices fails"
  (all-solutions (lambda () (choose '())))
  '())

(test "all-solutions single choice"
  (all-solutions (lambda () (choose '(1))))
  '(1))

(test "all-solutions two choices"
  (all-solutions (lambda () (choose '(a b))))
  '(a b))

(test "all-solutions three choices"
  (all-solutions (lambda () (choose '(1 2 3))))
  '(1 2 3))

;;; ======== 4. all-solutions with computation ========

(test "all-solutions computed values"
  (all-solutions (lambda ()
    (* (choose '(1 2 3)) 10)))
  '(10 20 30))

;;; ======== 5. Nested choices (Cartesian product) ========

(test "all-solutions nested choices"
  (all-solutions
    (lambda ()
      (let ([x (choose '(1 2))]
            [y (choose '(a b))])
        (list x y))))
  '((1 a) (1 b) (2 a) (2 b)))

;;; ======== 6. fail / backtracking ========

(test "fail causes empty result"
  (all-solutions (lambda () (fail) 'unreachable))
  '())

(test "fail filters choices"
  (all-solutions
    (lambda ()
      (let ([x (choose '(1 2 3 4 5 6))])
        (when (odd? x) (fail))
        x)))
  '(2 4 6))

;;; ======== 7. one-solution ========

(test "one-solution returns first"
  (one-solution (lambda () (choose '(x y z))))
  'x)

(test "one-solution no choices returns #f"
  (one-solution (lambda () (choose '())))
  #f)

(test "one-solution single"
  (one-solution (lambda () (choose '(42))))
  42)

(test "one-solution after fail returns #f"
  (one-solution (lambda () (fail)))
  #f)

;;; ======== 8. amb macro ========

(test "amb-all collects all"
  (amb-all 10 20 30)
  '(10 20 30))

;;; ======== 9. with-multishot-handler custom effect ========

;; Define a custom effect to test with-multishot-handler directly
(defeffect MChoice
  (pick2 options))

(test "with-multishot-handler single pick"
  (with-multishot-handler
    ([MChoice
      (pick2 (k options)
        (if (null? options)
          'none
          (resume/multi k (car options))))])
    (MChoice pick2 '(hello world)))
  'hello)

;;; ======== 10. all-solutions with guard ========

(test "all-solutions with filtering"
  (all-solutions
    (lambda ()
      (let ([x (choose '(2 3 4 5 6))])
        (unless (even? x) (fail))
        (* x x))))
  '(4 16 36))

;;; ======== 11. sample ========

(test "sample from single choice"
  (sample '(only) '(1))
  'only)

(test "sample from multiple always returns member"
  (let ([choices '(a b c)]
        [weights '(1 1 1)])
    (and (member (sample choices weights) choices) #t))
  #t)

(test "sample result is member of choices"
  (let ([result (sample '(x y z) '(3 2 1))])
    (or (eq? result 'x) (eq? result 'y) (eq? result 'z)))
  #t)

;;; ======== 12. Complex nondeterminism: Pythagorean triples ========

(test "pythagorean triples"
  (all-solutions
    (lambda ()
      (let ([a (choose '(3 4 5))]
            [b (choose '(3 4 5))]
            [c (choose '(3 4 5))])
        (unless (= (* c c) (+ (* a a) (* b b))) (fail))
        (list a b c))))
  '((4 3 5) (3 4 5)))

;;; ======== 13. all-solutions with state side-effect ========

(test "all-solutions independent branches"
  (let ([calls 0])
    (let ([results
           (all-solutions
             (lambda ()
               (set! calls (+ calls 1))
               (choose '(1 2 3))))])
      ;; The choice-sequence approach: 1 initial probe run (fails at branch)
      ;; + 3 option runs = 4 total calls to thunk.
      (list results (>= calls 3))))
  '((1 2 3) #t))

;;; ======== 14. one-solution is lazy ========

(test "one-solution does not explore extra branches"
  (let ([count 0])
    (let ([result
           (one-solution
             (lambda ()
               (let ([x (choose '(1 2 3))])
                 (set! count (+ count 1))
                 x)))])
      ;; one-solution short-circuits after first result: count = 1
      (list result count)))
  '(1 1))

;;; ======== 15. amb-all with two expressions ========

(test "amb-all two"
  (amb-all 'left 'right)
  '(left right))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass nfail) pass nfail)
(when (> nfail 0) (exit 1))
