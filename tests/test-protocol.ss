#!chezscheme
;;; Tests for (std protocol) — Clojure-style protocols.

(import (jerboa prelude)
        (std protocol))

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

(printf "--- std/protocol ---~%~%")

;;; ---- defprotocol basics ----------------------------------------

(defprotocol Shape
  (area      (self))
  (perimeter (self)))

(test "protocol? true for defprotocol result"
  (protocol? Shape)
  #t)

(test "protocol? false for non-protocols"
  (list (protocol? 42) (protocol? '()) (protocol? "str"))
  '(#f #f #f))

(test "protocol-name"
  (protocol-name Shape)
  'Shape)

(test "protocol-methods"
  (list-sort (lambda (a b)
               (string<? (symbol->string a) (symbol->string b)))
             (protocol-methods Shape))
  '(area perimeter))

;;; ---- extend-type on built-in types -----------------------------

(extend-type 'string Shape
  (area      (s) (string-length s))
  (perimeter (s) (* 4 (string-length s))))

(extend-type 'pair Shape
  (area      (p) (length p))
  (perimeter (p) (* 2 (length p))))

(test "dispatch on string"
  (area "hello")
  5)

(test "perimeter on string"
  (perimeter "hello")
  20)

(test "dispatch on pair"
  (area '(a b c d))
  4)

(test "perimeter on pair"
  (perimeter '(a b c))
  6)

;;; ---- No implementation => raise --------------------------------

(test "calling method on unsupported type raises"
  (guard (_ [else 'raised])
    (area 42))
  'raised)

;;; ---- satisfies? ------------------------------------------------

(test "satisfies? true when all methods implemented for type"
  (satisfies? Shape "foo")
  #t)

(test "satisfies? false for unsupported type"
  (satisfies? Shape 42)
  #f)

(test "satisfies? false when type has only some methods"
  (let ()
    (defprotocol Partial
      (m1 (self))
      (m2 (self)))
    (extend-type 'number Partial
      (m1 (n) n))
    (satisfies? Partial 42))
  #f)

(test "satisfies? error on non-protocol"
  (guard (_ [else 'raised])
    (satisfies? "not-a-protocol" 42))
  'raised)

;;; ---- extend-protocol (bulk) ------------------------------------

(defprotocol Describable
  (describe (self)))

(extend-protocol Describable
  ('string
    (describe (s) (list 'string (string-length s))))
  ('number
    (describe (n) (list 'number n)))
  ('symbol
    (describe (s) (list 'symbol s))))

(test "extend-protocol string"
  (describe "abc")
  '(string 3))

(test "extend-protocol number"
  (describe 42)
  '(number 42))

(test "extend-protocol symbol"
  (describe 'hi)
  '(symbol hi))

;;; ---- Records via defstruct -------------------------------------

(defstruct point (x y))
(defstruct circle (r))

(defprotocol Geom
  (center-of-mass (self))
  (shape-name     (self)))

(extend-type point::t Geom
  (center-of-mass (p) (list (point-x p) (point-y p)))
  (shape-name     (p) 'point))

(extend-type circle::t Geom
  (center-of-mass (c) (list 0 0))
  (shape-name     (c) 'circle))

(test "dispatch on defstruct point"
  (center-of-mass (make-point 3 4))
  '(3 4))

(test "dispatch on defstruct circle"
  (center-of-mass (make-circle 5))
  '(0 0))

(test "shape-name point"
  (shape-name (make-point 1 2))
  'point)

(test "shape-name circle"
  (shape-name (make-circle 7))
  'circle)

(test "satisfies? works on records"
  (list (satisfies? Geom (make-point 1 2))
        (satisfies? Geom (make-circle 3))
        (satisfies? Geom "not-a-record"))
  '(#t #t #f))

;;; ---- 'any fallback ---------------------------------------------

(defprotocol Greetable
  (greet (self)))

(extend-type 'any Greetable
  (greet (x) (list 'hi x)))

(test "'any fallback fires when no type-specific method"
  (greet 42)
  '(hi 42))

(test "'any fallback also works for strings"
  (greet "world")
  '(hi "world"))

(test "type-specific override beats 'any"
  (begin
    (extend-type 'string Greetable
      (greet (s) (list 'hello-string s)))
    (greet "world"))
  '(hello-string "world"))

(test "'any fallback still works for number after string override"
  (greet 99)
  '(hi 99))

(test "satisfies? does NOT count 'any fallback"
  (let ()
    (defprotocol OnlyAny
      (foo (self)))
    (extend-type 'any OnlyAny
      (foo (x) x))
    (satisfies? OnlyAny 42))
  #f)

;;; ---- Method redefinition replaces ------------------------------

(defprotocol Counter
  (n (self)))

(extend-type 'number Counter
  (n (x) (* 2 x)))

(test "first extend-type"
  (n 21)
  42)

(extend-type 'number Counter
  (n (x) (* 3 x)))

(test "re-extend-type replaces"
  (n 21)
  63)

;;; ---- Multi-argument methods ------------------------------------

(defprotocol Mixer
  (mix (self other)))

(extend-type 'number Mixer
  (mix (a b) (+ a b)))

(extend-type 'string Mixer
  (mix (a b) (string-append a (if (string? b) b (format "~a" b)))))

(test "multi-arg dispatch number"
  (mix 3 4)
  7)

(test "multi-arg dispatch string"
  (mix "hello " "world")
  "hello world")

(test "dispatch uses first arg only"
  (mix "x=" 42)
  "x=42")

;;; ---- protocol-methods returns list -----------------------------

(test "protocol-methods order matches defprotocol"
  (let ()
    (defprotocol Three
      (a (self))
      (b (self))
      (c (self)))
    (protocol-methods Three))
  '(a b c))

;;; ---- extenders / extends? (Round 5 §34) ------------------------

(defprotocol MyShape
  (my-area (self))
  (my-perimeter (self)))

(extend-protocol MyShape
  ('string (my-area (s) (string-length s))
           (my-perimeter (s) (* 4 (string-length s))))
  ('pair   (my-area (p) (length p))
           (my-perimeter (p) (* 2 (length p)))))

(test "extends? reports covered type"
  (extends? MyShape 'string)
  #t)

(test "extends? rejects unrelated type"
  (extends? MyShape 'vector)
  #f)

(test "extends? rejects partial coverage"
  (let ()
    (defprotocol Partial
      (p-a (self))
      (p-b (self)))
    (extend-type 'symbol Partial (p-a (s) s))  ;; only p-a
    (extends? Partial 'symbol))
  #f)

(test "extenders lists all fully-covered type keys"
  (let ([ex (extenders MyShape)])
    (and (memq 'string ex) (memq 'pair ex) #t))
  #t)

(test "extenders excludes partial coverage"
  (let ()
    (defprotocol Partial2
      (pp-a (self))
      (pp-b (self)))
    (extend-type 'bytevector Partial2 (pp-a (n) n))
    (memq 'bytevector (extenders Partial2)))
  #f)

(test "extends? errors on non-protocol"
  (guard (exn [else 'caught])
    (extends? 'not-a-proto 'string))
  'caught)

(test "extenders errors on non-protocol"
  (guard (exn [else 'caught])
    (extenders 'not-a-proto))
  'caught)

;;; ---- Summary ---------------------------------------------------
(printf "~%std/protocol: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
