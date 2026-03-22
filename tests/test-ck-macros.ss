#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc ck-macros))

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

;; ---------------------------------------------------------------------------
;; c-quote
;; ---------------------------------------------------------------------------

(test "c-quote returns a value"
  (lambda ()
    (assert-equal (ck () (c-quote hello)) 'hello "quote atom")
    (assert-equal (ck () (c-quote (a b c))) '(a b c) "quote list")))

;; ---------------------------------------------------------------------------
;; c-cons
;; ---------------------------------------------------------------------------

(test "c-cons builds a pair"
  (lambda ()
    (assert-equal (ck () (c-cons '1 '2)) '(1 . 2) "pair")
    (assert-equal (ck () (c-cons 'a '(b c))) '(a b c) "cons onto list")))

(test "c-cons with nested CK expression"
  (lambda ()
    (assert-equal (ck () (c-cons 'a (c-cons 'b '()))) '(a b) "nested cons")))

;; ---------------------------------------------------------------------------
;; c-car / c-cdr
;; ---------------------------------------------------------------------------

(test "c-car extracts head"
  (lambda ()
    (assert-equal (ck () (c-car '(x y z))) 'x "car")))

(test "c-cdr extracts tail"
  (lambda ()
    (assert-equal (ck () (c-cdr '(x y z))) '(y z) "cdr")))

(test "c-car of c-cons"
  (lambda ()
    (assert-equal (ck () (c-car (c-cons 'a '(b)))) 'a "car of cons")))

(test "c-cdr of c-cons"
  (lambda ()
    (assert-equal (ck () (c-cdr (c-cons 'a '(b)))) '(b) "cdr of cons")))

;; ---------------------------------------------------------------------------
;; c-null?
;; ---------------------------------------------------------------------------

(test "c-null? on empty list"
  (lambda ()
    (assert-equal (ck () (c-null? '())) #t "null? of ()")))

(test "c-null? on non-empty list"
  (lambda ()
    (assert-equal (ck () (c-null? '(a b))) #f "null? of (a b)")))

(test "c-null? on atom"
  (lambda ()
    (assert-equal (ck () (c-null? 'x)) #f "null? of atom")))

;; ---------------------------------------------------------------------------
;; c-if
;; ---------------------------------------------------------------------------

(test "c-if true branch"
  (lambda ()
    (assert-equal (ck () (c-if '#t 'yes 'no)) 'yes "if true")))

(test "c-if false branch"
  (lambda ()
    (assert-equal (ck () (c-if '#f 'yes 'no)) 'no "if false")))

(test "c-if with CK condition"
  (lambda ()
    (assert-equal (ck () (c-if (c-null? '()) 'empty 'notempty))
                  'empty "if null? empty")))

(test "c-if with CK condition false"
  (lambda ()
    (assert-equal (ck () (c-if (c-null? '(a)) 'empty 'notempty))
                  'notempty "if null? non-empty")))

;; ---------------------------------------------------------------------------
;; c-map
;; ---------------------------------------------------------------------------

(test "c-map empty list"
  (lambda ()
    (assert-equal (ck () (c-map (c-car) '())) '() "map empty")))

(test "c-map c-car over list of pairs"
  (lambda ()
    (assert-equal (ck () (c-map (c-car) '((a 1) (b 2) (c 3))))
                  '(a b c) "map car")))

(test "c-map c-cdr over list of pairs"
  (lambda ()
    (assert-equal (ck () (c-map (c-cdr) '((a 1) (b 2) (c 3))))
                  '((1) (2) (3)) "map cdr")))

(test "c-map c-cons with partial application"
  (lambda ()
    (assert-equal (ck () (c-map (c-cons 'x) '(1 2 3)))
                  '((x . 1) (x . 2) (x . 3)) "map cons")))

;; ---------------------------------------------------------------------------
;; c-filter
;; ---------------------------------------------------------------------------

;; Define a CK predicate: c-pair? returns #t for pairs, #f for atoms
(define-syntax c-pair?
  (syntax-rules (quote)
    [(c-pair? s '(a . d)) (ck s '#t)]
    [(c-pair? s 'v) (ck s '#f)]))

(test "c-filter selects matching elements"
  (lambda ()
    (assert-equal (ck () (c-filter (c-pair?) '((a 1) b (c 2) d)))
                  '((a 1) (c 2)) "filter pairs")))

(test "c-filter empty list"
  (lambda ()
    (assert-equal (ck () (c-filter (c-pair?) '())) '() "filter empty")))

(test "c-filter keeps all"
  (lambda ()
    (assert-equal (ck () (c-filter (c-pair?) '((a) (b) (c))))
                  '((a) (b) (c)) "filter all match")))

(test "c-filter keeps none"
  (lambda ()
    (assert-equal (ck () (c-filter (c-pair?) '(a b c)))
                  '() "filter none match")))

;; ---------------------------------------------------------------------------
;; c-foldr
;; ---------------------------------------------------------------------------

(test "c-foldr with c-cons reconstructs list"
  (lambda ()
    (assert-equal (ck () (c-foldr (c-cons) '() '(a b c)))
                  '(a b c) "foldr cons")))

(test "c-foldr empty list returns init"
  (lambda ()
    (assert-equal (ck () (c-foldr (c-cons) '(x) '()))
                  '(x) "foldr empty")))

;; ---------------------------------------------------------------------------
;; c-append
;; ---------------------------------------------------------------------------

(test "c-append two lists"
  (lambda ()
    (assert-equal (ck () (c-append '(a b) '(c d)))
                  '(a b c d) "append")))

(test "c-append empty first"
  (lambda ()
    (assert-equal (ck () (c-append '() '(x y)))
                  '(x y) "append empty first")))

(test "c-append empty second"
  (lambda ()
    (assert-equal (ck () (c-append '(x y) '()))
                  '(x y) "append empty second")))

(test "c-append both empty"
  (lambda ()
    (assert-equal (ck () (c-append '() '()))
                  '() "append both empty")))

;; ---------------------------------------------------------------------------
;; c-reverse
;; ---------------------------------------------------------------------------

(test "c-reverse a list"
  (lambda ()
    (assert-equal (ck () (c-reverse '(a b c)))
                  '(c b a) "reverse")))

(test "c-reverse empty"
  (lambda ()
    (assert-equal (ck () (c-reverse '()))
                  '() "reverse empty")))

(test "c-reverse singleton"
  (lambda ()
    (assert-equal (ck () (c-reverse '(x)))
                  '(x) "reverse singleton")))

;; ---------------------------------------------------------------------------
;; c-length
;; ---------------------------------------------------------------------------

(test "c-length of empty list"
  (lambda ()
    (assert-equal (ck () (c-length '())) '() "length 0")))

(test "c-length of 3-element list"
  (lambda ()
    (assert-equal (length (ck () (c-length '(a b c)))) 3 "length 3")))

(test "c-length of singleton"
  (lambda ()
    (assert-equal (length (ck () (c-length '(x)))) 1 "length 1")))

;; ---------------------------------------------------------------------------
;; Composition tests
;; ---------------------------------------------------------------------------

(test "composition: c-map inside c-append"
  (lambda ()
    (assert-equal (ck () (c-append (c-map (c-car) '((a 1) (b 2)))
                                   '(c d)))
                  '(a b c d) "map then append")))

(test "composition: c-reverse of c-map"
  (lambda ()
    (assert-equal (ck () (c-reverse (c-map (c-car) '((a 1) (b 2) (c 3)))))
                  '(c b a) "reverse of map")))

(test "composition: c-filter then c-map"
  (lambda ()
    ;; Filter pairs, then extract cars
    (assert-equal (ck () (c-map (c-car) (c-filter (c-pair?) '((a 1) b (c 2) d))))
                  '(a c) "map car of filtered pairs")))

(test "composition: c-foldr with c-cons and c-reverse"
  (lambda ()
    (assert-equal (ck () (c-reverse (c-foldr (c-cons) '() '(a b c))))
                  '(c b a) "reverse of foldr cons")))

(test "composition: nested c-if with CK operations"
  (lambda ()
    (assert-equal (ck () (c-if (c-null? '())
                               (c-cons 'was-empty '())
                               (c-cons 'was-notempty '())))
                  '(was-empty) "if-then with CK branches")))

;; ---------------------------------------------------------------------------
;; Results
;; ---------------------------------------------------------------------------

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
