#!chezscheme
;;; Tests for (jerboa wasm runtime) -- WebAssembly interpreter

(import (except (chezscheme) compile-program)
        (jerboa wasm format)
        (jerboa wasm codegen)
        (jerboa wasm runtime))

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
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Phase 3e: WASM Runtime ---~%~%")

;;; ======== Basic runtime construction ========

(test "make-wasm-runtime"
  (wasm-runtime? (make-wasm-runtime))
  #t)

(test "make-wasm-store"
  (wasm-store? (make-wasm-store))
  #t)

;;; ======== Decode valid WASM module ========

(test "decode empty module"
  (let* ([bv (compile-program '((define (const42) 42)))]
         [mod (wasm-decode-module bv)])
    (not (null? (wasm-module-sections mod))))
  #t)

(test "wasm-module-sections returns list"
  (let* ([bv (compile-program '((define (foo x) x)))]
         [mod (wasm-decode-module bv)])
    (list? (wasm-module-sections mod)))
  #t)

;;; ======== Store instantiation ========

(test "store-instantiate returns instance"
  (let* ([bv (compile-program '((define (identity x) x)))]
         [decoded (wasm-decode-module bv)]
         [store (make-wasm-store)]
         [inst (wasm-store-instantiate store decoded)])
    (wasm-instance? inst))
  #t)

(test "instance has exports"
  (let* ([bv (compile-program '((define (foo x) x)))]
         [decoded (wasm-decode-module bv)]
         [store (make-wasm-store)]
         [inst (wasm-store-instantiate store decoded)])
    (list? (wasm-instance-exports inst)))
  #t)

;;; ======== Runtime load and call ========

(test "runtime load"
  (let* ([bv (compile-program '((define (identity x) x)))]
         [rt (make-wasm-runtime)])
    (wasm-instance? (wasm-runtime-load rt bv)))
  #t)

(test "call identity(5) = 5"
  (let* ([bv (compile-program '((define (identity x) x)))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "identity" 5))
  5)

(test "call identity(0) = 0"
  (let* ([bv (compile-program '((define (identity x) x)))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "identity" 0))
  0)

(test "call const42() = 42"
  (let* ([bv (compile-program '((define (const42) 42)))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "const42"))
  42)

;;; ======== Arithmetic ========

(test "add(3, 4) = 7"
  (let* ([bv (compile-program '((define (add a b) (+ a b))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "add" 3 4))
  7)

(test "sub(10, 3) = 7"
  (let* ([bv (compile-program '((define (sub a b) (- a b))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "sub" 10 3))
  7)

(test "mul(6, 7) = 42"
  (let* ([bv (compile-program '((define (mul a b) (* a b))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "mul" 6 7))
  42)

(test "div(20, 4) = 5"
  (let* ([bv (compile-program '((define (div a b) (quotient a b))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "div" 20 4))
  5)

;;; ======== Comparisons ========

(test "eq(5, 5) = 1"
  (let* ([bv (compile-program '((define (eq a b) (= a b))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "eq" 5 5))
  1)

(test "eq(3, 5) = 0"
  (let* ([bv (compile-program '((define (eq a b) (= a b))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "eq" 3 5))
  0)

(test "lt(3, 5) = 1"
  (let* ([bv (compile-program '((define (lt a b) (< a b))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "lt" 3 5))
  1)

(test "lt(5, 3) = 0"
  (let* ([bv (compile-program '((define (lt a b) (< a b))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "lt" 5 3))
  0)

;;; ======== Conditionals ========

(test "if true branch"
  (let* ([bv (compile-program '((define (choose c a b) (if (= c 1) a b))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "choose" 1 100 200))
  100)

(test "if false branch"
  (let* ([bv (compile-program '((define (choose c a b) (if (= c 1) a b))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "choose" 0 100 200))
  200)

;;; ======== Let bindings ========

(test "let binding"
  (let* ([bv (compile-program '((define (double-add x) (let ([y (+ x x)]) (+ y 1)))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "double-add" 5))
  11)

;;; ======== More complex programs ========

(test "factorial-like (non-recursive, unrolled)"
  (let* ([bv (compile-program
               '((define (six-fact)
                   ;; 3 * 2 * 1
                   (* 3 (* 2 1)))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "six-fact"))
  6)

(test "nested arithmetic"
  (let* ([bv (compile-program '((define (expr a b c) (+ (* a b) c))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "expr" 3 4 5))
  17)

(test "multiple locals"
  (let* ([bv (compile-program
               '((define (calc x)
                   (let ([a (+ x 1)])
                     (let ([b (* a 2)])
                       b)))))]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (wasm-runtime-call rt "calc" 5))
  12)

;;; ======== Trap behavior ========

(test "wasm-trap? predicate"
  (wasm-trap? (make-wasm-trap "test error"))
  #t)

(test "wasm-trap-message"
  (wasm-trap-message (make-wasm-trap "division by zero"))
  "division by zero")

(test "trap on divide by zero"
  (guard (exn [#t 'trapped])
    (let* ([bv (compile-program '((define (divz x) (quotient x 0))))]
           [rt (make-wasm-runtime)])
      (wasm-runtime-load rt bv)
      (wasm-runtime-call rt "divz" 5)
      'no-trap))
  'trapped)

;;; ======== wasm-run-start ========

(test "wasm-run-start returns #f (no start section)"
  (let* ([bv (compile-program '((define (foo x) x)))]
         [decoded (wasm-decode-module bv)]
         [store (make-wasm-store)]
         [inst (wasm-store-instantiate store decoded)])
    (wasm-run-start inst))
  #f)

;;; Summary

(printf "~%WASM Runtime: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
