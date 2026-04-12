(import (jerboa prelude))
(import (std clojure))

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

;; Helper: create a relation (set of maps)
(def (make-rel . rows)
  (fold-left (lambda (s row)
               (conj s (apply hash-map row)))
             (hash-set)
             rows))

;; =========================================================================
;; set-select tests
;; =========================================================================

(test "set-select filters elements"
  (let ([nums (hash-set 1 2 3 4 5 6)])
    (let ([evens (set-select even? nums)])
      (assert-true (contains? evens 2) "has 2")
      (assert-true (contains? evens 4) "has 4")
      (assert-true (contains? evens 6) "has 6")
      (assert-true (not (contains? evens 1)) "no 1")
      (assert-true (not (contains? evens 3)) "no 3"))))

(test "set-select on maps"
  (let ([rel (make-rel '("name" "Alice" "age" 30)
                       '("name" "Bob" "age" 25)
                       '("name" "Carol" "age" 35))])
    (let ([over30 (set-select (lambda (m) (>= (get m "age") 30)) rel)])
      (assert-equal (count over30) 2 "two people >= 30"))))

;; =========================================================================
;; set-project tests
;; =========================================================================

(test "set-project extracts keys"
  (let ([rel (make-rel '("name" "Alice" "age" 30 "city" "NYC")
                       '("name" "Bob" "age" 25 "city" "LA"))])
    (let ([names-only (set-project rel '("name"))])
      (assert-equal (count names-only) 2 "two rows")
      (for-each (lambda (m)
                  (assert-true (contains? m "name") "has name")
                  (assert-true (not (contains? m "age")) "no age"))
                (persistent-set->list names-only)))))

;; =========================================================================
;; set-rename tests
;; =========================================================================

(test "set-rename renames keys"
  (let ([rel (make-rel '("name" "Alice" "age" 30))])
    (let ([renamed (set-rename rel '(("name" . "full_name")))])
      (let ([row (car (persistent-set->list renamed))])
        (assert-true (contains? row "full_name") "has full_name")
        (assert-equal (get row "full_name") "Alice" "value preserved")
        (assert-true (not (contains? row "name")) "no old name")))))

;; =========================================================================
;; set-index tests
;; =========================================================================

(test "set-index groups by keys"
  (let ([rel (make-rel '("dept" "eng" "name" "Alice")
                       '("dept" "eng" "name" "Bob")
                       '("dept" "sales" "name" "Carol"))])
    (let ([idx (set-index rel '("dept"))])
      ;; set-index returns a Chez hashtable with =?/hash equality
      (let ([eng-key (hash-map "dept" "eng")])
        (let ([eng-set (hashtable-ref idx eng-key #f)])
          (assert-true eng-set "has eng group")
          (assert-equal (count eng-set) 2 "two engineers"))))))

;; =========================================================================
;; set-join tests
;; =========================================================================

(test "set-join natural join"
  (let ([employees (make-rel '("name" "Alice" "dept" "eng")
                             '("name" "Bob" "dept" "sales"))]
        [depts (make-rel '("dept" "eng" "building" "A")
                         '("dept" "sales" "building" "B"))])
    (let ([joined (set-join employees depts)])
      (assert-equal (count joined) 2 "two joined rows")
      ;; Each row should have name, dept, AND building
      (for-each (lambda (m)
                  (assert-true (contains? m "name") "has name")
                  (assert-true (contains? m "dept") "has dept")
                  (assert-true (contains? m "building") "has building"))
                (persistent-set->list joined)))))

(test "set-join empty result"
  (let ([r1 (make-rel '("a" 1 "b" 2))]
        [r2 (make-rel '("a" 99 "c" 3))])
    (let ([joined (set-join r1 r2)])
      (assert-equal (count joined) 0 "no matches"))))

;; =========================================================================
;; map-invert tests
;; =========================================================================

(test "map-invert swaps keys and values"
  (let ([m (hash-map "a" 1 "b" 2)])
    (let ([inv (map-invert m)])
      (assert-equal (get inv 1) "a" "1 -> a")
      (assert-equal (get inv 2) "b" "2 -> b"))))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(displayln (str "========================================="))
(displayln (str "Results: " pass-count "/" test-count " passed"))
(displayln (str "========================================="))
(when (< pass-count test-count)
  (exit 1))
