#!chezscheme
;;; tests/test-relation.ss -- Tests for (std misc relation)

(import (chezscheme) (std misc relation))

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

(printf "--- (std misc relation) tests ---~%~%")

;; ---- Sample data ----
(define people
  (make-relation '(name age city)
    '(("Alice" 30 "NYC")
      ("Bob"   25 "LA")
      ("Carol" 35 "NYC")
      ("Dave"  25 "LA"))))

;; ---- 1. Basic accessors ----
(test "relation?" (relation? people) #t)
(test "relation?-neg" (relation? '()) #f)
(test "columns" (relation-columns people) '(name age city))
(test "count" (relation-count people) 4)
(test "rows-count" (length (relation-rows people)) 4)

;; ---- 2. relation-ref ----
(let ([row (car (relation-rows people))])
  (test "ref-name" (relation-ref row 'name) "Alice")
  (test "ref-age"  (relation-ref row 'age) 30)
  (test "ref-city" (relation-ref row 'city) "NYC"))

;; ---- 3. make-relation from alists ----
(let ([r (make-relation '(x y)
           (list '((x . 1) (y . 2))
                 '((x . 3) (y . 4))))])
  (test "from-alist count" (relation-count r) 2)
  (test "from-alist ref" (relation-ref (car (relation-rows r)) 'x) 1))

;; ---- 4. relation-select ----
(let ([nyc (relation-select people
             (lambda (row) (equal? (relation-ref row 'city) "NYC")))])
  (test "select count" (relation-count nyc) 2)
  (test "select cols" (relation-columns nyc) '(name age city))
  (test "select first"
    (relation-ref (car (relation-rows nyc)) 'name) "Alice"))

(let ([empty (relation-select people (lambda (row) #f))])
  (test "select-none" (relation-count empty) 0))

;; ---- 5. relation-project ----
(let ([names-ages (relation-project people '(name age))])
  (test "project cols" (relation-columns names-ages) '(name age))
  (test "project count" (relation-count names-ages) 4)
  (test "project row"
    (relation-ref (car (relation-rows names-ages)) 'name) "Alice")
  ;; Projected rows should not have city
  (test "project no-city"
    (assq 'city (car (relation-rows names-ages))) #f))

;; ---- 6. relation-extend ----
(let ([extended (relation-extend people 'senior
                  (lambda (row) (>= (relation-ref row 'age) 30)))])
  (test "extend cols" (relation-columns extended) '(name age city senior))
  (test "extend count" (relation-count extended) 4)
  (test "extend val-alice"
    (relation-ref (car (relation-rows extended)) 'senior) #t)
  (test "extend val-bob"
    (relation-ref (cadr (relation-rows extended)) 'senior) #f))

;; ---- 7. relation-sort ----
(let ([by-age (relation-sort people 'age <)])
  (test "sort first" (relation-ref (car (relation-rows by-age)) 'age) 25)
  (test "sort last"
    (relation-ref (list-ref (relation-rows by-age) 3) 'age) 35))

(let ([by-name (relation-sort people 'name string<?)])
  (test "sort-by-name first"
    (relation-ref (car (relation-rows by-name)) 'name) "Alice")
  (test "sort-by-name last"
    (relation-ref (list-ref (relation-rows by-name) 3) 'name) "Dave"))

;; ---- 8. relation-group-by ----
(let ([groups (relation-group-by people 'city)])
  (test "group-by keys" (length groups) 2)
  (let ([nyc-group (cdr (assoc "NYC" groups))]
        [la-group  (cdr (assoc "LA" groups))])
    (test "group-nyc count" (relation-count nyc-group) 2)
    (test "group-la count"  (relation-count la-group) 2)
    (test "group-nyc cols"  (relation-columns nyc-group) '(name age city))))

;; ---- 9. relation-join ----
(let* ([depts (make-relation '(name dept)
                '(("Alice" "Eng")
                  ("Bob"   "Sales")
                  ("Carol" "Eng")))]
       [joined (relation-join people depts 'name)])
  (test "join count" (relation-count joined) 3)  ;; Dave has no dept match
  (test "join cols" (relation-columns joined) '(name age city dept))
  (let ([first-row (car (relation-rows
                          (relation-sort joined 'name string<?)))])
    (test "join alice dept" (relation-ref first-row 'dept) "Eng")
    (test "join alice age"  (relation-ref first-row 'age) 30)))

;; ---- 10. relation->alist-list / alist-list->relation ----
(let* ([alists (relation->alist-list people)]
       [roundtrip (alist-list->relation alists)])
  (test "alist-list count" (length alists) 4)
  (test "alist-list first" (cdr (assq 'name (car alists))) "Alice")
  (test "roundtrip count" (relation-count roundtrip) 4)
  (test "roundtrip cols" (relation-columns roundtrip) '(name age city)))

;; Empty relation roundtrip
(let ([empty (alist-list->relation '())])
  (test "alist-empty" (relation-count empty) 0)
  (test "alist-empty-cols" (relation-columns empty) '()))

;; ---- 11. relation-aggregate ----
(test "aggregate sum-age" (relation-aggregate people 'age + 0) 115)
(test "aggregate max-age"
  (relation-aggregate people 'age
    (lambda (acc v) (if (> v acc) v acc)) 0)
  35)
(test "aggregate min-age"
  (relation-aggregate people 'age
    (lambda (acc v) (if (< v acc) v acc)) 999)
  25)
(test "aggregate count-rows"
  (relation-aggregate people 'age (lambda (acc v) (+ acc 1)) 0)
  4)

;; ---- 12. Composition: select + project + sort ----
(let* ([step1 (relation-select people
                (lambda (row) (>= (relation-ref row 'age) 30)))]
       [step2 (relation-project step1 '(name age))]
       [step3 (relation-sort step2 'age >)])
  (test "compose count" (relation-count step3) 2)
  (test "compose first-name"
    (relation-ref (car (relation-rows step3)) 'name) "Carol")
  (test "compose second-name"
    (relation-ref (cadr (relation-rows step3)) 'name) "Alice"))

;; ---- 13. Edge: single-row relation ----
(let ([r (make-relation '(x) '((42)))])
  (test "single-row count" (relation-count r) 1)
  (test "single-row ref" (relation-ref (car (relation-rows r)) 'x) 42))

;; ---- 14. Edge: empty relation ----
(let ([r (make-relation '(a b) '())])
  (test "empty count" (relation-count r) 0)
  (test "empty cols" (relation-columns r) '(a b))
  (test "empty select" (relation-count (relation-select r (lambda (row) #t))) 0)
  (test "empty project" (relation-count (relation-project r '(a))) 0)
  (test "empty aggregate" (relation-aggregate r 'a + 0) 0))

;; ---- 15. group-by + aggregate ----
(let ([groups (relation-group-by people 'city)])
  (let* ([nyc (cdr (assoc "NYC" groups))]
         [la  (cdr (assoc "LA" groups))])
    (test "group+agg nyc-sum" (relation-aggregate nyc 'age + 0) 65)
    (test "group+agg la-sum"  (relation-aggregate la 'age + 0) 50)))

;; ---- 16. Join with duplicates ----
(let* ([orders (make-relation '(customer item)
                 '(("Alice" "Book")
                   ("Alice" "Pen")
                   ("Bob"   "Notebook")))]
       [info (make-relation '(customer city)
                '(("Alice" "NYC")
                  ("Bob"   "LA")))]
       [joined (relation-join orders info 'customer)])
  (test "join-dup count" (relation-count joined) 3)
  (let ([alice-rows (relation-select joined
                      (lambda (row) (equal? (relation-ref row 'customer) "Alice")))])
    (test "join-dup alice count" (relation-count alice-rows) 2)))

(printf "~%~a tests, ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
