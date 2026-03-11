#!chezscheme
;;; Tests for Phase 11 Step 40: Data Tables

(import (chezscheme)
        (std table))

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

(printf "--- Phase 11 Step 40: Data Tables ---~%")

;; Create a table
(let ([t (make-table '(name age country score))])
  (table-add-row! t '((name . "Alice")   (age . 30) (country . "US") (score . 95)))
  (table-add-row! t '((name . "Bob")     (age . 25) (country . "UK") (score . 87)))
  (table-add-row! t '((name . "Charlie") (age . 35) (country . "US") (score . 92)))
  (table-add-row! t '((name . "Diana")   (age . 28) (country . "UK") (score . 91)))
  (table-add-row! t '((name . "Eve")     (age . 22) (country . "US") (score . 78)))

  (test "row-count"
    (table-row-count t)
    5)

  (test "column-names"
    (table-column-names t)
    '(name age country score))

  (test "table-ref"
    (table-ref t 0 'name)
    "Alice")

  (test "table-ref age"
    (table-ref t 1 'age)
    25)

  (test "table-column scores"
    (table-column t 'score)
    '(95 87 92 91 78))

  ;; table-row
  (let ([row (table-row t 0)])
    (test "table-row name"
      (cdr (assoc 'name row))
      "Alice")
    (test "table-row age"
      (cdr (assoc 'age row))
      30))

  ;; table-select
  (let ([t2 (table-select t '(name score))])
    (test "table-select columns"
      (table-column-names t2)
      '(name score))
    (test "table-select row-count"
      (table-row-count t2)
      5)
    (test "table-select values"
      (table-ref t2 0 'name)
      "Alice"))

  ;; table-where
  (let ([t3 (table-where t (lambda (row) (> (cdr (assoc 'age row)) 27)))])
    (test "table-where row-count"
      (table-row-count t3)
      3)
    (test "table-where first name"
      (table-ref t3 0 'name)
      "Alice"))

  ;; table-sort-by
  (let ([t4 (table-sort-by t 'age)])
    (test "table-sort-by ascending"
      (table-column t4 'age)
      '(22 25 28 30 35)))

  (let ([t5 (table-sort-by t 'score 'descending: #t)])
    (test "table-sort-by descending"
      (list-ref (table-column t5 'score) 0)
      95))

  ;; table-take / table-drop
  (let ([t6 (table-take t 3)])
    (test "table-take"
      (table-row-count t6)
      3))

  (let ([t7 (table-drop t 2)])
    (test "table-drop"
      (table-row-count t7)
      3))

  ;; table-group-by + aggregation
  (let* ([groups (table-group-by t 'country)]
         [result (table-aggregate groups
                   'country agg-count 'country
                   'avg-score agg-mean 'score)])
    (test "table-aggregate count > 0"
      (> (table-row-count result) 0)
      #t))

  ;; table-from-rows
  (let ([t8 (table-from-rows '(x y)
                              '((1 2) (3 4) (5 6)))])
    (test "table-from-rows count"
      (table-row-count t8)
      3)
    (test "table-from-rows values"
      (table-column t8 'x)
      '(1 3 5)))

  ;; aggregation functions
  (test "agg-count"
    (agg-count '(1 2 3 4 5))
    5)

  (test "agg-sum"
    (agg-sum '(1 2 3 4 5))
    15)

  (test "agg-mean"
    (agg-mean '(1 2 3 4 5))
    3)

  (test "agg-min"
    (agg-min '(3 1 4 1 5))
    1)

  (test "agg-max"
    (agg-max '(3 1 4 1 5))
    5)

  ;; table-join
  (let* ([orders (table-from-rows
                   '(order-id name amount)
                   '((1 "Alice" 100) (2 "Bob" 200) (3 "Alice" 150)))]
         [users  (table-from-rows
                   '(name email)
                   '(("Alice" "alice@example.com") ("Bob" "bob@example.com")))]
         [joined (table-join orders users 'name)])
    (test "table-join row-count"
      (table-row-count joined)
      3)
    (test "table-join has email"
      (member 'email (table-column-names joined))
      (list 'email)))

  ;; table->list
  (let ([rows (table->list (table-take t 2))])
    (test "table->list length"
      (length rows)
      2)
    (test "table->list first row has name"
      (and (assoc 'name (car rows)) #t)
      #t)))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
