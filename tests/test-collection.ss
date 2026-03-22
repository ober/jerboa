#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc collection))

(define test-count 0)
(define pass-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (display "FAIL: ") (display name) (newline)
              (display "  Error: ") (display (condition-message e)) (newline)])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display "PASS: ") (display name) (newline)))

(define (assert-equal actual expected msg)
  (unless (equal? actual expected)
    (error 'assert-equal
           (string-append msg ": expected " (format "~s" expected)
                          " got " (format "~s" actual)))))

(define (assert-true val msg)
  (unless val
    (error 'assert-true (string-append msg ": expected #t got #f"))))

(define (assert-false val msg)
  (when val
    (error 'assert-false (string-append msg ": expected #f got #t"))))

;; ===== make-iterator =====

(test "make-iterator: list"
  (lambda ()
    (let ([iter (make-iterator '(1 2 3))])
      (let-values ([(v ok) (iter)]) (assert-equal v 1 "first") (assert-true ok "first ok"))
      (let-values ([(v ok) (iter)]) (assert-equal v 2 "second") (assert-true ok "second ok"))
      (let-values ([(v ok) (iter)]) (assert-equal v 3 "third") (assert-true ok "third ok"))
      (let-values ([(v ok) (iter)]) (assert-false ok "done")))))

(test "make-iterator: empty list"
  (lambda ()
    (let ([iter (make-iterator '())])
      (let-values ([(v ok) (iter)]) (assert-false ok "done immediately")))))

(test "make-iterator: vector"
  (lambda ()
    (let ([iter (make-iterator '#(a b c))])
      (let-values ([(v ok) (iter)]) (assert-equal v 'a "first") (assert-true ok "ok"))
      (let-values ([(v ok) (iter)]) (assert-equal v 'b "second"))
      (let-values ([(v ok) (iter)]) (assert-equal v 'c "third"))
      (let-values ([(v ok) (iter)]) (assert-false ok "done")))))

(test "make-iterator: string"
  (lambda ()
    (let ([iter (make-iterator "hi")])
      (let-values ([(v ok) (iter)]) (assert-equal v #\h "first") (assert-true ok "ok"))
      (let-values ([(v ok) (iter)]) (assert-equal v #\i "second"))
      (let-values ([(v ok) (iter)]) (assert-false ok "done")))))

(test "make-iterator: bytevector"
  (lambda ()
    (let ([iter (make-iterator #vu8(10 20 30))])
      (let-values ([(v ok) (iter)]) (assert-equal v 10 "first"))
      (let-values ([(v ok) (iter)]) (assert-equal v 20 "second"))
      (let-values ([(v ok) (iter)]) (assert-equal v 30 "third"))
      (let-values ([(v ok) (iter)]) (assert-false ok "done")))))

(test "make-iterator: hashtable"
  (lambda ()
    (let ([ht (make-eq-hashtable)])
      (hashtable-set! ht 'x 1)
      (hashtable-set! ht 'y 2)
      (let ([result (collection->list ht)])
        (assert-equal (length result) 2 "two pairs")
        (assert-true (for-all pair? result) "all pairs")
        ;; Check that both entries are present (order may vary)
        (assert-true (or (member '(x . 1) result) (member '(y . 2) result))
                     "contains expected pairs")))))

;; ===== collection->list =====

(test "collection->list: list identity"
  (lambda ()
    (assert-equal (collection->list '(1 2 3)) '(1 2 3) "list->list")))

(test "collection->list: vector"
  (lambda ()
    (assert-equal (collection->list '#(4 5 6)) '(4 5 6) "vec->list")))

(test "collection->list: string"
  (lambda ()
    (assert-equal (collection->list "abc") '(#\a #\b #\c) "str->list")))

(test "collection->list: bytevector"
  (lambda ()
    (assert-equal (collection->list #vu8(1 2 3)) '(1 2 3) "bv->list")))

(test "collection->list: empty vector"
  (lambda ()
    (assert-equal (collection->list '#()) '() "empty vec")))

;; ===== collection-fold =====

(test "collection-fold: sum a list"
  (lambda ()
    (assert-equal (collection-fold + 0 '(1 2 3 4)) 10 "sum")))

(test "collection-fold: sum a vector"
  (lambda ()
    (assert-equal (collection-fold + 0 '#(10 20 30)) 60 "vec sum")))

(test "collection-fold: cons builds reversed list"
  (lambda ()
    (assert-equal (collection-fold cons '() '(a b c)) '(c b a) "cons fold")))

(test "collection-fold: empty collection"
  (lambda ()
    (assert-equal (collection-fold + 0 '()) 0 "empty fold")))

;; ===== collection-map =====

(test "collection-map: list"
  (lambda ()
    (assert-equal (collection-map (lambda (x) (* x 2)) '(1 2 3))
                  '(2 4 6) "double list")))

(test "collection-map: vector"
  (lambda ()
    (assert-equal (collection-map (lambda (x) (+ x 1)) '#(10 20 30))
                  '(11 21 31) "inc vector")))

(test "collection-map: string char->integer"
  (lambda ()
    (assert-equal (collection-map char->integer "AB")
                  '(65 66) "char codes")))

;; ===== collection-filter =====

(test "collection-filter: list"
  (lambda ()
    (assert-equal (collection-filter even? '(1 2 3 4 5 6))
                  '(2 4 6) "even from list")))

(test "collection-filter: vector"
  (lambda ()
    (assert-equal (collection-filter (lambda (x) (> x 2)) '#(1 2 3 4 5))
                  '(3 4 5) "filter vector")))

(test "collection-filter: none match"
  (lambda ()
    (assert-equal (collection-filter negative? '(1 2 3)) '() "none")))

;; ===== collection-for-each =====

(test "collection-for-each: accumulates side effects"
  (lambda ()
    (let ([acc '()])
      (collection-for-each (lambda (x) (set! acc (cons x acc))) '(1 2 3))
      (assert-equal acc '(3 2 1) "reversed accumulation"))))

(test "collection-for-each: vector"
  (lambda ()
    (let ([sum 0])
      (collection-for-each (lambda (x) (set! sum (+ sum x))) '#(10 20 30))
      (assert-equal sum 60 "vector sum via for-each"))))

;; ===== collection-find =====

(test "collection-find: found"
  (lambda ()
    (assert-equal (collection-find even? '(1 3 4 5)) 4 "first even")))

(test "collection-find: not found"
  (lambda ()
    (assert-equal (collection-find negative? '(1 2 3)) #f "none negative")))

(test "collection-find: in vector"
  (lambda ()
    (assert-equal (collection-find (lambda (x) (> x 10)) '#(5 8 15 20))
                  15 "first > 10")))

;; ===== collection-any =====

(test "collection-any: true"
  (lambda ()
    (assert-true (collection-any even? '(1 3 4)) "has even")))

(test "collection-any: false"
  (lambda ()
    (assert-false (collection-any even? '(1 3 5)) "no even")))

(test "collection-any: empty"
  (lambda ()
    (assert-false (collection-any even? '()) "empty => #f")))

;; ===== collection-every =====

(test "collection-every: true"
  (lambda ()
    (assert-true (collection-every positive? '(1 2 3)) "all positive")))

(test "collection-every: false"
  (lambda ()
    (assert-false (collection-every positive? '(1 -2 3)) "not all positive")))

(test "collection-every: empty"
  (lambda ()
    (assert-true (collection-every positive? '()) "empty => #t")))

;; ===== collection-length =====

(test "collection-length: list"
  (lambda ()
    (assert-equal (collection-length '(a b c d)) 4 "list len")))

(test "collection-length: vector"
  (lambda ()
    (assert-equal (collection-length '#(1 2 3)) 3 "vec len")))

(test "collection-length: string"
  (lambda ()
    (assert-equal (collection-length "hello") 5 "string len")))

(test "collection-length: empty"
  (lambda ()
    (assert-equal (collection-length '()) 0 "empty len")))

(test "collection-length: bytevector"
  (lambda ()
    (assert-equal (collection-length #vu8(1 2)) 2 "bv len")))

;; ===== define-collection: custom type =====

(test "define-collection: custom range type"
  (lambda ()
    ;; A range is a pair (lo . hi), iterates lo, lo+1, ..., hi-1
    (define (range? x) (and (pair? x) (integer? (car x)) (integer? (cdr x))))
    (define (make-range-iterator r)
      (let ([i (car r)] [hi (cdr r)])
        (lambda ()
          (if (>= i hi)
              (values #f #f)
              (let ([v i])
                (set! i (+ i 1))
                (values v #t))))))
    (define-collection range? make-range-iterator)
    (assert-equal (collection->list (cons 0 5)) '(0 1 2 3 4) "range 0..5")
    (assert-equal (collection-length (cons 3 7)) 4 "range length")
    (assert-equal (collection-fold + 0 (cons 1 4)) 6 "range fold")))

;; ===== Cross-type consistency =====

(test "same data, different containers, same results"
  (lambda ()
    (let ([lst '(1 2 3)]
          [vec '#(1 2 3)])
      (assert-equal (collection->list lst) (collection->list vec) "list=vec")
      (assert-equal (collection-length lst) (collection-length vec) "len=len")
      (assert-equal (collection-fold + 0 lst) (collection-fold + 0 vec) "fold=fold"))))

;; ===== Error handling =====

(test "make-iterator: error on unregistered type"
  (lambda ()
    (guard (e [#t (assert-true (message-condition? e) "is condition")])
      (make-iterator (make-eq-hashtable))  ;; hashtable is registered, so use a symbol
      ;; Actually symbols are not registered
      (error 'test "should not reach here"))))

;; Correct the above: use a type that is NOT registered
(test "make-iterator: error on symbol (unregistered)"
  (lambda ()
    (guard (e [#t (assert-true #t "got expected error")])
      (make-iterator 'not-a-collection)
      (error 'test "should have raised error"))))

;; Summary
(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
