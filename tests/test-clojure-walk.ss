#!chezscheme
;;; Tests for (std clojure walk) — clojure.walk parity.

(import (jerboa prelude)
        (std clojure walk)
        (only (std pmap)
              persistent-map persistent-map-ref persistent-map->list)
        (only (std pvec)
              persistent-vector persistent-vector->list)
        (only (std pset)
              persistent-set persistent-set->list))

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

(printf "--- std/clojure walk ---~%~%")

;;; ---- postwalk on lists -----------------------------------------

(test "postwalk doubles every number"
  (postwalk (lambda (x) (if (number? x) (* 2 x) x))
            '(1 (2 (3 :tag)) 4))
  '(2 (4 (6 :tag)) 8))

(test "postwalk preserves non-numbers"
  (postwalk (lambda (x) x) '(a (b (c (d e)))))
  '(a (b (c (d e)))))

;;; ---- prewalk on lists ------------------------------------------

(test "prewalk replaces top-level then recurses"
  (prewalk (lambda (x)
             (cond
               [(and (pair? x) (eq? (car x) 'replace-me)) '(1 2 3)]
               [else x]))
           '(a (replace-me x y) b))
  '(a (1 2 3) b))

(test "prewalk applies F before recursion"
  (prewalk (lambda (x) (if (number? x) (+ x 100) x))
           '(1 (2 3)))
  '(101 (102 103)))

;;; ---- vectors ---------------------------------------------------

(test "postwalk through vector"
  (postwalk (lambda (x) (if (number? x) (* x x) x))
            (vector 1 2 3))
  (vector 1 4 9))

(test "postwalk through nested vector + list"
  (postwalk (lambda (x) (if (number? x) (- x) x))
            (list 1 (vector 2 3) 4))
  (list -1 (vector -2 -3) -4))

;;; ---- persistent-vector -----------------------------------------

(test "postwalk through persistent-vector"
  (persistent-vector->list
    (postwalk (lambda (x) (if (number? x) (* 10 x) x))
              (persistent-vector 1 2 3)))
  '(10 20 30))

;;; ---- persistent-set --------------------------------------------

(test "postwalk through persistent-set"
  (list-sort < (persistent-set->list
                 (postwalk (lambda (x) (if (number? x) (+ 1 x) x))
                           (persistent-set 1 2 3))))
  '(2 3 4))

;;; ---- persistent-map --------------------------------------------

(test "postwalk doubles map values"
  (let* ([m (persistent-map 'a 1 'b 2)]
         [m* (postwalk (lambda (x) (if (number? x) (* 2 x) x)) m)])
    (list (persistent-map-ref m* 'a)
          (persistent-map-ref m* 'b)))
  '(2 4))

;;; ---- hash-table ------------------------------------------------

(test "postwalk doubles hash-table values"
  (let* ([h (make-hash-table)])
    (hash-put! h "a" 1)
    (hash-put! h "b" 2)
    (let ([h* (postwalk (lambda (x) (if (number? x) (* 3 x) x)) h)])
      (list-sort < (list (hash-ref h* "a") (hash-ref h* "b")))))
  '(3 6))

;;; ---- keywordize-keys -------------------------------------------

(test "keywordize-keys on persistent-map"
  (let* ([m (persistent-map "a" 1 "b" 2)]
         [m* (keywordize-keys m)])
    (list (persistent-map-ref m* (string->keyword "a"))
          (persistent-map-ref m* (string->keyword "b"))))
  '(1 2))

(test "keywordize-keys on hash-table"
  (let ([h (make-hash-table)])
    (hash-put! h "x" 10)
    (hash-put! h "y" 20)
    (let ([h* (keywordize-keys h)])
      (list (hash-ref h* (string->keyword "x"))
            (hash-ref h* (string->keyword "y")))))
  '(10 20))

(test "keywordize-keys preserves non-string keys"
  (let* ([m (persistent-map 'sym 1 "str" 2)]
         [m* (keywordize-keys m)])
    (list (persistent-map-ref m* 'sym)
          (persistent-map-ref m* (string->keyword "str"))))
  '(1 2))

;;; ---- stringify-keys --------------------------------------------

(test "stringify-keys on persistent-map"
  (let* ([m (persistent-map (string->keyword "a") 1
                            (string->keyword "b") 2)]
         [m* (stringify-keys m)])
    (list (persistent-map-ref m* "a")
          (persistent-map-ref m* "b")))
  '(1 2))

(test "stringify-keys on hash-table"
  (let ([h (make-hash-table)])
    (hash-put! h (string->keyword "a") 100)
    (hash-put! h (string->keyword "b") 200)
    (let ([h* (stringify-keys h)])
      (list (hash-ref h* "a") (hash-ref h* "b"))))
  '(100 200))

;;; ---- prewalk-replace / postwalk-replace ------------------------

(test "postwalk-replace with alist"
  (postwalk-replace '((a . 1) (b . 2)) '(a (b a) c))
  '(1 (2 1) c))

(test "prewalk-replace with alist"
  (prewalk-replace '((a . X)) '(a (a b)))
  '(X (X b)))

(test "postwalk-replace leaves non-keys alone"
  (postwalk-replace '((a . 1)) '(b c (d a)))
  '(b c (d 1)))

;;; ---- improper lists --------------------------------------------

(test "postwalk preserves improper list tail"
  (postwalk (lambda (x) (if (number? x) (* 10 x) x))
            '(1 2 . 3))
  '(10 20 . 30))

;;; ---- leaves stay leaves ----------------------------------------

(test "strings are leaves"
  (postwalk (lambda (x) (if (string? x) (string-upcase x) x))
            '("a" ("b" "c")))
  '("A" ("B" "C")))

(test "numbers are leaves"
  (postwalk (lambda (x) x) '(1 2 3))
  '(1 2 3))

;;; ---- Summary ---------------------------------------------------
(printf "~%std/clojure walk: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
