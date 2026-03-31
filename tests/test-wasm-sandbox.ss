#!chezscheme
;;; test-wasm-sandbox.ss — Tests for Rust wasmi WASM sandbox
;;;
;;; Verifies that WASM modules compiled from Scheme execute correctly
;;; inside the Rust wasmi interpreter, fully isolated from Chez Scheme.

(import (except (chezscheme) compile-program)
        (jerboa wasm format)
        (jerboa wasm codegen)
        (std wasm sandbox))

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

(define (string-contains s sub)
  (let ([slen (string-length s)] [sublen (string-length sub)])
    (let lp ([i 0])
      (cond
        [(> (+ i sublen) slen) #f]
        [(string=? (substring s i (+ i sublen)) sub) i]
        [else (lp (+ i 1))]))))

(printf "--- Rust wasmi Sandbox Tests ---~%~%")

;;; ============================================================
;;; Section 1: Availability
;;; ============================================================
(printf "--- Section 1: Availability ---~%")

(test "wasmi sandbox is available"
  (wasm-sandbox-available?)
  #t)

;;; ============================================================
;;; Section 2: Basic computation
;;; ============================================================
(printf "~%--- Section 2: Basic computation ---~%")

(test "factorial(10) in wasmi"
  (let* ([bv (compile-program
               '((define (factorial n)
                   (if (= n 0) 1 (* n (factorial (- n 1)))))))]
         [mod-h (wasm-sandbox-load bv)]
         [inst (wasm-sandbox-instantiate mod-h)])
    (let ([r (wasm-sandbox-call inst "factorial" 10)])
      (wasm-sandbox-free inst)
      (wasm-sandbox-free-module mod-h)
      r))
  3628800)

(test "fibonacci(20) in wasmi"
  (let* ([bv (compile-program
               '((define (fib n)
                   (if (<= n 1) n
                     (+ (fib (- n 1)) (fib (- n 2)))))))]
         [mod-h (wasm-sandbox-load bv)]
         [inst (wasm-sandbox-instantiate mod-h)])
    (let ([r (wasm-sandbox-call inst "fib" 20)])
      (wasm-sandbox-free inst)
      (wasm-sandbox-free-module mod-h)
      r))
  6765)

(test "arithmetic in wasmi"
  (let* ([bv (compile-program
               '((define (compute (a i32) (b i32) -> i32)
                   (+ (* a a) (* b b)))))]
         [mod-h (wasm-sandbox-load bv)]
         [inst (wasm-sandbox-instantiate mod-h)])
    (let ([r (wasm-sandbox-call inst "compute" 3 4)])
      (wasm-sandbox-free inst)
      (wasm-sandbox-free-module mod-h)
      r))
  25)

;;; ============================================================
;;; Section 3: Memory operations
;;; ============================================================
(printf "~%--- Section 3: Memory operations ---~%")

(test "memory store and load via WASM"
  (let* ([bv (compile-program
               '((define-memory 1)
                 (define (store-val (addr i32) (val i32) -> i32)
                   (i32.store addr val) val)
                 (define (load-val (addr i32) -> i32)
                   (i32.load addr))))]
         [mod-h (wasm-sandbox-load bv)]
         [inst (wasm-sandbox-instantiate mod-h)])
    (wasm-sandbox-call inst "store-val" 0 42)
    (let ([r (wasm-sandbox-call inst "load-val" 0)])
      (wasm-sandbox-free inst)
      (wasm-sandbox-free-module mod-h)
      r))
  42)

(test "host memory read"
  (let* ([bv (compile-program
               '((define-memory 1)
                 (define (store-val (addr i32) (val i32) -> i32)
                   (i32.store addr val) val)))]
         [mod-h (wasm-sandbox-load bv)]
         [inst (wasm-sandbox-instantiate mod-h)])
    (wasm-sandbox-call inst "store-val" 0 42)
    (let ([data (wasm-sandbox-memory-read inst 0 4)])
      (wasm-sandbox-free inst)
      (wasm-sandbox-free-module mod-h)
      data))
  #vu8(42 0 0 0))

(test "host memory write then WASM read"
  (let* ([bv (compile-program
               '((define-memory 1)
                 (define (load-val (addr i32) -> i32)
                   (i32.load addr))))]
         [mod-h (wasm-sandbox-load bv)]
         [inst (wasm-sandbox-instantiate mod-h)])
    (wasm-sandbox-memory-write inst 0 (bytevector 99 0 0 0))
    (let ([r (wasm-sandbox-call inst "load-val" 0)])
      (wasm-sandbox-free inst)
      (wasm-sandbox-free-module mod-h)
      r))
  99)

(test "memory size is 1 page (65536 bytes)"
  (let* ([bv (compile-program
               '((define-memory 1)
                 (define (nop) 0)))]
         [mod-h (wasm-sandbox-load bv)]
         [inst (wasm-sandbox-instantiate mod-h)])
    (let ([sz (wasm-sandbox-memory-size inst)])
      (wasm-sandbox-free inst)
      (wasm-sandbox-free-module mod-h)
      sz))
  65536)

;;; ============================================================
;;; Section 4: Fuel metering (deterministic termination)
;;; ============================================================
(printf "~%--- Section 4: Fuel metering ---~%")

(test "fuel exhaustion traps infinite loop"
  (let* ([bv (compile-program '((define (spin) (while #t 0) 0)))]
         [mod-h (wasm-sandbox-load bv)]
         [inst (wasm-sandbox-instantiate mod-h 'fuel: 1000)])
    (guard (exn
      [#t (let ([msg (if (message-condition? exn) (condition-message exn) "")])
            (wasm-sandbox-free inst)
            (wasm-sandbox-free-module mod-h)
            (and (string-contains msg "fuel") 'trapped))])
      (wasm-sandbox-call inst "spin")
      'no-trap))
  'trapped)

(test "sufficient fuel allows computation"
  (let* ([bv (compile-program '((define (f x) (+ x 1))))]
         [mod-h (wasm-sandbox-load bv)]
         [inst (wasm-sandbox-instantiate mod-h 'fuel: 10000000)])
    (let ([r (wasm-sandbox-call inst "f" 41)])
      (wasm-sandbox-free inst)
      (wasm-sandbox-free-module mod-h)
      r))
  42)

(test "fuel remaining decreases after execution"
  (let* ([bv (compile-program '((define (f x) (+ x 1))))]
         [mod-h (wasm-sandbox-load bv)]
         [inst (wasm-sandbox-instantiate mod-h 'fuel: 10000)])
    (let ([before (wasm-sandbox-fuel-remaining inst)])
      (wasm-sandbox-call inst "f" 1)
      (let ([after (wasm-sandbox-fuel-remaining inst)])
        (wasm-sandbox-free inst)
        (wasm-sandbox-free-module mod-h)
        (< after before))))
  #t)

;;; ============================================================
;;; Section 5: Module validation
;;; ============================================================
(printf "~%--- Section 5: Module validation ---~%")

(test "invalid WASM bytecode rejected"
  (guard (exn [#t 'rejected])
    (wasm-sandbox-load (bytevector 0 1 2 3 4 5 6 7))
    'accepted)
  'rejected)

(test "empty bytevector rejected"
  (guard (exn [#t 'rejected])
    (wasm-sandbox-load (bytevector))
    'accepted)
  'rejected)

;;; ============================================================
;;; Section 6: Multiple instances
;;; ============================================================
(printf "~%--- Section 6: Multiple instances ---~%")

(test "multiple instances from same module"
  (let* ([bv (compile-program '((define (f x) (+ x 1))))]
         [mod-h (wasm-sandbox-load bv)]
         [inst1 (wasm-sandbox-instantiate mod-h)]
         [inst2 (wasm-sandbox-instantiate mod-h)])
    (let ([r1 (wasm-sandbox-call inst1 "f" 10)]
          [r2 (wasm-sandbox-call inst2 "f" 20)])
      (wasm-sandbox-free inst1)
      (wasm-sandbox-free inst2)
      (wasm-sandbox-free-module mod-h)
      (+ r1 r2)))
  32)

(test "instances have isolated memory"
  (let* ([bv (compile-program
               '((define-memory 1)
                 (define (store-val (addr i32) (val i32) -> i32)
                   (i32.store addr val) val)
                 (define (load-val (addr i32) -> i32)
                   (i32.load addr))))]
         [mod-h (wasm-sandbox-load bv)]
         [inst1 (wasm-sandbox-instantiate mod-h)]
         [inst2 (wasm-sandbox-instantiate mod-h)])
    ;; Write different values in each instance
    (wasm-sandbox-call inst1 "store-val" 0 111)
    (wasm-sandbox-call inst2 "store-val" 0 222)
    ;; Verify isolation: inst1 still has 111
    (let ([r1 (wasm-sandbox-call inst1 "load-val" 0)]
          [r2 (wasm-sandbox-call inst2 "load-val" 0)])
      (wasm-sandbox-free inst1)
      (wasm-sandbox-free inst2)
      (wasm-sandbox-free-module mod-h)
      (list r1 r2)))
  '(111 222))

;;; ============================================================
;;; Summary
;;; ============================================================

(printf "~%--- Rust wasmi Sandbox: ~a passed, ~a failed ---~%" pass fail)
(when (> fail 0) (exit 1))
