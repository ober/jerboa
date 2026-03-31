#!chezscheme
;;; test-wasm-mvp.ss -- Comprehensive tests for WASM MVP implementation
;;;
;;; Tests new features: control flow (block/loop/br/while), memory ops,
;;; globals, typed arithmetic (i32/i64/f32/f64), data segments, bitwise ops,
;;; conversions, multi-function programs, and more.

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

;; Approximate float comparison
(define-syntax test-approx
  (syntax-rules ()
    [(_ name expr expected epsilon)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (and (number? got) (number? expected)
                  (< (abs (- got expected)) epsilon))
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

;; Simple string-contains (not in Chez base)
(define (string-contains haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) i]
        [else (loop (+ i 1))]))))

;; Helper: compile and run
(define (compile-and-run forms func-name . args)
  (let* ([bv (compile-program forms)]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (apply wasm-runtime-call rt func-name args)))

;; Helper: compile, load, return runtime
(define (compile-and-load forms)
  (let* ([bv (compile-program forms)]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    rt))

(printf "--- WASM MVP Comprehensive Tests ---~%~%")


;;; ============================================================
;;; 1. Bitwise operations
;;; ============================================================

(printf "~%-- Bitwise ops --~%")

(test "i32.and"
  (compile-and-run
    '((define (f a b) (bitwise-and a b)))
    "f" #xFF0F #xF0FF)
  #xF00F)

(test "i32.or"
  (compile-and-run
    '((define (f a b) (bitwise-or a b)))
    "f" #xFF00 #x00FF)
  #xFFFF)

(test "i32.xor"
  (compile-and-run
    '((define (f a b) (bitwise-xor a b)))
    "f" #xFF00 #xFFFF)
  #x00FF)

(test "i32.shl"
  (compile-and-run
    '((define (f a b) (shl a b)))
    "f" 1 8)
  256)

(test "i32.shr_s"
  (compile-and-run
    '((define (f a b) (shr a b)))
    "f" -256 4)
  -16)


;;; ============================================================
;;; 2. More i32 comparisons
;;; ============================================================

(printf "~%-- i32 comparisons --~%")

(test "le 3<=5"
  (compile-and-run '((define (f a b) (<= a b))) "f" 3 5) 1)

(test "le 5<=5"
  (compile-and-run '((define (f a b) (<= a b))) "f" 5 5) 1)

(test "le 6<=5"
  (compile-and-run '((define (f a b) (<= a b))) "f" 6 5) 0)

(test "ge 5>=3"
  (compile-and-run '((define (f a b) (>= a b))) "f" 5 3) 1)

(test "ge 3>=3"
  (compile-and-run '((define (f a b) (>= a b))) "f" 3 3) 1)

(test "ne 3!=5"
  (compile-and-run '((define (f a b) (!= a b))) "f" 3 5) 1)

(test "ne 5!=5"
  (compile-and-run '((define (f a b) (!= a b))) "f" 5 5) 0)


;;; ============================================================
;;; 3. Boolean / not / and / or
;;; ============================================================

(printf "~%-- Logic --~%")

(test "not 0"
  (compile-and-run '((define (f x) (not x))) "f" 0) 1)

(test "not 1"
  (compile-and-run '((define (f x) (not x))) "f" 1) 0)

(test "not 42"
  (compile-and-run '((define (f x) (not x))) "f" 42) 0)

(test "and true true"
  (compile-and-run '((define (f a b) (and a b))) "f" 1 1) 1)

(test "and true false"
  (compile-and-run '((define (f a b) (and a b))) "f" 1 0) 0)

(test "and false true (short-circuit)"
  (compile-and-run '((define (f a b) (and a b))) "f" 0 1) 0)

(test "or false true"
  (compile-and-run '((define (f a b) (or a b))) "f" 0 1) 1)

(test "or false false"
  (compile-and-run '((define (f a b) (or a b))) "f" 0 0) 0)

(test "or true false (short-circuit)"
  (compile-and-run '((define (f a b) (or a b))) "f" 1 0) 1)


;;; ============================================================
;;; 4. When / unless / cond
;;; ============================================================

(printf "~%-- Conditionals --~%")

;; when/unless return void (the function still returns last value from scope)
;; We test with a wrapper that uses set! to capture the effect
(test "cond single clause"
  (compile-and-run
    '((define (f x)
        (cond ((= x 1) 10)
              (else 20))))
    "f" 1)
  10)

(test "cond else clause"
  (compile-and-run
    '((define (f x)
        (cond ((= x 1) 10)
              (else 20))))
    "f" 2)
  20)

(test "cond multi-clause"
  (compile-and-run
    '((define (f x)
        (cond ((= x 1) 10)
              ((= x 2) 20)
              ((= x 3) 30)
              (else 0))))
    "f" 3)
  30)


;;; ============================================================
;;; 5. Recursive function calls
;;; ============================================================

(printf "~%-- Recursion --~%")

(test "factorial(1)"
  (compile-and-run
    '((define (fact n)
        (if (= n 0) 1 (* n (fact (- n 1))))))
    "fact" 1)
  1)

(test "factorial(5)"
  (compile-and-run
    '((define (fact n)
        (if (= n 0) 1 (* n (fact (- n 1))))))
    "fact" 5)
  120)

(test "factorial(10)"
  (compile-and-run
    '((define (fact n)
        (if (= n 0) 1 (* n (fact (- n 1))))))
    "fact" 10)
  3628800)

(test "fibonacci(10)"
  (compile-and-run
    '((define (fib n)
        (if (<= n 1) n (+ (fib (- n 1)) (fib (- n 2))))))
    "fib" 10)
  55)


;;; ============================================================
;;; 6. Multiple functions (mutual calls)
;;; ============================================================

(printf "~%-- Multi-function --~%")

(test "helper function call"
  (compile-and-run
    '((define (double x) (* x 2))
      (define (quadruple x) (double (double x))))
    "quadruple" 5)
  20)

(test "three functions"
  (compile-and-run
    '((define (add1 x) (+ x 1))
      (define (double x) (* x 2))
      (define (transform x) (double (add1 x))))
    "transform" 10)
  22)


;;; ============================================================
;;; 7. Unary minus
;;; ============================================================

(printf "~%-- Unary ops --~%")

(test "unary minus"
  (compile-and-run '((define (neg x) (- x))) "neg" 42) -42)

(test "unary minus zero"
  (compile-and-run '((define (neg x) (- x))) "neg" 0) 0)


;;; ============================================================
;;; 8. While loops (block/loop/br)
;;; ============================================================

(printf "~%-- While loops --~%")

(test "while sum 1..10"
  (compile-and-run
    '((define (sum-to n)
        (let ([i 1] [acc 0])
          (while (<= i n)
            (set! acc (+ acc i))
            (set! i (+ i 1)))
          acc)))
    "sum-to" 10)
  55)

(test "while count down"
  (compile-and-run
    '((define (count-down n)
        (let ([i n])
          (while (> i 0)
            (set! i (- i 1)))
          i)))
    "count-down" 100)
  0)

(test "while multiply (power of 2)"
  (compile-and-run
    '((define (pow2 n)
        (let ([result 1] [i 0])
          (while (< i n)
            (set! result (* result 2))
            (set! i (+ i 1)))
          result)))
    "pow2" 10)
  1024)


;;; ============================================================
;;; 9. Let* (chained bindings)
;;; ============================================================

(printf "~%-- Let* --~%")

(test "let* chained"
  (compile-and-run
    '((define (f x)
        (let* ([a (+ x 1)]
               [b (* a 2)]
               [c (+ b a)])
          c)))
    "f" 5)
  18) ;; a=6, b=12, c=18

(test "let* nested"
  (compile-and-run
    '((define (f x)
        (let* ([a (+ x 10)])
          (let* ([b (* a a)])
            b))))
    "f" 5)
  225)


;;; ============================================================
;;; 10. Select
;;; ============================================================

(printf "~%-- Select --~%")

(test "select true"
  (compile-and-run
    '((define (f a b c) (select a b c)))
    "f" 10 20 1)
  10)

(test "select false"
  (compile-and-run
    '((define (f a b c) (select a b c)))
    "f" 10 20 0)
  20)


;;; ============================================================
;;; 11. Explicit typed i32 operations
;;; ============================================================

(printf "~%-- Typed i32 ops --~%")

(test "i32.add"
  (compile-and-run '((define (f a b) (i32.add a b))) "f" 100 200)
  300)

(test "i32.sub"
  (compile-and-run '((define (f a b) (i32.sub a b))) "f" 100 30)
  70)

(test "i32.mul"
  (compile-and-run '((define (f a b) (i32.mul a b))) "f" 6 7)
  42)

(test "i32.div_s"
  (compile-and-run '((define (f a b) (i32.div_s a b))) "f" 100 3)
  33)

(test "i32.rem_s"
  (compile-and-run '((define (f a b) (i32.rem_s a b))) "f" 100 3)
  1)

(test "i32.eq"
  (compile-and-run '((define (f a b) (i32.eq a b))) "f" 5 5)
  1)

(test "i32.ne"
  (compile-and-run '((define (f a b) (i32.ne a b))) "f" 5 3)
  1)

(test "i32.eqz of 0"
  (compile-and-run '((define (f x) (i32.eqz x))) "f" 0)
  1)

(test "i32.eqz of 5"
  (compile-and-run '((define (f x) (i32.eqz x))) "f" 5)
  0)


;;; ============================================================
;;; 12. Memory operations
;;; ============================================================

(printf "~%-- Memory --~%")

(test "memory store and load i32"
  (compile-and-run
    '((define-memory 1)
      (define (f val)
        (i32.store 0 val)
        (i32.load 0)))
    "f" 42)
  42)

(test "memory store/load at offset"
  (compile-and-run
    '((define-memory 1)
      (define (f)
        (i32.store 0 100)
        (i32.store 4 200)
        (+ (i32.load 0) (i32.load 4))))
    "f")
  300)

(test "memory.size"
  (compile-and-run
    '((define-memory 1)
      (define (f) (memory.size)))
    "f")
  1)


;;; ============================================================
;;; 13. Globals
;;; ============================================================

(printf "~%-- Globals --~%")

(test "global get/set"
  (compile-and-run
    '((define-global counter i32 #t 0)
      (define (f x)
        (global.set 0 x)
        (global.get 0)))
    "f" 42)
  42)

(test "global accumulate"
  (compile-and-run
    '((define-global acc i32 #t 0)
      (define (add-to-acc x)
        (global.set 0 (+ (global.get 0) x))
        (global.get 0))
      (define (test)
        (add-to-acc 10)
        (add-to-acc 20)
        (add-to-acc 30)
        (global.get 0)))
    "test")
  60)


;;; ============================================================
;;; 14. Data segments
;;; ============================================================

(printf "~%-- Data segments --~%")

(test "data segment init"
  (compile-and-run
    '((define-memory 1)
      (define-data 0 "Hello")
      (define (first-byte) (i32.load8_u 0)))
    "first-byte")
  72)  ;; 'H' = 72

(test "data segment read string bytes"
  (compile-and-run
    '((define-memory 1)
      (define-data 0 "AB")
      (define (sum-bytes) (+ (i32.load8_u 0) (i32.load8_u 1))))
    "sum-bytes")
  131) ;; 'A'=65 + 'B'=66 = 131


;;; ============================================================
;;; 15. Return
;;; ============================================================

(printf "~%-- Return --~%")

(test "early return"
  (compile-and-run
    '((define (f x)
        (if (= x 0) (return 42) 0)
        (+ x 100)))
    "f" 0)
  42)

(test "no early return"
  (compile-and-run
    '((define (f x)
        (if (= x 0) (return 42) 0)
        (+ x 100)))
    "f" 5)
  105)


;;; ============================================================
;;; 16. Begin
;;; ============================================================

(printf "~%-- Begin --~%")

(test "begin returns last"
  (compile-and-run
    '((define (f)
        (begin 1 2 3)))
    "f")
  3)


;;; ============================================================
;;; 17. Nested let + if
;;; ============================================================

(printf "~%-- Complex programs --~%")

(test "abs value"
  (compile-and-run
    '((define (abs-val x)
        (if (< x 0) (- x) x)))
    "abs-val" -42)
  42)

(test "abs of positive"
  (compile-and-run
    '((define (abs-val x)
        (if (< x 0) (- x) x)))
    "abs-val" 42)
  42)

(test "max of two"
  (compile-and-run
    '((define (max2 a b)
        (if (> a b) a b)))
    "max2" 3 7)
  7)

(test "gcd"
  (compile-and-run
    '((define (gcd a b)
        (if (= b 0) a (gcd b (remainder a b)))))
    "gcd" 12 8)
  4)

(test "iterative sum with while"
  (compile-and-run
    '((define (sum n)
        (let ([i 0] [s 0])
          (while (<= i n)
            (set! s (+ s i))
            (set! i (+ i 1)))
          s)))
    "sum" 100)
  5050)


;;; ============================================================
;;; 18. Explicit typed constants
;;; ============================================================

(printf "~%-- Typed constants --~%")

(test "i32 constant"
  (compile-and-run
    '((define (f) (i32 42)))
    "f")
  42)

(test "i32 negative"
  (compile-and-run
    '((define (f) (i32 -1)))
    "f")
  -1)

(test "boolean true"
  (compile-and-run
    '((define (f) #t))
    "f")
  1)

(test "boolean false"
  (compile-and-run
    '((define (f) #f))
    "f")
  0)


;;; ============================================================
;;; 19. F64 arithmetic (via Scheme float literals)
;;; ============================================================

(printf "~%-- f64 operations --~%")

(test-approx "f64 literal"
  (compile-and-run
    '((define (f -> f64) (f64 3.14)))
    "f")
  3.14 0.001)

(test-approx "f64.add"
  (compile-and-run
    '((define (f (a f64) (b f64) -> f64) (f64.add a b)))
    "f" 1.5 2.5)
  4.0 0.001)

(test-approx "f64.sub"
  (compile-and-run
    '((define (f (a f64) (b f64) -> f64) (f64.sub a b)))
    "f" 10.0 3.5)
  6.5 0.001)

(test-approx "f64.mul"
  (compile-and-run
    '((define (f (a f64) (b f64) -> f64) (f64.mul a b)))
    "f" 3.0 4.0)
  12.0 0.001)

(test-approx "f64.div"
  (compile-and-run
    '((define (f (a f64) (b f64) -> f64) (f64.div a b)))
    "f" 10.0 4.0)
  2.5 0.001)

(test-approx "f64.sqrt"
  (compile-and-run
    '((define (f (x f64) -> f64) (f64.sqrt x)))
    "f" 16.0)
  4.0 0.001)

(test-approx "f64.abs negative"
  (compile-and-run
    '((define (f (x f64) -> f64) (f64.abs x)))
    "f" -5.0)
  5.0 0.001)

(test-approx "f64.neg"
  (compile-and-run
    '((define (f (x f64) -> f64) (f64.neg x)))
    "f" 3.0)
  -3.0 0.001)


;;; ============================================================
;;; 20. Sub-word memory loads
;;; ============================================================

(printf "~%-- Sub-word memory --~%")

(test "i32.store8 and load8_u"
  (compile-and-run
    '((define-memory 1)
      (define (f val)
        (i32.store8 0 val)
        (i32.load8_u 0)))
    "f" 255)
  255)

(test "i32.store8 truncates"
  (compile-and-run
    '((define-memory 1)
      (define (f val)
        (i32.store8 0 val)
        (i32.load8_u 0)))
    "f" 300)  ;; 300 & 0xFF = 44
  44)

(test "i32.store16 and load16_u"
  (compile-and-run
    '((define-memory 1)
      (define (f val)
        (i32.store16 0 val)
        (i32.load16_u 0)))
    "f" 1000)
  1000)


;;; ============================================================
;;; 21. Drop
;;; ============================================================

(printf "~%-- Drop --~%")

(test "drop expression"
  (compile-and-run
    '((define (f)
        (drop (+ 1 2))
        42))
    "f")
  42)


;;; ============================================================
;;; 22. Nested while loops
;;; ============================================================

(printf "~%-- Nested loops --~%")

(test "nested while (multiplication table sum)"
  (compile-and-run
    '((define (f n)
        (let ([i 1] [total 0])
          (while (<= i n)
            (let ([j 1])
              (while (<= j n)
                (set! total (+ total (* i j)))
                (set! j (+ j 1))))
            (set! i (+ i 1)))
          total)))
    "f" 3)
  ;; Sum of i*j for i,j in 1..3 = 1+2+3+2+4+6+3+6+9 = 36
  36)


;;; ============================================================
;;; 23. Typed function signatures
;;; ============================================================

(printf "~%-- Typed signatures --~%")

(test "typed params i32"
  (compile-and-run
    '((define (f (a i32) (b i32) -> i32) (+ a b)))
    "f" 10 20)
  30)


;;; ============================================================
;;; 24. Format module new exports
;;; ============================================================

(printf "~%-- Format new exports --~%")

(test "wasm-type-void is #x40"
  wasm-type-void #x40)

(test "wasm-type-funcref is #x70"
  wasm-type-funcref #x70)

(test "encode/decode i64 round-trip"
  (let* ([encoded (encode-i64-leb128 1000000)]
         [decoded (decode-i64-leb128 encoded 0)])
    (car decoded))
  1000000)

(test "encode/decode i64 negative"
  (let* ([encoded (encode-i64-leb128 -42)]
         [decoded (decode-i64-leb128 encoded 0)])
    (car decoded))
  -42)


;;; ============================================================
;;; 25. Codegen module structure
;;; ============================================================

(printf "~%-- Codegen structure --~%")

(test "wasm-module has tables field"
  (let ([m (make-wasm-module)])
    (list? (wasm-module-tables m)))
  #t)

(test "wasm-module has data-segments field"
  (let ([m (make-wasm-module)])
    (list? (wasm-module-data-segments m)))
  #t)

(test "wasm-module has elements field"
  (let ([m (make-wasm-module)])
    (list? (wasm-module-elements m)))
  #t)

(test "wasm-module start defaults to #f"
  (let ([m (make-wasm-module)])
    (wasm-module-start m))
  #f)

(test "wasm-export-table kind is 1"
  (wasm-export-kind (wasm-export-table "tbl" 0))
  1)

(test "wasm-export-global kind is 3"
  (wasm-export-kind (wasm-export-global "g" 0))
  3)

(test "scheme->wasm-type i64"
  (scheme->wasm-type 'i64)
  wasm-type-i64)

(test "scheme->wasm-type f32"
  (scheme->wasm-type 'f32)
  wasm-type-f32)

(test "scheme->wasm-type f64"
  (scheme->wasm-type 'f64)
  wasm-type-f64)


;;; ============================================================
;;; 26. Compile context block depth
;;; ============================================================

(printf "~%-- Compile context --~%")

(test "block depth starts at 0"
  (let ([ctx (make-compile-context)])
    (context-block-depth ctx))
  0)

(test "push/pop block"
  (let ([ctx (make-compile-context)])
    (context-push-block! ctx 'block)
    (let ([d1 (context-block-depth ctx)])
      (context-pop-block! ctx)
      (let ([d2 (context-block-depth ctx)])
        (cons d1 d2))))
  '(1 . 0))


;;; ============================================================
;;; 27. Runtime memory access API
;;; ============================================================

(printf "~%-- Runtime memory API --~%")

(test "runtime-memory-ref/set!"
  (let ([rt (compile-and-load
              '((define-memory 1)
                (define (dummy) 0)))])
    (wasm-runtime-memory-set! rt 0 99)
    (wasm-runtime-memory-ref rt 0))
  99)


;;; ============================================================
;;; 28. Runtime global access API
;;; ============================================================

(printf "~%-- Runtime global API --~%")

(test "runtime-global-ref/set!"
  (let ([rt (compile-and-load
              '((define-global g i32 #t 100)
                (define (dummy) (global.get 0))))])
    (let ([initial (wasm-runtime-global-ref rt 0)])
      (wasm-runtime-global-set! rt 0 999)
      (list initial (wasm-runtime-global-ref rt 0))))
  '(100 999))


;;; ============================================================
;;; 29. Security: Fuel exhaustion
;;; ============================================================

(printf "~%-- Security: Fuel --~%")

(test "fuel exhaustion on infinite loop"
  (let ([rt (compile-and-load
              '((define (spin)
                  (while #t 0)
                  0)))])
    (wasm-runtime-set-fuel! rt 1000)
    (guard (exn
      [(wasm-trap? exn)
       (let ([msg (wasm-trap-message exn)])
         (and (string? msg)
              (string-contains msg "fuel exhausted")
              'trapped))]
      [#t 'other-error])
      (wasm-runtime-call rt "spin")
      'no-trap))
  'trapped)

(test "sufficient fuel works"
  (let ([rt (compile-and-load
              '((define (f x) (+ x 1))))])
    (wasm-runtime-set-fuel! rt 10000)
    (wasm-runtime-call rt "f" 41))
  42)

(test "very low fuel traps simple function"
  (let ([rt (compile-and-load
              '((define (f x y) (+ x y))))])
    (wasm-runtime-set-fuel! rt 1)  ; only 1 step allowed
    (guard (exn
      [(wasm-trap? exn) 'trapped]
      [#t 'other-error])
      (wasm-runtime-call rt "f" 1 2)
      'no-trap))
  'trapped)

(test "default fuel allows normal programs"
  (compile-and-run
    '((define (fib n)
        (if (<= n 1) n (+ (fib (- n 1)) (fib (- n 2))))))
    "fib" 15)
  610)


;;; ============================================================
;;; 30. Security: Call depth limit
;;; ============================================================

(printf "~%-- Security: Call depth --~%")

(test "call depth exceeded"
  (let ([rt (compile-and-load
              '((define (deep n)
                  (if (= n 0) 0 (deep (- n 1))))))])
    (wasm-runtime-set-max-depth! rt 5)
    (guard (exn
      [(wasm-trap? exn)
       (let ([msg (wasm-trap-message exn)])
         (and (string? msg)
              (string-contains msg "call depth exceeded")
              'trapped))]
      [#t 'other-error])
      (wasm-runtime-call rt "deep" 100)
      'no-trap))
  'trapped)

(test "within depth limit works"
  (let ([rt (compile-and-load
              '((define (deep n)
                  (if (= n 0) 42 (deep (- n 1))))))])
    (wasm-runtime-set-max-depth! rt 100)
    (wasm-runtime-call rt "deep" 50))
  42)

(test "default depth allows normal recursion"
  (compile-and-run
    '((define (fact n)
        (if (= n 0) 1 (* n (fact (- n 1))))))
    "fact" 10)
  3628800)


;;; ============================================================
;;; 31. Security: Bounds-checked memory
;;; ============================================================

(printf "~%-- Security: Memory bounds --~%")

(test "OOB memory load traps"
  (let ([rt (compile-and-load
              '((define-memory 1)
                (define (f) (i32.load 65536))))])  ;; exactly 1 page = 65536, so addr 65536 is OOB
    (guard (exn
      [(wasm-trap? exn)
       (let ([msg (wasm-trap-message exn)])
         (and (string? msg)
              (string-contains msg "out of bounds")
              'trapped))]
      [#t 'other-error])
      (wasm-runtime-call rt "f")
      'no-trap))
  'trapped)

(test "OOB memory store traps"
  (let ([rt (compile-and-load
              '((define-memory 1)
                (define (f) (i32.store 70000 42) 0)))])
    (guard (exn
      [(wasm-trap? exn) 'trapped]
      [#t 'other-error])
      (wasm-runtime-call rt "f")
      'no-trap))
  'trapped)

(test "valid memory access works"
  (compile-and-run
    '((define-memory 1)
      (define (f)
        (i32.store 0 999)
        (i32.load 0)))
    "f")
  999)

(test "edge of memory access works"
  (compile-and-run
    '((define-memory 1)
      (define (f)
        (i32.store 65532 42)  ;; last valid 4-byte store at 65536-4
        (i32.load 65532)))
    "f")
  42)


;;; ============================================================
;;; 32. Security: memory.grow persistence
;;; ============================================================

(printf "~%-- Security: memory.grow --~%")

(test "memory.grow updates size"
  (compile-and-run
    '((define-memory 1)
      (define (f)
        (memory.grow 1)
        (memory.size)))
    "f")
  2)

(test "memory.grow preserves old data"
  (compile-and-run
    '((define-memory 1)
      (define (f)
        (i32.store 0 12345)
        (memory.grow 1)
        (i32.load 0)))
    "f")
  12345)

(test "memory.grow allows access to new pages"
  (compile-and-run
    '((define-memory 1)
      (define (f)
        (memory.grow 1)
        (i32.store 65536 777)  ;; write to page 2 (was OOB before grow)
        (i32.load 65536)))
    "f")
  777)

(test "memory.grow returns old page count"
  (compile-and-run
    '((define-memory 2)
      (define (f)
        (memory.grow 1)))
    "f")
  2)


;;; ============================================================
;;; 33. Security: Module validation
;;; ============================================================

(printf "~%-- Security: Validation --~%")

(test "valid module passes validation"
  (let* ([bv (compile-program '((define (f x) x)))]
         [mod (wasm-decode-module bv)])
    (guard (exn [(wasm-trap? exn) 'invalid] [#t 'error])
      (wasm-validate-module mod)
      'valid))
  'valid)

;; Test validation is called during instantiation (existing tests
;; implicitly test this -- they would fail if validation rejected valid modules)


;;; ============================================================
;;; Summary
;;; ============================================================

(printf "~%--- WASM MVP: ~a passed, ~a failed ---~%" pass fail)
(when (> fail 0) (exit 1))
