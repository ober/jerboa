#!chezscheme
;;; Tests for (std typed) — Gradual typing

(import (chezscheme) (std typed))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn
              [#t (set! fail (+ fail 1))
                  (printf "FAIL ~a: exception ~a~%" name
                    (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1))
                  (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~a, expected ~a~%" name got expected)))))]))

(printf "--- (std typed) tests ---~%")

;; Test 1: define/t with fixnum types (debug mode — assertions)
(parameterize ([*typed-mode* 'debug])
  (define/t (add-fixnums [a : fixnum] [b : fixnum]) : fixnum
    (fx+ a b))
  (test "define/t fixnum add" (add-fixnums 3 4) 7))

;; Test 2: define/t type error in debug mode
(parameterize ([*typed-mode* 'debug])
  (define/t (need-fixnum [x : fixnum]) : fixnum x)
  (test "define/t type error"
    (guard (exn [#t #t])
      (need-fixnum "not a fixnum")
      #f)
    #t))

;; Test 3: define/t in release mode (no assertions)
(parameterize ([*typed-mode* 'release])
  (define/t (add-release [a : fixnum] [b : fixnum]) : fixnum
    (+ a b))
  ;; In release mode, passing wrong types won't error (no checks)
  (test "define/t release no check" (add-release 3 4) 7))

;; Test 4: define/t in none mode (stripped)
(parameterize ([*typed-mode* 'none])
  (define/t (add-none [a : fixnum] [b : fixnum]) : fixnum
    (+ a b))
  (test "define/t none mode" (add-none 3 4) 7))

;; Test 5: define/t without return type
(parameterize ([*typed-mode* 'debug])
  (define/t (greet [name : string])
    (string-append "hello " name))
  (test "define/t no return type" (greet "world") "hello world"))

;; Test 6: define/t return type check
(parameterize ([*typed-mode* 'debug])
  (define/t (bad-return [x : fixnum]) : string
    x)  ;; returns fixnum, not string
  (test "define/t return type error"
    (guard (exn [#t #t])
      (bad-return 42)
      #f)
    #t))

;; Test 7: lambda/t
(parameterize ([*typed-mode* 'debug])
  (let ([f (lambda/t ([x : fixnum] [y : fixnum]) : fixnum
             (fx+ x y))])
    (test "lambda/t" (f 10 20) 30)))

;; Test 8: inline assertion (assert-type)
(parameterize ([*typed-mode* 'debug])
  (test "assert-type pass" (assert-type 42 fixnum) 42)
  (test "assert-type fail"
    (guard (exn [#t #t])
      (assert-type "hello" fixnum)
      #f)
    #t))

;; Test 9: Multiple argument types
(parameterize ([*typed-mode* 'debug])
  (define/t (mixed [n : fixnum] [s : string]) : string
    (string-append s (number->string n)))
  (test "mixed types" (mixed 42 "value=") "value=42"))

;; Test 10: Untyped args (any)
(parameterize ([*typed-mode* 'debug])
  (define/t (identity x) x)
  (test "untyped arg" (identity 'hello) 'hello))

;; Test 11: Register custom type
(register-type-predicate! 'positive (lambda (x) (and (number? x) (> x 0))))
(define/t (need-positive [x : positive]) : positive x)
(parameterize ([*typed-mode* 'debug])
  (test "custom type pass" (need-positive 5) 5)
  (test "custom type fail"
    (guard (exn [#t #t])
      (need-positive -1)
      #f)
    #t))

;;; Phase 2: Parametric Types

;; Test 12: (listof fixnum)
(parameterize ([*typed-mode* 'debug])
  (define/t (sum-fixnums [lst : (listof fixnum)]) : fixnum
    (apply + lst))
  (test "listof fixnum pass" (sum-fixnums '(1 2 3)) 6)
  (test "listof fixnum fail"
    (guard (exn [#t #t])
      (sum-fixnums '(1 "bad" 3))
      #f)
    #t))

;; Test 13: (vectorof string)
(parameterize ([*typed-mode* 'debug])
  (define/t (first-str [v : (vectorof string)]) : string
    (vector-ref v 0))
  (test "vectorof string pass" (first-str (vector "a" "b")) "a")
  (test "vectorof string fail"
    (guard (exn [#t #t])
      (first-str (vector 1 2))
      #f)
    #t))

;; Test 14: (hashof string fixnum) — checks hashtable? only
(parameterize ([*typed-mode* 'debug])
  (define/t (get-count [ht : (hashof string fixnum)] [key : string]) : fixnum
    (hashtable-ref ht key 0))
  (let ([ht (make-hashtable string-hash string=?)])
    (hashtable-set! ht "x" 42)
    (test "hashof pass" (get-count ht "x") 42))
  (test "hashof fail"
    (guard (exn [#t #t])
      (get-count "not-a-table" "x")
      #f)
    #t))

;; Test 15: (-> fixnum fixnum) — checks procedure?
(parameterize ([*typed-mode* 'debug])
  (define/t (apply-fn [f : (-> fixnum fixnum)] [n : fixnum]) : fixnum
    (f n))
  (test "-> type pass" (apply-fn (lambda (x) (+ x 1)) 5) 6)
  (test "-> type fail"
    (guard (exn [#t #t])
      (apply-fn 42 5)
      #f)
    #t))

;;; Phase 3: Op Specialization

;; Test 16: with-fixnum-ops replaces + → fx+
(test "with-fixnum-ops addition"
  (with-fixnum-ops (+ 3 4))
  7)

;; Test 17: with-fixnum-ops in a recursive function
(define (fib-fx n)
  (with-fixnum-ops
    (if (< n 2)
      n
      (+ (fib-fx (- n 1)) (fib-fx (- n 2))))))
(test "with-fixnum-ops fibonacci" (fib-fx 10) 55)

;; Test 18: with-fixnum-ops nested let
(test "with-fixnum-ops let"
  (with-fixnum-ops
    (let ([a 10] [b 3])
      (- a b)))
  7)

;; Test 19: with-fixnum-ops comparison
(test "with-fixnum-ops comparison"
  (with-fixnum-ops
    (and (< 1 2) (>= 5 5)))
  #t)

;; Test 20: with-flonum-ops replaces + → fl+
(test "with-flonum-ops addition"
  (with-flonum-ops (+ 1.5 2.5))
  4.0)

;; Test 21: with-flonum-ops in a computation
(test "with-flonum-ops multiply"
  (with-flonum-ops (* 2.0 3.14))
  6.28)

;; Test 22: with-flonum-ops preserves if/let structure
(test "with-flonum-ops let"
  (with-flonum-ops
    (let ([x 2.0])
      (if (> x 1.0)
        (* x x)
        x)))
  4.0)

;; Test 23: with-fixnum-ops + define/t integration
(parameterize ([*typed-mode* 'release])
  (define/t (dot-product [n : fixnum]) : fixnum
    (with-fixnum-ops
      (let loop ([i 0] [acc 0])
        (if (= i n)
          acc
          (loop (+ i 1) (+ acc i))))))
  (test "define/t with-fixnum-ops" (dot-product 5) 10))

(printf "~%~a tests, ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
