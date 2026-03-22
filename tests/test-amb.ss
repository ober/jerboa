#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc amb))

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

;; Test 1: basic amb choice
(test "amb returns first value"
  (lambda ()
    (assert-equal (with-amb (amb 1 2 3)) 1 "first choice")))

;; Test 2: amb with assertion
(test "amb with constraint"
  (lambda ()
    (let ([result (with-amb
                    (let ([x (amb 1 2 3 4 5)])
                      (amb-assert (> x 3))
                      x))])
      (assert-equal result 4 "first x > 3"))))

;; Test 3: two variables with constraint
(test "amb two variables with sum constraint"
  (lambda ()
    (let ([result (with-amb
                    (let ([x (amb 1 2 3)]
                          [y (amb 1 2 3)])
                      (amb-assert (= (+ x y) 4))
                      (cons x y)))])
      (assert-equal result '(1 . 3) "first pair summing to 4"))))

;; Test 4: no solution returns #f
(test "amb no solution returns #f"
  (lambda ()
    (let ([result (with-amb
                    (let ([x (amb 1 2 3)])
                      (amb-assert (> x 10))
                      x))])
      (assert-equal result #f "no solution"))))

;; Test 5: collect all solutions
(test "amb-collect gathers all solutions"
  (lambda ()
    (let ([results (amb-collect
                     (let ([x (amb 1 2 3)]
                           [y (amb 1 2 3)])
                       (amb-assert (= (+ x y) 4))
                       (cons x y)))])
      (assert-equal results '((1 . 3) (2 . 2) (3 . 1))
                    "all pairs summing to 4"))))

;; Test 6: single choice
(test "amb single choice"
  (lambda ()
    (assert-equal (with-amb (amb 42)) 42 "single")))

;; Test 7: nested amb
(test "nested with-amb"
  (lambda ()
    (let ([result (with-amb
                    (let ([x (amb 1 2)])
                      (amb-assert (= x 2))
                      (* x (with-amb
                              (let ([y (amb 10 20)])
                                (amb-assert (= y 20))
                                y)))))])
      (assert-equal result 40 "nested"))))

;; Test 8: Pythagorean triples
(test "Pythagorean triple"
  (lambda ()
    (let ([result (with-amb
                    (let ([a (amb 1 2 3 4 5 6 7 8 9 10)]
                          [b (amb 1 2 3 4 5 6 7 8 9 10)]
                          [c (amb 1 2 3 4 5 6 7 8 9 10)])
                      (amb-assert (<= a b))
                      (amb-assert (= (+ (* a a) (* b b)) (* c c)))
                      (list a b c)))])
      (assert-equal result '(3 4 5) "first Pythagorean triple"))))

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
