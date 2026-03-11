#!chezscheme
;;; Tests for (std typed gadt) — Generalized Algebraic Data Types

(import (chezscheme) (std typed gadt))

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

(printf "--- Phase 2c: GADTs ---~%~%")

;; ========== GADT: Expr ==========

(define-gadt Expr
  (Lit  val)
  (Add  a b)
  (IsZ  e)
  (If   c t f))

;; Constructor tests
(test "gadt?/Lit"
  (gadt? (Lit 42))
  #t)

(test "gadt?/non-gadt"
  (gadt? 42)
  #f)

(test "gadt?/vector-not-gadt"
  (gadt? (vector 1 2 3))
  #f)

(test "Expr? predicate"
  (Expr? (Lit 10))
  #t)

(test "Expr? wrong type"
  (Expr? (vector 'gadt-box 'Other 'Lit 10))
  #f)

(test "gadt-tag/Lit"
  (gadt-tag (Lit 99))
  'Lit)

(test "gadt-tag/Add"
  (gadt-tag (Add (Lit 1) (Lit 2)))
  'Add)

(test "gadt-constructor alias"
  (gadt-constructor (Lit 5))
  'Lit)

(test "gadt-fields/Lit"
  (gadt-fields (Lit 42))
  '(42))

(test "gadt-fields/Add"
  (let ([e (Add (Lit 1) (Lit 2))])
    (length (gadt-fields e)))
  2)

(test "gadt-fields/If 3 args"
  (length (gadt-fields (If (IsZ (Lit 0)) (Lit 1) (Lit 2))))
  3)

;; ========== Pattern matching ==========

(define (eval-expr e)
  (gadt-match e
    [(Lit v)    v]
    [(Add a b)  (+ (eval-expr a) (eval-expr b))]
    [(IsZ x)    (= (eval-expr x) 0)]
    [(If c t f) (if (eval-expr c) (eval-expr t) (eval-expr f))]))

(test "gadt-match/Lit"
  (eval-expr (Lit 10))
  10)

(test "gadt-match/Add"
  (eval-expr (Add (Lit 3) (Lit 4)))
  7)

(test "gadt-match/IsZ true"
  (eval-expr (IsZ (Lit 0)))
  #t)

(test "gadt-match/IsZ false"
  (eval-expr (IsZ (Lit 5)))
  #f)

(test "gadt-match/If true branch"
  (eval-expr (If (IsZ (Lit 0)) (Lit 100) (Lit 200)))
  100)

(test "gadt-match/If false branch"
  (eval-expr (If (IsZ (Lit 1)) (Lit 100) (Lit 200)))
  200)

(test "gadt-match/nested Add"
  (eval-expr (Add (Add (Lit 1) (Lit 2)) (Add (Lit 3) (Lit 4))))
  10)

;; ========== No-arg constructor ==========

(define-gadt Shape
  (Circle r)
  (Rect   w h)
  (Point))

(test "gadt/zero-field constructor"
  (gadt? (Point))
  #t)

(test "gadt/zero-field tag"
  (gadt-tag (Point))
  'Point)

(test "gadt/zero-field fields"
  (gadt-fields (Point))
  '())

(test "gadt-match/zero-field"
  (gadt-match (Point)
    [(Circle r) (* 3 r r)]
    [(Rect w h) (* w h)]
    [(Point)    0])
  0)

;; ========== Error cases ==========

(test "gadt-tag/non-gadt errors"
  (guard (exn [#t (condition-message exn)])
    (gadt-tag 42))
  "not a GADT value")

(test "gadt-fields/non-gadt errors"
  (guard (exn [#t (condition-message exn)])
    (gadt-fields "oops"))
  "not a GADT value")

(test "gadt-match/no-arm errors"
  (guard (exn [#t (condition-message exn)])
    (gadt-match (Lit 1)
      [(Add a b) 'add]))
  "no matching arm")

;; ========== Multiple GADTs don't mix ==========

(define-gadt Tree
  (Leaf v)
  (Node l r))

(test "Expr? rejects Tree"
  (Expr? (Leaf 1))
  #f)

(test "Tree? rejects Expr"
  (Tree? (Lit 1))
  #f)

(test "gadt-match/Tree"
  (let loop ([t (Node (Leaf 1) (Node (Leaf 2) (Leaf 3)))])
    (gadt-match t
      [(Leaf v) v]
      [(Node l r) (+ (loop l) (loop r))]))
  6)

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
