#!chezscheme
;;; Tests for (std typed typeclass) — Type class system

(import (chezscheme) (std typed typeclass))

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

(printf "--- Phase 2c: Type Classes ---~%~%")

;; ========== Basic class definition ==========

(define-class Eq
  (== a b)
  (/= a b))

(test "class is a descriptor"
  (vector? Eq)
  #t)

;; ========== Instance registration ==========

(define-instance Eq fixnum
  (== equal?)
  (/= (lambda (a b) (not (equal? a b)))))

(define-instance Eq string
  (== string=?)
  (/= (lambda (a b) (not (string=? a b)))))

(test "instance-of/fixnum returns hashtable"
  (hashtable? (instance-of 'Eq 'fixnum))
  #t)

(test "instance-of/string returns hashtable"
  (hashtable? (instance-of 'Eq 'string))
  #t)

(test "instance-of/unknown returns #f"
  (instance-of 'Eq 'unknown-type)
  #f)

;; ========== class-method ==========

(test "class-method/== for fixnum"
  (let* ([inst (instance-of 'Eq 'fixnum)]
         [proc (class-method inst '==)])
    (proc 5 5))
  #t)

(test "class-method//= for fixnum"
  (let* ([inst (instance-of 'Eq 'fixnum)]
         [proc (class-method inst '/=)])
    (proc 1 2))
  #t)

(test "class-method/== for string"
  (let* ([inst (instance-of 'Eq 'string)]
         [proc (class-method inst '==)])
    (proc "hello" "hello"))
  #t)

(test "class-method//= for string"
  (let* ([inst (instance-of 'Eq 'string)]
         [proc (class-method inst '/=)])
    (proc "a" "b"))
  #t)

(test "class-method/missing returns #f"
  (let ([inst (instance-of 'Eq 'fixnum)])
    (class-method inst 'nonexistent))
  #f)

;; ========== with-class ==========

(test "with-class/== fixnum equal"
  (with-class Eq
    (Eq == 42 42))
  #t)

(test "with-class/== fixnum not equal"
  (with-class Eq
    (Eq == 1 2))
  #f)

(test "with-class//= fixnum"
  (with-class Eq
    (Eq /= 3 4))
  #t)

(test "with-class/== string"
  (with-class Eq
    (Eq == "abc" "abc"))
  #t)

(test "with-class//= string"
  (with-class Eq
    (Eq /= "x" "y"))
  #t)

(test "with-class/body has multiple exprs"
  (with-class Eq
    (Eq == 1 1)
    (Eq /= 1 2))
  #t)

;; ========== Multiple classes ==========

(define-class Show
  (show v))

(define-instance Show fixnum
  (show number->string))

(define-instance Show string
  (show (lambda (s) (string-append "\"" s "\""))))

(test "Show/fixnum"
  (with-class Show
    (Show show 42))
  "42")

(test "Show/string"
  (with-class Show
    (Show show "hi"))
  "\"hi\"")

;; ========== Type inference ==========

;; infer-type-tag covers standard Scheme types
(test "type inference: fixnum"
  (let* ([inst (instance-of 'Eq 'fixnum)]
         [proc (class-method inst '==)])
    (procedure? proc))
  #t)

(test "type inference: string"
  (let* ([inst (instance-of 'Eq 'string)]
         [proc (class-method inst '==)])
    (procedure? proc))
  #t)

;; ========== Error cases ==========

(test "define-instance/unknown class errors"
  (guard (exn [#t (condition-message exn)])
    (define-instance NonExistentClass foo
      (method (lambda (x) x))))
  "unknown class")

(test "with-class/no instance errors"
  (guard (exn [#t (condition-message exn)])
    (with-class Eq
      (Eq == 'some-symbol 'other)))
  "no instance for type")

;; ========== Ord class with multiple methods ==========

(define-class Ord
  (< a b)
  (> a b)
  (<= a b)
  (>= a b))

(define-instance Ord fixnum
  (<  (lambda (a b) (fx<  a b)))
  (>  (lambda (a b) (fx>  a b)))
  (<= (lambda (a b) (fx<= a b)))
  (>= (lambda (a b) (fx>= a b))))

(test "Ord/< true"
  (with-class Ord
    (Ord < 1 2))
  #t)

(test "Ord/< false"
  (with-class Ord
    (Ord < 2 1))
  #f)

(test "Ord/> true"
  (with-class Ord
    (Ord > 5 3))
  #t)

(test "Ord/<= equal"
  (with-class Ord
    (Ord <= 4 4))
  #t)

(test "Ord/>= greater"
  (with-class Ord
    (Ord >= 10 5))
  #t)

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
