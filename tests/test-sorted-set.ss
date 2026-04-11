#!chezscheme
;;; Tests for (std sorted-set) and Clojure's sorted-set dispatch.
;;;
;;; Exercises the sorted-set-* primitives directly and verifies the
;;; polymorphic conj/disj/contains?/count/first/last/seq dispatch in
;;; (std clojure) handles sorted sets, plus the clojure.set/ algebra
;;; (union / intersection / difference / subset? / superset?).

(import (chezscheme)
        (std sorted-set)
        (except (std clojure) pop))  ;; avoid clash with test helper

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

(printf "--- (std sorted-set) + Clojure dispatch ---~%~%")

;;; ===== sorted-set primitives =====

(test "sorted-set-empty is empty"
  (sorted-set-size sorted-set-empty)
  0)

(test "sorted-set? accepts the empty sorted set"
  (sorted-set? sorted-set-empty)
  #t)

(test "sorted-set? rejects plain list"
  (sorted-set? '(1 2 3))
  #f)

(test "sorted-set? rejects hash-set"
  (sorted-set? (hash-set 1 2 3))
  #f)

(test "sorted-set constructor sorts numeric input"
  (sorted-set->list (sorted-set 3 1 4 1 5 9 2 6))
  '(1 2 3 4 5 6 9))

(test "sorted-set-add inserts in order"
  (sorted-set->list
    (sorted-set-add (sorted-set-add (sorted-set-add sorted-set-empty 2) 1) 3))
  '(1 2 3))

(test "sorted-set-add is idempotent"
  (sorted-set-size
    (sorted-set-add (sorted-set-add sorted-set-empty 'a) 'a))
  1)

(test "sorted-set-remove drops element"
  (sorted-set->list (sorted-set-remove (sorted-set 1 2 3) 2))
  '(1 3))

(test "sorted-set-remove missing is a no-op"
  (sorted-set->list (sorted-set-remove (sorted-set 1 2 3) 99))
  '(1 2 3))

(test "sorted-set-contains? present"
  (sorted-set-contains? (sorted-set 1 2 3) 2)
  #t)

(test "sorted-set-contains? absent"
  (sorted-set-contains? (sorted-set 1 2 3) 99)
  #f)

(test "sorted-set-size"
  (sorted-set-size (sorted-set 'a 'b 'c 'd))
  4)

(test "sorted-set-min"
  (sorted-set-min (sorted-set 7 3 9 1 5))
  1)

(test "sorted-set-max"
  (sorted-set-max (sorted-set 7 3 9 1 5))
  9)

(test "sorted-set-min on empty is #f"
  (sorted-set-min sorted-set-empty)
  #f)

(test "sorted-set-max on empty is #f"
  (sorted-set-max sorted-set-empty)
  #f)

(test "sorted-set-range closed interval"
  (sorted-set-range (sorted-set 1 2 3 4 5 6 7 8 9 10) 3 7)
  '(3 4 5 6 7))

(test "sorted-set-range symbol keys"
  (sorted-set-range (sorted-set 'alpha 'beta 'gamma 'delta 'epsilon) 'beta 'delta)
  ;; Sorted by symbol name: alpha, beta, delta, epsilon, gamma
  ;; range beta..delta → (beta delta)
  '(beta delta))

(test "sorted-set->list is sorted"
  (sorted-set->list (sorted-set "charlie" "alpha" "bravo"))
  '("alpha" "bravo" "charlie"))

(test "sorted-set-fold sum"
  (sorted-set-fold (sorted-set 1 2 3 4 5) + 0)
  15)

(test "sorted-set-fold builds reverse list"
  (sorted-set-fold (sorted-set 1 2 3) cons '())
  '(3 2 1))

;;; ===== sorted-set-by custom comparator =====

(test "sorted-set-by reverse order"
  (sorted-set->list
    (sorted-set-by (lambda (a b) (cond [(> a b) -1] [(< a b) 1] [else 0]))
                   1 2 3 4 5))
  '(5 4 3 2 1))

;;; ===== Clojure polymorphic dispatch =====

(test "count sorted-set"
  (count (sorted-set 1 2 3 4 5))
  5)

(test "empty? sorted-set — empty"
  (empty? sorted-set-empty)
  #t)

(test "empty? sorted-set — non-empty"
  (empty? (sorted-set 1))
  #f)

(test "contains? sorted-set — present"
  (contains? (sorted-set 'x 'y 'z) 'y)
  #t)

(test "contains? sorted-set — absent"
  (contains? (sorted-set 'x 'y 'z) 'w)
  #f)

(test "get sorted-set — present returns element"
  (get (sorted-set 1 2 3) 2)
  2)

(test "get sorted-set — absent returns default"
  (get (sorted-set 1 2 3) 99 'missing)
  'missing)

(test "first sorted-set = min"
  (first (sorted-set 5 3 8 1 4))
  1)

(test "last sorted-set = max"
  (last (sorted-set 5 3 8 1 4))
  8)

(test "seq sorted-set is sorted list"
  (seq (sorted-set 3 1 2))
  '(1 2 3))

(test "seq empty sorted-set is #f"
  (seq sorted-set-empty)
  #f)

(test "conj sorted-set single"
  (sorted-set->list (conj (sorted-set 1 2) 3))
  '(1 2 3))

(test "conj sorted-set multiple preserves sort"
  (sorted-set->list (conj (sorted-set 5) 1 3 9 2))
  '(1 2 3 5 9))

(test "disj sorted-set single"
  (sorted-set->list (disj (sorted-set 1 2 3) 2))
  '(1 3))

(test "disj sorted-set multiple"
  (sorted-set->list (disj (sorted-set 1 2 3 4 5) 2 4))
  '(1 3 5))

;;; ===== clojure.set algebra =====

(test "union sorted-sets — result is sorted-set"
  (sorted-set?
    (union (sorted-set 1 3 5) (sorted-set 2 4 6)))
  #t)

(test "union sorted-sets — content"
  (sorted-set->list
    (union (sorted-set 1 3 5) (sorted-set 2 4 6)))
  '(1 2 3 4 5 6))

(test "union sorted-sets three-way"
  (sorted-set->list
    (union (sorted-set 1) (sorted-set 2 3) (sorted-set 4 5 6)))
  '(1 2 3 4 5 6))

(test "intersection sorted-sets — content"
  (sorted-set->list
    (intersection (sorted-set 1 2 3 4 5) (sorted-set 3 4 5 6 7)))
  '(3 4 5))

(test "intersection sorted-sets — empty overlap"
  (sorted-set->list
    (intersection (sorted-set 1 2 3) (sorted-set 4 5 6)))
  '())

(test "intersection sorted-sets — three-way"
  (sorted-set->list
    (intersection (sorted-set 1 2 3 4) (sorted-set 2 3 4 5) (sorted-set 3 4 5 6)))
  '(3 4))

(test "difference sorted-sets — content"
  (sorted-set->list
    (difference (sorted-set 1 2 3 4 5) (sorted-set 2 4)))
  '(1 3 5))

(test "difference sorted-sets — three-way"
  (sorted-set->list
    (difference (sorted-set 1 2 3 4 5 6) (sorted-set 2) (sorted-set 4 6)))
  '(1 3 5))

(test "subset? sorted-sets — true"
  (subset? (sorted-set 2 3) (sorted-set 1 2 3 4))
  #t)

(test "subset? sorted-sets — false"
  (subset? (sorted-set 2 5) (sorted-set 1 2 3 4))
  #f)

(test "subset? sorted-sets — empty is subset"
  (subset? sorted-set-empty (sorted-set 1 2 3))
  #t)

(test "superset? sorted-sets — true"
  (superset? (sorted-set 1 2 3 4) (sorted-set 2 3))
  #t)

(test "superset? sorted-sets — false"
  (superset? (sorted-set 1 2) (sorted-set 1 2 3))
  #f)

;;; ===== Immutability check =====

(test "sorted-set-add does not mutate original"
  (let ([s (sorted-set 1 2 3)])
    (sorted-set-add s 99)
    (sorted-set->list s))
  '(1 2 3))

(test "conj does not mutate original sorted-set"
  (let ([s (sorted-set 'a 'b 'c)])
    (conj s 'd 'e)
    (sorted-set->list s))
  '(a b c))

;;; ===== Large-ish sanity =====

(test "1000 insertions stay sorted"
  (let loop ([i 999] [s sorted-set-empty])
    (if (< i 0)
        (let ([lst (sorted-set->list s)])
          (and (= (length lst) 1000)
               (= (car lst) 0)
               (= (last lst) 999)))
        (loop (- i 1) (sorted-set-add s i))))
  #t)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
