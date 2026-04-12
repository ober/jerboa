(import (jerboa prelude))
(import (std zipper))

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
;; List zipper tests
;; =========================================================================

(def tree '(a (b c) (d (e f) g)))

(test "list-zipper creation"
  (assert-equal (zip-node (list-zipper tree)) tree "root node"))

(test "zip-down to first child"
  (let ([z (zip-down (list-zipper tree))])
    (assert-equal (zip-node z) 'a "first child is a")))

(test "zip-right to second child"
  (let* ([z (list-zipper tree)]
         [d (zip-down z)]
         [r (zip-right d)])
    (assert-equal (zip-node r) '(b c) "second child")))

(test "zip-down then down into nested"
  (let* ([z (list-zipper tree)]
         [d1 (zip-down z)]
         [r1 (zip-right d1)]
         [d2 (zip-down r1)])
    (assert-equal (zip-node d2) 'b "nested first child")))

(test "zip-up returns to parent"
  (let* ([z (list-zipper tree)]
         [d (zip-down z)]
         [u (zip-up d)])
    (assert-equal (zip-node u) tree "back to root")))

(test "zip-root from deep location"
  (let* ([z (list-zipper tree)]
         [d1 (zip-down z)]
         [r1 (zip-right d1)]
         [d2 (zip-down r1)])
    (assert-equal (zip-root d2) tree "root from deep")))

(test "zip-replace a node"
  (let* ([z (list-zipper tree)]
         [d (zip-down z)]
         [replaced (zip-replace d 'X)])
    (assert-equal (zip-root replaced) '(X (b c) (d (e f) g)) "replaced first child")))

(test "zip-edit applies function"
  (let* ([z (list-zipper '(1 2 3))]
         [d (zip-down z)]
         [r (zip-right d)]
         [edited (zip-edit r + 10)])
    (assert-equal (zip-root edited) '(1 12 3) "edited second child")))

(test "zip-remove a node"
  (let* ([z (list-zipper '(a b c d))]
         [d (zip-down z)]
         [r (zip-right d)]
         [removed (zip-remove r)])
    (assert-equal (zip-root removed) '(a c d) "removed b")))

(test "zip-insert-left"
  (let* ([z (list-zipper '(a b c))]
         [d (zip-down z)]
         [r (zip-right d)]
         [inserted (zip-insert-left r 'X)])
    (assert-equal (zip-root inserted) '(a X b c) "inserted X before b")))

(test "zip-insert-right"
  (let* ([z (list-zipper '(a b c))]
         [d (zip-down z)]
         [r (zip-right d)]
         [inserted (zip-insert-right r 'X)])
    (assert-equal (zip-root inserted) '(a b X c) "inserted X after b")))

(test "zip-leftmost"
  (let* ([z (list-zipper '(a b c d))]
         [d (zip-down z)]
         [r1 (zip-right d)]
         [r2 (zip-right r1)]
         [lm (zip-leftmost r2)])
    (assert-equal (zip-node lm) 'a "leftmost is a")))

(test "zip-rightmost"
  (let* ([z (list-zipper '(a b c d))]
         [d (zip-down z)]
         [rm (zip-rightmost d)])
    (assert-equal (zip-node rm) 'd "rightmost is d")))

(test "zip-lefts and zip-rights"
  (let* ([z (list-zipper '(a b c d))]
         [d (zip-down z)]
         [r1 (zip-right d)]
         [r2 (zip-right r1)])
    (assert-equal (zip-lefts r2) '(a b) "left siblings")
    (assert-equal (zip-rights r2) '(d) "right siblings")))

(test "zip-top? at root"
  (assert-equal (zip-top? (list-zipper '(a b))) #t "root is top"))

(test "zip-top? not at root"
  (assert-equal (zip-top? (zip-down (list-zipper '(a b)))) #f "child is not top"))

(test "zip-branch? on list"
  (assert-equal (zip-branch? (list-zipper '(a b))) #t "list is branch"))

(test "zip-branch? on atom"
  (let ([z (zip-down (list-zipper '(a b)))])
    (assert-equal (zip-branch? z) #f "atom is not branch")))

(test "zip-insert-child"
  (let* ([z (list-zipper '(a b c))]
         [inserted (zip-insert-child z 'X)])
    (assert-equal (zip-node inserted) '(X a b c) "inserted child at front")))

(test "zip-append-child"
  (let* ([z (list-zipper '(a b c))]
         [appended (zip-append-child z 'X)])
    (assert-equal (zip-node appended) '(a b c X) "appended child at end")))

;; =========================================================================
;; Depth-first traversal
;; =========================================================================

(test "zip-next traverses depth-first"
  (let* ([z (list-zipper '(a (b c) d))]
         [nodes '()])
    (let loop ([loc z])
      (unless (zip-end? loc)
        (set! nodes (cons (zip-node loc) nodes))
        (loop (zip-next loc))))
    (assert-equal (reverse nodes)
      '((a (b c) d) a (b c) b c d)
      "depth-first order")))

(test "zip-end? after full traversal"
  (let loop ([loc (list-zipper '(a b))])
    (if (zip-end? loc)
      (assert-equal #t #t "reached end")
      (loop (zip-next loc)))))

;; =========================================================================
;; Vector zipper tests
;; =========================================================================

(test "vector-zipper basic"
  (let* ([z (vector-zipper (vector 1 (vector 2 3) 4))]
         [d (zip-down z)]
         [r (zip-right d)])
    (assert-equal (zip-node r) (vector 2 3) "second child is vector")))

(test "vector-zipper edit and root"
  (let* ([z (vector-zipper (vector 1 2 3))]
         [d (zip-down z)]
         [r (zip-right d)]
         [edited (zip-replace r 99)])
    (assert-equal (zip-root edited) (vector 1 99 3) "replaced in vector")))

(test "zip-path returns ancestors"
  (let* ([z (list-zipper '(a (b c) d))]
         [d1 (zip-down z)]
         [r1 (zip-right d1)]
         [d2 (zip-down r1)])
    (assert-equal (zip-path d2) '((a (b c) d) (b c)) "path has root and parent")))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(displayln (str "========================================="))
(displayln (str "Results: " pass-count "/" test-count " passed"))
(displayln (str "========================================="))
(when (< pass-count test-count)
  (exit 1))
