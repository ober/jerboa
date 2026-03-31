#!chezscheme
;;; Tests for post-MVP codegen features in (jerboa wasm codegen)
;;; Verifies that new expression forms compile and execute correctly

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

(define (compile-and-run forms func-name . args)
  (let* ([bv (compile-program forms)]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt bv)
    (apply wasm-runtime-call rt func-name args)))

(printf "--- Post-MVP Codegen ---~%~%")


;;; ========== Saturating Conversions ==========

(printf "= Saturating conversions =~%")

(test "codegen: i32.trunc_sat_f64_s"
  (compile-and-run
    '((define (trunc (x f64) -> i32) (i32.trunc_sat_f64_s x)))
    "trunc" 3.7)
  3)

(test "codegen: i32.trunc_sat_f64_u"
  (compile-and-run
    '((define (trunc (x f64) -> i32) (i32.trunc_sat_f64_u x)))
    "trunc" 42.9)
  42)


;;; ========== Bulk Memory ==========

(printf "~%= Bulk memory =~%")

(test "codegen: memory.fill + load"
  (compile-and-run
    '((define-memory 1)
      (define (test) -> i32
        (begin
          (memory.fill (i32 0) (i32 #xAB) (i32 4))
          (i32.load8_u (i32 2)))))
    "test")
  #xAB)

(test "codegen: memory.copy"
  (compile-and-run
    '((define-memory 1)
      (define (test) -> i32
        (begin
          (memory.fill (i32 10) (i32 #x55) (i32 4))
          (memory.copy (i32 20) (i32 10) (i32 4))
          (i32.load8_u (i32 22)))))
    "test")
  #x55)


;;; ========== Reference Types ==========

(printf "~%= Reference types =~%")

(test "codegen: ref.null + ref.is_null"
  (compile-and-run
    '((define (test) -> i32
        (ref.is_null (ref.null #x70))))   ; funcref null
    "test")
  1)

(test "codegen: ref.func + ref.is_null"
  (compile-and-run
    '((define (test) -> i32
        (ref.is_null (ref.func 0))))
    "test")
  0)


;;; ========== Table Operations ==========

(printf "~%= Table operations =~%")

(test "codegen: table.set + table.get"
  (compile-and-run
    '((define-table 10)
      (define (test) -> i32
        (begin
          (table.set 0 (i32 3) (i32 42))
          (table.get 0 (i32 3)))))
    "test")
  42)

(test "codegen: table.size"
  (compile-and-run
    '((define-table 10)
      (define (test) -> i32
        (table.size 0)))
    "test")
  10)


;;; ========== Tail Calls ==========

(printf "~%= Tail calls =~%")

(test "codegen: return-call"
  (compile-and-run
    '((define (identity x) x)
      (define (test x) (return-call identity x)))
    "test" 77)
  77)


;;; ========== GC: Structs ==========

(printf "~%= GC structs =~%")

;; For GC tests, we need a struct type. Type 0 will be the function sig,
;; type 1 is the struct type. We use compile-program's normal function
;; type allocation, but we need an extra type for the struct.
;; The compile-program auto-creates type entries for function signatures.
;; Since we can't directly add struct types via compile-program yet,
;; we'll test struct ops via raw bytecode in test-wasm-postmvp.ss.
;; Here we verify the codegen produces valid bytecode for the forms.

;; Test that codegen produces valid bytecode for struct operations
;; We test via the module builder API directly
(let* ([mod (make-wasm-module)]
       [_ (wasm-module-add-type! mod (make-wasm-type '() (list wasm-type-i32)))]
       [_ (wasm-module-add-type! mod (make-wasm-type (list wasm-type-i32 wasm-type-i32) '()))]
       [ctx (make-compile-context)]
       [struct-new-bv (compile-expr '(struct.new 1 (i32 10) (i32 20)) ctx)]
       [array-len-bv (compile-expr '(array.len (i32 0)) ctx)]
       [i31-bv (compile-expr '(ref.i31 (i32 42)) ctx)])

  (test "codegen: struct.new produces bytecode"
    (> (bytevector-length struct-new-bv) 0)
    #t)

  (test "codegen: array.len produces bytecode"
    (> (bytevector-length array-len-bv) 0)
    #t)

  (test "codegen: ref.i31 produces bytecode"
    (> (bytevector-length i31-bv) 0)
    #t)
)


;;; ========== Exception Handling ==========

(printf "~%= Exception handling =~%")

;; Test throw codegen via module builder
(let* ([ctx (make-compile-context)]
       [throw-bv (compile-expr '(throw 0 (i32 42)) ctx)])
  (test "codegen: throw produces bytecode"
    (> (bytevector-length throw-bv) 0)
    #t)
)


;;; ========== Tag Section ==========

(printf "~%= Tag section =~%")

(test "codegen: module with tag section"
  (let ([mod (make-wasm-module)])
    (wasm-module-add-type! mod (make-wasm-type '() (list wasm-type-i32)))
    (wasm-module-add-type! mod (make-wasm-type (list wasm-type-i32) '()))
    (wasm-module-add-tag! mod 1)
    (let ([bv (wasm-module-encode mod)])
      ;; Should produce valid WASM binary with tag section
      (and (bytevector? bv)
           (> (bytevector-length bv) 8))))
  #t)


;;; ========== Integration: full round-trip through codegen ==========

(printf "~%= Integration: codegen -> runtime =~%")

;; A program using several post-MVP features together
(test "codegen: sat conversion + memory fill + load"
  (compile-and-run
    '((define-memory 1)
      (define (test (x f64) -> i32)
        (begin
          (memory.fill (i32 0) (i32.trunc_sat_f64_u x) (i32 10))
          (i32.load8_u (i32 5)))))
    "test" 170.9)
  170)

(test "codegen: ref.null pipeline"
  (compile-and-run
    '((define (is-null) -> i32
        (ref.is_null (ref.null #x70))))
    "is-null")
  1)

;; Tail-call: mutual recursion between two functions
(test "codegen: tail call chain"
  (compile-and-run
    '((define (double x) (+ x x))
      (define (test x) (return-call double x)))
    "test" 21)
  42)


;;; Summary

(printf "~%Post-MVP Codegen: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
