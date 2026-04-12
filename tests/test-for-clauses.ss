(import (jerboa prelude))

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
;; Backwards compatibility — existing syntax still works
;; =========================================================================

(test "for/collect single binding"
  (assert-equal (for/collect ([x (in-range 5)]) (* x x))
    '(0 1 4 9 16) "squares"))

(test "for/collect two bindings"
  (assert-equal (for/collect ([x '(1 2)] [y '(a b)]) (list x y))
    '((1 a) (2 b)) "zipped"))

(test "for single binding side effect"
  (let ([acc '()])
    (for ([x '(1 2 3)]) (set! acc (cons x acc)))
    (assert-equal (reverse acc) '(1 2 3) "side effects")))

(test "for/fold single binding"
  (assert-equal (for/fold ([sum 0]) ([x (in-range 5)]) (+ sum x))
    10 "sum 0-4"))

(test "for/or single binding"
  (assert-equal (for/or ([x '(1 3 4 7)]) (and (even? x) x))
    4 "first even"))

(test "for/and single binding"
  (assert-true (for/and ([x '(2 4 6)]) (even? x))
    "all even"))

;; =========================================================================
;; :when clause
;; =========================================================================

(test "for/collect :when"
  (assert-equal (for/collect ([x (in-range 10)] when: (even? x)) x)
    '(0 2 4 6 8) "even only"))

(test "for/collect :when with body"
  (assert-equal (for/collect ([x (in-range 10)] when: (> x 5)) (* x 10))
    '(60 70 80 90) "filtered and transformed"))

(test "for :when side effect"
  (let ([acc '()])
    (for ([x (in-range 10)] when: (even? x))
      (set! acc (cons x acc)))
    (assert-equal (reverse acc) '(0 2 4 6 8) "side effects with when")))

(test "for/fold :when"
  (assert-equal (for/fold ([sum 0]) ([x (in-range 10)] when: (even? x))
                  (+ sum x))
    20 "sum of evens 0-8"))

(test "for/or :when"
  (assert-equal (for/or ([x '(1 3 5 6 7)] when: (even? x)) x)
    6 "first match after filter"))

(test "for/and :when"
  (assert-true (for/and ([x '(1 2 3 4 5 6)] when: (even? x)) (< x 10))
    "all filtered elements < 10"))

;; =========================================================================
;; :while clause
;; =========================================================================

(test "for/collect :while"
  (assert-equal (for/collect ([x (in-range 10)] while: (< x 5)) x)
    '(0 1 2 3 4) "take while < 5"))

(test "for/collect :while stops early"
  (assert-equal (for/collect ([x '(1 2 3 10 4 5)] while: (< x 10)) x)
    '(1 2 3) "stops at 10"))

(test "for/fold :while"
  (assert-equal (for/fold ([sum 0]) ([x (in-range 100)] while: (< x 5))
                  (+ sum x))
    10 "sum while < 5"))

;; =========================================================================
;; :let clause
;; =========================================================================

(test "for/collect :let"
  (assert-equal (for/collect ([x (in-range 5)]
                              let: ([y (* x x)])
                              when: (even? y))
                  y)
    '(0 4 16) "let + when"))

(test "for/collect :let multiple bindings"
  (assert-equal (for/collect ([x (in-range 1 4)]
                              let: ([y (* x 10)] [z (+ x 1)]))
                  (list x y z))
    '((1 10 2) (2 20 3) (3 30 4)) "multi-let"))

;; =========================================================================
;; Nested bindings (Clojure for comprehension)
;; =========================================================================

(test "for/collect two bindings zips"
  (assert-equal (for/collect ([x '(1 2)] [y '(a b)]) (list x y))
    '((1 a) (2 b)) "zip, not cross-product"))

(test "for/collect general path cross-product"
  (assert-equal (for/collect ([x '(1 2)] when: #t [y '(a b)]) (list x y))
    '((1 a) (1 b) (2 a) (2 b)) "cross-product via clauses"))

(test "for/collect nested with :when"
  (assert-equal (for/collect ([x (in-range 1 4)]
                              [y (in-range 1 4)]
                              when: (not (= x y)))
                  (list x y))
    '((1 2) (1 3) (2 1) (2 3) (3 1) (3 2)) "permutations"))

;; =========================================================================
;; Combined clauses
;; =========================================================================

(test "for/collect :when + :while"
  (assert-equal (for/collect ([x (in-range 20)]
                              when: (even? x)
                              while: (< x 10))
                  x)
    '(0 2 4 6 8) "when + while"))

(test "for/collect :let + :when + nested"
  (assert-equal (for/collect ([x (in-range 1 5)]
                              let: ([sq (* x x)])
                              when: (odd? sq)
                              [y '(10 20)])
                  (+ sq y))
    '(11 21 19 29) "complex comprehension"))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(displayln (str "========================================="))
(displayln (str "Results: " pass-count "/" test-count " passed"))
(displayln (str "========================================="))
(when (< pass-count test-count)
  (exit 1))
