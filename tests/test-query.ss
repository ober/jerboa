#!chezscheme
;;; Tests for (std query) -- Query DSL over collections

(import (chezscheme)
        (std query))

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

(printf "--- Phase 3d: Query DSL ---~%~%")

;;; ---- Datasource ----

(test "datasource?"
  (datasource? (make-datasource '(1 2 3)))
  #t)

(test "datasource-data"
  (datasource-data (make-datasource '(a b c)))
  '(a b c))

(test "datasource? negative"
  (datasource? '(1 2 3))
  #f)

;;; ---- from ----

(test "from list"
  (from '(1 2 3))
  '(1 2 3))

(test "from vector"
  (from (vector 1 2 3))
  '(1 2 3))

(test "from datasource"
  (from (make-datasource '(10 20 30)))
  '(10 20 30))

;;; ---- where / filter ----

(test "where filter evens"
  (where even? '(1 2 3 4 5 6))
  '(2 4 6))

(test "where no match"
  (where (lambda (x) (> x 100)) '(1 2 3))
  '())

;;; ---- limit / offset ----

(test "limit 3"
  (limit 3 '(1 2 3 4 5))
  '(1 2 3))

(test "limit larger than list"
  (limit 10 '(1 2 3))
  '(1 2 3))

(test "offset 2"
  (offset 2 '(1 2 3 4 5))
  '(3 4 5))

(test "offset past end"
  (offset 10 '(1 2 3))
  '())

;;; ---- predicates ----

(test "q:= match"
  ((q:= 'name "Alice") (list (cons 'name "Alice") (cons 'age 30)))
  #t)

(test "q:= no match"
  ((q:= 'name "Bob") (list (cons 'name "Alice") (cons 'age 30)))
  #f)

(test "q:> match"
  ((q:> 'age 25) (list (cons 'name "Alice") (cons 'age 30)))
  #t)

(test "q:< match"
  ((q:< 'age 40) (list (cons 'name "Alice") (cons 'age 30)))
  #t)

(test "q:<= equal"
  ((q:<= 'age 30) (list (cons 'name "Alice") (cons 'age 30)))
  #t)

(test "q:>= equal"
  ((q:>= 'age 30) (list (cons 'name "Alice") (cons 'age 30)))
  #t)

(test "q:in match"
  (if ((q:in 'role '("admin" "user")) (list (cons 'role "admin")))
    #t #f)
  #t)

(test "q:between"
  ((q:between 'score 50 100) (list (cons 'score 75)))
  #t)

(test "q:between out of range"
  ((q:between 'score 50 100) (list (cons 'score 25)))
  #f)

(test "q:and"
  (let ([pred (q:and (q:> 'age 20) (q:< 'age 40))])
    (pred (list (cons 'age 30))))
  #t)

(test "q:or"
  (let ([pred (q:or (q:= 'role "admin") (q:= 'role "root"))])
    (pred (list (cons 'role "admin"))))
  #t)

(test "q:not"
  (let ([pred (q:not (q:= 'name "Alice"))])
    (pred (list (cons 'name "Bob"))))
  #t)

;;; ---- hashtable access ----

(test "q:= hashtable"
  (let ([rec (let ([h (make-hashtable equal-hash equal?)])
               (hashtable-set! h 'name "Alice")
               (hashtable-set! h 'age 30)
               h)])
    ((q:= 'name "Alice") rec))
  #t)

;;; ---- select ----

(test "select identity"
  (select #t '(1 2 3))
  '(1 2 3))

(test "select with procedure"
  (select (lambda (x) (* x 2)) '(1 2 3))
  '(2 4 6))

;;; ---- order-by ----

(test "order-by asc"
  (order-by 'score 'asc
    (list (list (cons 'score 30))
          (list (cons 'score 10))
          (list (cons 'score 20))))
  (list (list (cons 'score 10))
        (list (cons 'score 20))
        (list (cons 'score 30))))

(test "order-by desc"
  (order-by 'score 'desc
    (list (list (cons 'score 30))
          (list (cons 'score 10))
          (list (cons 'score 20))))
  (list (list (cons 'score 30))
        (list (cons 'score 20))
        (list (cons 'score 10))))

;;; ---- group-by ----

(test "group-by result type"
  (let* ([data (list (list (cons 'dept "eng") (cons 'name "Alice"))
                     (list (cons 'dept "hr")  (cons 'name "Bob"))
                     (list (cons 'dept "eng") (cons 'name "Carol")))]
         [groups (group-by 'dept data)])
    (and (list? groups)
         (= (length groups) 2)))
  #t)

;;; ---- combined pipeline ----

(test "from+where+limit pipeline"
  (limit 2 (where even? (from '(1 2 3 4 5 6))))
  '(2 4))

(test "from+where+select pipeline"
  (select (lambda (x) (* x x))
          (where even? (from '(1 2 3 4))))
  '(4 16))

(printf "~%Query tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
