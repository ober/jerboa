#!chezscheme
;;; Tests for (std clojure data) — clojure.data/diff parity.

(import (jerboa prelude)
        (std clojure data)
        (only (std pmap)
              persistent-map persistent-map-ref persistent-map-size)
        (only (std pvec)
              persistent-vector persistent-vector-length)
        (only (std pset)
              persistent-set persistent-set-size))

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

(printf "--- std/clojure data ---~%~%")

;;; Scalar equality / inequality.
(test "scalar equal"
  (diff 1 1)
  (list #f #f 1))

(test "scalar unequal"
  (diff 1 2)
  (list 1 2 #f))

(test "different types fall through"
  (diff 1 "a")
  (list 1 "a" #f))

;;; List diff.
(test "list equal"
  (diff '(1 2 3) '(1 2 3))
  (list #f #f '(1 2 3)))

(test "list trailing extra in b"
  (diff '(1 2) '(1 2 3))
  (list #f '(#f #f 3) '(1 2)))

(test "list elementwise difference"
  (diff '(1 2 3) '(1 2 4))
  (list '(#f #f 3) '(#f #f 4) '(1 2)))

(test "list trailing extra in a"
  (diff '(1 2 3) '(1 2))
  (list '(#f #f 3) #f '(1 2)))

;;; Vector diff.
(test "vector equal"
  (diff (vector 1 2 3) (vector 1 2 3))
  (list #f #f (vector 1 2 3)))

(test "vector elementwise difference"
  (diff (vector 1 2 3) (vector 1 2 4))
  (list (vector #f #f 3) (vector #f #f 4) (vector 1 2)))

;;; Persistent-map diff.
(let* ([a (persistent-map "a" 1 "b" 2)]
       [b (persistent-map "b" 2 "c" 3)]
       [d (diff a b)])
  (test "pmap only-in-a contains :a"
    (and (car d) (persistent-map-ref (car d) "a"))
    1)
  (test "pmap only-in-b contains :c"
    (and (cadr d) (persistent-map-ref (cadr d) "c"))
    3)
  (test "pmap in-both contains :b"
    (and (caddr d) (persistent-map-ref (caddr d) "b"))
    2))

;;; Persistent-set diff.
(let* ([a (persistent-set 1 2 3)]
       [b (persistent-set 2 3 4)]
       [d (diff a b)])
  (test "pset only-in-a size=1"
    (persistent-set-size (car d))
    1)
  (test "pset only-in-b size=1"
    (persistent-set-size (cadr d))
    1)
  (test "pset in-both size=2"
    (persistent-set-size (caddr d))
    2))

;;; Persistent-vector diff.
(test "pvec equal"
  (let ([d (diff (persistent-vector 1 2 3) (persistent-vector 1 2 3))])
    (and (not (car d))
         (not (cadr d))
         (= 3 (persistent-vector-length (caddr d)))))
  #t)

(printf "~%passed: ~a / failed: ~a~%" pass fail)
(unless (zero? fail) (exit 1))
