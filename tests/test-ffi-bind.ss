#!chezscheme
;;; Tests for (std foreign bind) — Fearless FFI

(import (chezscheme) (std foreign bind))

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

(printf "--- (std foreign bind) tests ---~%")

;;; ======== Step 19: define-c-library ========

(printf "~%-- c-type->ffi-type --~%")

(test "c-type->ffi-type int"    (c-type->ffi-type 'int)    'int)
(test "c-type->ffi-type double" (c-type->ffi-type 'double) 'double)
(test "c-type->ffi-type void*"  (c-type->ffi-type 'void*)  'uptr)
(test "c-type->ffi-type char*"  (c-type->ffi-type 'char*)  'string)
(test "c-type->ffi-type void"   (c-type->ffi-type 'void)   'void)
(test "c-type->ffi-type unknown passes through"
  (c-type->ffi-type 'my-special-type)
  'my-special-type)

(printf "~%-- define-c-library --~%")

;; Use standard C library functions (always available)
(define-c-library libc
  (bind strlen (char*) -> size_t)
  (bind strcmp (char* char*) -> int))

(test "strlen via define-c-library"
  (strlen "hello")
  5)

(test "strcmp equal"
  (= 0 (strcmp "abc" "abc"))
  #t)

(test "strcmp less than"
  (< (strcmp "abc" "abd") 0)
  #t)

;;; ======== Step 19: parse-c-signature ========

(printf "~%-- parse-c-signature --~%")

(test "parse-c-signature simple function"
  (parse-c-signature "int foo(char* s, int n);")
  '(foo (char* int) int))

(test "parse-c-signature no args"
  (parse-c-signature "void bar(void);")
  '(bar (void) void))

(test "parse-c-signature pointer return"
  (parse-c-signature "char* strdup(char* s);")
  '(strdup (char*) char*))

(test "parse-c-signature empty args"
  (parse-c-signature "int getpid();")
  '(getpid () int))

(test "parse-c-signature returns #f for non-function"
  (parse-c-signature "/* comment */")
  #f)

;;; ======== Step 20: foreign-ptr ========

(printf "~%-- foreign-ptr / defstruct/foreign --~%")

(test "foreign-ptr? on non-foreign"
  (foreign-ptr? 42)
  #f)

;; Create a foreign pointer with a value and manual destructor
(let* ([freed? #f]
       [fp (make-managed-ptr 12345 (lambda (v) (set! freed? #t)))])
  (test "foreign-ptr? on fp"
    (foreign-ptr? fp) #t)
  (test "foreign-ptr-valid? on fresh fp"
    (foreign-ptr-valid? fp) #t)
  (test "foreign-ptr-value on fresh fp"
    (foreign-ptr-value fp) 12345)
  (foreign-ptr-free! fp)
  (test "foreign-ptr-valid? after free"
    (foreign-ptr-valid? fp) #f)
  (test "destructor called on free"
    freed? #t))

;; Use-after-free raises error
(test "use-after-free raises error"
  (let* ([fp (make-managed-ptr 999 #f)])
    (foreign-ptr-free! fp)
    (guard (exn [#t 'caught])
      (foreign-ptr-value fp)
      'missed))
  'caught)

;; defstruct/foreign
(defstruct/foreign my-resource
  (size)
  (destructor (lambda (ptr) (void))))  ; no-op destructor for testing

(test "my-resource? on fresh resource"
  (my-resource? (make-my-resource 0 42))
  #t)

(test "my-resource-valid? on fresh resource"
  (let ([r (make-my-resource 0 100)])
    (my-resource-valid? r))
  #t)

(test "my-resource-ptr extracts value"
  (let ([r (make-my-resource 777 0)])
    (my-resource-ptr r))
  777)

(test "my-resource-free! invalidates"
  (let ([r (make-my-resource 0 42)])
    (my-resource-free! r)
    (my-resource-valid? r))
  #f)

;; with-foreign: frees on normal exit
(test "with-foreign: frees on exit"
  (let ([freed? #f]
        [seen-valid? #f])
    (with-foreign ([fp (make-managed-ptr 1 (lambda (v) (set! freed? #t)))])
      (set! seen-valid? (foreign-ptr-valid? fp)))
    (and seen-valid? freed?))
  #t)

;; with-foreign: frees on exception
(test "with-foreign: frees on exception"
  (let ([freed? #f])
    (guard (exn [#t 'caught])
      (with-foreign ([fp (make-managed-ptr 1 (lambda (v) (set! freed? #t)))])
        (error 'test "boom")))
    freed?)
  #t)

;;; ======== Step 21: FFI thread pool ========

(printf "~%-- ffi-thread-pool --~%")

(let ([pool (make-ffi-thread-pool 2)])

  (test "ffi-thread-pool-call: simple thunk"
    (ffi-thread-pool-call pool (lambda () 42))
    42)

  (test "ffi-thread-pool-call: arithmetic"
    (ffi-thread-pool-call pool (lambda () (+ 1 2 3)))
    6)

  (test "ffi-thread-pool-call: multiple calls"
    (let ([results '()])
      (set! results (cons (ffi-thread-pool-call pool (lambda () 'a)) results))
      (set! results (cons (ffi-thread-pool-call pool (lambda () 'b)) results))
      (set! results (cons (ffi-thread-pool-call pool (lambda () 'c)) results))
      (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) results))
    '(a b c))

  (test "ffi-thread-pool-call: exception propagated"
    (guard (exn [#t 'caught])
      (ffi-thread-pool-call pool (lambda () (error 'test "from pool")))
      'missed)
    'caught)

  (ffi-thread-pool-shutdown! pool))

;; define-foreign/async
(define-foreign/async async-add
  (lambda (a b) (+ a b)))

(test "define-foreign/async: basic call"
  (async-add 3 4)
  7)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
