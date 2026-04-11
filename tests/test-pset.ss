#!chezscheme
;;; Tests for (std pset) -- Persistent Hash Sets
;;;
;;; Covers construction, membership, set ops, structural equality,
;;; hashing, and iterators.

(import (chezscheme)
        (std pset))

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

(printf "--- Persistent Hash Sets ---~%~%")

;;; ======== Construction & membership ========

(test "empty set size"
  (persistent-set-size pset-empty)
  0)

(test "empty predicate"
  (persistent-set? pset-empty)
  #t)

(test "non-set predicate"
  (persistent-set? '(1 2 3))
  #f)

(test "from items"
  (persistent-set-size (persistent-set 1 2 3 4 5))
  5)

(test "duplicates collapsed"
  (persistent-set-size (persistent-set 1 2 1 3 2 1))
  3)

(test "contains? hit"
  (persistent-set-contains? (persistent-set 'a 'b 'c) 'b)
  #t)

(test "contains? miss"
  (persistent-set-contains? (persistent-set 'a 'b 'c) 'z)
  #f)

;;; ======== Functional update ========

(test "add preserves original"
  (let* ([s1 (persistent-set 1 2)]
         [s2 (persistent-set-add s1 3)])
    (list (persistent-set-size s1)
          (persistent-set-size s2)
          (persistent-set-contains? s1 3)
          (persistent-set-contains? s2 3)))
  '(2 3 #f #t))

(test "add existing is no-op"
  (let* ([s1 (persistent-set 1 2)]
         [s2 (persistent-set-add s1 1)])
    (eq? s1 s2))
  #t)

(test "remove preserves original"
  (let* ([s1 (persistent-set 1 2 3)]
         [s2 (persistent-set-remove s1 2)])
    (list (persistent-set-size s1)
          (persistent-set-size s2)
          (persistent-set-contains? s2 2)))
  '(3 2 #f))

;;; ======== Set operations ========

(test "union"
  (persistent-set-size
    (persistent-set-union (persistent-set 1 2 3) (persistent-set 3 4 5)))
  5)

(test "intersection"
  (let ([s (persistent-set-intersection
             (persistent-set 1 2 3 4)
             (persistent-set 3 4 5 6))])
    (list (persistent-set-size s)
          (persistent-set-contains? s 3)
          (persistent-set-contains? s 4)
          (persistent-set-contains? s 1)))
  '(2 #t #t #f))

(test "difference"
  (let ([s (persistent-set-difference
             (persistent-set 1 2 3)
             (persistent-set 2))])
    (list (persistent-set-size s)
          (persistent-set-contains? s 1)
          (persistent-set-contains? s 3)
          (persistent-set-contains? s 2)))
  '(2 #t #t #f))

(test "subset?"
  (persistent-set-subset? (persistent-set 1 2) (persistent-set 1 2 3))
  #t)

(test "subset? false"
  (persistent-set-subset? (persistent-set 1 2 3) (persistent-set 1 2))
  #f)

;;; ======== Structural equality ========

(test "=? same"
  (persistent-set=? (persistent-set 1 2 3) (persistent-set 1 2 3))
  #t)

(test "=? reordered"
  (persistent-set=? (persistent-set 1 2 3) (persistent-set 3 2 1))
  #t)

(test "=? different size"
  (persistent-set=? (persistent-set 1 2) (persistent-set 1 2 3))
  #f)

(test "=? different elements"
  (persistent-set=? (persistent-set 1 2 3) (persistent-set 1 2 4))
  #f)

(test "=? empty"
  (persistent-set=? pset-empty pset-empty)
  #t)

;;; ======== Structural hash ========

(test "hash reordered equal"
  (= (persistent-set-hash (persistent-set 1 2 3))
     (persistent-set-hash (persistent-set 3 2 1)))
  #t)

(test "hash different differs"
  (not (= (persistent-set-hash (persistent-set 1 2))
          (persistent-set-hash (persistent-set 1 3))))
  #t)

(test "hash empty is integer"
  (integer? (persistent-set-hash pset-empty))
  #t)

;;; ======== Iteration ========

(test "->list count"
  (length (persistent-set->list (persistent-set 'a 'b 'c 'd)))
  4)

(test "fold sum"
  (persistent-set-fold + 0 (persistent-set 1 2 3 4 5))
  15)

(test "filter"
  (let ([s (persistent-set-filter even? (persistent-set 1 2 3 4 5))])
    (list (persistent-set-size s)
          (persistent-set-contains? s 2)
          (persistent-set-contains? s 4)
          (persistent-set-contains? s 1)))
  '(2 #t #t #f))

(test "map"
  (let ([s (persistent-set-map (lambda (x) (* x x))
                                (persistent-set 1 2 3))])
    (list (persistent-set-size s)
          (persistent-set-contains? s 1)
          (persistent-set-contains? s 4)
          (persistent-set-contains? s 9)))
  '(3 #t #t #t))

(test "in-pset iterator"
  (length (in-pset (persistent-set 'a 'b 'c)))
  3)

;;; ======== Transients ========

(test "transient bulk insert"
  (let ([t (transient-set pset-empty)])
    (tset-add! t 1)
    (tset-add! t 2)
    (tset-add! t 3)
    (persistent-set-size (persistent-set! t)))
  3)

(test "transient size tracking"
  (let ([t (transient-set pset-empty)])
    (tset-add! t 1)
    (tset-add! t 1)
    (tset-add! t 2)
    (tset-size t))
  2)

;;; Summary

(printf "~%Persistent Hash Sets: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
