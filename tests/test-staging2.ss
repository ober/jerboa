#!chezscheme
;;; Tests for (std staging2) — Enhanced Multi-Stage Programming

(import (chezscheme) (std staging2))

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

(define-syntax test-pred
  (syntax-rules ()
    [(_ name expr pred)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (pred got)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: predicate failed on ~s~%" name got)))))]))

(printf "--- (std staging2) tests ---~%")

;; ======== Code Quotation ========

(printf "~%-- Code Quotation --~%")

(test "quote-stage creates staged object"
  (staged? (quote-stage (+ 1 2)))
  #t)

(test "staged? false for non-staged"
  (staged? 42)
  #f)

(test "staged-code extracts expression"
  (staged-code (quote-stage (+ 1 2)))
  '(+ 1 2))

(test "staged-code extracts symbol"
  (staged-code (quote-stage x))
  'x)

(test "staged-code extracts nested"
  (staged-code (quote-stage (if #t 1 2)))
  '(if #t 1 2))

(test "staged-eval evaluates expression"
  (staged-eval (quote-stage (+ 3 4)))
  7)

(test "staged-eval evaluates with standard env"
  (staged-eval (quote-stage (string-append "hello" " " "world")))
  "hello world")

(test "staged-eval on raw datum"
  (staged-eval '(+ 10 20))
  30)

;; ======== Staged Functions ========

(printf "~%-- Staged Functions --~%")

;; define-staged: ct-arg is the compile-time arg, rt-args are run-time
(define-staged (make-adder base) (x)
  (+ base x))

(test "define-staged creates staged function"
  (procedure? make-adder)
  #t)

(test "define-staged specializes"
  (let ([add5 (make-adder 5)])
    (add5 3))
  8)

(test "define-staged different specializations"
  (let ([add10 (make-adder 10)]
        [add20 (make-adder 20)])
    (list (add10 1) (add20 1)))
  '(11 21))

(define-staged (make-multiplier factor) (x)
  (* factor x))

(test "define-staged: multiplier"
  (let ([double (make-multiplier 2)]
        [triple (make-multiplier 3)])
    (list (double 5) (triple 5)))
  '(10 15))

;; lambda-staged
(test "lambda-staged creates anonymous staged fn"
  (let ([fn (lambda-staged (base) (x) (+ base x))])
    ((fn 100) 1))
  101)

;; ======== Specialization ========

(printf "~%-- Specialization --~%")

(test "specialize applies first arg"
  (let ([add-n (lambda (n x) (+ n x))]
        [add5  (specialize (lambda (n) (lambda (x) (+ n x))) 5)])
    (add5 3))
  8)

(test "specialize with define-staged result"
  (let ([triple (specialize make-multiplier 3)])
    (triple 7))
  21)

;; ======== partial-eval ========

(printf "~%-- partial-eval --~%")

(test "partial-eval: symbol lookup"
  (partial-eval 'x '((x . 42)))
  42)

(test "partial-eval: unknown symbol"
  (partial-eval 'y '((x . 42)))
  'y)

(test "partial-eval: literal passthrough"
  (partial-eval 99 '())
  99)

(test "partial-eval: constant folding +"
  (partial-eval '(+ 3 4) '())
  7)

(test "partial-eval: constant folding *"
  (partial-eval '(* 6 7) '())
  42)

(test "partial-eval: mixed known/unknown"
  (partial-eval '(+ x 1) '((x . 10)))
  11)

(test "partial-eval: if #t folds to then"
  (partial-eval '(if #t 'yes 'no) '())
  '(quote yes))

(test "partial-eval: if #f folds to else"
  (partial-eval '(if #f 'yes 'no) '())
  '(quote no))

(test "partial-eval: nested arithmetic"
  (partial-eval '(+ (* 2 3) (* 4 5)) '())
  26)

(test "partial-eval: let with constant binding"
  (partial-eval '(let ([x 5]) (+ x 1)) '())
  '(let ((x 5)) 6))

;; ======== stage-if, stage-begin, stage-apply ========

(printf "~%-- Code Generation Utilities --~%")

(test "stage-if creates staged if"
  (let ([s (stage-if #t 'yes 'no)])
    (and (staged? s)
         (equal? (staged-code s) '(if #t yes no))))
  #t)

(test "stage-begin creates staged begin"
  (let ([s (stage-begin 1 2 3)])
    (and (staged? s)
         (equal? (staged-code s) '(begin 1 2 3))))
  #t)

(test "stage-apply creates staged call"
  (let ([s (stage-apply '+ (list 1 2 3))])
    (and (staged? s)
         (equal? (staged-code s) '(+ 1 2 3))))
  #t)

(test "stage-apply with staged args"
  (let ([arg1 (quote-stage 10)]
        [arg2 (quote-stage 20)])
    (staged-code (stage-apply '+ (list arg1 arg2))))
  '(+ 10 20))

;; ======== Optimization Helpers ========

(printf "~%-- Optimization Helpers --~%")

(test "constant-fold: arithmetic"
  (constant-fold '(+ 2 3))
  5)

(test "constant-fold: nested"
  (constant-fold '(+ (* 2 3) 4))
  10)

(test "constant-fold: unknown args unchanged"
  (constant-fold '(+ x 1))
  '(+ x 1))

(test "constant-fold: non-arithmetic unchanged"
  (constant-fold '(cons 1 2))
  '(cons 1 2))

(test "inline-calls: simple inlining"
  (inline-calls '(double 5) '((double (x) (* 2 x))))
  '(* 2 5))

(test "inline-calls: nested"
  (inline-calls '(add1 (add1 3)) '((add1 (x) (+ x 1))))
  '(+ (+ 3 1) 1))

(test "inline-calls + constant-fold"
  (constant-fold (inline-calls '(double 5) '((double (x) (* 2 x)))))
  10)

(test "inline-calls: unknown fn unchanged"
  (inline-calls '(foo 1 2) '())
  '(foo 1 2))

(test "dead-code-elim: (if #t then else) -> then"
  (dead-code-elim '(if #t 'yes 'no))
  '(quote yes))

(test "dead-code-elim: (if #f then else) -> else"
  (dead-code-elim '(if #f 'yes 'no))
  '(quote no))

(test "dead-code-elim: unknown test unchanged"
  (dead-code-elim '(if x 1 2))
  '(if x 1 2))

(test "dead-code-elim: nested"
  (dead-code-elim '(if #t (if #f 'a 'b) 'c))
  '(quote b))

;; ======== gensym-stage ========

(printf "~%-- Utilities --~%")

(test "gensym-stage returns symbol"
  (symbol? (gensym-stage))
  #t)

(test "gensym-stage unique"
  (not (eq? (gensym-stage) (gensym-stage)))
  #t)

;; ======== with-stage-env ========

(test "with-stage-env binds values"
  (with-stage-env ([x 10] [y 20])
    (+ x y))
  30)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
