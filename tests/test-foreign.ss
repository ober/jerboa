#!chezscheme
;;; Tests for (std foreign) — FFI DSL macros

(import (chezscheme) (std foreign))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn
              [#t (set! fail (+ fail 1))
                  (printf "FAIL ~a: exception ~a~%" name (condition-message exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1))
                  (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~a, expected ~a~%" name got expected)))))]))

(printf "--- (std foreign) tests ---~%")

;; Load libc for direct foreign-procedure tests
(load-shared-object "libc.so.6")

;; Test 1: define-foreign with libc
(define-foreign c-getpid "getpid" () -> int)
(test "define-foreign getpid" (> (c-getpid) 0) #t)

;; Test 2: define-foreign/check with success
(define-foreign/check c-getpid-checked "getpid" () -> int
  (check: (lambda (rc) (> rc 0))))
(test "define-foreign/check success" (> (c-getpid-checked) 0) #t)

;; Test 3: define-foreign/check with custom error
(define-foreign/check c-getpid-custom "getpid" () -> int
  (check: (lambda (rc) (> rc 0)))
  (error: (lambda (rc) (error 'test "should not happen" rc))))
(test "define-foreign/check custom error" (> (c-getpid-custom) 0) #t)

;; Test 4: define-foreign with unsigned types
(define-foreign c-getuid "getuid" () -> unsigned-int)
(test "define-foreign getuid" (>= (c-getuid) 0) #t)

;; Test 5: with-foreign-resource
(let ([cleaned #f])
  (with-foreign-resource (ptr (foreign-alloc 64) (lambda (p) (foreign-free p) (set! cleaned #t)))
    (foreign-set! 'int ptr 0 42)
    (test "with-foreign-resource read/write" (foreign-ref 'int ptr 0) 42))
  (test "with-foreign-resource cleanup" cleaned #t))

;; Test 6: with-foreign-resource cleans up on exception
(let ([cleaned #f])
  (guard (exn [#t #t])
    (with-foreign-resource (ptr (foreign-alloc 64) (lambda (p) (foreign-free p) (set! cleaned #t)))
      (error 'test "boom")))
  (test "with-foreign-resource exception cleanup" cleaned #t))

;; Test 7: define-foreign-type (constructor registers for cleanup)
(define-foreign-type managed-ptr void*
  (destructor: foreign-free))
(let ([ptr (managed-ptr (foreign-alloc 32))])
  (test "define-foreign-type wraps ptr" (> ptr 0) #t))

;; Test 8: define-callback
(define-callback add-cb (int int -> int)
  (lambda (a b) (+ a b)))
(test "define-callback creates entry point" (> add-cb 0) #t)

;; Test 9: define-foreign-struct
(define-foreign-struct test-struct
  (x int offset: 0)
  (y int offset: 4))
(let ([ptr (foreign-alloc 8)])
  (test-struct-x-set! ptr 100)
  (test-struct-y-set! ptr 200)
  (test "define-foreign-struct getter x" (test-struct-x ptr) 100)
  (test "define-foreign-struct getter y" (test-struct-y ptr) 200)
  (foreign-free ptr))

;; Test 10: define-ffi-library with single shared object
(define-ffi-library mylibc "libc.so.6"
  (define-foreign ffi-getpid "getpid" () -> int))
(test "define-ffi-library single" (> (ffi-getpid) 0) #t)

;; Test 11: define-ffi-library with multiple shared objects
(define-ffi-library mylibs ("libc.so.6" "libm.so.6")
  (define-foreign ffi-ceil "ceil" (double) -> double))
(test "define-ffi-library multi" (ffi-ceil 3.2) 4.0)

;; Test 12: define-foreign auto-name
(load-shared-object "libm.so.6")
(define-foreign floor (double) -> double)
(test "define-foreign auto-name" (floor 3.7) 3.0)

(printf "~%~a tests, ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
