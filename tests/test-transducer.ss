#!chezscheme
;;; Tests for (std transducer) — Composable data transformations

(import (chezscheme) (std transducer))

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

(printf "--- (std transducer) tests ---~%")

;;;; Test 1: (mapping f) basic — map +1 over list

(test "mapping/basic +1"
  (sequence (mapping (lambda (x) (+ x 1))) '(1 2 3 4 5))
  '(2 3 4 5 6))

;;;; Test 2: (filtering pred) basic — keep evens

(test "filtering/basic evens"
  (sequence (filtering even?) '(1 2 3 4 5 6))
  '(2 4 6))

;;;; Test 3: (taking n) basic — take first 3

(test "taking/basic first 3"
  (sequence (taking 3) '(1 2 3 4 5 6 7))
  '(1 2 3))

;;;; Test 4: (dropping n) basic — drop first 2

(test "dropping/basic drop 2"
  (sequence (dropping 2) '(1 2 3 4 5))
  '(3 4 5))

;;;; Test 5: (flat-mapping f) basic — each element becomes a list

(test "flat-mapping/basic"
  (sequence (flat-mapping (lambda (x) (list x (* x 10)))) '(1 2 3))
  '(1 10 2 20 3 30))

;;;; Test 6: (taking-while pred) stops at first false

(test "taking-while/stops at first false"
  (sequence (taking-while (lambda (x) (< x 4))) '(1 2 3 4 5 6))
  '(1 2 3))

;;;; Test 7: (dropping-while pred) drops until predicate fails

(test "dropping-while/drops while pred true"
  (sequence (dropping-while (lambda (x) (< x 4))) '(1 2 3 4 5 6))
  '(4 5 6))

;;;; Test 8: (deduplicate) removes consecutive duplicates

(test "deduplicate/removes consecutive"
  (sequence (deduplicate) '(1 1 2 2 3 1 1))
  '(1 2 3 1))

(test "deduplicate/no change when no consecutive dupes"
  (sequence (deduplicate) '(1 2 3 4))
  '(1 2 3 4))

;;;; Test 9: (indexing) produces (index . value) pairs

(test "indexing/basic"
  (sequence (indexing) '(a b c))
  '((0 . a) (1 . b) (2 . c)))

(test "indexing/empty list"
  (sequence (indexing) '())
  '())

;;;; Test 10: (compose-transducers mapping filtering)

(test "compose-transducers/mapping then filtering"
  (sequence (compose-transducers (mapping (lambda (x) (* x 2)))
                                 (filtering even?))
            '(1 2 3 4 5))
  '(2 4 6 8 10))

(test "compose-transducers/filtering then mapping"
  (sequence (compose-transducers (filtering odd?)
                                 (mapping (lambda (x) (* x 10))))
            '(1 2 3 4 5))
  '(10 30 50))

;;;; Test 11: (transduce xf rf init coll) basic

(test "transduce/mapping with rf-cons"
  (transduce (mapping (lambda (x) (+ x 1))) (rf-cons) '() '(1 2 3))
  '(2 3 4))

;;;; Test 12: (into '() xf coll) into list

(test "into/list destination"
  (into '() (mapping (lambda (x) (* x x))) '(1 2 3 4))
  '(1 4 9 16))

;;;; Test 13: (into #() xf coll) into vector

(test "into/vector destination"
  (into (vector) (mapping (lambda (x) (+ x 10))) '(1 2 3))
  (vector 11 12 13))

;;;; Test 14: (sequence xf coll) returns list

(test "sequence/returns list"
  (sequence (mapping (lambda (x) (- x 1))) '(10 20 30))
  '(9 19 29))

;;;; Test 15: transduce with rf-count

(test "transduce/rf-count"
  (transduce (filtering odd?) (rf-count) 0 '(1 2 3 4 5 6 7))
  4)

;;;; Test 16: transduce with rf-sum

(test "transduce/rf-sum"
  (transduce (mapping (lambda (x) (* x x))) (rf-sum) 0 '(1 2 3 4))
  30)

;;;; Test 17: Composition of 3 transducers

(test "compose/three transducers"
  (sequence (compose-transducers
              (filtering odd?)
              (mapping (lambda (x) (* x 2)))
              (taking 3))
            '(1 2 3 4 5 6 7 8 9))
  '(2 6 10))

;;;; Test 18: (taking n) short-circuits early

;; We verify this works correctly (early stop returns exactly n items)
(test "taking/short-circuits at n"
  (sequence (taking 0) '(1 2 3 4 5))
  '())

(test "taking/exactly n items"
  (sequence (taking 5) '(1 2 3 4 5 6 7 8 9 10))
  '(1 2 3 4 5))

;;;; Test 19: (partitioning-by f) groups consecutive equal results

(test "partitioning-by/basic"
  (sequence (partitioning-by even?) '(1 3 2 4 5 7))
  '((1 3) (2 4) (5 7)))

(test "partitioning-by/all same key"
  (sequence (partitioning-by odd?) '(1 3 5 7))
  '((1 3 5 7)))

;;;; Test 20: (windowing n) sliding window

(test "windowing/basic window of 3"
  (sequence (windowing 3) '(1 2 3 4 5))
  '((1 2 3) (2 3 4) (3 4 5)))

(test "windowing/window of 2"
  (sequence (windowing 2) '(1 2 3 4))
  '((1 2) (2 3) (3 4)))

(test "windowing/list shorter than window — no output"
  (sequence (windowing 5) '(1 2 3))
  '())

;;;; Test 21: transducer? predicate

(test-true "transducer?/true for mapping"
  (transducer? (mapping car)))

(test "transducer?/false for procedure"
  (transducer? car)
  #f)

(test "transducer?/false for number"
  (transducer? 42)
  #f)

;;;; Test 22: xf-compose is alias for compose-transducers

(test "xf-compose/alias works"
  (sequence (xf-compose (filtering odd?) (mapping (lambda (x) (* x 3))))
            '(1 2 3 4 5))
  '(3 9 15))

;;;; Test 23: (cat) flattens one level

(test "cat/flatten one level"
  (sequence (cat) '((1 2) (3 4) (5)))
  '(1 2 3 4 5))

;;;; Test 24: (enumerating) alias for indexing

(test "enumerating/alias for indexing"
  (sequence (enumerating) '(x y z))
  '((0 . x) (1 . y) (2 . z)))

;;;; Test 25: into with string destination (chars)

(test "into/string destination with chars"
  (into "" (mapping (lambda (c) c)) '(#\h #\i))
  "hi")

;;;; Test 26: rf-sum with mapping

(test "rf-sum/sum of mapped values"
  (transduce (mapping (lambda (x) (* x 2))) (rf-sum) 0 '(1 2 3 4 5))
  30)

;;;; Test 27: empty collection

(test "mapping/empty collection"
  (sequence (mapping (lambda (x) (+ x 1))) '())
  '())

(test "filtering/empty collection"
  (sequence (filtering even?) '())
  '())

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
