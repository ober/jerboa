#!chezscheme
;;; tests/test-sorted-map.ss -- Tests for (std ds sorted-map)

(import (chezscheme) (std ds sorted-map))

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

(printf "--- Phase 2e: Sorted Map ---~%~%")

;; ---- 1. empty map ----
(let ([m (sorted-map-empty)])
  (test "sm-empty?"    (sorted-map? m) #t)
  (test "sm-empty-size" (sorted-map-size m) 0)
  (test "sm-empty-lookup" (sorted-map-lookup m 'x) #f))

;; ---- 2. insert and lookup ----
(let* ([m0 (sorted-map-empty)]
       [m1 (sorted-map-insert m0 'b 2)]
       [m2 (sorted-map-insert m1 'a 1)]
       [m3 (sorted-map-insert m2 'c 3)])
  (test "sm-insert-a" (sorted-map-lookup m3 'a) 1)
  (test "sm-insert-b" (sorted-map-lookup m3 'b) 2)
  (test "sm-insert-c" (sorted-map-lookup m3 'c) 3)
  (test "sm-missing"  (sorted-map-lookup m3 'd) #f)
  (test "sm-size-3"   (sorted-map-size m3) 3))

;; ---- 3. update existing key ----
(let* ([m0 (sorted-map-empty)]
       [m1 (sorted-map-insert m0 'x 100)]
       [m2 (sorted-map-insert m1 'x 200)])
  (test "sm-update-value" (sorted-map-lookup m2 'x) 200)
  (test "sm-update-size"  (sorted-map-size m2) 1))

;; ---- 4. sorted-map->alist (in-order) ----
(let* ([m (alist->sorted-map '((c . 3) (a . 1) (b . 2)))]
       [al (sorted-map->alist m)])
  (test "sm-alist-ordered" al '((a . 1) (b . 2) (c . 3))))

;; ---- 5. sorted-map-keys and sorted-map-values ----
(let ([m (alist->sorted-map '((z . 26) (a . 1) (m . 13)))])
  (test "sm-keys"   (sorted-map-keys m)   '(a m z))
  (test "sm-values" (sorted-map-values m) '(1 13 26)))

;; ---- 6. sorted-map-min / sorted-map-max ----
(let ([m (alist->sorted-map '((5 . "five") (1 . "one") (3 . "three")))])
  (test "sm-min" (sorted-map-min m) '(1 . "one"))
  (test "sm-max" (sorted-map-max m) '(5 . "five")))

;; ---- 7. sorted-map-fold ----
(let ([m (alist->sorted-map '((a . 1) (b . 2) (c . 3)))])
  (let ([sum (sorted-map-fold m (lambda (k v acc) (+ v acc)) 0)])
    (test "sm-fold-sum" sum 6))
  (let ([keys (sorted-map-fold m (lambda (k v acc) (cons k acc)) '())])
    (test "sm-fold-keys-reversed" keys '(c b a))))

;; ---- 8. sorted-map-delete ----
(let* ([m0 (alist->sorted-map '((a . 1) (b . 2) (c . 3) (d . 4)))]
       [m1 (sorted-map-delete m0 'b)])
  (test "sm-delete-removed"   (sorted-map-lookup m1 'b) #f)
  (test "sm-delete-remaining-a" (sorted-map-lookup m1 'a) 1)
  (test "sm-delete-remaining-c" (sorted-map-lookup m1 'c) 3)
  (test "sm-delete-size"        (sorted-map-size m1) 3)
  ;; Delete non-existent key - size unchanged
  (let ([m2 (sorted-map-delete m0 'z)])
    (test "sm-delete-nonexistent-size" (sorted-map-size m2) 4)))

;; ---- 9. sorted-map-range ----
(let* ([m (alist->sorted-map '((1 . "one") (2 . "two") (3 . "three")
                                (4 . "four") (5 . "five")))]
       [r (sorted-map-range m 2 4)])
  (test "sm-range-keys" (sorted-map-keys r) '(2 3 4))
  (test "sm-range-size" (sorted-map-size r) 3))

;; ---- 10. make-sorted-map with custom comparator ----
(let* ([m (make-sorted-map (lambda (a b) (- b a)))]  ; reverse order
       [m1 (sorted-map-insert m 1 "one")]
       [m2 (sorted-map-insert m1 3 "three")]
       [m3 (sorted-map-insert m2 2 "two")])
  (test "sm-custom-cmp-alist"
        (sorted-map->alist m3)
        '((3 . "three") (2 . "two") (1 . "one"))))

;; ---- 11. persistence (functional updates) ----
(let* ([m0 (alist->sorted-map '((a . 1) (b . 2)))]
       [m1 (sorted-map-insert m0 'c 3)]
       [m2 (sorted-map-delete m0 'a)])
  ;; m0 is unchanged
  (test "sm-persistent-original-size" (sorted-map-size m0) 2)
  (test "sm-persistent-m1-size"       (sorted-map-size m1) 3)
  (test "sm-persistent-m2-size"       (sorted-map-size m2) 1))

;; ---- 12. larger map correctness ----
(let* ([pairs (map (lambda (i) (cons i (* i i))) '(5 3 8 1 9 2 7 4 6 10))]
       [m (alist->sorted-map pairs)])
  (test "sm-large-size"  (sorted-map-size m) 10)
  (test "sm-large-keys"  (sorted-map-keys m) '(1 2 3 4 5 6 7 8 9 10))
  (test "sm-large-lookup-7" (sorted-map-lookup m 7) 49))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
