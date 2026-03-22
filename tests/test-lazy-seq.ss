#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc lazy-seq))

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

;; ---- lazy-null and lazy-null? ----

(test "lazy-null is empty"
  (lambda ()
    (assert-equal (lazy-null? lazy-null) #t "lazy-null is null")))

(test "lazy-cons is not empty"
  (lambda ()
    (assert-equal (lazy-null? (lazy-cons 1 lazy-null)) #f "lazy-cons not null")))

;; ---- lazy-car / lazy-cdr ----

(test "lazy-car returns head"
  (lambda ()
    (assert-equal (lazy-car (lazy-cons 42 lazy-null)) 42 "head")))

(test "lazy-cdr returns tail"
  (lambda ()
    (assert-equal (lazy-null? (lazy-cdr (lazy-cons 42 lazy-null))) #t "tail is null")))

(test "nested lazy-cons"
  (lambda ()
    (let ([s (lazy-cons 1 (lazy-cons 2 (lazy-cons 3 lazy-null)))])
      (assert-equal (lazy-car s) 1 "first")
      (assert-equal (lazy-car (lazy-cdr s)) 2 "second")
      (assert-equal (lazy-car (lazy-cdr (lazy-cdr s))) 3 "third"))))

;; ---- lazy-seq->list / list->lazy-seq ----

(test "lazy-seq->list on empty"
  (lambda ()
    (assert-equal (lazy-seq->list lazy-null) '() "empty")))

(test "lazy-seq->list on elements"
  (lambda ()
    (let ([s (lazy-cons 1 (lazy-cons 2 (lazy-cons 3 lazy-null)))])
      (assert-equal (lazy-seq->list s) '(1 2 3) "three elements"))))

(test "list->lazy-seq round-trip"
  (lambda ()
    (assert-equal (lazy-seq->list (list->lazy-seq '(a b c))) '(a b c) "round-trip")))

(test "list->lazy-seq empty"
  (lambda ()
    (assert-equal (lazy-seq->list (list->lazy-seq '())) '() "empty round-trip")))

;; ---- lazy-seq macro ----

(test "lazy-seq macro creates sequence"
  (lambda ()
    (let ([s (lazy-seq (cons 10 (lazy-seq (cons 20 lazy-null))))])
      (assert-equal (lazy-seq->list s) '(10 20) "lazy-seq macro"))))

;; ---- memoization ----

(test "lazy-seq memoizes (thunk called only once)"
  (lambda ()
    (let* ([count 0]
           [s (lazy-seq
                (set! count (+ count 1))
                (cons count lazy-null))])
      (assert-equal (lazy-car s) 1 "first force")
      (assert-equal (lazy-car s) 1 "second force (cached)")
      (assert-equal count 1 "thunk called once"))))

(test "lazy-cons memoizes tail"
  (lambda ()
    (let* ([count 0]
           [s (lazy-cons 'a
                (begin
                  (set! count (+ count 1))
                  (lazy-cons count lazy-null)))])
      (lazy-car (lazy-cdr s))
      (lazy-car (lazy-cdr s))
      (assert-equal count 1 "tail forced once"))))

;; ---- lazy-take ----

(test "lazy-take from finite"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-take 2 (list->lazy-seq '(1 2 3 4))))
                  '(1 2) "take 2")))

(test "lazy-take more than available"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-take 10 (list->lazy-seq '(1 2))))
                  '(1 2) "take 10 from 2")))

(test "lazy-take 0"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-take 0 (list->lazy-seq '(1 2 3))))
                  '() "take 0")))

;; ---- lazy-drop ----

(test "lazy-drop elements"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-drop 2 (list->lazy-seq '(1 2 3 4 5))))
                  '(3 4 5) "drop 2")))

(test "lazy-drop 0"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-drop 0 (list->lazy-seq '(1 2 3))))
                  '(1 2 3) "drop 0")))

(test "lazy-drop more than available"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-drop 10 (list->lazy-seq '(1 2))))
                  '() "drop all")))

;; ---- lazy-map ----

(test "lazy-map over sequence"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-map (lambda (x) (* x x))
                                            (list->lazy-seq '(1 2 3 4))))
                  '(1 4 9 16) "map square")))

(test "lazy-map over empty"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-map add1 lazy-null))
                  '() "map empty")))

;; ---- lazy-filter ----

(test "lazy-filter odds"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-filter odd? (list->lazy-seq '(1 2 3 4 5 6))))
                  '(1 3 5) "filter odd")))

(test "lazy-filter none match"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-filter (lambda (x) #f) (list->lazy-seq '(1 2 3))))
                  '() "filter none")))

(test "lazy-filter all match"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-filter (lambda (x) #t) (list->lazy-seq '(1 2 3))))
                  '(1 2 3) "filter all")))

;; ---- lazy-append ----

(test "lazy-append two sequences"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-append (list->lazy-seq '(1 2))
                                               (list->lazy-seq '(3 4))))
                  '(1 2 3 4) "append")))

(test "lazy-append with empty first"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-append lazy-null (list->lazy-seq '(1 2))))
                  '(1 2) "append empty first")))

(test "lazy-append with empty second"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-append (list->lazy-seq '(1 2)) lazy-null))
                  '(1 2) "append empty second")))

;; ---- lazy-range ----

(test "lazy-range with end"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-range 5)) '(0 1 2 3 4) "range 5")))

(test "lazy-range with start and end"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-range 2 7)) '(2 3 4 5 6) "range 2..7")))

(test "lazy-range with step"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-range 0 10 3)) '(0 3 6 9) "range step 3")))

(test "lazy-range negative step"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-range 5 0 -1)) '(5 4 3 2 1) "range negative")))

(test "lazy-range empty"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-range 5 5)) '() "range empty")))

;; ---- lazy-iterate ----

(test "lazy-iterate produces infinite sequence (take 5)"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-take 5 (lazy-iterate add1 0)))
                  '(0 1 2 3 4) "iterate add1 from 0")))

(test "lazy-iterate doubling"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-take 6 (lazy-iterate (lambda (x) (* x 2)) 1)))
                  '(1 2 4 8 16 32) "iterate double")))

;; ---- lazy-zip ----

(test "lazy-zip two sequences"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-zip (list->lazy-seq '(a b c))
                                            (list->lazy-seq '(1 2 3))))
                  '((a . 1) (b . 2) (c . 3)) "zip")))

(test "lazy-zip uneven lengths"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-zip (list->lazy-seq '(a b))
                                            (list->lazy-seq '(1 2 3))))
                  '((a . 1) (b . 2)) "zip stops at shorter")))

(test "lazy-zip with empty"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-zip lazy-null (list->lazy-seq '(1 2 3))))
                  '() "zip empty")))

;; ---- composition: infinite sequences ----

(test "take from infinite range"
  (lambda ()
    (assert-equal (lazy-seq->list (lazy-take 5 (lazy-range)))
                  '(0 1 2 3 4) "infinite range take 5")))

(test "filter + take on infinite"
  (lambda ()
    (assert-equal (lazy-seq->list
                    (lazy-take 5 (lazy-filter even? (lazy-range))))
                  '(0 2 4 6 8) "filter even from infinite")))

(test "map + take on infinite"
  (lambda ()
    (assert-equal (lazy-seq->list
                    (lazy-take 4 (lazy-map (lambda (x) (* x x)) (lazy-range 1 +inf.0))))
                  '(1 4 9 16) "map square on infinite range")))

(test "drop + take on infinite"
  (lambda ()
    (assert-equal (lazy-seq->list
                    (lazy-take 3 (lazy-drop 5 (lazy-range))))
                  '(5 6 7) "drop 5 take 3")))

(test "zip two infinite sequences"
  (lambda ()
    (assert-equal (lazy-seq->list
                    (lazy-take 3 (lazy-zip (lazy-iterate add1 0)
                                           (lazy-iterate (lambda (x) (* x 2)) 1))))
                  '((0 . 1) (1 . 2) (2 . 4)) "zip infinite")))

(test "append finite to infinite, take from result"
  (lambda ()
    (assert-equal (lazy-seq->list
                    (lazy-take 5 (lazy-append (list->lazy-seq '(a b c))
                                              (lazy-range))))
                  '(a b c 0 1) "append then take")))

;; ---- laziness verification ----

(test "lazy-map does not force ahead"
  (lambda ()
    (let* ([count 0]
           [s (lazy-map (lambda (x) (set! count (+ count 1)) (* x 10))
                        (list->lazy-seq '(1 2 3 4 5)))])
      (assert-equal count 0 "nothing forced yet")
      (lazy-car s)
      (assert-equal count 1 "forced one element")
      (lazy-car (lazy-cdr s))
      (assert-equal count 2 "forced two elements"))))

;; ---- Summary ----

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
