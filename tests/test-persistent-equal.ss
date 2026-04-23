#!chezscheme
;;; Tests for Chez equal? / equal-hash integration on persistent
;;; collections (pmap, pvec, pset). Phase 25 of Round 4.
;;;
;;; Contract:
;;;   - (equal? pm1 pm2) holds when pm1 and pm2 have the same entries,
;;;     independent of insertion order.
;;;   - (equal-hash pm) is the same for equal maps.
;;;   - pmap/pvec/pset can be keys in an equal-hashtable.

(import (chezscheme) (std pmap) (std pvec) (std pset))

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

(printf "--- Round 4 Phase 25: equal? / equal-hash integration ---~%~%")

;;; ========== pmap ==========

(test "pm equal same order"
  (equal? (make-persistent-map 'a 1 'b 2)
          (make-persistent-map 'a 1 'b 2))
  #t)

(test "pm equal reversed order"
  (equal? (make-persistent-map 'a 1 'b 2)
          (make-persistent-map 'b 2 'a 1))
  #t)

(test "pm not equal different values"
  (equal? (make-persistent-map 'a 1)
          (make-persistent-map 'a 2))
  #f)

(test "pm not equal different sizes"
  (equal? (make-persistent-map 'a 1)
          (make-persistent-map 'a 1 'b 2))
  #f)

(test "pm hash equal for equal maps"
  (= (equal-hash (make-persistent-map 'a 1 'b 2))
     (equal-hash (make-persistent-map 'b 2 'a 1)))
  #t)

(test "pm nested equal"
  (equal?
    (make-persistent-map 'outer (make-persistent-map 'x 1))
    (make-persistent-map 'outer (make-persistent-map 'x 1)))
  #t)

(test "pm as equal-hashtable key"
  (let ([ht (make-hashtable equal-hash equal?)]
        [k1 (make-persistent-map 'a 1 'b 2)]
        [k2 (make-persistent-map 'b 2 'a 1)])
    (hashtable-set! ht k1 "v")
    (hashtable-ref ht k2 #f))
  "v")

;;; ========== pvec ==========

(test "pv equal same elements"
  (equal? (persistent-vector 1 2 3)
          (persistent-vector 1 2 3))
  #t)

(test "pv not equal different elements"
  (equal? (persistent-vector 1 2 3)
          (persistent-vector 1 2 4))
  #f)

(test "pv not equal reversed"
  (equal? (persistent-vector 1 2 3)
          (persistent-vector 3 2 1))
  #f)

(test "pv not equal different lengths"
  (equal? (persistent-vector 1 2 3)
          (persistent-vector 1 2 3 4))
  #f)

(test "pv hash equal for equal vectors"
  (= (equal-hash (persistent-vector 'a 'b 'c))
     (equal-hash (persistent-vector 'a 'b 'c)))
  #t)

(test "pv large equal"
  (let* ([lst (iota 100)]
         [v1 (list->persistent-vector lst)]
         [v2 (list->persistent-vector lst)])
    (equal? v1 v2))
  #t)

(test "pv nested pmap equal"
  (equal?
    (persistent-vector (make-persistent-map 'k 1))
    (persistent-vector (make-persistent-map 'k 1)))
  #t)

(test "pv as equal-hashtable key"
  (let ([ht (make-hashtable equal-hash equal?)]
        [k1 (persistent-vector 1 2 3)]
        [k2 (persistent-vector 1 2 3)])
    (hashtable-set! ht k1 "vec")
    (hashtable-ref ht k2 #f))
  "vec")

;;; ========== pset ==========

(test "ps equal same order"
  (equal? (make-persistent-set 1 2 3)
          (make-persistent-set 1 2 3))
  #t)

(test "ps equal reversed order"
  (equal? (make-persistent-set 1 2 3)
          (make-persistent-set 3 2 1))
  #t)

(test "ps not equal"
  (equal? (make-persistent-set 1 2 3)
          (make-persistent-set 1 2 4))
  #f)

(test "ps hash equal for equal sets"
  (= (equal-hash (make-persistent-set 'a 'b 'c))
     (equal-hash (make-persistent-set 'c 'a 'b)))
  #t)

(test "ps as equal-hashtable key"
  (let ([ht (make-hashtable equal-hash equal?)]
        [k1 (make-persistent-set 'a 'b)]
        [k2 (make-persistent-set 'b 'a)])
    (hashtable-set! ht k1 "set")
    (hashtable-ref ht k2 #f))
  "set")

;;; ========== Mixed nesting ==========

(test "pmap with pvec value"
  (equal?
    (make-persistent-map 'lst (persistent-vector 1 2 3))
    (make-persistent-map 'lst (persistent-vector 1 2 3)))
  #t)

(test "pvec with pset element"
  (equal?
    (persistent-vector (make-persistent-set 1 2))
    (persistent-vector (make-persistent-set 2 1)))
  #t)

(printf "~%--- Results: ~a/~a passed, ~a failed ---~%"
  pass (+ pass fail) fail)

(exit (if (= fail 0) 0 1))
