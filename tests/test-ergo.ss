#!chezscheme
;;; Tests for (std ergo) — Ergonomic typing layer

(import (chezscheme) (std typed) (std ergo) (jerboa core))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn
              [#t (set! fail (+ fail 1))
                  (printf "FAIL ~a: exception ~a~%" name
                    (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1))
                  (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~a, expected ~a~%" name got expected)))))]))

(define-syntax test-error
  (syntax-rules ()
    [(_ name expr)
     (test name
       (guard (exn [#t #t])
         expr
         #f)
       #t)]))

(printf "--- (std ergo) tests ---~%")

;;; ========== : (checked cast) ==========

(printf "~%-- : (checked cast) --~%")

(parameterize ([*typed-mode* 'debug])
  (test ": fixnum pass" (: 42 fixnum) 42)
  (test ": string pass" (: "hello" string) "hello")
  (test-error ": fixnum fail" (: "oops" fixnum))
  (test-error ": string fail" (: 42 string)))

(parameterize ([*typed-mode* 'release])
  (test ": release mode no check" (: "oops" fixnum) "oops"))

;;; ========== maybe / list-of? ==========

(printf "~%-- contract predicates --~%")

(test "maybe: #f passes" ((maybe string?) #f) #t)
(test "maybe: string passes" ((maybe string?) "hi") #t)
(test "maybe: fixnum fails" ((maybe string?) 42) #f)

(test "list-of?: empty" ((list-of? fixnum?) '()) #t)
(test "list-of?: valid" ((list-of? fixnum?) '(1 2 3)) #t)
(test "list-of?: invalid" ((list-of? fixnum?) '(1 "x" 3)) #f)
(test "list-of?: not list" ((list-of? fixnum?) 42) #f)

;;; ========== using with : ==========

(printf "~%-- using (checked) --~%")

(defstruct point (x y))

(parameterize ([*typed-mode* 'debug])
  ;; Basic dot-access
  (test "using : dot-access x"
    (using (p (make-point 10 20) : point)
      p.x)
    10)

  (test "using : dot-access y"
    (using (p (make-point 10 20) : point)
      p.y)
    20)

  ;; Dot-access in expressions
  (test "using : dot in expr"
    (using (p (make-point 3 4) : point)
      (+ p.x p.y))
    7)

  ;; Dot-access in nested forms
  (test "using : dot in if"
    (using (p (make-point 5 0) : point)
      (if (> p.x 0) p.y -1))
    0)

  ;; Type check in debug mode
  (test-error "using : type check fails"
    (using (p "not a point" : point)
      p.x)))

;;; ========== using with as (unchecked) ==========

(printf "~%-- using (unchecked) --~%")

;; Unchecked: no type check, but dot-access works
(test "using as: dot-access"
  (using (p (make-point 7 8) as point)
    (+ p.x p.y))
  15)

;; No type check even in debug mode
(parameterize ([*typed-mode* 'debug])
  (test "using as: no type check"
    (using (p "not-a-point" as point)
      42)
    42))

;;; ========== using multiple bindings ==========

(printf "~%-- using (multiple bindings) --~%")

(defstruct rect (w h))

(test "using: two bindings"
  (using ((p (make-point 1 2) : point)
          (r (make-rect 10 20) : rect))
    (+ p.x r.w))
  11)

(test "using: mixed checked/unchecked"
  (using ((p (make-point 3 4) : point)
          (r (make-rect 5 6) as rect))
    (* p.y r.h))
  24)

;;; ========== using: quoted symbols not transformed ==========

(printf "~%-- using: quotes preserved --~%")

(test "using: quote not transformed"
  (using (p (make-point 1 2) : point)
    'p.x)
  'p.x)

;;; ========== def with typed params ==========

(printf "~%-- def with typed params --~%")

;; Basic typed def
(def (add-fx (x : fixnum) (y : fixnum))
  (fx+ x y))

(parameterize ([*typed-mode* 'debug])
  (test "def typed: basic" (add-fx 3 4) 7)
  (test-error "def typed: arg type error"
    (add-fx "bad" 4)))

;; Typed def with return type
(def (greet (name : string)) : string
  (string-append "hello " name))

(parameterize ([*typed-mode* 'debug])
  (test "def typed: return type" (greet "world") "hello world"))

;; Return type error
(def (bad-ret (x : fixnum)) : string
  x)

(parameterize ([*typed-mode* 'debug])
  (test-error "def typed: return type error"
    (bad-ret 42)))

;; Mixed typed and untyped params
(def (mixed (x : fixnum) y)
  (list x y))

(parameterize ([*typed-mode* 'debug])
  (test "def typed: mixed" (mixed 1 "two") '(1 "two"))
  (test-error "def typed: mixed type error"
    (mixed "bad" "two")))

;;; ========== def backward compat ==========

(printf "~%-- def backward compat --~%")

;; Plain def still works
(def (plain-add x y) (+ x y))
(test "def plain" (plain-add 3 4) 7)

;; Optional args still work
(def (with-default x (y 10)) (+ x y))
(test "def optional: both" (with-default 1 2) 3)
(test "def optional: default" (with-default 5) 15)

;; Variable def
(def my-val 42)
(test "def value" my-val 42)

;; Void def
(def my-void)
(test "def void" my-void (void))

;;; ========== Summary ==========

(printf "~%~a tests, ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
