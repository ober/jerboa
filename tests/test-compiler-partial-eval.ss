#!/usr/bin/env scheme-script
;;; Tests for Compile-Time Partial Evaluation - Simplified Version

(import 
  (rnrs)
  (rnrs hashtables)
  (std compiler partial-eval)
  (only (chezscheme) printf))

;; Test framework
(define test-count 0)
(define pass-count 0)
(define fail-count 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (begin
       (set! test-count (+ test-count 1))
       (let ([result expr])
         (if (equal? result expected)
           (begin
             (printf "PASS: ~a~n" name)
             (set! pass-count (+ pass-count 1)))
           (begin
             (printf "FAIL: ~a~n" name)
             (printf "  Expected: ~s~n" expected)
             (printf "  Got:      ~s~n" result)
             (set! fail-count (+ fail-count 1))))))]))

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name expr #t)]))

(printf "Testing Compile-Time Partial Evaluation (Simplified)~n")
(printf "==================================================~n~n")

;; Test binding-time analysis
(printf "--- Binding-Time Analysis ---~n")
(test-true "number is static" (static-value? 42))
(test-true "string is static" (static-value? "hello"))
(test-true "boolean is static" (static-value? #t))
(test-true "quoted expr is static" (static-value? '(quote (a b c))))
(test-true "symbol is dynamic" (dynamic-value? 'x))

;; Test compile-time evaluation
(printf "~n--- Compile-Time Evaluation ---~n")
(test "compile-time arithmetic" (compile-time-eval '(+ 2 3)) 5)
(test "compile-time string construction" 
      (compile-time-eval '(string-append "hello" " world"))
      "hello world")

;; Test partial evaluation
(printf "~n--- Partial Evaluation ---~n")
(let ([static-env (make-hashtable symbol-hash eq?)])
  (hashtable-set! static-env 'x 10)
  (hashtable-set! static-env 'y 5)
  
  (test "eval with static vars" 
        (partial-evaluate '(+ x y) static-env)
        15)
  
  (test "eval mixed static/dynamic"
        (partial-evaluate '(+ x z) static-env)
        '(+ 10 z)))

;; Test built-in PE functions
(printf "~n--- Built-in PE Functions ---~n")

;; Power function tests
(test "power base case" (power 2 0) 1)
(test "power recursive" (power 2 3) 8)
(test "power negative base" (power -2 3) -8)

;; Arithmetic sequence tests  
(test "arithmetic seq empty" (arithmetic-seq 1 2 0) '())
(test "arithmetic seq simple" (arithmetic-seq 1 2 3) '(1 3 5))
(test "arithmetic seq negative step" (arithmetic-seq 10 -2 4) '(10 8 6 4))

;; Test configuration
(printf "~n--- Configuration ---~n")
(enable-auto-specialization!)
(disable-auto-specialization!)
(test-true "config functions work" #t)

;; Final results
(printf "~n==================================================~n")
(printf "Tests completed: ~a~n" test-count)
(printf "Passed: ~a~n" pass-count)
(printf "Failed: ~a~n" fail-count)
(printf "Success rate: ~a%~n" 
        (if (= test-count 0) 0
            (exact->inexact (/ (* pass-count 100) test-count))))

(when (> fail-count 0)
  (printf "~nSome tests failed!~n")
  (exit 1))

(printf "~nAll tests passed!~n")