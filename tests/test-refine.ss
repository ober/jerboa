#!chezscheme
;;; Tests for (std typed refine) — Refinement Types

(import (chezscheme) (std typed refine))

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

(define-syntax test-error
  (syntax-rules ()
    [(_ name expr)
     (let ([raised? #f])
       (guard (exn [#t (set! raised? #t)])
         expr)
       (if raised?
         (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
         (begin (set! fail (+ fail 1))
                (printf "FAIL ~a: expected error, got success~%" name))))]))

(define-syntax test-pred
  (syntax-rules ()
    [(_ name expr)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (if expr
         (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
         (begin (set! fail (+ fail 1))
                (printf "FAIL ~a: expected truthy~%" name))))]))

(printf "--- (std typed refine) tests ---~%")

;;; ===== make-refinement and predicates =====

(define MyR (make-refinement 'MyR number? (lambda (x) (> x 10))))

(test "refinement? true"  (refinement? MyR) #t)
(test "refinement? false" (refinement? 42)  #f)
(test "refinement-name"   (refinement-name MyR) 'MyR)
(test "refinement-pred result"
  ((refinement-pred MyR) 15)
  #t)

;;; ===== satisfies-refinement? =====

(test "satisfies-refinement? pass"
  (satisfies-refinement? MyR 20)
  #t)

(test "satisfies-refinement? fail pred"
  (satisfies-refinement? MyR 5)
  #f)

(test "satisfies-refinement? fail base"
  (satisfies-refinement? MyR "hello")
  #f)

;;; ===== check-refinement! =====

(test "check-refinement! no error on pass"
  (begin (check-refinement! MyR 15 'test) 'ok)
  'ok)

(test-error "check-refinement! error on fail"
  (check-refinement! MyR 3 'test))

;;; ===== assert-refined =====

(test "assert-refined returns value on pass"
  (assert-refined 42 (make-refinement 'PosNum number? positive?))
  42)

(test-error "assert-refined raises on fail"
  (assert-refined -1 (make-refinement 'PosNum number? positive?)))

;;; ===== Refine macro =====

(define MyRefine (Refine number? (lambda (x) (even? x))))

(test "Refine: even number passes"
  (satisfies-refinement? MyRefine 4)
  #t)

(test "Refine: odd number fails"
  (satisfies-refinement? MyRefine 3)
  #f)

;;; ===== Built-in refinements =====

;; NonNeg
(test "NonNeg: 0 passes"   (satisfies-refinement? NonNeg 0)   #t)
(test "NonNeg: 5 passes"   (satisfies-refinement? NonNeg 5)   #t)
(test "NonNeg: -1 fails"   (satisfies-refinement? NonNeg -1)  #f)

;; Positive
(test "Positive: 1 passes"  (satisfies-refinement? Positive 1)  #t)
(test "Positive: 0 fails"   (satisfies-refinement? Positive 0)  #f)
(test "Positive: -5 fails"  (satisfies-refinement? Positive -5) #f)

;; NonNull
(test "NonNull: pair passes"  (satisfies-refinement? NonNull '(1 2))  #t)
(test "NonNull: null fails"   (satisfies-refinement? NonNull '())     #f)

;; NonEmpty (list)
(test "NonEmpty list: non-empty passes" (satisfies-refinement? NonEmpty '(1)) #t)
(test "NonEmpty list: empty fails"      (satisfies-refinement? NonEmpty '())  #f)

;; NonEmpty (string)
(test "NonEmpty string: non-empty" (satisfies-refinement? NonEmpty "hi") #t)
(test "NonEmpty string: empty"     (satisfies-refinement? NonEmpty "")   #f)

;; NonZero
(test "NonZero: 1 passes"  (satisfies-refinement? NonZero 1)  #t)
(test "NonZero: 0 fails"   (satisfies-refinement? NonZero 0)  #f)
(test "NonZero: -3 passes" (satisfies-refinement? NonZero -3) #t)

;; Natural
(test "Natural: 0 passes"   (satisfies-refinement? Natural 0)   #t)
(test "Natural: 5 passes"   (satisfies-refinement? Natural 5)   #t)
(test "Natural: -1 fails"   (satisfies-refinement? Natural -1)  #f)
(test "Natural: 1.5 fails"  (satisfies-refinement? Natural 1.5) #f)

;; Bounded
(define B0to10 (Bounded 0 10))
(test "Bounded: 5 in [0,10]"  (satisfies-refinement? B0to10 5)   #t)
(test "Bounded: 0 in [0,10]"  (satisfies-refinement? B0to10 0)   #t)
(test "Bounded: 10 in [0,10]" (satisfies-refinement? B0to10 10)  #t)
(test "Bounded: 11 not in"    (satisfies-refinement? B0to10 11)  #f)
(test "Bounded: -1 not in"    (satisfies-refinement? B0to10 -1)  #f)

;;; ===== define/r =====

(define/r (safe-div [x : Positive] [y : NonZero])
  (/ x y))

(test "define/r: valid args"
  (safe-div 10 2)
  5)

(test-error "define/r: x violates Positive"
  (safe-div 0 2))

(test-error "define/r: y violates NonZero"
  (safe-div 10 0))

;;; ===== lambda/r =====

(define safe-sqrt
  (lambda/r ([x : NonNeg])
    (sqrt x)))

(test "lambda/r: valid"   (safe-sqrt 4)  2)
(test "lambda/r: zero ok" (safe-sqrt 0)  0)

(test-error "lambda/r: negative fails"
  (safe-sqrt -1))

;;; ===== refine-branch =====

(test "refine-branch true branch"
  (refine-branch 5
    (make-refinement 'Pos number? positive?)
    'positive
    'not-positive)
  'positive)

(test "refine-branch false branch"
  (refine-branch -3
    (make-refinement 'Pos number? positive?)
    'positive
    'not-positive)
  'not-positive)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
