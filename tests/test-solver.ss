#!chezscheme
;;; Tests for (std typed solver) — Lightweight constraint solver

(import (chezscheme) (std typed solver))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(printf "--- (std typed solver) tests ---~%")

;;; ===== Literal analysis =====

(test "is-literal-zero? 0"      (is-literal-zero? 0)    #t)
(test "is-literal-zero? 1"      (is-literal-zero? 1)    #f)
(test "is-literal-zero? -1"     (is-literal-zero? -1)   #f)
(test "is-literal-zero? string" (is-literal-zero? "0")  #f)

(test "is-literal-null? '()"    (is-literal-null? '())     #t)
(test "is-literal-null? pair"   (is-literal-null? '(1 2))  #f)
(test "is-literal-null? 0"      (is-literal-null? 0)       #f)

(test "is-literal-positive? 1"   (is-literal-positive? 1)    #t)
(test "is-literal-positive? 100" (is-literal-positive? 100)  #t)
(test "is-literal-positive? 0"   (is-literal-positive? 0)    #f)
(test "is-literal-positive? -1"  (is-literal-positive? -1)   #f)

;;; ===== make-constraint / constraint? =====

(let ([c (make-constraint 'zero? '(0))])
  (test "constraint? true"  (constraint? c)       #t)
  (test "constraint-pred"   (constraint-pred c)   'zero?)
  (test "constraint-args"   (constraint-args c)   '(0)))

(test "constraint? false" (constraint? 42) #f)

;;; ===== solve-constraint: zero? =====

(test "solve zero? 0 → satisfied"
  (solve-constraint (make-constraint 'zero? '(0)))
  'satisfied)

(test "solve zero? 1 → violated"
  (solve-constraint (make-constraint 'zero? '(1)))
  'violated)

(test "solve zero? 0.0 → satisfied"
  (solve-constraint (make-constraint 'zero? '(0.0)))
  'satisfied)

(test "solve zero? x → unknown"
  (solve-constraint (make-constraint 'zero? '(x)))
  'unknown)

;;; ===== solve-constraint: null? =====

(test "solve null? '() → satisfied"
  (solve-constraint (make-constraint 'null? (list '())))
  'satisfied)

(test "solve null? pair → violated"
  (solve-constraint (make-constraint 'null? (list '(1 2))))
  'violated)

(test "solve null? x → unknown"
  (solve-constraint (make-constraint 'null? '(x)))
  'unknown)

;;; ===== solve-constraint: positive? =====

(test "solve positive? 5 → satisfied"
  (solve-constraint (make-constraint 'positive? '(5)))
  'satisfied)

(test "solve positive? 0 → violated"
  (solve-constraint (make-constraint 'positive? '(0)))
  'violated)

(test "solve positive? -3 → violated"
  (solve-constraint (make-constraint 'positive? '(-3)))
  'violated)

(test "solve positive? x → unknown"
  (solve-constraint (make-constraint 'positive? '(x)))
  'unknown)

;;; ===== solve-constraint: number? =====

(test "solve number? 42 → satisfied"
  (solve-constraint (make-constraint 'number? '(42)))
  'satisfied)

(test "solve number? \"str\" → violated"
  (solve-constraint (make-constraint 'number? (list "hello")))
  'violated)

(test "solve number? x → unknown"
  (solve-constraint (make-constraint 'number? '(x)))
  'unknown)

;;; ===== can-prove? / can-refute? =====

(test "can-prove? zero? 0"
  (can-prove? (make-constraint 'zero? '(0)))
  #t)

(test "can-prove? zero? 1 is #f"
  (can-prove? (make-constraint 'zero? '(1)))
  #f)

(test "can-refute? zero? 1"
  (can-refute? (make-constraint 'zero? '(1)))
  #t)

(test "can-refute? zero? 0 is #f"
  (can-refute? (make-constraint 'zero? '(0)))
  #f)

(test "can-prove? unknown is #f"
  (can-prove? (make-constraint 'zero? '(x)))
  #f)

(test "can-refute? unknown is #f"
  (can-refute? (make-constraint 'zero? '(x)))
  #f)

;;; ===== Solver context =====

(let ([ctx (make-solver-context)])
  (solver-context-add! ctx 'x 'zero)
  (test "context lookup found"
    (solver-context-lookup ctx 'x)
    'zero)
  (test "context lookup missing"
    (solver-context-lookup ctx 'y)
    #f))

;;; ===== with-solver-context =====

(let ([ctx (make-solver-context)])
  (solver-context-add! ctx 'n 'zero)
  (test "with-solver-context: zero? n → satisfied"
    (with-solver-context ctx
      (lambda ()
        (solve-constraint (make-constraint 'zero? '(n)))))
    'satisfied))

(let ([ctx (make-solver-context)])
  (solver-context-add! ctx 'n 'positive)
  (test "with-solver-context: zero? n → violated"
    (with-solver-context ctx
      (lambda ()
        (solve-constraint (make-constraint 'zero? '(n)))))
    'violated))

(let ([ctx (make-solver-context)])
  (solver-context-add! ctx 'lst 'null)
  (test "with-solver-context: null? lst → satisfied"
    (with-solver-context ctx
      (lambda ()
        (solve-constraint (make-constraint 'null? '(lst)))))
    'satisfied))

(let ([ctx (make-solver-context)])
  (solver-context-add! ctx 'lst 'non-null)
  (test "with-solver-context: null? lst → violated"
    (with-solver-context ctx
      (lambda ()
        (solve-constraint (make-constraint 'null? '(lst)))))
    'violated))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
