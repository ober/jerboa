#!chezscheme
;;; Tests for (std pmap) -- Persistent Hash Maps

(import (chezscheme)
        (std pmap))

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

(printf "--- Phase 2a: Persistent Hash Maps ---~%~%")

;;; ======== Empty map ========

(test "empty size"
  (persistent-map-size pmap-empty)
  0)

(test "empty type"
  (persistent-map? pmap-empty)
  #t)

(test "not a map"
  (persistent-map? '(1 2))
  #f)

;;; ======== Construction ========

(test "make from pairs"
  (let ([m (persistent-map 'a 1 'b 2 'c 3)])
    (persistent-map-size m))
  3)

;;; ======== Set and Ref ========

(test "set creates new map"
  (let* ([m1 pmap-empty]
         [m2 (persistent-map-set m1 'x 42)])
    (list (persistent-map-size m1)
          (persistent-map-size m2)))
  '(0 1))

(test "ref basic"
  (persistent-map-ref (persistent-map 'a 1 'b 2) 'a)
  1)

(test "ref returns correct value"
  (persistent-map-ref (persistent-map 'a 1 'b 2 'c 3) 'b)
  2)

(test "ref missing with default"
  (persistent-map-ref pmap-empty 'missing (lambda () 99))
  99)

(test "ref missing raises"
  (guard (exn [(message-condition? exn) 'error])
    (persistent-map-ref pmap-empty 'missing))
  'error)

(test "has? true"
  (persistent-map-has? (persistent-map 'a 1) 'a)
  #t)

(test "has? false"
  (persistent-map-has? (persistent-map 'a 1) 'b)
  #f)

;;; ======== Update immutability ========

(test "set returns new, old unchanged"
  (let* ([m1 (persistent-map 'x 1)]
         [m2 (persistent-map-set m1 'x 99)])
    (list (persistent-map-ref m1 'x)
          (persistent-map-ref m2 'x)))
  '(1 99))

(test "add key preserves old keys"
  (let* ([m1 (persistent-map 'a 1 'b 2)]
         [m2 (persistent-map-set m1 'c 3)])
    (list (persistent-map-has? m2 'a)
          (persistent-map-has? m2 'b)
          (persistent-map-has? m2 'c)))
  '(#t #t #t))

;;; ======== Delete ========

(test "delete removes key"
  (let* ([m1 (persistent-map 'a 1 'b 2 'c 3)]
         [m2 (persistent-map-delete m1 'b)])
    (list (persistent-map-size m2)
          (persistent-map-has? m2 'b)
          (persistent-map-has? m2 'a)))
  '(2 #f #t))

(test "delete non-existent returns same"
  (let* ([m (persistent-map 'a 1)])
    (= (persistent-map-size (persistent-map-delete m 'missing))
       (persistent-map-size m)))
  #t)

;;; ======== Many keys ========

(test "100 keys"
  (let ([m (let loop ([i 0] [m pmap-empty])
             (if (= i 100)
               m
               (loop (+ i 1) (persistent-map-set m i (* i i)))))])
    (and (= (persistent-map-size m) 100)
         (= (persistent-map-ref m 50) 2500)
         (= (persistent-map-ref m 0) 0)
         (= (persistent-map-ref m 99) 9801)))
  #t)

(test "1000 string keys"
  (let ([m (let loop ([i 0] [m pmap-empty])
             (if (= i 1000)
               m
               (loop (+ i 1)
                     (persistent-map-set m (number->string i) i))))])
    (and (= (persistent-map-size m) 1000)
         (= (persistent-map-ref m "500") 500)))
  #t)

;;; ======== Iteration ========

(test "to-list contains all pairs"
  (let* ([m (persistent-map 'a 1 'b 2 'c 3)]
         [lst (sort (lambda (a b) (string<? (symbol->string (car a))
                                            (symbol->string (car b))))
                    (persistent-map->list m))])
    lst)
  '((a . 1) (b . 2) (c . 3)))

(test "keys"
  (let* ([m (persistent-map 'a 1 'b 2 'c 3)]
         [ks (sort (lambda (a b) (string<? (symbol->string a)
                                           (symbol->string b)))
                   (persistent-map-keys m))])
    ks)
  '(a b c))

(test "values"
  (let* ([m (persistent-map 'a 1 'b 2 'c 3)]
         [vs (sort < (persistent-map-values m))])
    vs)
  '(1 2 3))

(test "for-each accumulates"
  (let* ([m   (persistent-map 'a 1 'b 2 'c 3)]
         [sum 0])
    (persistent-map-for-each (lambda (k v) (set! sum (+ sum v))) m)
    sum)
  6)

(test "map values"
  (let* ([m1 (persistent-map 'a 1 'b 2 'c 3)]
         [m2 (persistent-map-map (lambda (k v) (* v 2)) m1)])
    (list (persistent-map-ref m2 'a)
          (persistent-map-ref m2 'b)))
  '(2 4))

(test "fold sum"
  (let ([m (persistent-map 'a 1 'b 2 'c 3)])
    (persistent-map-fold (lambda (acc k v) (+ acc v)) 0 m))
  6)

(test "filter even values"
  (let* ([m  (persistent-map 'a 1 'b 2 'c 3 'd 4)]
         [m2 (persistent-map-filter (lambda (k v) (even? v)) m)])
    (list (persistent-map-size m2)
          (persistent-map-has? m2 'b)
          (persistent-map-has? m2 'd)
          (persistent-map-has? m2 'a)))
  '(2 #t #t #f))

;;; ======== Merge / Diff ========

(test "merge two maps"
  (let* ([m1 (persistent-map 'a 1 'b 2)]
         [m2 (persistent-map 'b 20 'c 3)]
         [m3 (persistent-map-merge m1 m2)])
    (list (persistent-map-ref m3 'a)
          (persistent-map-ref m3 'b)  ; m2's value wins by default
          (persistent-map-ref m3 'c)))
  '(1 20 3))

(test "merge with conflict resolution"
  (let* ([m1 (persistent-map 'a 1 'b 2)]
         [m2 (persistent-map 'b 10 'c 3)]
         [m3 (persistent-map-merge m1 m2 (lambda (k v1 v2) (+ v1 v2)))])
    (persistent-map-ref m3 'b))
  12)

(test "diff"
  (let* ([m1 (persistent-map 'a 1 'b 2 'c 3)]
         [m2 (persistent-map 'b 99 'd 4)]
         [m3 (persistent-map-diff m1 m2)])
    (list (persistent-map-size m3)
          (persistent-map-has? m3 'a)
          (persistent-map-has? m3 'b)
          (persistent-map-has? m3 'c)))
  '(2 #t #f #t))

;;; Summary

(printf "~%Persistent Hash Maps: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
