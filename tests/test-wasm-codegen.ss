#!chezscheme
;;; Tests for (jerboa wasm codegen) -- WebAssembly code generation

(import (except (chezscheme) compile-program)
        (jerboa wasm format)
        (jerboa wasm codegen))

(define pass 0)
(define fail 0)

;; Chez Scheme does not have bytevector->list; provide it
(define (bytevector->list bv)
  (map (lambda (i) (bytevector-u8-ref bv i))
       (iota (bytevector-length bv))))

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

(printf "--- Phase 3e: WASM Codegen ---~%~%")

;;; ======== WASM type construction ========

(test "wasm-type params"
  (wasm-type-params (make-wasm-type '(#x7F #x7F) '(#x7F)))
  '(#x7F #x7F))

(test "wasm-type results"
  (wasm-type-results (make-wasm-type '(#x7F) '(#x7F #x7F)))
  '(#x7F #x7F))

;;; ======== WASM module construction ========

(test "make-wasm-module returns module"
  (wasm-module? (make-wasm-module))
  #t)

(test "module starts empty"
  (length (wasm-module-types (make-wasm-module)))
  0)

(test "add-type!"
  (let ([m (make-wasm-module)])
    (wasm-module-add-type! m (make-wasm-type '(#x7F) '(#x7F)))
    (length (wasm-module-types m)))
  1)

;;; ======== Export construction ========

(test "wasm-export-func name"
  (wasm-export-name (wasm-export-func "main" 0))
  "main")

(test "wasm-export-func kind"
  (wasm-export-kind (wasm-export-func "main" 0))
  0)

(test "wasm-export-func index"
  (wasm-export-index (wasm-export-func "main" 0))
  0)

(test "wasm-export-memory kind"
  (wasm-export-kind (wasm-export-memory "mem" 0))
  2)

;;; ======== Import construction ========

(test "wasm-import-module"
  (wasm-import-module (make-wasm-import "env" "print" '(0 . 0)))
  "env")

(test "wasm-import-name"
  (wasm-import-name (make-wasm-import "env" "print" '(0 . 0)))
  "print")

;;; ======== Module encoding produces valid WASM magic ========

(test "empty module starts with magic"
  (let* ([m (make-wasm-module)]
         [bv (wasm-module-encode m)])
    (list (bytevector-u8-ref bv 0)
          (bytevector-u8-ref bv 1)
          (bytevector-u8-ref bv 2)
          (bytevector-u8-ref bv 3)))
  '(#x00 #x61 #x73 #x6D))

(test "empty module has version 1"
  (let* ([m (make-wasm-module)]
         [bv (wasm-module-encode m)])
    (list (bytevector-u8-ref bv 4)
          (bytevector-u8-ref bv 5)
          (bytevector-u8-ref bv 6)
          (bytevector-u8-ref bv 7)))
  '(#x01 #x00 #x00 #x00))

;;; ======== Compile context ========

(test "compile-context add-local"
  (let ([ctx (make-compile-context)])
    (context-add-local! ctx 'x))
  0)

(test "compile-context local-index"
  (let ([ctx (make-compile-context)])
    (context-add-local! ctx 'x)
    (context-add-local! ctx 'y)
    (context-local-index ctx 'y))
  1)

(test "compile-context add-func"
  (let ([ctx (make-compile-context)])
    (context-add-func! ctx 'foo))
  0)

(test "compile-context func-index"
  (let ([ctx (make-compile-context)])
    (context-add-func! ctx 'foo)
    (context-add-func! ctx 'bar)
    (context-func-index ctx 'bar))
  1)

;;; ======== scheme->wasm-type ========

(test "scheme->wasm-type i32"
  (scheme->wasm-type 'i32)
  #x7F)

(test "scheme->wasm-type integer"
  (scheme->wasm-type 'integer)
  #x7F)

(test "scheme->wasm-type f64"
  (scheme->wasm-type 'f64)
  #x7C)

;;; ======== compile-expr ========

(test "compile integer literal"
  (let ([ctx (make-compile-context)])
    (bytevector->list (compile-expr 42 ctx)))
  (list #x41 42))  ; i32.const 42

(test "compile integer zero"
  (let ([ctx (make-compile-context)])
    (bytevector->list (compile-expr 0 ctx)))
  (list #x41 0))   ; i32.const 0

(test "compile addition"
  (let ([ctx (make-compile-context)])
    (let ([bv (compile-expr '(+ 1 2) ctx)])
      ;; i32.const 1, i32.const 2, i32.add
      (and (>= (bytevector-length bv) 5)
           (= (bytevector-u8-ref bv 0) #x41)  ; i32.const
           (= (bytevector-u8-ref bv (- (bytevector-length bv) 1)) #x6A))))  ; i32.add
  #t)

;;; ======== compile-program ========

(test "compile-program returns bytevector"
  (bytevector? (compile-program '((define (identity x) x))))
  #t)

(test "compile-program starts with WASM magic"
  (let ([bv (compile-program '((define (identity x) x)))])
    (list (bytevector-u8-ref bv 0)
          (bytevector-u8-ref bv 1)
          (bytevector-u8-ref bv 2)
          (bytevector-u8-ref bv 3)))
  '(#x00 #x61 #x73 #x6D))

(test "compile-program non-empty"
  (let ([bv (compile-program '((define (add a b) (+ a b))))])
    (> (bytevector-length bv) 8))
  #t)

(test "compile-program two functions"
  (let ([bv (compile-program
              '((define (double x) (+ x x))
                (define (triple x) (+ x (+ x x)))))])
    (> (bytevector-length bv) 20))
  #t)

;;; ======== wasm-func ========

(test "make-wasm-func"
  (wasm-func? (make-wasm-func '() (bytevector #x0B)))
  #t)

(test "wasm-func-locals"
  (wasm-func-locals (make-wasm-func '(#x7F #x7F) (bytevector #x0B)))
  '(#x7F #x7F))

(test "wasm-func-body"
  (bytevector->list (wasm-func-body (make-wasm-func '() (bytevector #x41 #x05 #x0B))))
  '(#x41 #x05 #x0B))

;;; Summary

(printf "~%WASM Codegen: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
