#!chezscheme
;;; Tests for match2 destructuring on persistent collections.
;;; Phase 27 of Round 4.
;;;
;;; Pattern forms added:
;;;   (pmap k1 p1 k2 p2 ...)   → pmap? guard + has?/ref per key
;;;   (pvec p1 p2 ...)         → pvec? + exact length + ref per index
;;;   (pset x1 x2 ...)         → pset? + contains? per element
;;;
;;; Aliases: persistent-map/pmap/imap, persistent-vector/pvec/ivec,
;;;          persistent-set/pset.

(import (chezscheme) (std match2) (std pmap) (std pvec) (std pset))

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

(printf "--- Round 4 Phase 27: match2 persistent destructuring ---~%~%")

;;; ========== pmap patterns ==========

(test "pmap simple extract"
  (let ([m (make-persistent-map 'a 1 'b 2)])
    (match m
      ((pmap 'a a 'b b) (list a b))
      (_ 'no-match)))
  '(1 2))

(test "pmap missing key falls through"
  (let ([m (make-persistent-map 'a 1)])
    (match m
      ((pmap 'missing x) x)
      (_ 'miss)))
  'miss)

(test "pmap non-pmap value falls through"
  ;; Critical: must NOT crash on non-pmap value.
  (match '(1 2 3)
    ((pmap 'a x) x)
    (_ 'not-pm))
  'not-pm)

(test "pmap nil value falls through"
  (match #f
    ((pmap 'a x) x)
    (_ 'not-pm))
  'not-pm)

(test "pmap alias persistent-map"
  (let ([m (make-persistent-map 'x 42)])
    (match m ((persistent-map 'x n) n) (_ #f)))
  42)

(test "pmap alias imap"
  (let ([m (make-persistent-map 'y 99)])
    (match m ((imap 'y n) n) (_ #f)))
  99)

(test "pmap nested pmap value"
  (let ([m (make-persistent-map 'outer (make-persistent-map 'inner 'found))])
    (match m
      ((pmap 'outer (pmap 'inner v)) v)
      (_ 'no)))
  'found)

(test "pmap with predicate subpattern"
  (let ([m (make-persistent-map 'n 5)])
    (match m
      ((pmap 'n (and (? number?) n)) (+ n 1))
      (_ 'no)))
  6)

(test "pmap with guard"
  (let ([m (make-persistent-map 'age 30)])
    (match m
      ((pmap 'age a) (where (>= a 18)) 'adult)
      (_ 'minor)))
  'adult)

(test "pmap guard fails → fall through"
  (let ([m (make-persistent-map 'age 10)])
    (match m
      ((pmap 'age a) (where (>= a 18)) 'adult)
      (_ 'minor)))
  'minor)

(test "pmap empty pattern (type-only check)"
  (match (make-persistent-map) ((pmap) 'yes) (_ 'no))
  'yes)

(test "pmap empty pattern rejects non-pmap"
  (match '() ((pmap) 'yes) (_ 'no))
  'no)

;;; ========== pvec patterns ==========

(test "pvec simple extract"
  (let ([v (persistent-vector 10 20 30)])
    (match v
      ((pvec a b c) (list a b c))
      (_ 'no)))
  '(10 20 30))

(test "pvec length mismatch falls through"
  (let ([v (persistent-vector 1 2 3)])
    (match v
      ((pvec a b) (list a b))
      (_ 'wrong-length)))
  'wrong-length)

(test "pvec non-pvec value falls through"
  (match '(1 2 3)
    ((pvec a b c) (list a b c))
    (_ 'not-pv))
  'not-pv)

(test "pvec empty"
  (match (persistent-vector) ((pvec) 'empty) (_ 'no))
  'empty)

(test "pvec alias persistent-vector"
  (let ([v (persistent-vector 'a 'b)])
    (match v
      ((persistent-vector x y) (list x y))
      (_ 'no)))
  '(a b))

(test "pvec alias ivec"
  (let ([v (persistent-vector 7 8)])
    (match v ((ivec x y) (+ x y)) (_ #f)))
  15)

(test "pvec nested"
  (let ([v (persistent-vector (persistent-vector 1 2) (persistent-vector 3 4))])
    (match v
      ((pvec (pvec a b) (pvec c d)) (list a b c d))
      (_ 'no)))
  '(1 2 3 4))

;;; ========== pset patterns ==========

(test "pset contains both"
  (let ([s (make-persistent-set 'red 'blue 'green)])
    (match s
      ((pset 'red 'blue) 'both-in)
      (_ 'no)))
  'both-in)

(test "pset missing falls through"
  (let ([s (make-persistent-set 'red)])
    (match s
      ((pset 'yellow) 'has-yellow)
      (_ 'no-yellow)))
  'no-yellow)

(test "pset non-pset value falls through"
  (match '(red)
    ((pset 'red) 'yes)
    (_ 'not-ps))
  'not-ps)

(test "pset empty (type-only)"
  (match (make-persistent-set) ((pset) 'ok) (_ 'no))
  'ok)

(test "pset empty rejects non-pset"
  (match 42 ((pset) 'ok) (_ 'no))
  'no)

;;; ========== Mixed nesting ==========

(test "pmap of pvec"
  (let ([m (make-persistent-map 'xs (persistent-vector 1 2 3))])
    (match m
      ((pmap 'xs (pvec a b c)) (+ a b c))
      (_ 'no)))
  6)

(test "pvec of pmap"
  (let ([v (persistent-vector (make-persistent-map 'n 7))])
    (match v
      ((pvec (pmap 'n x)) x)
      (_ 'no)))
  7)

(test "pmap of pset"
  (let ([m (make-persistent-map 'tags (make-persistent-set 'a 'b))])
    (match m
      ((pmap 'tags (pset 'a)) 'has-a)
      (_ 'no)))
  'has-a)

;;; ========== Regression — non-persistent patterns still work ==========

(test "regression list pattern still works"
  (match '(1 2 3)
    ((list a b c) (+ a b c))
    (_ 'no))
  6)

(test "regression vector pattern still works"
  (match (vector 1 2)
    ((vector a b) (list a b))
    (_ 'no))
  '(1 2))

(test "regression cons pattern still works"
  (match '(1 . 2)
    ((cons a b) (list a b))
    (_ 'no))
  '(1 2))

(printf "~%--- Results: ~a/~a passed, ~a failed ---~%"
  pass (+ pass fail) fail)

(exit (if (= fail 0) 0 1))
