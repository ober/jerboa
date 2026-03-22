#!chezscheme
;;; tests/test-persistent.ss -- Tests for (std misc persistent) HAMT

(import (chezscheme) (std misc persistent))

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

(printf "--- Persistent HAMT Tests ---~%~%")

;; ---- 1. empty hamt ----
(test "empty-hamt?"      (hamt? hamt-empty) #t)
(test "empty-size"       (hamt-size hamt-empty) 0)
(test "empty-ref"        (hamt-ref hamt-empty 'x 'default) 'default)
(test "empty-contains?"  (hamt-contains? hamt-empty 'x) #f)
(test "empty->alist"     (hamt->alist hamt-empty) '())
(test "empty-keys"       (hamt-keys hamt-empty) '())
(test "empty-values"     (hamt-values hamt-empty) '())
(test "empty-fold"       (hamt-fold (lambda (k v acc) (+ acc 1)) 0 hamt-empty) 0)

;; ---- 2. single insert and lookup ----
(let ([h (hamt-set hamt-empty "hello" 42)])
  (test "single-hamt?"     (hamt? h) #t)
  (test "single-size"      (hamt-size h) 1)
  (test "single-ref"       (hamt-ref h "hello" #f) 42)
  (test "single-contains?" (hamt-contains? h "hello") #t)
  (test "single-missing"   (hamt-ref h "world" 'nope) 'nope)
  (test "single-not-contains?" (hamt-contains? h "world") #f))

;; ---- 3. multiple inserts ----
(let* ([h0 hamt-empty]
       [h1 (hamt-set h0 'a 1)]
       [h2 (hamt-set h1 'b 2)]
       [h3 (hamt-set h2 'c 3)])
  (test "multi-size"    (hamt-size h3) 3)
  (test "multi-ref-a"   (hamt-ref h3 'a #f) 1)
  (test "multi-ref-b"   (hamt-ref h3 'b #f) 2)
  (test "multi-ref-c"   (hamt-ref h3 'c #f) 3)
  (test "multi-missing"  (hamt-ref h3 'd #f) #f))

;; ---- 4. update existing key ----
(let* ([h1 (hamt-set hamt-empty 'k 100)]
       [h2 (hamt-set h1 'k 200)])
  (test "update-new-value"  (hamt-ref h2 'k #f) 200)
  (test "update-old-value"  (hamt-ref h1 'k #f) 100)  ; persistence!
  (test "update-size"       (hamt-size h2) 1))

;; ---- 5. update with same value ----
(let* ([h1 (hamt-set hamt-empty 'k 42)]
       [h2 (hamt-set h1 'k 42)])
  (test "same-value-size" (hamt-size h2) 1))

;; ---- 6. delete ----
(let* ([h (alist->hamt '((a . 1) (b . 2) (c . 3)))]
       [h2 (hamt-delete h 'b)])
  (test "delete-size"      (hamt-size h2) 2)
  (test "delete-removed"   (hamt-contains? h2 'b) #f)
  (test "delete-kept-a"    (hamt-ref h2 'a #f) 1)
  (test "delete-kept-c"    (hamt-ref h2 'c #f) 3)
  ;; original preserved
  (test "delete-original"  (hamt-size h) 3)
  (test "delete-original-b" (hamt-ref h 'b #f) 2))

;; ---- 7. delete non-existent key ----
(let* ([h (hamt-set hamt-empty 'a 1)]
       [h2 (hamt-delete h 'nonexistent)])
  (test "delete-nonexist-size" (hamt-size h2) 1)
  (test "delete-nonexist-eq"   (eq? h h2) #t))

;; ---- 8. delete from empty ----
(let ([h (hamt-delete hamt-empty 'x)])
  (test "delete-empty-size" (hamt-size h) 0))

;; ---- 9. delete all keys ----
(let* ([h (alist->hamt '((a . 1) (b . 2) (c . 3)))]
       [h2 (hamt-delete (hamt-delete (hamt-delete h 'a) 'b) 'c)])
  (test "delete-all-size"   (hamt-size h2) 0)
  (test "delete-all-alist"  (hamt->alist h2) '()))

;; ---- 10. hamt-fold ----
(let ([h (alist->hamt '((a . 1) (b . 2) (c . 3)))])
  (test "fold-sum" (hamt-fold (lambda (k v acc) (+ v acc)) 0 h) 6)
  (test "fold-count" (hamt-fold (lambda (k v acc) (+ acc 1)) 0 h) 3))

;; ---- 11. hamt-keys and hamt-values ----
(let ([h (alist->hamt '((x . 10) (y . 20)))])
  (test "keys-length"   (length (hamt-keys h)) 2)
  (test "values-length" (length (hamt-values h)) 2)
  ;; Order may vary but all keys/values must be present
  (test "keys-contain-x"   (not (not (member 'x (hamt-keys h)))) #t)
  (test "keys-contain-y"   (not (not (member 'y (hamt-keys h)))) #t)
  (test "values-contain-10" (not (not (member 10 (hamt-values h)))) #t)
  (test "values-contain-20" (not (not (member 20 (hamt-values h)))) #t))

;; ---- 12. hamt-map ----
(let* ([h (alist->hamt '((a . 1) (b . 2) (c . 3)))]
       [h2 (hamt-map (lambda (v) (* v 10)) h)])
  (test "map-a"    (hamt-ref h2 'a #f) 10)
  (test "map-b"    (hamt-ref h2 'b #f) 20)
  (test "map-c"    (hamt-ref h2 'c #f) 30)
  (test "map-size" (hamt-size h2) 3)
  ;; original unchanged
  (test "map-orig" (hamt-ref h 'a #f) 1))

;; ---- 13. hamt->alist and alist->hamt round-trip ----
(let* ([original '((x . 10) (y . 20) (z . 30))]
       [h (alist->hamt original)]
       [al (hamt->alist h)])
  (test "roundtrip-size" (length al) 3)
  ;; Check all entries present (order may differ)
  (test "roundtrip-x" (cdr (assoc 'x al)) 10)
  (test "roundtrip-y" (cdr (assoc 'y al)) 20)
  (test "roundtrip-z" (cdr (assoc 'z al)) 30))

;; ---- 14. persistence / structural sharing ----
(let* ([h0 hamt-empty]
       [h1 (hamt-set h0 'a 1)]
       [h2 (hamt-set h1 'b 2)]
       [h3 (hamt-set h2 'c 3)]
       [h4 (hamt-delete h3 'a)])
  ;; Each version is independent
  (test "persist-h0" (hamt-size h0) 0)
  (test "persist-h1" (hamt-size h1) 1)
  (test "persist-h2" (hamt-size h2) 2)
  (test "persist-h3" (hamt-size h3) 3)
  (test "persist-h4" (hamt-size h4) 2)
  ;; h1 doesn't see b or c
  (test "persist-h1-no-b" (hamt-contains? h1 'b) #f)
  (test "persist-h1-no-c" (hamt-contains? h1 'c) #f)
  ;; h4 doesn't see a
  (test "persist-h4-no-a" (hamt-contains? h4 'a) #f)
  (test "persist-h4-has-b" (hamt-contains? h4 'b) #t)
  (test "persist-h4-has-c" (hamt-contains? h4 'c) #t))

;; ---- 15. various key types ----
(let* ([h hamt-empty]
       [h (hamt-set h 42 "number")]
       [h (hamt-set h "str" "string")]
       [h (hamt-set h 'sym "symbol")]
       [h (hamt-set h '(a b) "list")]
       [h (hamt-set h #t "boolean")]
       [h (hamt-set h #\x "char")])
  (test "key-number"  (hamt-ref h 42 #f) "number")
  (test "key-string"  (hamt-ref h "str" #f) "string")
  (test "key-symbol"  (hamt-ref h 'sym #f) "symbol")
  (test "key-list"    (hamt-ref h '(a b) #f) "list")
  (test "key-boolean" (hamt-ref h #t #f) "boolean")
  (test "key-char"    (hamt-ref h #\x #f) "char")
  (test "mixed-size"  (hamt-size h) 6))

;; ---- 16. stress test: 500 entries ----
(let ([h (let loop ([h hamt-empty] [i 0])
           (if (= i 500)
             h
             (loop (hamt-set h i (* i i)) (+ i 1))))])
  (test "stress-size" (hamt-size h) 500)
  (test "stress-ref-0"   (hamt-ref h 0 #f)   0)
  (test "stress-ref-250" (hamt-ref h 250 #f) 62500)
  (test "stress-ref-499" (hamt-ref h 499 #f) 249001)
  (test "stress-missing" (hamt-ref h 500 'no) 'no)
  ;; Delete every other entry
  (let ([h2 (let loop ([h h] [i 0])
              (if (= i 500)
                h
                (loop (if (even? i) (hamt-delete h i) h) (+ i 1))))])
    (test "stress-after-delete-size" (hamt-size h2) 250)
    (test "stress-deleted-even"  (hamt-contains? h2 0) #f)
    (test "stress-kept-odd"      (hamt-contains? h2 1) #t)
    (test "stress-deleted-100"   (hamt-contains? h2 100) #f)
    (test "stress-kept-101"      (hamt-contains? h2 101) #t)))

;; ---- 17. alist->hamt with duplicate keys (last wins) ----
(let ([h (alist->hamt '((a . 1) (b . 2) (a . 3)))])
  (test "alist-dup-value" (hamt-ref h 'a #f) 3)
  (test "alist-dup-size"  (hamt-size h) 2))

;; ---- 18. hamt-map preserves keys ----
(let* ([h (alist->hamt '((a . 1) (b . 2)))]
       [h2 (hamt-map (lambda (v) (string-append "val" (number->string v))) h)])
  (test "map-preserves-key-a" (hamt-ref h2 'a #f) "val1")
  (test "map-preserves-key-b" (hamt-ref h2 'b #f) "val2"))

;; ---- 19. hamt-fold accumulation order ----
;; fold should visit all entries exactly once
(let* ([h (alist->hamt '((a . 1) (b . 2) (c . 3)))]
       [collected (hamt-fold (lambda (k v acc) (cons (cons k v) acc)) '() h)])
  (test "fold-collected-length" (length collected) 3)
  (test "fold-has-a" (not (not (assoc 'a collected))) #t)
  (test "fold-has-b" (not (not (assoc 'b collected))) #t)
  (test "fold-has-c" (not (not (assoc 'c collected))) #t))

;; ---- 20. type predicate ----
(test "hamt?-true"   (hamt? hamt-empty) #t)
(test "hamt?-set"    (hamt? (hamt-set hamt-empty 'k 1)) #t)
(test "hamt?-false-list"  (hamt? '()) #f)
(test "hamt?-false-num"   (hamt? 42) #f)
(test "hamt?-false-str"   (hamt? "hello") #f)

;; ---- 21. string keys (common use case) ----
(let* ([h hamt-empty]
       [h (hamt-set h "name" "Alice")]
       [h (hamt-set h "email" "alice@example.com")]
       [h (hamt-set h "age" 30)])
  (test "string-keys-name"  (hamt-ref h "name" #f) "Alice")
  (test "string-keys-email" (hamt-ref h "email" #f) "alice@example.com")
  (test "string-keys-age"   (hamt-ref h "age" #f) 30)
  (test "string-keys-size"  (hamt-size h) 3))

;; ---- 22. large-scale correctness ----
;; Insert 1000 keys, verify all, delete all, verify empty
(let ([h (let loop ([h hamt-empty] [i 0])
           (if (= i 1000) h
             (loop (hamt-set h i (number->string i)) (+ i 1))))])
  (test "large-size" (hamt-size h) 1000)
  ;; Verify every key
  (let ([all-ok (let loop ([i 0])
                  (if (= i 1000) #t
                    (if (equal? (hamt-ref h i #f) (number->string i))
                      (loop (+ i 1))
                      #f)))])
    (test "large-all-present" all-ok #t))
  ;; Delete all
  (let ([h2 (let loop ([h h] [i 0])
              (if (= i 1000) h
                (loop (hamt-delete h i) (+ i 1))))])
    (test "large-delete-all" (hamt-size h2) 0)))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
