#!chezscheme
;;; Tests for (std typed infer) — Type inference engine

(import (chezscheme) (std typed env) (std typed infer))

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
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #t #f) #t)]))

(printf "--- (std typed infer) tests ---~%")

;; Shorthand: infer in the empty environment
(define (infer expr)
  (infer-type expr (empty-type-env)))

;;;; Test 1: Infer type of number literal

(test "infer/fixnum literal"
  (infer 5)
  'fixnum)

(test "infer/fixnum literal 0"
  (infer 0)
  'fixnum)

(test "infer/flonum literal"
  (infer 3.14)
  'flonum)

;;;; Test 2: Infer type of string literal

(test "infer/string literal"
  (infer "hello")
  'string)

(test "infer/empty string"
  (infer "")
  'string)

;;;; Test 3: Infer type of boolean

(test "infer/boolean #t"
  (infer #t)
  'boolean)

(test "infer/boolean #f"
  (infer #f)
  'boolean)

;;;; Test 4: Infer type of (+ 1 2) → fixnum

(test "infer/addition of fixnums"
  (infer '(+ 1 2))
  'fixnum)

(test "infer/addition produces number when mixed"
  ;; flonum arg makes result flonum
  (let ([t (infer '(+ 1 2.0))])
    (memq t '(flonum number)))
  '(flonum number))

;;;; Test 5: string-append → string

(test "infer/string-append"
  (infer '(string-append "a" "b"))
  'string)

;;;; Test 6: string-length → fixnum

(test "infer/string-length"
  (infer '(string-length "foo"))
  'fixnum)

;;;; Test 7: if with numeric branches

(test-true "infer/if numeric branches gives numeric type"
  (let ([t (infer '(if #t 1 2))])
    (memq t '(fixnum integer real number))))

;;;; Test 8: lambda infers function type

(test-true "infer/lambda returns arrow type"
  (let ([t (infer '(lambda (x) x))])
    (and (pair? t) (eq? (car t) '->))))

(test "infer/lambda with no args returns arrow type with any return"
  (infer '(lambda () 42))
  '(-> any))

(test "infer/lambda with one arg"
  (infer '(lambda (x) x))
  '(-> any any))

;;;; Test 9: type error: string-length of non-string

(test-true "infer/string-length of non-string records error"
  (let ([errors (with-type-errors-collected
                  (lambda ()
                    (check-type '(string-length 42) 'fixnum (empty-type-env))))])
    ;; Should have at least one type error
    (not (null? errors))))

;;;; Test 10: type error: string-append of non-strings

(test-true "infer/string-append of numbers records error"
  (let ([errors (with-type-errors-collected
                  (lambda ()
                    (infer-type '(string-append 1 2) (empty-type-env))))])
    (not (null? errors))))

;;;; Test 11: with-type-errors-collected captures errors as list

(test-true "infer/with-type-errors-collected returns list"
  (let ([errors (with-type-errors-collected
                  (lambda ()
                    (infer-type '(string-length 42) (empty-type-env))))])
    (list? errors)))

(test "infer/with-type-errors-collected on valid expr is empty"
  (with-type-errors-collected
    (lambda ()
      (infer-type '(string-length "ok") (empty-type-env))))
  '())

;;;; Test 12: reset-type-errors! clears errors

(test "infer/reset-type-errors! clears"
  (begin
    ;; Accumulate an error by checking with wrong type
    (parameterize ([*type-errors* '()])
      (infer-type '(string-length 42) (empty-type-env))
      (reset-type-errors!)
      (null? (*type-errors*))))
  #t)

;;;; Test 13: unify-types on compatible types

(test "unify/fixnum fixnum -> fixnum"
  (unify-types 'fixnum 'fixnum)
  'fixnum)

(test "unify/fixnum and number -> number"
  (unify-types 'fixnum 'number)
  'number)

(test "unify/string and string -> string"
  (unify-types 'string 'string)
  'string)

(test "unify/flonum and number -> number"
  (unify-types 'flonum 'number)
  'number)

;;;; Test 14: unify-types on 'any with anything → anything (specific type wins)

(test "unify/any with fixnum -> fixnum"
  (unify-types 'any 'fixnum)
  'fixnum)

(test "unify/fixnum with any -> fixnum"
  (unify-types 'fixnum 'any)
  'fixnum)

(test "unify/any with any -> any"
  (unify-types 'any 'any)
  'any)

;;;; Test 15: subtype? where fixnum is subtype of number

(test "subtype?/fixnum < number"
  (subtype? 'fixnum 'number)
  #t)

(test "subtype?/fixnum < integer"
  (subtype? 'fixnum 'integer)
  #t)

(test "subtype?/fixnum < real"
  (subtype? 'fixnum 'real)
  #t)

(test "subtype?/string not < fixnum"
  (subtype? 'string 'fixnum)
  #f)

(test "subtype?/any supertype of everything"
  (subtype? 'string 'any)
  #t)

(test "subtype?/never subtype of everything"
  (subtype? 'never 'string)
  #t)

(test "subtype?/reflexivity"
  (subtype? 'string 'string)
  #t)

(test "subtype?/flonum < number"
  (subtype? 'flonum 'number)
  #t)

;;;; Test 16: type-error? predicate

(test "type-error?/true for make-type-error"
  (type-error? (make-type-error "msg" #f 'expected 'actual))
  #t)

(test "type-error?/false for string"
  (type-error? "not an error")
  #f)

;;;; Test 17: type-error accessors

(test "type-error/message"
  (type-error-message (make-type-error "test message" #f 'string 'fixnum))
  "test message")

(test "type-error/expected"
  (type-error-expected (make-type-error "msg" #f 'string 'fixnum))
  'string)

(test "type-error/actual"
  (type-error-actual (make-type-error "msg" #f 'string 'fixnum))
  'fixnum)

(test "type-error/location"
  (type-error-location (make-type-error "msg" 'here 'string 'fixnum))
  'here)

;;;; Test 18: Variable lookup in env during infer

(test "infer/variable from env"
  (let ([env (type-env-extend (empty-type-env) '((x . fixnum)))])
    (infer-type 'x env))
  'fixnum)

(test "infer/unbound variable returns any"
  (infer-type 'unknown-var (empty-type-env))
  'any)

;;;; Test 19: infer-type of null

(test "infer/null literal"
  (infer '())
  'null)

;;;; Test 20: infer-type of char

(test "infer/char literal"
  (infer #\a)
  'char)

;;;; Test 21: subtype? with union types

(test "subtype?/t1 is subtype of union containing t1"
  (subtype? 'fixnum '(union fixnum string))
  #t)

(test "subtype?/t1 not subtype of union not containing t1"
  (subtype? 'boolean '(union fixnum string))
  #f)

;;;; Test 22: unify incompatible types creates union

(test-true "unify/incompatible types creates union"
  (let ([t (unify-types 'string 'fixnum)])
    (and (pair? t) (eq? (car t) 'union))))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
