(import (jerboa prelude))
(import (std specter))

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

;; =========================================================================
;; Basic select tests
;; =========================================================================

(test "select ALL from list"
  (assert-equal (select (list ALL) '(1 2 3)) '(1 2 3) "all elements"))

(test "select FIRST from list"
  (assert-equal (select (list FIRST) '(1 2 3)) '(1) "first element"))

(test "select LAST from list"
  (assert-equal (select (list LAST) '(1 2 3)) '(3) "last element"))

(test "select nthpath"
  (assert-equal (select (list (nthpath 1)) '(a b c)) '(b) "second element"))

(test "select nested: ALL then FIRST"
  (assert-equal (select (list ALL FIRST) '((1 2) (3 4) (5 6)))
    '(1 3 5) "first of each"))

(test "select filterer"
  (assert-equal (select (list (filterer even?)) '(1 2 3 4 5 6))
    '(2 4 6) "even elements"))

(test "select-one"
  (assert-equal (select-one (list FIRST) '(42 99)) 42 "first value"))

;; =========================================================================
;; Transform tests
;; =========================================================================

(test "transform ALL"
  (assert-equal (transform (list ALL) add1 '(1 2 3))
    '(2 3 4) "increment all"))

(test "transform FIRST"
  (assert-equal (transform (list FIRST) add1 '(10 20 30))
    '(11 20 30) "increment first"))

(test "transform LAST"
  (assert-equal (transform (list LAST) add1 '(10 20 30))
    '(10 20 31) "increment last"))

(test "transform nthpath"
  (assert-equal (transform (list (nthpath 1)) (lambda (x) (* x 10)) '(1 2 3))
    '(1 20 3) "transform second"))

(test "transform nested"
  (assert-equal (transform (list ALL FIRST) add1 '((1 2) (3 4) (5 6)))
    '((2 2) (4 4) (6 6)) "increment first of each"))

(test "setval"
  (assert-equal (setval (list FIRST) 'X '(1 2 3))
    '(X 2 3) "set first to X"))

(test "transform filterer"
  (assert-equal (transform (list (filterer even?)) add1 '(1 2 3 4))
    '(1 3 3 5) "increment evens"))

;; =========================================================================
;; Hash table navigation
;; =========================================================================

(test "select keypath from hash table"
  (let ([ht (make-hashtable equal-hash equal?)])
    (hashtable-set! ht 'name "Alice")
    (hashtable-set! ht 'age 30)
    (assert-equal (select (list (keypath 'name)) ht) '("Alice") "name value")))

(test "transform keypath in hash table"
  (let ([ht (make-hashtable equal-hash equal?)])
    (hashtable-set! ht 'x 10)
    (hashtable-set! ht 'y 20)
    (let ([result (transform (list (keypath 'x)) add1 ht)])
      (assert-equal (hashtable-ref result 'x #f) 11 "x incremented")
      (assert-equal (hashtable-ref result 'y #f) 20 "y unchanged"))))

(test "select MAP-VALS"
  (let ([ht (make-hashtable equal-hash equal?)])
    (hashtable-set! ht 'a 1)
    (hashtable-set! ht 'b 2)
    (let ([vals (list-sort < (select (list MAP-VALS) ht))])
      (assert-equal vals '(1 2) "all values"))))

(test "transform MAP-VALS"
  (let ([ht (make-hashtable equal-hash equal?)])
    (hashtable-set! ht 'a 1)
    (hashtable-set! ht 'b 2)
    (let ([result (transform (list MAP-VALS) add1 ht)])
      (assert-equal (hashtable-ref result 'a #f) 2 "a incremented")
      (assert-equal (hashtable-ref result 'b #f) 3 "b incremented"))))

;; =========================================================================
;; Walker (recursive)
;; =========================================================================

(test "select walker"
  (assert-equal (list-sort < (select (list (walker number?)) '(1 (2 "x") (3 (4)))))
    '(1 2 3 4) "all numbers recursively"))

(test "transform walker"
  (assert-equal (transform (list (walker number?)) add1 '(1 (2 "x") (3 (4))))
    '(2 (3 "x") (4 (5))) "increment all numbers recursively"))

;; =========================================================================
;; pred-nav
;; =========================================================================

(test "pred-nav selects matching"
  (assert-equal (select (list (pred-nav number?)) 42) '(42) "matches number"))

(test "pred-nav skips non-matching"
  (assert-equal (select (list (pred-nav number?)) "hello") '() "skips string"))

;; =========================================================================
;; srange
;; =========================================================================

(test "select srange"
  (assert-equal (select (list (srange 1 3)) '(a b c d e))
    '((b c)) "subrange"))

(test "transform srange"
  (assert-equal (transform (list (srange 1 3)) reverse '(a b c d e))
    '(a c b d e) "reversed subrange"))

;; =========================================================================
;; multi-path
;; =========================================================================

(test "multi-path select"
  (assert-equal (select (list (multi-path FIRST LAST)) '(1 2 3 4))
    '(1 4) "first and last"))

;; =========================================================================
;; Vector support
;; =========================================================================

(test "select ALL from vector"
  (assert-equal (select (list ALL) (vector 10 20 30)) '(10 20 30) "vector all"))

(test "transform ALL in vector"
  (assert-equal (transform (list ALL) add1 (vector 1 2 3))
    (vector 2 3 4) "vector transform all"))

(test "nthpath in vector"
  (assert-equal (transform (list (nthpath 1)) (lambda (x) (* x 10)) (vector 1 2 3))
    (vector 1 20 3) "vector nthpath transform"))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(displayln (str "========================================="))
(displayln (str "Results: " pass-count "/" test-count " passed"))
(displayln (str "========================================="))
(when (< pass-count test-count)
  (exit 1))
