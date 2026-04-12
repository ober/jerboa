(import (jerboa prelude))
(import (std test check))

(def test-count 0)
(def pass-count 0)

(defrule (test name body ...)
  (begin
    (set! test-count (+ test-count 1))
    (guard (exn [#t
      (displayln (str "FAIL: " name))
      (displayln (str "  Error: " (if (message-condition? exn)
                                    (condition-message exn) exn)))])
      body ...
      (set! pass-count (+ pass-count 1))
      (displayln (str "PASS: " name)))))

(defrule (assert-equal got expected msg)
  (unless (equal? got expected)
    (error 'assert msg (list 'got: got 'expected: expected))))

(defrule (assert-true val msg)
  (unless val (error 'assert msg)))

;; =========================================================================
;; Generator sampling tests
;; =========================================================================

(test "gen:integer produces integers"
  (let ([samples (gen:sample (gen:integer) 20)])
    (assert-true (every integer? samples) "all integers")
    (assert-true (> (length samples) 0) "non-empty")))

(test "gen:nat produces non-negative integers"
  (let ([samples (gen:sample (gen:nat) 20)])
    (assert-true (every (lambda (n) (and (integer? n) (>= n 0))) samples)
      "all non-negative")))

(test "gen:boolean produces booleans"
  (let ([samples (gen:sample (gen:boolean) 50)])
    (assert-true (every boolean? samples) "all booleans")
    ;; With 50 samples, expect both #t and #f
    (assert-true (any (lambda (x) (eq? x #t)) samples) "has true")
    (assert-true (any (lambda (x) (eq? x #f)) samples) "has false")))

(test "gen:char produces printable chars"
  (let ([samples (gen:sample (gen:char) 20)])
    (assert-true (every char? samples) "all chars")
    (assert-true (every (lambda (c) (and (char>=? c #\space) (char<=? c #\~)))
                        samples)
      "all printable")))

(test "gen:string produces strings"
  (let ([samples (gen:sample (gen:string) 10)])
    (assert-true (every string? samples) "all strings")))

(test "gen:elements picks from list"
  (let ([samples (gen:sample (gen:elements '(a b c)) 30)])
    (assert-true (every (lambda (x) (memq x '(a b c))) samples)
      "all from list")))

(test "gen:choose within range"
  (let ([samples (gen:sample (gen:choose 5 10) 50)])
    (assert-true (every (lambda (n) (and (>= n 5) (<= n 10))) samples)
      "all in range")))

(test "gen:list produces lists"
  (let ([samples (gen:sample (gen:list (gen:nat)) 10)])
    (assert-true (every list? samples) "all lists")
    (assert-true (every (lambda (lst) (every (lambda (x) (and (integer? x) (>= x 0))) lst))
                        samples)
      "all elements are nats")))

(test "gen:vector produces vectors"
  (let ([samples (gen:sample (gen:vector (gen:boolean)) 10)])
    (assert-true (every vector? samples) "all vectors")))

(test "gen:pair produces pairs"
  (let ([samples (gen:sample (gen:pair (gen:nat) (gen:boolean)) 10)])
    (assert-true (every pair? samples) "all pairs")
    (assert-true (every (lambda (p) (integer? (car p))) samples) "car is int")
    (assert-true (every (lambda (p) (boolean? (cdr p))) samples) "cdr is bool")))

(test "gen:tuple produces tuples"
  (let ([samples (gen:sample (gen:tuple (gen:nat) (gen:boolean) (gen:char)) 10)])
    (assert-true (every (lambda (t) (= (length t) 3)) samples) "length 3")
    (assert-true (every (lambda (t) (integer? (car t))) samples) "first is int")))

(test "gen:fmap transforms values"
  (let ([samples (gen:sample (gen:fmap (lambda (n) (* n 2)) (gen:nat)) 20)])
    (assert-true (every even? samples) "all even")))

(test "gen:such-that filters"
  (let ([samples (gen:sample (gen:such-that even? (gen:integer)) 20)])
    (assert-true (every even? samples) "all even")))

(test "gen:one-of picks from generators"
  (let ([samples (gen:sample (gen:one-of (list (gen:return 'a) (gen:return 'b))) 30)])
    (assert-true (every (lambda (x) (memq x '(a b))) samples) "all a or b")))

;; =========================================================================
;; Shrinking tests
;; =========================================================================

(test "shrink-integer toward zero"
  (let ([shrinks (shrink-integer 10)])
    (assert-true (memv 0 shrinks) "contains 0")
    (assert-true (every (lambda (n) (< (abs n) (abs 10))) shrinks)
      "all smaller")))

(test "shrink-integer from 0 is empty"
  (assert-equal (shrink-integer 0) '() "no shrinks from 0"))

(test "shrink-list removes elements"
  (let ([shrinks (shrink-list '(1 2 3))])
    (assert-true (member '(2 3) shrinks) "can remove first")
    (assert-true (member '(1 3) shrinks) "can remove middle")
    (assert-true (member '(1 2) shrinks) "can remove last")))

;; =========================================================================
;; Property checking tests
;; =========================================================================

(test "check-property passing"
  (let ([result (check-property 100
                  (for-all ([x (gen:integer)]
                            [y (gen:integer)])
                    (= (+ x y) (+ y x))))])
    (assert-equal (car result) 'ok "addition is commutative")))

(test "check-property failing with shrink"
  (let ([result (check-property 100
                  (for-all ([x (gen:choose 0 200)])
                    (< x 10)))])
    (assert-equal (car result) 'fail "finds failure")
    ;; Shrunk value should be close to 10
    (let ([shrunk (cadddr result)])
      (assert-true (pair? shrunk) "has shrunk values"))))

(test "check-property list reversal"
  (let ([result (check-property 100
                  (for-all ([xs (gen:list (gen:integer))])
                    (equal? xs (reverse (reverse xs)))))])
    (assert-equal (car result) 'ok "reverse is involutory")))

(test "check-property detects simple failure"
  (let ([result (check-property 50
                  (for-all ([x (gen:choose 0 100)])
                    (even? x)))])
    (assert-equal (car result) 'fail "finds odd number")))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(displayln (str "========================================="))
(displayln (str "Results: " pass-count "/" test-count " passed"))
(displayln (str "========================================="))
(when (< pass-count test-count)
  (exit 1))
