#!/usr/bin/env scheme-script
#!chezscheme
(import (except (chezscheme) reset)
        (std misc delimited))

(define test-count 0)
(define pass-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (display "FAIL: ") (display name) (newline)
              (display "  Error: ") (display (condition-message e)) (newline)
              (when (irritants-condition? e)
                (display "  Irritants: ") (display (condition-irritants e)) (newline))])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display "PASS: ") (display name) (newline)))

(define (assert-equal actual expected msg)
  (unless (equal? actual expected)
    (error 'assert-equal
           (string-append msg ": expected " (format "~s" expected)
                          " got " (format "~s" actual)))))

(test "reset without shift"
  (lambda ()
    (assert-equal (reset (+ 1 2)) 3 "no shift")))

(test "shift calls continuation"
  (lambda ()
    (assert-equal (reset (+ 1 (shift k (k 10)))) 11 "k applied to 10")))

(test "shift discards continuation"
  (lambda ()
    (assert-equal (reset (+ 1 (shift k 42))) 42 "k not used")))

(test "shift uses continuation twice"
  (lambda ()
    (assert-equal (reset (+ 1 (shift k (+ (k 10) (k 20))))) 32 "k(10)+k(20)")))

(test "nested reset"
  (lambda ()
    (assert-equal
      (reset (+ 1 (reset (+ 2 (shift k (k 10))))))
      13 "inner reset captures inner shift")))

(test "shift as early return"
  (lambda ()
    (assert-equal
      (reset
        (let ([x 5])
          (when (> x 3) (shift k 'too-big))
          (* x 2)))
      'too-big "early return")))

(test "k(k(3)) double application"
  (lambda ()
    (assert-equal
      (reset (* 2 (shift k (k (k 3)))))
      12 "k(k(3)) = 2*(2*3)")))

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
