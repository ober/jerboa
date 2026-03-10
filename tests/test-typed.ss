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

(printf "~%~a tests, ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
