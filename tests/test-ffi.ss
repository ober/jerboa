#!chezscheme
;;; test-ffi.ss -- Tests for FFI translation macros

(import (chezscheme)
        (jerboa ffi))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]))

;;; ---- FFI type mapping ----

;; c-lambda creates a foreign-procedure
;; We can test that c-lambda expands and produces a procedure for libc functions
(load-shared-object "libc.so.6")

;; Test c-lambda with a real C function
(let ([my-getpid (c-lambda () int "getpid")])
  (check (procedure? my-getpid) => #t)
  (check (> (my-getpid) 0) => #t))

;; Test define-c-lambda
(define-c-lambda my-getuid () unsigned-int "getuid")
(check (procedure? my-getuid) => #t)
(check (>= (my-getuid) 0) => #t)

;; Test c-lambda with string types
(let ([my-strlen (c-lambda (char-string) int "strlen")])
  (check (my-strlen "hello") => 5)
  (check (my-strlen "") => 0))

;; Test c-declare is a no-op (doesn't error)
(c-declare "/* this is ignored in Chez mode */")

;; Test begin-ffi is a passthrough
(begin-ffi (test-val)
  (define test-val 42))
(check test-val => 42)

;;; ---- Summary ----
(newline)
(display "FFI tests: ")
(display pass-count)
(display " passed, ")
(display fail-count)
(display " failed")
(newline)
(when (> fail-count 0) (exit 1))
