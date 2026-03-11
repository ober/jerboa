#!chezscheme
;;; Tests for (std pvec) -- Persistent Vectors

(import (chezscheme)
        (std pvec))

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

(printf "--- Phase 2a: Persistent Vectors ---~%~%")

;;; ======== Empty vector ========

(test "empty length"
  (persistent-vector-length pvec-empty)
  0)

(test "empty type"
  (persistent-vector? pvec-empty)
  #t)

(test "non-pvec"
  (persistent-vector? '(1 2 3))
  #f)

;;; ======== Construction ========

(test "single element"
  (let ([v (persistent-vector 42)])
    (persistent-vector-length v))
  1)

(test "three elements"
  (let ([v (persistent-vector 1 2 3)])
    (persistent-vector-length v))
  3)

(test "from list"
  (persistent-vector-length (list->persistent-vector '(a b c d e)))
  5)

;;; ======== Ref ========

(test "ref 0"
  (persistent-vector-ref (persistent-vector 10 20 30) 0)
  10)

(test "ref 1"
  (persistent-vector-ref (persistent-vector 10 20 30) 1)
  20)

(test "ref last"
  (persistent-vector-ref (persistent-vector 10 20 30) 2)
  30)

;;; ======== Set (returns new vector) ========

(test "set returns new"
  (let* ([v1 (persistent-vector 1 2 3)]
         [v2 (persistent-vector-set v1 1 99)])
    (list (persistent-vector-ref v1 1)
          (persistent-vector-ref v2 1)))
  '(2 99))

(test "set preserves other elements"
  (let* ([v1 (persistent-vector 1 2 3)]
         [v2 (persistent-vector-set v1 1 99)])
    (list (persistent-vector-ref v2 0)
          (persistent-vector-ref v2 1)
          (persistent-vector-ref v2 2)))
  '(1 99 3))

;;; ======== Append ========

(test "append grows"
  (let loop ([v pvec-empty] [i 0])
    (if (= i 100)
      (persistent-vector-length v)
      (loop (persistent-vector-append v i) (+ i 1))))
  100)

(test "append values correct (0..99)"
  (let ([v (list->persistent-vector (iota 100))])
    (let loop ([i 0] [ok #t])
      (if (= i 100)
        ok
        (loop (+ i 1)
              (and ok (= (persistent-vector-ref v i) i))))))
  #t)

;;; ======== Large vector (beyond single tail) ========

(test "32 elements"
  (let ([v (list->persistent-vector (iota 32))])
    (list (persistent-vector-length v)
          (persistent-vector-ref v 0)
          (persistent-vector-ref v 31)))
  '(32 0 31))

(test "33 elements (triggers first trie push)"
  (let ([v (list->persistent-vector (iota 33))])
    (list (persistent-vector-length v)
          (persistent-vector-ref v 0)
          (persistent-vector-ref v 32)))
  '(33 0 32))

(test "1000 elements"
  (let ([v (list->persistent-vector (iota 1000))])
    (and (= (persistent-vector-length v) 1000)
         (= (persistent-vector-ref v 500) 500)
         (= (persistent-vector-ref v 999) 999)))
  #t)

(test "1024 elements (multiple trie levels)"
  (let ([v (list->persistent-vector (iota 1024))])
    (and (= (persistent-vector-length v) 1024)
         (= (persistent-vector-ref v 0) 0)
         (= (persistent-vector-ref v 1023) 1023)))
  #t)

(test "set in large vector"
  (let* ([v1 (list->persistent-vector (iota 1000))]
         [v2 (persistent-vector-set v1 500 9999)])
    (list (persistent-vector-ref v1 500)
          (persistent-vector-ref v2 500)
          (persistent-vector-ref v2 499)
          (persistent-vector-ref v2 501)))
  '(500 9999 499 501))

;;; ======== Conversion ========

(test "to-list"
  (persistent-vector->list (persistent-vector 1 2 3 4 5))
  '(1 2 3 4 5))

(test "round-trip via list"
  (let ([lst (iota 50)])
    (equal? lst (persistent-vector->list (list->persistent-vector lst))))
  #t)

;;; ======== Derived operations ========

(test "map"
  (persistent-vector->list
    (persistent-vector-map (lambda (x) (* x x))
                           (persistent-vector 1 2 3 4 5)))
  '(1 4 9 16 25))

(test "fold sum"
  (persistent-vector-fold + 0 (persistent-vector 1 2 3 4 5))
  15)

(test "filter"
  (persistent-vector->list
    (persistent-vector-filter even? (persistent-vector 1 2 3 4 5 6)))
  '(2 4 6))

(test "concat"
  (persistent-vector->list
    (persistent-vector-concat
      (persistent-vector 1 2 3)
      (persistent-vector 4 5 6)))
  '(1 2 3 4 5 6))

(test "slice"
  (persistent-vector->list
    (persistent-vector-slice (persistent-vector 0 1 2 3 4 5 6 7 8 9) 3 7))
  '(3 4 5 6))

;;; ======== Transients ========

(test "transient and persistent!"
  (let* ([v1 (persistent-vector 1 2 3)]
         [t  (transient v1)])
    (transient-set! t 1 99)
    (transient-append! t 4)
    (let ([v2 (persistent! t)])
      (list (persistent-vector->list v1)    ; original unchanged
            (persistent-vector->list v2)))) ; new persistent
  '((1 2 3) (1 99 3 4)))

(test "transient batch"
  (let ([t (transient pvec-empty)])
    (do ([i 0 (+ i 1)])
        ((= i 100))
      (transient-append! t i))
    (persistent-vector->list (persistent! t)))
  (iota 100))

(test "transient ref"
  (let* ([v (persistent-vector 10 20 30)]
         [t (transient v)])
    (transient-ref t 1))
  20)

;;; ======== Error handling ========

(test "out-of-bounds ref"
  (guard (exn [(message-condition? exn) 'error])
    (persistent-vector-ref (persistent-vector 1 2 3) 5))
  'error)

(test "out-of-bounds set"
  (guard (exn [(message-condition? exn) 'error])
    (persistent-vector-set (persistent-vector 1 2 3) -1 0))
  'error)

;;; Summary

(printf "~%Persistent Vectors: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
