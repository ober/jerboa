#!chezscheme
;;; Tests for (std dataframe) — Tabular data library

(import (chezscheme) (std dataframe))

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

(define-syntax test-approx
  (syntax-rules ()
    [(_ name expr expected eps)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (< (abs (- got expected)) eps)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(printf "--- (std dataframe) tests ---~%")

;;; ---- Creation ----

(define df1 (make-dataframe '(name age score)
               '(("Alice" "Bob" "Carol")
                 (25 30 22)
                 (88 92 76))))

(test "dataframe?" (dataframe? df1) #t)
(test "dataframe? on non-df" (dataframe? '(1 2 3)) #f)
(test "dataframe-ncol" (dataframe-ncol df1) 3)
(test "dataframe-nrow" (dataframe-nrow df1) 3)
(test "dataframe-columns" (dataframe-columns df1) '(name age score))

;;; ---- Access ----

(test "dataframe-ref row 0 name" (dataframe-ref df1 0 'name) "Alice")
(test "dataframe-ref row 1 age"  (dataframe-ref df1 1 'age)  30)
(test "dataframe-ref row 2 score" (dataframe-ref df1 2 'score) 76)

(test "dataframe-column age"
  (vector->list (dataframe-column df1 'age))
  '(25 30 22))

(test "dataframe-row 0"
  (dataframe-row df1 0)
  '((name . "Alice") (age . 25) (score . 88)))

(test "dataframe-row 2"
  (dataframe-row df1 2)
  '((name . "Carol") (age . 22) (score . 76)))

;;; ---- Head / Tail ----

(define df-head (dataframe-head df1 2))
(test "dataframe-head nrow" (dataframe-nrow df-head) 2)
(test "dataframe-head col" (vector->list (dataframe-column df-head 'name)) '("Alice" "Bob"))

(define df-tail (dataframe-tail df1 2))
(test "dataframe-tail nrow" (dataframe-nrow df-tail) 2)
(test "dataframe-tail col" (vector->list (dataframe-column df-tail 'name)) '("Bob" "Carol"))

;;; ---- from-alists / to-alists ----

(define alists
  '(((x . 1) (y . 10))
    ((x . 2) (y . 20))
    ((x . 3) (y . 30))))

(define df-from-a (dataframe-from-alists alists))
(test "from-alists nrow" (dataframe-nrow df-from-a) 3)
(test "from-alists ncol" (dataframe-ncol df-from-a) 2)
(test "from-alists ref"  (dataframe-ref df-from-a 1 'y) 20)

(define back-to-a (dataframe->alists df-from-a))
(test "to-alists" back-to-a alists)

;;; ---- from-vectors / to-vectors ----

(define df-fv (dataframe-from-vectors '(a b) (list (vector 1 2 3) (vector 4 5 6))))
(test "from-vectors nrow" (dataframe-nrow df-fv) 3)
(test "from-vectors ref"  (dataframe-ref df-fv 2 'b) 6)

(define tv (dataframe->vectors df-fv))
(test "to-vectors"
  (map (lambda (p) (cons (car p) (vector->list (cdr p)))) tv)
  '((a 1 2 3) (b 4 5 6)))

;;; ---- Select / Drop ----

(define df-sel (dataframe-select df1 'name 'score))
(test "dataframe-select ncol" (dataframe-ncol df-sel) 2)
(test "dataframe-select columns" (dataframe-columns df-sel) '(name score))
(test "dataframe-select ref" (dataframe-ref df-sel 0 'score) 88)

(define df-drop (dataframe-drop df1 'age))
(test "dataframe-drop ncol" (dataframe-ncol df-drop) 2)
(test "dataframe-drop columns" (dataframe-columns df-drop) '(name score))

;;; ---- Filter ----

(define df-filtered
  (dataframe-filter df1 (lambda (row) (> (cdr (assq 'age row)) 23))))
(test "dataframe-filter nrow" (dataframe-nrow df-filtered) 2)
(test "dataframe-filter first name" (dataframe-ref df-filtered 0 'name) "Alice")

;;; ---- Map ----

(define df-mapped
  (dataframe-map df1
    (lambda (row)
      (map (lambda (pair)
             (if (eq? (car pair) 'score)
               (cons 'score (* (cdr pair) 2))
               pair))
           row))))
(test "dataframe-map score doubled" (dataframe-ref df-mapped 0 'score) 176)

;;; ---- Mutate ----

(define df-mutated
  (dataframe-mutate df1 'grade
    (lambda (row)
      (let ([s (cdr (assq 'score row))])
        (if (>= s 90) 'A 'B)))))
(test "dataframe-mutate new col" (dataframe-ncol df-mutated) 4)
(test "dataframe-mutate value A" (dataframe-ref df-mutated 1 'grade) 'A)
(test "dataframe-mutate value B" (dataframe-ref df-mutated 0 'grade) 'B)

;;; ---- Rename ----

(define df-renamed (dataframe-rename df1 'score 'points))
(test "dataframe-rename columns" (dataframe-columns df-renamed) '(name age points))
(test "dataframe-rename ref" (dataframe-ref df-renamed 0 'points) 88)

;;; ---- Sort ----

(define df-sorted (dataframe-sort df1 'age))
(test "dataframe-sort first" (dataframe-ref df-sorted 0 'name) "Carol")
(test "dataframe-sort last"  (dataframe-ref df-sorted 2 'name) "Bob")

;;; ---- Append ----

(define df2 (make-dataframe '(name age score)
               '(("Dave" "Eve")
                 (28 35)
                 (81 95))))
(define df-appended (dataframe-append df1 df2))
(test "dataframe-append nrow" (dataframe-nrow df-appended) 5)
(test "dataframe-append last" (dataframe-ref df-appended 4 'name) "Eve")

;;; ---- Join ----

(define df-dept (make-dataframe '(name dept)
                  '(("Alice" "Bob" "Carol")
                    ("Eng" "HR" "Eng"))))

(define df-joined (dataframe-join df1 df-dept 'name))
(test "dataframe-join ncol" (dataframe-ncol df-joined) 4)
(test "dataframe-join has dept col" (member 'dept (dataframe-columns df-joined)) '(dept))

;;; ---- Stats ----

(define v (vector 1 2 3 4 5))
(test "col-sum"    (col-sum v)    15)
(test "col-mean"   (col-mean v)   3)
(test "col-min"    (col-min v)    1)
(test "col-max"    (col-max v)    5)
(test "col-median" (col-median v) 3)
(test-approx "col-std" (col-std v) (sqrt 2.5) 0.0001)

;;; ---- Group-by / Summarize / Count ----

(define df-scores
  (make-dataframe '(dept score)
    '(("Eng" "HR" "Eng" "HR" "Eng")
      (90 70 85 65 95))))

(define groups (dataframe-group-by df-scores 'dept))
(test "group-by type" (hashtable? groups) #t)
(test "group-by count" (hashtable-size groups) 2)

(define eng-df (hashtable-ref groups '("Eng") #f))
(test "group-by Eng nrow" (dataframe-nrow eng-df) 3)

(define count-df (dataframe-count groups))
(test "dataframe-count nrow" (dataframe-nrow count-df) 2)

;;; ---- CSV I/O ----

(define csv-str (dataframe->csv-string df-from-a))
(test "csv header"
  (and (>= (string-length csv-str) 3)
       (string=? (substring csv-str 0 3) "x,y"))
  #t)

(define df-csv (dataframe-from-csv-string csv-str))
(test "csv roundtrip nrow" (dataframe-nrow df-csv) 3)
(test "csv roundtrip ref"  (dataframe-ref df-csv 0 'x) 1)
(test "csv roundtrip ref2" (dataframe-ref df-csv 2 'y) 30)

;;; ---- Empty dataframe ----

(define df-empty (make-dataframe '() '()))
(test "empty ncol" (dataframe-ncol df-empty) 0)
(test "empty nrow" (dataframe-nrow df-empty) 0)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
