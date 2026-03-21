#!chezscheme
;;; Tests for (std typed check) — compile-time type checking

(import (chezscheme)
        (std typed)
        (std typed env)
        (std typed infer)
        (std typed check))

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

(printf "--- Typed Check Tests ---~%~%")

;; ========== Basic compile-time checking ==========

(printf "-- Compile-time checking --~%")

(test "*enable-type-checking* defaults to #t"
  (*enable-type-checking*)
  #t)

(test "*type-errors-fatal* defaults to #f"
  (*type-errors-fatal*)
  #f)

;; Test that define/ct works at all — defines a function
(define/ct (add-ints [a : fixnum] [b : fixnum]) : fixnum
  (+ a b))

(test "define/ct function works correctly"
  (add-ints 3 4)
  7)

(test "define/ct enforces arg types at runtime in debug mode"
  (parameterize ([*typed-mode* 'debug])
    (guard (exn [#t #t])
      (add-ints "not" "ints")
      #f))
  #t)

(test "define/ct skips checks in release mode"
  (parameterize ([*typed-mode* 'release])
    (guard (exn [#t #f])
      (add-ints 3 4)))
  7)

;; ========== check-program-types ==========

(printf "~%-- check-program-types --~%")

(test "check-program-types: no errors for clean code"
  (let ([errors (check-program-types
                  '((define x 42)
                    (define y (+ x 1))))])
    (null? errors))
  #t)

(test "check-program-types: detects type mismatch"
  (let ([errors (check-program-types
                  '((define (f x) (string-length x))
                    (f 42)))])
    ;; string-length expects string, got fixnum
    (> (length errors) 0))
  #t)

;; ========== type-check-file ==========

(printf "~%-- type-check-file --~%")

;; Create a test file
(let ([test-file "/tmp/jerboa-test-typed.ss"])
  (call-with-output-file test-file
    (lambda (port)
      (display "(define (greet name) (string-append \"Hello, \" name))\n" port)
      (display "(greet 42)\n" port))
    'replace)

  (test "type-check-file detects string/fixnum mismatch"
    (let ([errors (type-check-file test-file)])
      (> (length errors) 0))
    #t))

;; ========== Fatal mode ==========

(printf "~%-- Fatal error mode --~%")

(test "fatal mode parameter exists and accepts boolean"
  (begin
    (*type-errors-fatal* #t)
    (let ([v (*type-errors-fatal*)])
      (*type-errors-fatal* #f)
      v))
  #t)

(test "*type-errors-fatal* rejects non-boolean"
  (guard (exn [#t #t])
    (*type-errors-fatal* 'maybe)
    #f)
  #t)

;; ========== Inference engine ==========

(printf "~%-- Type inference --~%")

(test "infer-type: fixnum literal"
  (infer-type 42 (empty-type-env))
  'fixnum)

(test "infer-type: string literal"
  (infer-type "hello" (empty-type-env))
  'string)

(test "infer-type: boolean"
  (infer-type #t (empty-type-env))
  'boolean)

(test "infer-type: string-append returns string"
  (infer-type '(string-append "a" "b") (empty-type-env))
  'string)

(test "subtype: fixnum <: integer"
  (subtype? 'fixnum 'integer)
  #t)

(test "subtype: fixnum <: number"
  (subtype? 'fixnum 'number)
  #t)

(test "subtype: string NOT <: fixnum"
  (subtype? 'string 'fixnum)
  #f)

(test "unify-types: fixnum + flonum = number"
  (unify-types 'fixnum 'flonum)
  'number)

;; ========== Summary ==========

(printf "~%Typed check tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
